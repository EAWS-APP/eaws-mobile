import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/theme.dart';
import '../../core/user_session.dart';
import '../../core/user_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'sos_api.dart';
import '../../core/location_service.dart';
import '../../core/webrtc_voice_call_widget.dart';

// Global notifier to control Dashboard bottom nav visibility
final ValueNotifier<bool> globalSosActiveNotifier = ValueNotifier(false);

class SOSScreen extends StatefulWidget {
  final bool startImmediately;

  const SOSScreen({super.key, this.startImmediately = false});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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
  bool _showRecoveryScreen = false;
  bool _isSilentModeUnlocked = false;
  String _enteredPin = '';
  String _selectedCategory = '';
  List<Map<String, dynamic>> _emergencyContacts = [];
  Timer? _backgroundTrackingTimer;
  Timer? _dispatchPollingTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;


  // ── Location state (single source of truth: LocationService) ───────────────
  // Rule: coordinates are NEVER fabricated. No fix => SOS is sent as
  // location_status 'pending' and upgraded the moment GPS locks.
  final LocationService _loc = LocationService.instance;
  GpsReadiness _gpsReadiness = GpsReadiness.acquiring;
  bool _trackingActive = false; // live SOS tracking (foreground service) on
  bool _locationPending = false; // SOS was sent without coordinates
  bool _addressResolved = false; // _address came from real reverse-geocoding
  bool _contactsNotified = false;
  Timer? _contactsFallbackTimer;
  double? _lastSentLat;
  double? _lastSentLng;
  double? _lastSentAccuracy;
  DateTime? _lastGeocodeAt;
  double? _lastGeocodeLat;
  double? _lastGeocodeLng;
  String _routedToLabel = '';

  Future<void> _initLocation() async {
    _loc.latestFix.addListener(_onLocationFix);
    _loc.readiness.addListener(_onReadinessChanged);
    await _loc.start(foreground: false); // warm-up stream keeps the GPS chip hot
    _onReadinessChanged();
    _onLocationFix();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from system settings: re-check permission / precision / GPS toggle.
    if (state == AppLifecycleState.resumed) {
      _loc
          .ensureReady(requestIfNeeded: false)
          .then((_) => _loc.start(foreground: _trackingActive));
    }
  }

  void _onReadinessChanged() {
    if (!mounted) return;
    setState(() => _gpsReadiness = _loc.readiness.value);
  }

  void _onLocationFix() {
    final fix = _loc.latestFix.value;
    if (fix == null || !mounted) return;
    setState(() {
      _latitude = fix.latitude;
      _longitude = fix.longitude;
      _gpsAccuracy = fix.accuracy;
    });
    if (_trackingActive && fix.source == FixSource.gps) _pushLiveLocation(fix);
  }

