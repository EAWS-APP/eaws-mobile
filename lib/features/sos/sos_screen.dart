import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sos_api.dart';

// Global notifier to control Dashboard bottom nav visibility
final ValueNotifier<bool> globalSosActiveNotifier = ValueNotifier(false);

class SOSScreen extends StatefulWidget {
  final bool startImmediately;

  const SOSScreen({super.key, this.startImmediately = false});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> with TickerProviderStateMixin {
  bool _isSOSActive = false;
  bool _isCountingDown = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;
  String? _activeIncidentId;
  double? _latitude;
  double? _longitude;
  String _address = 'Acquiring GPS location...';
  double? _gpsAccuracy;
  bool _isSilentMode = false;
  double _readinessScore = 95.0;
  bool _showRecoveryScreen = false;
  bool _isSilentModeUnlocked = false;
  String _enteredPin = '';
  String _selectedCategory = '';
  List<Map<String, dynamic>> _emergencyContacts = [];
  Timer? _backgroundTrackingTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Responder Tracking
  bool _isDispatched = false;
  double? _responderLat;
  double? _responderLng;
  String _responderETA = '~8 mins';
  String _responderName = 'Police Response Unit';
  GoogleMapController? _mapController;
  Timer? _simulationTimer;
  Timer? _blinkTimer;
  bool _isRedDotVisible = true;
  BitmapDescriptor? _responderIcon;

  // Radar pulsing animation
  late AnimationController _radarController;
  late Animation<double> _radarAnimation;

  // Flashing alert color animation
  late AnimationController _flashController;
  late Animation<Color?> _flashColorAnimation;

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _radarAnimation = Tween<double>(
      begin: 0.8,
      end: 2.2,
    ).animate(CurvedAnimation(parent: _radarController, curve: Curves.easeOut));

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _flashColorAnimation = ColorTween(
      begin: Colors.black,
      end: const Color(0xFFDC2626), // errorColor
    ).animate(_flashController);

    // If navigated from home screen SOS holding
    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerCountdown();
      });
    }

    _loadContacts();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final isOffline = results.every(
        (result) => result == ConnectivityResult.none,
      );
      if (mounted && !isOffline && _isSOSActive && _activeIncidentId == null) {
        // Internet came back, and we haven't successfully created an incident yet!
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connection restored. Switching to live telemetry...',
            ),
            backgroundColor: AppTheme.successColor,
          ),
        );
        _activateSOSBroadcast();
      }
    });
  }

  Future<void> _loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? contactsJson = prefs.getString('eaws_emergency_contacts');
      if (contactsJson != null) {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        if (mounted) {
          setState(() {
            _emergencyContacts = decoded
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (e) {
      print('Error loading contacts: $e');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _backgroundTrackingTimer?.cancel();
    _simulationTimer?.cancel();
    _blinkTimer?.cancel();
    _connectivitySubscription?.cancel();
    _mapController?.dispose();
    _radarController.dispose();
    _flashController.dispose();
    globalSosActiveNotifier.value = false;
    super.dispose();
  }

  void _triggerCountdown() {
    // Vibrate device briefly to notify user SOS triggered
    HapticFeedback.vibrate();

    setState(() {
      _isCountingDown = true;
      _countdownSeconds = 10;
      _isSOSActive = false;
      _isSilentModeUnlocked = false;
      _enteredPin = '';
    });
    globalSosActiveNotifier.value = true;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() {
          _countdownSeconds--;
        });
        HapticFeedback.lightImpact();
      } else {
        timer.cancel();
        _activateSOSBroadcast();
      }
    });
  }

  Future<void> _cancelSOS() async {
    _countdownTimer?.cancel();
    _backgroundTrackingTimer?.cancel();
    _backgroundTrackingTimer = null;
    _blinkTimer?.cancel();
    _flashController.stop();
    final incidentId = _activeIncidentId;
    setState(() {
      _isCountingDown = false;
      _isSOSActive = false;
      _activeIncidentId = null;
      _isSilentModeUnlocked = false;
      _enteredPin = '';
    });
    globalSosActiveNotifier.value = false;

    if (incidentId != null) {
      try {
        await SosApi.instance.cancelSos(incidentId);
      } catch (e) {
        print('EAWS SOS cancel API unavailable: $e');
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency dispatch cancelled.'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  Future<void> _activateSOSBroadcast() async {
    HapticFeedback.vibrate();
    setState(() {
      _isCountingDown = false;
      _isSOSActive = true;
      _address = 'Acquiring GPS location...';
    });

    // Repeat the red flashing beacon light animation
    _flashController.repeat(reverse: true);

    // 1. Check Internet Connectivity (Offline SMS Fallback)
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == [ConnectivityResult.none] ||
        connectivityResult.contains(ConnectivityResult.none)) {
      _triggerOfflineSMSFallback();
      return;
    }

    try {
      // 2. Query high-accuracy GPS coordinates
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gpsAccuracy = position.accuracy;
      });

      // 3. Resolve address from OSM Nominatim reverse geocoder
      String resolvedAddress =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final client = HttpClient();
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1',
        );
        final request = await client.getUrl(url);
        request.headers.set(
          'User-Agent',
          'EAWSMobileApp/1.0 (masters@eaws.org)',
        );
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        if (data != null && data['address'] != null) {
          final addr = data['address'];
          final poi =
              addr['amenity'] ??
              addr['building'] ??
              addr['shop'] ??
              addr['office'] ??
              '';
          final road = addr['road'] ?? addr['street'] ?? addr['highway'] ?? '';
          final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? '';
          final country = addr['country'] ?? '';

          List<String> parts = [];
          if (poi.isNotEmpty) parts.add(poi);
          if (road.isNotEmpty) parts.add(road);
          if (city.isNotEmpty) parts.add(city);
          if (parts.isEmpty && country.isNotEmpty) parts.add(country);

          if (parts.isNotEmpty) {
            resolvedAddress = parts.join(', ');
          }
        }
      } catch (geocodingErr) {
        print('Nominatim reverse geocoding unavailable: $geocodingErr');
      }

      setState(() {
        _address = resolvedAddress;
      });

      // 4. Connect to database backend
      final sos = await SosApi.instance.createSos(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        locationName: resolvedAddress,
      );

      setState(() {
        final incident = sos['incident'] ?? sos;
        _activeIncidentId =
            incident['id']?.toString() ?? incident['incident_id']?.toString();
      });

      // 5. Start background tracking timer
      _startBackgroundTracking();

      // 6. Start dispatch simulation
      _startResponderSimulation();
    } catch (e) {
      print('EAWS SOS API unavailable, active visual state retained: $e');
      setState(() {
        _address = 'Emergency telemetry broadcasting offline...';
      });
    }
  }

  Future<void> _triggerOfflineSMSFallback() async {
    setState(() {
      _address = 'Offline. Initiating SMS Emergency Fallback...';
    });

    double lat = 5.6037; // Default Accra latitude
    double lng = -0.1870; // Default Accra longitude

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      );
      lat = position.latitude;
      lng = position.longitude;
      setState(() {
        _latitude = lat;
        _longitude = lng;
        _gpsAccuracy = position.accuracy;
      });
    } catch (_) {
      // Fallback coordinates if GPS times out
      setState(() {
        _latitude = lat;
        _longitude = lng;
      });
    }

    final String message =
        'EAWS EMERGENCY SOS! CitizenEbenezar triggered alert. Location: Lat ${lat.toStringAsFixed(5)}, Lng ${lng.toStringAsFixed(5)} (https://maps.google.com/?q=$lat,$lng)';

    // Include 112 + all saved emergency contacts (stripped of spaces for iOS compatibility)
    String separator = Platform.isAndroid ? ';' : ',';
    List<String> numbers = ['112'];
    numbers.addAll(
      _emergencyContacts.map(
        (e) => e['phone'].toString().replaceAll(RegExp(r'\s+'), ''),
      ),
    );
    final nums = numbers.join(separator);

    final encodedBody = Uri.encodeComponent(message);
    String bodyPrefix = Platform.isIOS ? '&body=' : '?body=';
    final String urlString = 'sms:$nums$bodyPrefix$encodedBody';

    final Uri smsUri = Uri.parse(urlString);

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline SMS composer pre-populated and launched!'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to launch SMS composer automatically.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _updateMapBounds() {
    if (_mapController != null &&
        _latitude != null &&
        _longitude != null &&
        _responderLat != null &&
        _responderLng != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              _latitude! < _responderLat! ? _latitude! : _responderLat!,
              _longitude! < _responderLng! ? _longitude! : _responderLng!,
            ),
            northeast: LatLng(
              _latitude! > _responderLat! ? _latitude! : _responderLat!,
              _longitude! > _responderLng! ? _longitude! : _responderLng!,
            ),
          ),
          60.0, // padding
        ),
      );
    }
  }

  // Create a high-resolution emoji marker for the map
  Future<BitmapDescriptor> _createEmojiMarker(String emoji) async {
    const double size = 120;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Draw a white circle background
    final Paint bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, bgPaint);

    // Draw a subtle border
    final Paint borderPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 1.5,
      borderPaint,
    );

    // Draw the emoji text
    final textPainter = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 60)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // Get emoji and unit name for the selected emergency category
  String _getResponderEmoji() {
    switch (_selectedCategory.toLowerCase()) {
      case 'medical aid':
        return '🚑';
      case 'fire rescue':
        return '🚒';
      case 'natural disaster':
        return '🚁';
      case 'police / threat':
      default:
        return '🚓';
    }
  }

  String _getResponderUnitName() {
    switch (_selectedCategory.toLowerCase()) {
      case 'medical aid':
        return 'Ambulance Unit 07';
      case 'fire rescue':
        return 'Fire Engine Unit 12';
      case 'natural disaster':
        return 'Rescue Helicopter H3';
      case 'police / threat':
      default:
        return 'Police Rapid Response Unit 04';
    }
  }

  void _startResponderSimulation() {
    _simulationTimer?.cancel();

    // Start the blinking red dot for the user's location
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (mounted) {
        setState(() {
          _isRedDotVisible = !_isRedDotVisible;
        });
      } else {
        timer.cancel();
      }
    });

    // Simulate a dispatcher assigning a unit after 5 seconds
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted || !_isSOSActive) return;

      // Generate the responder vehicle marker based on category
      final icon = await _createEmojiMarker(_getResponderEmoji());

      if (!mounted) return;
      setState(() {
        _isDispatched = true;
        _responderName = _getResponderUnitName();
        _responderIcon = icon;
        // Start responder ~2km away diagonally
        _responderLat = (_latitude ?? 5.6037) + 0.015;
        _responderLng = (_longitude ?? -0.1870) + 0.015;
      });

      // Animate responder moving toward user every 3 seconds
      _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!mounted ||
            !_isSOSActive ||
            _latitude == null ||
            _longitude == null) {
          timer.cancel();
          return;
        }

        setState(() {
          // Move responder 10% closer each tick
          _responderLat = _responderLat! + (_latitude! - _responderLat!) * 0.1;
          _responderLng = _responderLng! + (_longitude! - _responderLng!) * 0.1;

          double dist = Geolocator.distanceBetween(
            _latitude!,
            _longitude!,
            _responderLat!,
            _responderLng!,
          );
          if (dist < 50) {
            _responderETA = 'Arriving now';
            timer.cancel();
            // Auto-transition to recovery screen after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _isSOSActive) {
                _stopSOS();
              }
            });
          } else {
            int mins = (dist / 400).ceil(); // Assuming ~24km/h speed
            _responderETA = '~$mins mins';
          }
        });

        _updateMapBounds();
      });
    });
  }

  void _startBackgroundTracking() {
    _backgroundTrackingTimer?.cancel();
    _backgroundTrackingTimer = Timer.periodic(const Duration(seconds: 15), (
      timer,
    ) async {
      final incidentId = _activeIncidentId;
      if (incidentId == null) return;

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );

        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _gpsAccuracy = position.accuracy;
        });

        if (!incidentId.startsWith('mock-')) {
          await Supabase.instance.client
              .from('incidents')
              .update({
                'latitude': position.latitude,
                'longitude': position.longitude,
              })
              .eq('id', incidentId);
        }

        print(
          'EAWS Telemetry background sync successful: ${position.latitude}, ${position.longitude}',
        );
      } catch (e) {
        print('EAWS Telemetry background sync failed: $e');
      }
    });
  }

  Future<void> _stopSOS() async {
    _flashController.stop();
    _backgroundTrackingTimer?.cancel();
    _backgroundTrackingTimer = null;
    _blinkTimer?.cancel();
    final incidentId = _activeIncidentId;
    setState(() {
      _isSOSActive = false;
      _isCountingDown = false;
      _activeIncidentId = null;
      _showRecoveryScreen = true;
      _isSilentModeUnlocked = false;
      _enteredPin = '';
    });
    globalSosActiveNotifier.value = true;

    if (incidentId != null) {
      try {
        await SosApi.instance.cancelSos(incidentId);
      } catch (e) {
        print('EAWS SOS cancel API unavailable: $e');
      }
    } else {
      // Offline fallback cancellation via SMS
      final String message =
          'FALSE ALARM. I am safe. Disregard previous EAWS SOS.';
      String separator = Platform.isAndroid ? ';' : ',';
      List<String> numbers = ['112'];
      numbers.addAll(
        _emergencyContacts.map(
          (e) => e['phone'].toString().replaceAll(RegExp(r'\s+'), ''),
        ),
      );
      final nums = numbers.join(separator);

      final encodedBody = Uri.encodeComponent(message);
      String bodyPrefix = Platform.isIOS ? '&body=' : '?body=';
      final Uri smsUri = Uri.parse('sms:$nums$bodyPrefix$encodedBody');

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency broadcast muted.'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showRecoveryScreen) {
      return _buildRecoveryLayout();
    } else if (_isCountingDown) {
      return _buildCountdownLayout();
    } else if (_isSOSActive) {
      return _buildActiveSOSLayout();
    } else {
      return _buildInactiveLayout();
    }
  }

  // Layout 1: Personal Safety Intelligence Dashboard
  Widget _buildInactiveLayout() {
    // Mock historical data — replace with Supabase query once backend is ready
    final List<Map<String, dynamic>> _history = [
      {
        'type': 'Police / Threat',
        'emoji': '👮',
        'date': '2 days ago',
        'status': 'Resolved',
        'statusColor': AppTheme.successColor,
        'responseTime': '4.2 mins',
        'location': 'East Legon, Accra',
      },
      {
        'type': 'Medical Aid',
        'emoji': '🚑',
        'date': '11 days ago',
        'status': 'False Alarm',
        'statusColor': AppTheme.warningColor,
        'responseTime': '—',
        'location': 'Cantonments, Accra',
      },
      {
        'type': 'Fire Rescue',
        'emoji': '🔥',
        'date': '23 days ago',
        'status': 'Resolved',
        'statusColor': AppTheme.successColor,
        'responseTime': '7.1 mins',
        'location': 'Tema, Greater Accra',
      },
    ];

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Safety & Emergency Hub',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Readiness Score Card (interactive) ─────────────────────
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    builder: (_) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Readiness Breakdown',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your score is based on these factors:',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildReadinessCheckItem(
                            true,
                            'GPS & Location Enabled',
                            '+30%',
                          ),
                          _buildReadinessCheckItem(
                            true,
                            'Emergency Contacts Set',
                            '+30%',
                          ),
                          _buildReadinessCheckItem(
                            true,
                            'SMS Fallback Ready',
                            '+20%',
                          ),
                          _buildReadinessCheckItem(
                            true,
                            'Internet Connection Active',
                            '+18%',
                          ),
                          _buildReadinessCheckItem(
                            false,
                            'Medical ID Not Configured',
                            '-2%',
                          ),
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '✅  You are 98% ready. Configure a Medical ID in your Profile to reach 100%.',
                              style: TextStyle(
                                color: Color(0xFF166534),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _radarAnimation,
                            builder: (context, child) => Transform.scale(
                              scale: _radarAnimation.value,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.successColor.withOpacity(
                                    0.15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.successColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Safety Readiness Score',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tap to see full breakdown',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '98%',
                          style: TextStyle(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── 2. Safety Analytics Cards ─────────────────────────────────
              const Text(
                'MY SAFETY ANALYTICS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildAnalyticsCard(
                      'Total Alerts',
                      '3',
                      LucideIcons.shieldAlert,
                      const Color(0xFFFEF2F2),
                      AppTheme.errorColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAnalyticsCard(
                      'Avg Response',
                      '5.7 min',
                      LucideIcons.timer,
                      const Color(0xFFEFF6FF),
                      const Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildAnalyticsCard(
                      'False Alarms',
                      '1',
                      LucideIcons.alertTriangle,
                      const Color(0xFFFFFBEB),
                      const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAnalyticsCard(
                      'Last Emergency',
                      '2 days ago',
                      LucideIcons.clock,
                      const Color(0xFFF0FDF4),
                      AppTheme.successColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── 3. Emergency History ──────────────────────────────────────
              const Text(
                'MY EMERGENCY HISTORY',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              if (_history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'No emergency history yet.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ..._history
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                item['emoji'],
                                style: const TextStyle(fontSize: 28),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['type'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item['location'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        const Icon(
                                          LucideIcons.clock,
                                          size: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          item['date'],
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        if (item['responseTime'] != '—') ...[
                                          const SizedBox(width: 10),
                                          const Icon(
                                            LucideIcons.zap,
                                            size: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${item['responseTime']} response',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: (item['statusColor'] as Color)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item['status'],
                                  style: TextStyle(
                                    color: item['statusColor'],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              const SizedBox(height: 28),

              // ── 4. Silent Threat Mode ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.eyeOff,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Silent Threat Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Silent tracking for stealth events',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isSilentMode,
                      onChanged: (val) {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _isSilentMode = val;
                        });
                      },
                      activeColor: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── 5. Emergency Type Selection ───────────────────────────────
              const Text(
                'EMERGENCY TYPE SELECTION',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildEmergencyCategoryCard(
                      'Medical Aid',
                      '🚑',
                      const Color(0xFFEFF6FF),
                      const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildEmergencyCategoryCard(
                      'Police / Threat',
                      '👮',
                      const Color(0xFFFEF2F2),
                      const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildEmergencyCategoryCard(
                      'Fire Rescue',
                      '🔥',
                      const Color(0xFFFFFBEB),
                      const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildEmergencyCategoryCard(
                      'Natural Disaster',
                      '🌪️',
                      const Color(0xFFF0FDF4),
                      const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── 6. SOS Trigger Button ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _triggerCountdown,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 4,
                  ),
                  icon: const Icon(LucideIcons.shieldAlert, size: 24),
                  label: Text(
                    _isSilentMode
                        ? 'Trigger Silent SOS Now'
                        : 'Trigger Emergency SOS Now',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── 7. Interactive First-Aid Toolkit ──────────────────────────
              const Text(
                'EMERGENCY PREPAREDNESS TOOLKIT',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              _buildToolkitCard(
                icon: LucideIcons.heart,
                iconColor: const Color(0xFFEF4444),
                iconBg: const Color(0xFFFEF2F2),
                title: 'CPR & Bleeding Control',
                steps: [
                  'Call ambulance immediately (193)',
                  'Lay person flat on their back',
                  'Apply firm pressure to bleeding wounds',
                  'Perform 30 chest compressions, then 2 rescue breaths',
                  'Repeat until ambulance arrives',
                ],
              ),
              const SizedBox(height: 10),
              _buildToolkitCard(
                icon: LucideIcons.flame,
                iconColor: const Color(0xFFF59E0B),
                iconBg: const Color(0xFFFFFBEB),
                title: 'Fire & Flood Protocol',
                steps: [
                  'Move to higher ground or evacuate immediately',
                  'Stay low to avoid smoke — crawl if needed',
                  'Do NOT cross fast-flowing flood water',
                  'Close doors to slow fire spread',
                  'Signal from a window if you cannot exit',
                ],
              ),
              const SizedBox(height: 10),
              _buildToolkitCard(
                icon: LucideIcons.phone,
                iconColor: const Color(0xFF3B82F6),
                iconBg: const Color(0xFFEFF6FF),
                title: 'Direct Emergency Hotlines',
                steps: [
                  'National Emergency: 112',
                  'Ghana Police: 191 / 18555',
                  'Ghana Fire Service: 192 / 193',
                  'National Ambulance: 193',
                ],
                isDialable: true,
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard(
    String label,
    String value,
    IconData icon,
    Color bg,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: iconColor,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessCheckItem(bool passed, String label, String impact) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            passed ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
            color: passed ? AppTheme.successColor : AppTheme.warningColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
          Text(
            impact,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: passed ? AppTheme.successColor : AppTheme.warningColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolkitCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required List<String> steps,
    bool isDialable = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppTheme.textPrimary,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: steps.asMap().entries.map((entry) {
                  final num = entry.key + 1;
                  final step = entry.value;
                  final phoneMatch = RegExp(
                    r'\d{3}[ /]*\d{3,5}|\d{3}',
                  ).firstMatch(step);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: iconBg,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$num',
                              style: TextStyle(
                                color: iconColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: isDialable && phoneMatch != null
                              ? GestureDetector(
                                  onTap: () async {
                                    final digits = step.replaceAll(
                                      RegExp(r'[^\d]'),
                                      '',
                                    );
                                    final uri = Uri.parse('tel:$digits');
                                    if (await canLaunchUrl(uri)) launchUrl(uri);
                                  },
                                  child: Text(
                                    step,
                                    style: TextStyle(
                                      color: iconColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                )
                              : Text(
                                  step,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyCategoryCard(
    String label,
    String emoji,
    Color bg,
    Color activeBorder,
  ) {
    final isSelected = _selectedCategory == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedCategory = isSelected ? '' : label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? bg : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeBorder : const Color(0xFFE2E8F0),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected ? activeBorder : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Layout 2: Countdown Overlay
  Widget _buildCountdownLayout() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(
          0xFF1F2937,
        ), // Dark slate bg during countdown
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const Icon(
                    LucideIcons.shieldAlert,
                    color: AppTheme.primaryColor,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SOS EMERGENCY INITIATED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Broadcasting live telemetry & initiating regional dispatch in:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Giant Animated Countdown Circle
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: CircularProgressIndicator(
                          value: _countdownSeconds / 10,
                          strokeWidth: 10,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Cancel Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _cancelSOS(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'CANCEL DISPATCH',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Press cancel if this was an accidental trigger',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handlePinInput(String digit) async {
    if (_enteredPin.length < 4) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin += digit;
      });
      if (_enteredPin.length == 4) {
        // verify PIN
        final prefs = await SharedPreferences.getInstance();
        final savedPin = prefs.getString('eaws_emergency_pin') ?? '1234';
        if (_enteredPin == savedPin) {
          HapticFeedback.heavyImpact();
          setState(() {
            _isSilentModeUnlocked = true;
            _enteredPin = '';
          });
        } else {
          HapticFeedback.vibrate();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect PIN'),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() {
                _enteredPin = '';
              });
            }
          });
        }
      }
    }
  }

  void _handlePinBackspace() {
    if (_enteredPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Widget _buildDialKey(String value, {bool isIcon = false}) {
    return GestureDetector(
      onTap: () {
        if (isIcon) {
          _handlePinBackspace();
        } else {
          _handlePinInput(value);
        }
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.05),
        ),
        child: Center(
          child: isIcon
              ? const Icon(
                  Icons.backspace_outlined,
                  color: Colors.white,
                  size: 24,
                )
              : Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPinLockScreen() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B101E), // Deep dark for stealth
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),
              const Icon(
                LucideIcons.shieldAlert,
                color: Colors.white24,
                size: 32,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter PIN to Unlock',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 40),
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? Colors.white : Colors.white10,
                      border: isFilled
                          ? null
                          : Border.all(color: Colors.white24, width: 1.5),
                    ),
                  );
                }),
              ),
              const Spacer(),
              // Keypad
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(3, (j) {
                            int digit = i * 3 + j + 1;
                            return _buildDialKey(digit.toString());
                          }),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 72), // Empty space for alignment
                        _buildDialKey('0'),
                        _buildDialKey('delete', isIcon: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Layout 3: Active Emergency Beacon Screen
  Widget _buildActiveSOSLayout() {
    if (_isSilentMode && !_isSilentModeUnlocked) {
      return _buildPinLockScreen();
    }

    return AnimatedBuilder(
      animation: _flashColorAnimation,
      builder: (context, child) {
        final bool showMap =
            _isDispatched &&
            _latitude != null &&
            _longitude != null &&
            _responderLat != null &&
            _responderLng != null;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: showMap
                ? Colors.black
                : _flashColorAnimation.value,
            body: Stack(
              children: [
                // LAYER 1: Background (Map or Pulsing Radar)
                if (showMap)
                  Positioned.fill(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_latitude!, _longitude!),
                        zoom: 14,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                        // Apply dark theme to map
                        _mapController?.setMapStyle('''
                        [
                          {
                            "elementType": "geometry",
                            "stylers": [{"color": "#212121"}]
                          },
                          {
                            "elementType": "labels.icon",
                            "stylers": [{"visibility": "off"}]
                          },
                          {
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#757575"}]
                          },
                          {
                            "elementType": "labels.text.stroke",
                            "stylers": [{"color": "#212121"}]
                          },
                          {
                            "featureType": "administrative",
                            "elementType": "geometry",
                            "stylers": [{"color": "#757575"}]
                          },
                          {
                            "featureType": "administrative.country",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#9e9e9e"}]
                          },
                          {
                            "featureType": "administrative.land_parcel",
                            "stylers": [{"visibility": "off"}]
                          },
                          {
                            "featureType": "administrative.locality",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#bdbdbd"}]
                          },
                          {
                            "featureType": "poi",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#757575"}]
                          },
                          {
                            "featureType": "poi.park",
                            "elementType": "geometry",
                            "stylers": [{"color": "#181818"}]
                          },
                          {
                            "featureType": "poi.park",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#616161"}]
                          },
                          {
                            "featureType": "poi.park",
                            "elementType": "labels.text.stroke",
                            "stylers": [{"color": "#1b1b1b"}]
                          },
                          {
                            "featureType": "road",
                            "elementType": "geometry.fill",
                            "stylers": [{"color": "#2c2c2c"}]
                          },
                          {
                            "featureType": "road",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#8a8a8a"}]
                          },
                          {
                            "featureType": "road.arterial",
                            "elementType": "geometry",
                            "stylers": [{"color": "#373737"}]
                          },
                          {
                            "featureType": "road.highway",
                            "elementType": "geometry",
                            "stylers": [{"color": "#3c3c3c"}]
                          },
                          {
                            "featureType": "road.highway.controlled_access",
                            "elementType": "geometry",
                            "stylers": [{"color": "#4e4e4e"}]
                          },
                          {
                            "featureType": "road.local",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#616161"}]
                          },
                          {
                            "featureType": "transit",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#757575"}]
                          },
                          {
                            "featureType": "water",
                            "elementType": "geometry",
                            "stylers": [{"color": "#000000"}]
                          },
                          {
                            "featureType": "water",
                            "elementType": "labels.text.fill",
                            "stylers": [{"color": "#3d3d3d"}]
                          }
                        ]
                      ''');
                        Future.delayed(
                          const Duration(milliseconds: 500),
                          _updateMapBounds,
                        );
                      },
                      markers: {
                        if (_isRedDotVisible)
                          Marker(
                            markerId: const MarkerId('user_location'),
                            position: LatLng(_latitude!, _longitude!),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueRed,
                            ),
                          ),
                        Marker(
                          markerId: const MarkerId('responder_location'),
                          position: LatLng(_responderLat!, _responderLng!),
                          icon:
                              _responderIcon ??
                              BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueBlue,
                              ),
                          infoWindow: InfoWindow(title: _responderName),
                        ),
                      },
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: [
                            LatLng(_latitude!, _longitude!),
                            LatLng(_responderLat!, _responderLng!),
                          ],
                          color: AppTheme.primaryColor,
                          width: 5,
                        ),
                      },
                      myLocationEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                    ),
                  )
                else
                  Positioned.fill(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pulsing Radar Circle
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _radarAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _radarAnimation.value,
                                  child: Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.12),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Container(
                              width: 100,
                              height: 100,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: const Icon(
                                LucideIcons.siren,
                                color: AppTheme.primaryColor,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'HELP IS ON THE WAY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(
                            _activeIncidentId != null
                                ? 'Location: $_address\nCoordinates and live telemetry are transmitting to Control Room.'
                                : 'GPS: ${_latitude?.toStringAsFixed(5) ?? '--'}, ${_longitude?.toStringAsFixed(5) ?? '--'}\nRead coordinates to operator if calling 112.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // LAYER 2: Top HUD
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SOS ACTIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: showMap
                                  ? Colors.black.withOpacity(0.6)
                                  : Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _activeIncidentId != null
                                      ? LucideIcons.radio
                                      : LucideIcons.wifiOff,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _activeIncidentId != null
                                      ? 'BROADCASTING'
                                      : 'SMS FALLBACK',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // LAYER 3: Bottom HUD
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: 24,
                      left: 24,
                      right: 24,
                      bottom: MediaQuery.of(context).padding.bottom + 24,
                    ),
                    decoration: BoxDecoration(
                      color: showMap ? Colors.white : Colors.transparent,
                      borderRadius: showMap
                          ? const BorderRadius.vertical(
                              top: Radius.circular(32),
                            )
                          : null,
                      boxShadow: showMap
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, -5),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Simulated Live Response Dispatch Card or Offline Notice
                        if (_activeIncidentId != null)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: showMap
                                  ? const Color(0xFFF8FAFC)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: showMap
                                  ? Border.all(color: const Color(0xFFE2E8F0))
                                  : null,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.successColor
                                            .withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.shieldCheck,
                                        color: AppTheme.successColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Dispatch Unit Dispatched',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$_responderName is en-route',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Estimated Arrival Time',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      _responderETA,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.errorColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.warningColor
                                            .withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.wifiOff,
                                        color: AppTheme.warningColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Offline — SMS Fallback Active',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Read coordinates to 112 operator:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'YOUR LOCATION',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 10,
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${_latitude?.toStringAsFixed(5) ?? "--"}, ${_longitude?.toStringAsFixed(5) ?? "--"}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      if (_gpsAccuracy != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            '±${_gpsAccuracy!.toStringAsFixed(1)}m accuracy',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Quick Action buttons inside SOS Active State
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  HapticFeedback.vibrate();
                                  final Uri telUri = Uri.parse('tel:112');
                                  if (await canLaunchUrl(telUri)) {
                                    await launchUrl(telUri);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Could not launch phone dialer',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(
                                  LucideIcons.phone,
                                  color: showMap
                                      ? AppTheme.primaryColor
                                      : Colors.white,
                                ),
                                label: Text(
                                  'CALL CONTROL',
                                  style: TextStyle(
                                    color: showMap
                                        ? AppTheme.primaryColor
                                        : Colors.white,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  side: BorderSide(
                                    color: showMap
                                        ? AppTheme.primaryColor
                                        : Colors.white,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _stopSOS,
                                icon: const Icon(LucideIcons.square),
                                label: const Text('STOP SOS'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: showMap
                                      ? AppTheme.errorColor
                                      : Colors.white,
                                  foregroundColor: showMap
                                      ? Colors.white
                                      : AppTheme.errorColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: showMap ? 4 : 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecoveryLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4), // Light soft green background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.shieldCheck,
                  color: Colors.white,
                  size: 64,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'YOU ARE SAFE',
                style: TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Emergency state resolved. Live coordinate broadcasting and background sensor sync have been completely deactivated.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF15803D),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // Recovery Status checklist cards
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildRecoveryRow(
                      LucideIcons.checkCircle2,
                      'GPS Broadcast Terminated',
                    ),
                    const Divider(height: 24),
                    _buildRecoveryRow(
                      LucideIcons.checkCircle2,
                      'Guardians Notified (I\'m Safe)',
                    ),
                    const Divider(height: 24),
                    _buildRecoveryRow(
                      LucideIcons.checkCircle2,
                      'National Control Room Closed File',
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // Primary recovery actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _showRecoveryScreen = false;
                    });
                    globalSosActiveNotifier.value = false;
                  },
                  icon: const Icon(LucideIcons.arrowLeft),
                  label: const Text(
                    'Return to Safety Hub',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecoveryRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.successColor, size: 20),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