  /// Sends a breadcrumb when: first fix after a 'pending' SOS, moved > 10 m,
  /// or accuracy improved by > 40 %. Otherwise skipped (saves data/battery).
  Future<void> _pushLiveLocation(LocationFix fix) async {
    final incidentId = _activeIncidentId;
    if (incidentId == null || incidentId.startsWith('mock-') || !_isSOSActive) return;

    final bool firstFix = _locationPending || _lastSentLat == null || _lastSentLng == null;
    final double moved = firstFix
        ? double.infinity
        : Geolocator.distanceBetween(_lastSentLat!, _lastSentLng!, fix.latitude, fix.longitude);
    final bool accuracyImproved =
        _lastSentAccuracy != null && fix.accuracy < _lastSentAccuracy! * 0.6;
    if (!firstFix && moved < 10 && !accuracyImproved) return;

    // Claim this update before awaiting to avoid duplicate concurrent sends.
    _lastSentLat = fix.latitude;
    _lastSentLng = fix.longitude;
    _lastSentAccuracy = fix.accuracy;
    final bool wasPending = _locationPending;
    if (wasPending && mounted) {
      setState(() {
        _locationPending = false;
        _address = _lookupGhanaGeofenceLandmark(fix.latitude, fix.longitude);
      });
    }

    await SosApi.instance.updateSosLocation(
      incidentId,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracy: fix.accuracy,
      locationName: _addressResolved ? _address : null,
    );

    if (wasPending) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS locked — your exact location has been sent to responders.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
      _contactsFallbackTimer?.cancel();
      _notifyContactsOnce(fix.latitude, fix.longitude);
    }
    _maybeResolveAddress(fix.latitude, fix.longitude);
  }

  /// Reverse-geocode at most every 30 s and only after moving > 75 m.
  void _maybeResolveAddress(double lat, double lng) {
    final last = _lastGeocodeAt;
    if (last != null && _lastGeocodeLat != null && _lastGeocodeLng != null) {
      final recent = DateTime.now().difference(last) < const Duration(seconds: 30);
      final near = Geolocator.distanceBetween(_lastGeocodeLat!, _lastGeocodeLng!, lat, lng) < 75;
      if (recent || near) return;
    }
    _resolveAddressAsync(lat, lng);
  }

  void _notifyContactsOnce(double? lat, double? lng) {
    final id = _activeIncidentId;
    if (_contactsNotified || id == null || id.startsWith('mock-') || _emergencyContacts.isEmpty) {
      return;
    }
    _contactsNotified = true;
    SosApi.instance.notifyEmergencyContacts(
      id,
      contacts: _emergencyContacts,
      latitude: lat,
      longitude: lng,
      locationName: _locationPending ? 'Location pending (GPS acquiring)' : _address,
    );
  }

  Future<void> _fixGpsProblem() async {
    HapticFeedback.lightImpact();
    switch (_gpsReadiness) {
      case GpsReadiness.reducedAccuracy:
        await _loc.requestPreciseAccuracy();
      case GpsReadiness.denied:
        await _loc.ensureReady(requestIfNeeded: true);
      case GpsReadiness.serviceDisabled:
      case GpsReadiness.deniedForever:
        await _loc.openFixSettings();
      case GpsReadiness.ready:
      case GpsReadiness.acquiring:
        break;
    }
    await _loc.start(foreground: _trackingActive);
  }

  /// Small status pill: tells the user whether responders will be able to find them.
  Widget _buildGpsStatusChip({bool onDark = false}) {
    final bool hasFix = _latitude != null && _longitude != null;
    final (Color color, IconData icon, String label, String? action) = switch (_gpsReadiness) {
      GpsReadiness.ready => (
          const Color(0xFF10B981),
          LucideIcons.locateFixed,
          _gpsAccuracy != null
              ? 'GPS ready · ±${_gpsAccuracy!.toStringAsFixed(0)} m'
              : 'GPS ready',
          null,
        ),
      GpsReadiness.acquiring => (
          const Color(0xFFF59E0B),
          LucideIcons.crosshair,
          hasFix ? 'Locking GPS… using recent position' : 'Acquiring GPS…',
          null,
        ),
      GpsReadiness.reducedAccuracy => (
          const Color(0xFFDC2626),
          LucideIcons.alertTriangle,
          'Approximate location only — responders may not find you',
          'Fix',
        ),
      GpsReadiness.serviceDisabled => (
          const Color(0xFFDC2626),
          LucideIcons.mapPinOff,
          'Location is turned off',
          'Turn on',
        ),
      GpsReadiness.denied => (
          const Color(0xFFDC2626),
          LucideIcons.mapPinOff,
          'Location permission needed',
          'Allow',
        ),
      GpsReadiness.deniedForever => (
          const Color(0xFFDC2626),
          LucideIcons.mapPinOff,
          'Location blocked in settings',
          'Open settings',
        ),
    };

    return Material(
      key: const ValueKey('sos_gps_status_chip'),
      color: color.withValues(alpha: onDark ? 0.18 : 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: action == null ? null : _fixGpsProblem,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: onDark ? Colors.white : AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 10),
                Text(
                  action,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _lookupGhanaGeofenceLandmark(double lat, double lng) {
    if (lat >= 5.550 && lat <= 5.575 && lng >= -0.225 && lng <= -0.200) {
      return 'Kwame Nkrumah Circle & Interchange, Accra';
    } else if (lat >= 5.640 && lat <= 5.730 && lng >= -0.060 && lng <= 0.050) {
      return 'Tema Metropolitan Area (Industrial / Community Sector)';
    } else if (lat >= 5.550 && lat <= 5.578 && lng >= -0.250 && lng <= -0.225) {
      return 'Kaneshie & Abossey Okai Commercial Sector, Accra';
    } else if (lat >= 5.625 && lat <= 5.670 && lng >= -0.175 && lng <= -0.130) {
      return 'East Legon / Bawaleshie Sector, Accra';
    } else if (lat >= 5.608 && lat <= 5.628 && lng >= -0.190 && lng <= -0.155) {
      return 'Accra Mall & Spanner Junction, Spintex Rd';
    } else if (lat >= 5.580 && lat <= 5.608 && lng >= -0.195 && lng <= -0.165) {
      return 'Airport Residential Area & 37 Military Sector, Accra';
    } else if (lat >= 5.545 && lat <= 5.580 && lng >= -0.190 && lng <= -0.150) {
      return 'Osu & Cantonments Sector, Accra';
    } else if (lat >= 5.530 && lat <= 5.555 && lng >= -0.220 && lng <= -0.190) {
      return 'Makola & Central Business District, Accra';
    } else if (lat >= 5.670 && lat <= 5.730 && lng >= -0.170 && lng <= -0.130) {
      return 'Madina & Adenta Municipal Sector, Accra';
    } else if (lat >= 5.595 && lat <= 5.635 && lng >= -0.245 && lng <= -0.210) {
      return 'Lapaz & Achimota Sector, Accra';
    } else if (lat >= 5.525 && lat <= 5.565 && lng >= -0.265 && lng <= -0.225) {
      return 'Dansoman & Korle Bu Sector, Accra';
    }
    return 'Live GPS Sector (${lat.toStringAsFixed(4)}° N, ${lng.abs().toStringAsFixed(4)}° W)';
  }

  // Per-user SOS history (loaded from UserDataStore)
  List<Map<String, dynamic>> _sosHistory = [];

  // Responder Tracking
  bool _isDispatched = false;
  double? _responderLat;
  double? _responderLng;
  String _responderETA = '';
  String _responderName = '';
  GoogleMapController? _mapController;
  Timer? _simulationTimer;
  Timer? _blinkTimer;
  bool _isRedDotVisible = true;
  BitmapDescriptor? _responderIcon;

  // Sprint B & C State (Jurisdiction, Category Auto-Routing & Dispatch Lifecycle)
  List<Map<String, dynamic>> _statusEvents = [];
  List<String> _routedAgencies = [];
  String? _responderUnitType;
  String? _responderStatus;
  String? _incidentStatus;
  bool _isAcknowledged = false;
  bool _showTimelineExpanded = true;

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
    _loadSosHistory();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
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

  Future<void> _loadSosHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = UserDataStore.instance.userKey;
      final raw = prefs.getString('eaws_sos_history_$userKey');
      if (raw != null) {
        final List decoded = jsonDecode(raw);
        if (mounted) {
          setState(() {
            _sosHistory = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (e) {
      print('Error loading SOS history: $e');
    }
  }

  Future<void> _saveSosEvent(String type, String location, String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = UserDataStore.instance.userKey;
      final newEntry = {
        'type': type,
        'emoji': type.contains('Medical') ? '🚑' : type.contains('Fire') ? '🚒' : '🚓',
        'date': 'Just now',
        'status': status,
        'statusColor': status == 'Resolved' ? 0xFF10B981 : 0xFFF59E0B,
        'responseTime': '—',
        'location': location,
        'createdAt': DateTime.now().toIso8601String(),
      };
      _sosHistory.insert(0, newEntry);
      if (_sosHistory.length > 20) _sosHistory = _sosHistory.sublist(0, 20);
      await prefs.setString('eaws_sos_history_$userKey', jsonEncode(_sosHistory));
      if (mounted) setState(() {});
    } catch (e) {
      print('Error saving SOS event: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loc.latestFix.removeListener(_onLocationFix);
    _loc.readiness.removeListener(_onReadinessChanged);
    _contactsFallbackTimer?.cancel();
    _loc.stop();
    _countdownTimer?.cancel();
    _backgroundTrackingTimer?.cancel();
    _dispatchPollingTimer?.cancel();
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
    // The 10s countdown is the GPS warm-up window (asks for permission if missing).
    _loc.start(foreground: false);

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
    _dispatchPollingTimer?.cancel();
    _dispatchPollingTimer = null;
    _blinkTimer?.cancel();
    _flashController.stop();
    _stopLiveTracking();
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
      _isDispatched = false;
      _responderName = '';
      _responderETA = '';
      _address = 'Acquiring GPS location...';
    });

    // Repeat the red flashing beacon light animation
    _flashController.repeat(reverse: true);

    // 1. Check Internet Connectivity (Offline SMS Fallback)
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == [ConnectivityResult.none] ||
        connectivityResult.contains(ConnectivityResult.none)) {
      await _triggerOfflineSMSFallback();
      return;
    }

    // 2. Best trustworthy fix. The 10s countdown was the GPS warm-up window.
    //    Coordinates are NEVER fabricated: no fix => SOS goes out with
    //    location_status 'pending' and is upgraded the moment GPS locks.
    final LocationFix? fix = await _loc.waitForFix(timeout: const Duration(seconds: 3));
    final double? lat = fix?.latitude;
    final double? lng = fix?.longitude;
    final double? accuracy = fix?.accuracy;

    setState(() {
      _locationPending = fix == null;
      _addressResolved = false;
      _contactsNotified = false;
      _routedToLabel = '';
      _lastSentLat = lat;
      _lastSentLng = lng;
      _lastSentAccuracy = accuracy;
      if (fix != null) {
        _latitude = fix.latitude;
        _longitude = fix.longitude;
        _gpsAccuracy = fix.accuracy;
        _address = _lookupGhanaGeofenceLandmark(fix.latitude, fix.longitude);
      } else {
        // Don't show a stale pin on the map while pending.
        _latitude = null;
        _longitude = null;
        _gpsAccuracy = null;
        _address = 'Acquiring GPS fix (location pending)';
      }
    });

    try {
      // 3. Connect to database backend immediately (do not block on geocoding)
      final sos = await SosApi.instance.createSos(
        latitude: lat,
        longitude: lng,
        accuracy: accuracy,
        locationName: _address,
        locationSource: fix?.source.wire ?? 'none',
        locationFixAt: fix?.timestamp,
      );

      final incident = sos['incident'] ?? sos;
      final returnedId = incident['id']?.toString() ?? incident['incident_id']?.toString();

      setState(() {
        _activeIncidentId = returnedId;
        _routedToLabel = incident['routed_to_label']?.toString() ??
            incident['metadata']?['routed_to_label']?.toString() ??
            '';
      });

      // If backend was unreachable and returned a mock fallback ID, also launch SMS fallback
      final isOfflineMock = returnedId == null || returnedId.startsWith('mock-');
      if (isOfflineMock) {
        print('Backend SOS returned mock ID ($returnedId). Launching SMS Emergency Fallback.');
        await _triggerOfflineSMSFallback();
      }

      // 4. Live tracking via foreground-service GPS stream (survives screen-lock)
      _startBackgroundTracking();
      _startLocationBlink();

      // 5. Notify emergency contacts. With a fix: now. Without: as soon as GPS
      //    locks, or after 20s without coordinates — whichever comes first.
      if (!isOfflineMock) {
        if (fix != null) {
          _notifyContactsOnce(lat, lng);
        } else {
          _contactsFallbackTimer?.cancel();
          _contactsFallbackTimer = Timer(
            const Duration(seconds: 20),
            () => _notifyContactsOnce(null, null),
          );
        }
      }

      // 6. Start real dispatch polling for assigned emergency units
      _startDispatchPolling();

      // 7. Save to local history
      _saveSosEvent(
        _selectedCategory.isNotEmpty ? _selectedCategory : 'Police / Threat',
        _address,
        'Active',
      );

      // 8. Reverse-geocode in background asynchronously
      if (lat != null && lng != null) _resolveAddressAsync(lat, lng);
    } catch (e) {
      print('EAWS SOS API failed ($e). Initiating SMS emergency fallback immediately.');
      setState(() {
        _address = 'Network offline. Launching SMS Emergency Fallback...';
      });
      await _triggerOfflineSMSFallback();
    }
  }

  Future<void> _triggerOfflineSMSFallback() async {
    setState(() {
      _address = 'Offline. Initiating SMS Emergency Fallback...';
    });

    // GPS works without internet. Never substitute fake coordinates.
    _loc.start(foreground: true);
    final LocationFix? fix = await _loc.waitForFix(timeout: const Duration(seconds: 6));
    if (fix != null && mounted) {
      setState(() {
        _latitude = fix.latitude;
        _longitude = fix.longitude;
        _gpsAccuracy = fix.accuracy;
      });
    }

    final String userName = UserSession.instance.displayName;
    final String locationText = fix != null
        ? 'Location: Lat ${fix.latitude.toStringAsFixed(5)}, Lng ${fix.longitude.toStringAsFixed(5)} (+/-${fix.accuracy.toStringAsFixed(0)}m) https://maps.google.com/?q=${fix.latitude},${fix.longitude}'
        : 'Location: GPS not yet available - please call me back to locate me.';
    final String message =
        'EAWS EMERGENCY SOS! $userName has triggered an emergency alert. $locationText. Please respond immediately.';

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline SMS composer pre-populated and launched!'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to launch SMS composer automatically.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _resolveAddressAsync(double lat, double lng) async {
    String resolvedAddress = _lookupGhanaGeofenceLandmark(lat, lng);
    bool geocoded = false;
    _lastGeocodeAt = DateTime.now();
    _lastGeocodeLat = lat;
    _lastGeocodeLng = lng;
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final res = await http.get(url, headers: {
        'User-Agent': 'EAWSMobileApp/1.0 (emergency@eaws.gov.gh)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data != null && data['address'] != null && mounted) {
          final addr = data['address'];
          final poi = addr['amenity'] ?? addr['building'] ?? addr['shop'] ?? addr['office'] ?? '';
          final quarter = addr['suburb'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? '';
          final road = addr['road'] ?? addr['street'] ?? addr['highway'] ?? '';
          final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '';

          List<String> parts = [];
          if (poi.toString().isNotEmpty) parts.add(poi.toString());
          if (quarter.toString().isNotEmpty && !parts.contains(quarter.toString())) parts.add(quarter.toString());
          if (road.toString().isNotEmpty && !parts.contains(road.toString())) parts.add(road.toString());
          if (city.toString().isNotEmpty && !parts.contains(city.toString())) parts.add(city.toString());

          if (parts.isNotEmpty) {
            resolvedAddress = parts.join(', ');
            geocoded = true;
          }
        }
      }
    } catch (e) {
      print('Nominatim reverse geocode lookup: $e');
    }

    if (mounted) {
      setState(() {
        _address = resolvedAddress;
        _addressResolved = geocoded;
      });
      final incId = _activeIncidentId;
      // Only push a real street address; otherwise let the backend resolve the name.
      if (geocoded && incId != null && !incId.startsWith('mock-')) {
        SosApi.instance.updateSosLocation(
          incId,
          latitude: lat,
          longitude: lng,
          accuracy: _gpsAccuracy ?? 10.0,
          locationName: resolvedAddress,
        );
      }
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

  void _startLocationBlink() {
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
  }

  /// Live SOS tracking: upgrades the location stream to an Android foreground
  /// service so updates continue with the screen locked / app backgrounded.
  /// Breadcrumbs are pushed from [_onLocationFix] -> [_pushLiveLocation].
  void _startBackgroundTracking() {
    _backgroundTrackingTimer?.cancel();
    _backgroundTrackingTimer = null;
    _trackingActive = true;
    _loc.start(foreground: true).then((_) {
      // A fix may have arrived while the SOS request was in flight.
      final fix = _loc.latestFix.value;
      if (fix != null && fix.source == FixSource.gps) _pushLiveLocation(fix);
    });
  }

  /// Drops the foreground service but keeps the GPS warm for a quick re-trigger.
  void _stopLiveTracking() {
    _trackingActive = false;
    _contactsFallbackTimer?.cancel();
    _contactsFallbackTimer = null;
    _loc.start(foreground: false);
  }

  void _startDispatchPolling() {
    _dispatchPollingTimer?.cancel();
    _dispatchPollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      final incidentId = _activeIncidentId;
      if (incidentId == null || !_isSOSActive) {
        timer.cancel();
        return;
      }
      try {
        final details = await SosApi.instance.getIncidentDetails(incidentId);
        if (details != null && mounted) {
          final assignments = details['assignments'] as List? ??
              details['incident_assignments'] as List? ??
              [];
          final responses = details['responses'] as List? ?? [];
          final responder = details['responder'] as Map<String, dynamic>?;

          // 1. Extract Jurisdiction & Routing label
          final routedLabel = details['routed_to_label']?.toString() ??
              details['metadata']?['routed_to_label']?.toString();

          // 2. Extract Status Events History
          List<Map<String, dynamic>> parsedEvents = [];
          if (details['status_events'] is List) {
            parsedEvents = (details['status_events'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }

          // 3. Extract Auto-Routed Target Agencies
          final Set<String> targetAgencies = {};
          for (final a in assignments) {
            final ag = a['agency_type']?.toString();
            if (ag != null && ag.isNotEmpty) targetAgencies.add(ag.toLowerCase());
          }
          if (targetAgencies.isEmpty) {
            final cat = (details['category'] ?? details['emergency_type'] ?? _selectedCategory)
                .toString()
                .toLowerCase();
            if (cat.contains('med') || cat.contains('health') || cat.contains('injur')) {
              targetAgencies.add('ambulance');
            } else if (cat.contains('fire') || cat.contains('gas') || cat.contains('burn')) {
              targetAgencies.addAll(['fire', 'ambulance']);
            } else if (cat.contains('flood') || cat.contains('disaster') || cat.contains('collapse')) {
              targetAgencies.addAll(['nadmo', 'fire']);
            } else {
              targetAgencies.add('police');
            }
          }

          // 4. Incident Status, Acknowledged, and En-Route checks
          final incStatus = details['status']?.toString().toLowerCase() ?? 'pending';
          final String firstAssignStatus = assignments.isNotEmpty
              ? (assignments.first['status']?.toString().toLowerCase() ?? 'assigned')
              : '';
          final String respStatus = responder?['status']?.toString().toLowerCase() ?? '';
          final bool isEnRouteStatus =
              ['en_route', 'arrived', 'on_scene', 'transporting', 'in_progress', 'resolved']
                  .contains(firstAssignStatus) ||
              ['en_route', 'arrived', 'on_scene', 'transporting'].contains(respStatus) ||
              ['in_progress', 'en_route', 'arrived', 'resolved'].contains(incStatus);
          final bool ack = isEnRouteStatus ||
              ['acknowledged', 'accepted'].contains(firstAssignStatus) ||
              ['acknowledged', 'accepted'].contains(respStatus) ||
              parsedEvents.any((e) =>
                  e['to_status'] == 'acknowledged' ||
                  e['to_status'] == 'accepted' ||
                  e['to_status'] == 'en_route');

          // 5. Responder Telemetry
          double? nextRespLat = _responderLat;
          double? nextRespLng = _responderLng;
          String unitCallsign = _responderName.isNotEmpty ? _responderName : 'National Rapid Response Unit';
          String? unitType = _responderUnitType;
          String? unitStatus = _responderStatus;
          String etaStr = _responderETA;
          bool dispatched = isEnRouteStatus;

          if (responder != null) {
            final rLat = responder['lat'] != null ? (responder['lat'] as num).toDouble() : null;
            final rLng = responder['lng'] != null ? (responder['lng'] as num).toDouble() : null;
            if (rLat != null && rLng != null && (rLat != 0.0 || rLng != 0.0)) {
              nextRespLat = rLat;
              nextRespLng = rLng;
            }
            if (responder['unit_callsign'] != null) {
              unitCallsign = responder['unit_callsign'].toString();
            }
            unitType = responder['unit_type']?.toString();
            unitStatus = responder['status']?.toString();
            final etaVal = responder['eta_minutes'] ?? details['eta_minutes'];
            if (etaVal != null) {
              final baseEta = etaVal is num ? etaVal.toDouble() : (double.tryParse(etaVal.toString()) ?? 5.0);
              etaStr = '~${baseEta.round()} mins';
            }
          } else if (assignments.isNotEmpty || responses.isNotEmpty) {
            if (assignments.isNotEmpty) {
              final first = assignments.first;
              unitCallsign = first['unit_callsign']?.toString() ??
                  first['agency_type']?.toString().toUpperCase() ??
                  unitCallsign;
              final etaVal = first['eta_minutes'] ?? details['eta_minutes'];
              if (etaVal != null) {
                final baseEta = etaVal is num ? etaVal.toDouble() : (double.tryParse(etaVal.toString()) ?? 6.0);
                final assignedTimeStr = first['assigned_at'];
                int remainingMinutes = baseEta.round();
                if (assignedTimeStr != null) {
                  final assignedDt = DateTime.tryParse(assignedTimeStr.toString());
                  if (assignedDt != null) {
                    final elapsedSecs = DateTime.now().difference(assignedDt).inSeconds;
                    remainingMinutes = (baseEta - (elapsedSecs / 60)).round().clamp(1, 20);
                  }
                }
                etaStr = '~$remainingMinutes mins';
              }
            }
          }

          final bool coordsUpdated = nextRespLat != null &&
              nextRespLng != null &&
              (nextRespLat != _responderLat || nextRespLng != _responderLng);

          setState(() {
            if (routedLabel != null && routedLabel.isNotEmpty) {
              _routedToLabel = routedLabel;
            }
            _statusEvents = parsedEvents;
            _routedAgencies = targetAgencies.toList();
            _incidentStatus = incStatus;
            _isAcknowledged = ack;
            _isDispatched = dispatched;
            _responderName = unitCallsign;
            _responderUnitType = unitType;
            _responderStatus = unitStatus;
            _responderETA = etaStr;
            _responderLat = nextRespLat;
            _responderLng = nextRespLng;
          });

          if (coordsUpdated) {
            _updateMapBounds();
          }
        }
      } catch (e) {
        print('Dispatch polling error: $e');
      }
    });
  }

  Future<void> _stopSOS() async {
    _flashController.stop();
    _backgroundTrackingTimer?.cancel();
    _backgroundTrackingTimer = null;
    _dispatchPollingTimer?.cancel();
    _dispatchPollingTimer = null;
    _blinkTimer?.cancel();
    _stopLiveTracking();
    final incidentId = _activeIncidentId;
    setState(() {
      _isSOSActive = false;
      _isCountingDown = false;
      _activeIncidentId = null;
      _showRecoveryScreen = true;
      _isSilentModeUnlocked = false;
      _enteredPin = '';
      _routedToLabel = '';
      _statusEvents = [];
      _routedAgencies = [];
      _responderStatus = null;
      _responderUnitType = null;
      _incidentStatus = null;
      _isAcknowledged = false;
      _isDispatched = false;
      _responderLat = null;
      _responderLng = null;
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
    // Load per-user SOS history from UserDataStore
    // Shown in initState via _sosHistory state field



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
              // ── 0. GPS readiness (can responders find me?) ───────────────────
              _buildGpsStatusChip(),
              const SizedBox(height: 16),

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
                            _gpsReadiness == GpsReadiness.ready,
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
                      _sosHistory.isEmpty ? 'None' : (_sosHistory.first['date'] ?? 'Just now'),
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
              if (_sosHistory.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'No emergency history yet. Your SOS activations will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ..._sosHistory
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
                                  color: (item['statusColor'] is Color ? (item['statusColor'] as Color) : (item['statusColor'] is int ? Color(item['statusColor'] as int) : const Color(0xFFF59E0B)))
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item['status'],
                                  style: TextStyle(
                                    color: (item['statusColor'] is Color ? (item['statusColor'] as Color) : (item['statusColor'] is int ? Color(item['statusColor'] as int) : const Color(0xFFF59E0B))),
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
                    ,
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
                  const SizedBox(height: 16),
                  _buildGpsStatusChip(onDark: true),
                  const SizedBox(height: 32),

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
                        Text(
                          _isDispatched ? 'HELP IS ON THE WAY' : 'SOS BROADCAST ACTIVE',
                          style: const TextStyle(
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
                                ? (_isDispatched
                                    ? 'Location: $_address\n$_responderName is navigating to your position.'
                                    : _locationPending
                                        ? 'Exact location pending — acquiring GPS.\n112 Command Centre has your alert and may call you to locate you.'
                                        : 'Location: $_address\n${_routedToLabel.isNotEmpty ? 'Routed to $_routedToLabel. ' : ''}Allocating the nearest responders.')
                                : (_latitude != null && _longitude != null
                                    ? 'GPS: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}\nRead coordinates to operator if calling 112.'
                                    : 'GPS not yet available.\nTell the 112 operator a nearby landmark.'),
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
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.65,
                    ),
                    padding: EdgeInsets.only(
                      top: 20,
                      left: 20,
                      right: 20,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    decoration: BoxDecoration(
                      color: showMap ? Colors.white : Colors.transparent,
                      borderRadius: showMap
                          ? const BorderRadius.vertical(
                              top: Radius.circular(28),
                            )
                          : null,
                      boxShadow: showMap
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 20,
                                offset: const Offset(0, -6),
                              ),
                            ]
                          : null,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_activeIncidentId != null) ...[
                            // 1. Dynamic Jurisdiction & Auto-Routing Card (Sprint B)
                            _buildJurisdictionRoutingCard(isLight: showMap),

                            // 2. CAD Dispatch / Responder Telemetry Card (Sprint B & C)
                            Container(
                              padding: const EdgeInsets.all(16),
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
                                          color: (_isDispatched ? AppTheme.successColor : const Color(0xFFF59E0B))
                                              .withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          _isDispatched ? LucideIcons.shieldCheck : LucideIcons.radio,
                                          color: _isDispatched ? AppTheme.successColor : const Color(0xFFF59E0B),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _isDispatched
                                                  ? 'Emergency Unit Dispatched'
                                                  : (_isAcknowledged
                                                      ? 'Officer Acknowledged Case'
                                                      : (_incidentStatus == 'assigned'
                                                          ? 'Unit Assigned — Awaiting Officer'
                                                          : 'SOS Connected to Control Room')),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _isDispatched
                                                  ? '$_responderName is en-route${_responderUnitType != null ? " (${_responderUnitType!.replaceAll('_', ' ').toUpperCase()})" : ""}'
                                                  : (_isAcknowledged
                                                      ? '$_responderName acknowledged — preparing to depart'
                                                      : (_incidentStatus == 'assigned'
                                                          ? 'Assigned to $_responderName — waiting for officer to accept & depart'
                                                          : '112 CAD is evaluating case and dispatching nearest sector unit...')),
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
                                  const Divider(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _isDispatched ? 'Estimated Arrival Time' : 'Dispatch Assignment Status',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        _isDispatched
                                            ? _responderETA
                                            : (_isAcknowledged ? 'CAD Priority Queue' : 'Awaiting CAD Allocation'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _isDispatched ? AppTheme.errorColor : const Color(0xFFD97706),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // 3. Live Dispatch Lifecycle Timeline Widget (Sprint C)
                            _buildDispatchTimeline(isLight: showMap),
                          ] else ...[
                            // Offline SMS Fallback Card
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
                                          color: AppTheme.warningColor.withOpacity(0.1),
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
                                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                            padding: const EdgeInsets.only(top: 4),
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
                          ],

                          const SizedBox(height: 16),

                          if (_activeIncidentId != null) ...[
                            WebRtcVoiceCallWidget(incidentId: _activeIncidentId!),
                            const SizedBox(height: 10),
                          ],

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
                                          content: Text('Could not launch phone dialer'),
                                        ),
                                      );
                                    }
                                  },
                                  icon: Icon(
                                    LucideIcons.phone,
                                    color: showMap ? AppTheme.primaryColor : Colors.white,
                                  ),
                                  label: Text(
                                    'CALL 112',
                                    style: TextStyle(
                                      color: showMap ? AppTheme.primaryColor : Colors.white,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(
                                      color: showMap ? AppTheme.primaryColor : Colors.white,
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
                                    backgroundColor: showMap ? AppTheme.errorColor : Colors.white,
                                    foregroundColor: showMap ? Colors.white : AppTheme.errorColor,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildJurisdictionRoutingCard({required bool isLight}) {
    final String label = _routedToLabel.isNotEmpty
        ? _routedToLabel
        : (_isAcknowledged ? 'Assigned Sector Command' : 'National 112 Command Centre');
    final bool isSpecificStation = _routedToLabel.toLowerCase().contains('command') ||
        _routedToLabel.toLowerCase().contains('metro') ||
        _routedToLabel.toLowerCase().contains('station');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFEFF6FF) : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? const Color(0xFFBFDBFE) : Colors.white24,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSpecificStation ? LucideIcons.mapPin : LucideIcons.globe,
                size: 14,
                color: isLight ? const Color(0xFF1D4ED8) : Colors.lightBlueAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ROUTED DISPATCH JURISDICTION',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold,
                    color: isLight ? const Color(0xFF1E40AF) : Colors.white70,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (_isAcknowledged ? AppTheme.successColor : const Color(0xFFD97706))
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isAcknowledged ? AppTheme.successColor : const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isAcknowledged ? 'ACKNOWLEDGED' : 'ROUTING',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: _isAcknowledged ? AppTheme.successColor : const Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isLight ? const Color(0xFF0F172A) : Colors.white,
            ),
          ),
          if (_routedAgencies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _routedAgencies
                  .map((agency) => _buildAgencyChip(agency, isLight: isLight))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgencyChip(String agency, {required bool isLight}) {
    Color bg;
    Color fg = Colors.white;
    IconData icon;
    String name;

    switch (agency.toLowerCase()) {
      case 'police':
        bg = const Color(0xFF1E3A8A);
        icon = LucideIcons.shield;
        name = 'Ghana Police';
        break;
      case 'ambulance':
        bg = const Color(0xFFDC2626);
        icon = LucideIcons.heart;
        name = 'Ambulance';
        break;
      case 'fire':
        bg = const Color(0xFFEA580C);
        icon = LucideIcons.flame;
        name = 'Fire Service';
        break;
      case 'nadmo':
        bg = const Color(0xFF047857);
        icon = LucideIcons.alertTriangle;
        name = 'NADMO Disaster';
        break;
      default:
        bg = const Color(0xFF475569);
        icon = LucideIcons.radio;
        name = agency.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchTimeline({required bool isLight}) {
    int currentStep = 0;
    if (_activeIncidentId != null) currentStep = 1;
    if (_routedToLabel.isNotEmpty) currentStep = 1;
    if (_isAcknowledged) currentStep = 2;
    if (_isDispatched) currentStep = 3;
    if (_responderStatus == 'on_scene' || _incidentStatus == 'on_scene') currentStep = 4;

    final steps = [
      {
        'title': 'Emergency SOS Broadcasted',
        'subtitle': 'Live GPS telemetry received by CAD',
        'icon': LucideIcons.radio,
      },
      {
        'title': _routedToLabel.isNotEmpty
            ? 'Routed to $_routedToLabel'
            : 'Auto-Routing to Sector Command',
        'subtitle': _routedAgencies.isNotEmpty
            ? 'Auto-dispatched: ${_routedAgencies.map((a) => a.toUpperCase()).join(", ")}'
            : 'Evaluating jurisdiction sector',
        'icon': LucideIcons.mapPin,
      },
      {
        'title': _isAcknowledged
            ? 'Station Control Room Acknowledged'
            : 'Awaiting Station Intake',
        'subtitle': _isAcknowledged
            ? 'Dispatcher confirmed emergency queue'
            : 'Incident in active priority queue (< 60s SLA)',
        'icon': LucideIcons.shieldCheck,
      },
      {
        'title': _isDispatched
            ? '$_responderName Dispatched'
            : 'Unit Assignment in Progress',
        'subtitle': _isDispatched
            ? 'Navigating to your live location ($_responderETA)'
            : 'CAD allocating closest sector unit',
        'icon': LucideIcons.navigation,
      },
    ];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? const Color(0xFFE2E8F0) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE DISPATCH TIMELINE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold,
                  color: isLight ? const Color(0xFF64748B) : Colors.white60,
                ),
              ),
              InkWell(
                onTap: () => setState(() => _showTimelineExpanded = !_showTimelineExpanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showTimelineExpanded ? 'Hide' : 'View steps',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isLight ? AppTheme.primaryColor : Colors.lightBlueAccent,
                        ),
                      ),
                      Icon(
                        _showTimelineExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                        size: 14,
                        color: isLight ? AppTheme.primaryColor : Colors.lightBlueAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showTimelineExpanded) ...[
            const SizedBox(height: 10),
            for (int i = 0; i < steps.length; i++) ...[
              _buildTimelineStep(
                stepIndex: i,
                currentStep: currentStep,
                title: steps[i]['title'] as String,
                subtitle: steps[i]['subtitle'] as String,
                icon: steps[i]['icon'] as IconData,
                isLast: i == steps.length - 1 && _statusEvents.isEmpty,
                isLight: isLight,
              ),
            ],
            if (_statusEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFF1F5F9) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 11,
                      color: isLight ? const Color(0xFF64748B) : Colors.white60,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Audit Log: ${_statusEvents.last['actor_label'] ?? _statusEvents.last['notes'] ?? "Status updated"}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isLight ? const Color(0xFF475569) : Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required int stepIndex,
    required int currentStep,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLast,
    required bool isLight,
  }) {
    final bool isDone = stepIndex < currentStep;
    final bool isCurrent = stepIndex == currentStep;

    final Color dotColor = isDone
        ? AppTheme.successColor
        : (isCurrent ? const Color(0xFF2563EB) : (isLight ? const Color(0xFFCBD5E1) : Colors.white24));

    final Color textColor = isDone || isCurrent
        ? (isLight ? const Color(0xFF0F172A) : Colors.white)
        : (isLight ? const Color(0xFF94A3B8) : Colors.white38);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? AppTheme.successColor
                      : (isCurrent ? const Color(0xFF2563EB) : Colors.transparent),
                  border: Border.all(
                    color: dotColor,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(LucideIcons.checkCircle2, size: 12, color: Colors.white)
                      : (isCurrent
                          ? Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            )
                          : null),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone
                        ? AppTheme.successColor
                        : (isLight ? const Color(0xFFE2E8F0) : Colors.white12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: isLight ? const Color(0xFF64748B) : Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
