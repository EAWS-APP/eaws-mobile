import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:map_launcher/map_launcher.dart' as ml;
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../sos/sos_screen.dart';
import '../feed/report_incident_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart' hide PermissionStatus;
import 'models/alert_model.dart';
import 'models/safe_zone_model.dart';
import 'services/home_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // SOS hold progress animations
  late AnimationController _sosHoldController;
  bool _isSosHolding = false;
  Timer? _vibrationTimer;

  // Pulse animation for GPS status indicator
  late AnimationController _pulseController;

  // Live System GPS Location State
  String _currentLocationName = 'Locating...';
  double _latitude = 1.3521;
  double _longitude = 103.8198;
  double _accuracy = 3.0;
  bool _locationLoaded = false;

  // Emergency Contacts state
  List<Map<String, dynamic>> _contacts = [];

  // Dynamic Alerts & Safe Zones state
  List<AlertModel> _activeAlerts = [];
  List<SafeZoneModel> _safeZones = [];
  SafeZoneModel? _nearestZone;
  double? _nearestZoneDistance;
  bool _alertsLoading = true;

  // Connectivity state
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();

    _sosHoldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _sosHoldController.addListener(() {
      setState(() {});
    });

    _sosHoldController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _vibrationTimer?.cancel();
        _sosHoldController.reset();
        setState(() {
          _isSosHolding = false;
        });
        _triggerSOS();
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadContacts();
    _initConnectivity();
    _initLocationService();
    _loadAlertsAndZones();
  }

  void _initConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (mounted) {
        setState(() {
          _isOffline = results.every((result) => result == ConnectivityResult.none);
        });
      }
    });
  }

  Future<void> _loadAlertsAndZones() async {
    try {
      final alerts = await HomeService().getActiveAlerts();
      final zones = await HomeService().getSafeZones();

      if (mounted) {
        setState(() {
          _activeAlerts = alerts;
          _safeZones = zones;
          _alertsLoading = false;
        });
      }

      // Calculate nearest zone once we have location
      if (_locationLoaded) {
        _updateNearestZone();
      }
    } catch (e) {
      print('Error loading alerts/zones: $e');
      if (mounted) {
        setState(() {
          _alertsLoading = false;
        });
      }
    }
  }

  void _updateNearestZone() {
    if (_safeZones.isEmpty) return;
    final openZones = _safeZones.where((z) => z.isOpen).toList();
    if (openZones.isEmpty) return;
    openZones.sort((a, b) =>
        a.distanceFrom(_latitude, _longitude).compareTo(b.distanceFrom(_latitude, _longitude)));
    setState(() {
      _nearestZone = openZones.first;
      _nearestZoneDistance = openZones.first.distanceFrom(_latitude, _longitude);
    });
  }

  Future<void> _loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? contactsJson = prefs.getString('eaws_emergency_contacts');
      if (contactsJson != null) {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        setState(() {
          _contacts = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      print('Error loading contacts: $e');
    }
  }

  Future<void> _saveContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eaws_emergency_contacts', jsonEncode(_contacts));
    } catch (e) {
      print('Error saving contacts: $e');
    }
  }

  Future<void> _initLocationService() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _currentLocationName = 'Location services disabled';
        });
        return;
      }

      // Auto-request permission on first load (triggers native iOS dialog)
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _currentLocationName = 'Location permission denied';
          });
          return;
        }
      }
      
      // EAWS specific: escalate to background permissions for SOS tracking
      if (permission == LocationPermission.whileInUse) {
        final status = await Permission.locationAlways.request();
        if (status.isGranted) {
          print('EAWS: Successfully escalated to Background Location Always Allow');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _currentLocationName = 'Location permission restricted';
        });
        return;
      } 

      // Retrieve high accuracy position with timeout and fallback
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
        );
      } catch (e) {
        print('EAWS getCurrentPosition timeout, trying last known: $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        setState(() {
          _currentLocationName = 'Locating...';
        });
        return;
      }

      setState(() {
        _latitude = position!.latitude;
        _longitude = position.longitude;
        _accuracy = position.accuracy;
        _locationLoaded = true;
        _currentLocationName = '${_latitude.toStringAsFixed(4)}\u00B0, ${_longitude.toStringAsFixed(4)}\u00B0';
      });

      // Recalculate nearest safe zone now that we have coordinates
      _updateNearestZone();

      // Query OpenStreetMap Nominatim reverse geocoding API to dynamically translate to city/country
      await _fetchReverseGeocode(_latitude, _longitude);
    } catch (e) {
      print('EAWS Location Service Error: $e');
      setState(() {
        _currentLocationName = 'Location unavailable';
      });
    }
  }

  Future<void> _calibrateGPS() async {
    // Show a premium loading indicator modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: AppTheme.primaryColor),
            SizedBox(height: 20),
            Text(
              'Calibrating High-Accuracy GPS...',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Requesting system sensor permission and satellite lock...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );

    try {
      // 1. Force check & request permission (this will trigger the OS prompt natively)
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) Navigator.pop(context);
        _showErrorDialog('Location Services Disabled', 'Please enable location services in your system settings.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) Navigator.pop(context);
          _showErrorDialog('Permission Denied', 'GPS location permissions were denied by the user.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) Navigator.pop(context);
        _showErrorDialog('Permission Permanently Denied', 'GPS location permissions are permanently disabled. Please grant them in iOS Settings.');
        return;
      }

      // 2. Fetch position with a 10 second timeout & fallback to last known
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        print('EAWS getCurrentPosition timeout/error, fetching last known... $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        if (mounted) Navigator.pop(context);
        _showErrorDialog('GPS Calibration Failed', 'Failed to retrieve coordinates from satellite sensors. Please try again.');
        return;
      }

      setState(() {
        _latitude = position!.latitude;
        _longitude = position.longitude;
        _accuracy = position.accuracy;
        _locationLoaded = true;
        _currentLocationName = '${_latitude.toStringAsFixed(4)}°, ${_longitude.toStringAsFixed(4)}°';
      });

      // 3. Query OpenStreetMap Nominatim reverse geocoding API to dynamically translate to city/country
      await _fetchReverseGeocode(_latitude, _longitude);

      if (mounted) {
        Navigator.pop(context); // Close loading modal
        HapticFeedback.mediumImpact();
        
        // Show success snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.gps_fixed, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'GPS successfully calibrated! Current: $_currentLocationName',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('EAWS Calibration Error: $e');
      if (mounted) {
        Navigator.pop(context);
        _showErrorDialog('GPS Calibration Error', 'An unexpected error occurred while accessing the GPS hardware: $e');
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(LucideIcons.alertTriangle, color: AppTheme.errorColor, size: 40),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _fetchReverseGeocode(double lat, double lon) async {
    try {
      final client = HttpClient();
      client.userAgent = 'EAWS_App/1.0';
      final request = await client.getUrl(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon'),
      );
      final response = await request.close();
      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        final data = json.decode(content);
        final address = data['address'];
        if (address != null) {
          final String city = address['city'] ?? address['town'] ?? address['village'] ?? address['suburb'] ?? address['state'] ?? '';
          final String country = address['country'] ?? '';
          final String name = city.isNotEmpty ? '$city, $country' : country;
          if (name.isNotEmpty) {
            setState(() {
              _currentLocationName = name;
            });
          }
        }
      }
    } catch (e) {
      print('EAWS Geocoding Error: $e');
    }
  }

  @override
  void dispose() {
    _sosHoldController.dispose();
    _pulseController.dispose();
    _vibrationTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Starts tracking user holding down the SOS button
  void _onSosHoldStart() {
    setState(() {
      _isSosHolding = true;
    });
    _sosHoldController.forward();
    
    // Periodically pulse vibration to simulate feedback during hold
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      HapticFeedback.lightImpact();
    });
  }

  // Stops tracking user holding down SOS button (if they release before 3 seconds)
  void _onSosHoldEnd() {
    _vibrationTimer?.cancel();
    if (_sosHoldController.status == AnimationStatus.forward) {
      _sosHoldController.reverse();
    }
    setState(() {
      _isSosHolding = false;
    });
  }

  // Redirect to active SOS screen
  void _triggerSOS() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SOSScreen(startImmediately: true),
      ),
    );
  }

  // Interactive Action: Report Incident Dialog
  void _showReportIncidentSheet() {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReportIncidentScreen(),
      ),
    );
  }

  // Interactive Action: Share Location Dialog
  void _showShareLocationSheet() {
    bool includeGps = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(
              children: [
                // Red header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  decoration: const BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  child: Row(children: [
                    InkWell(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(LucideIcons.chevronLeft, color: Colors.white, size: 20))),
                    const Expanded(child: Column(children: [Text('Share Location', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), SizedBox(height: 2), Text('Send your live position', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12))])),
                    const SizedBox(width: 36),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Map placeholder
                    Container(
                      height: 180, width: double.infinity,
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC8E6C9))),
                      child: Stack(children: [
                        Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(LucideIcons.mapPin, color: AppTheme.primaryColor, size: 32)),
                          const SizedBox(height: 8),
                          Text(_currentLocationName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Accuracy: ±${_accuracy.toStringAsFixed(1)}m · Updated now', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        ])),
                        Positioned(top: 12, left: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(LucideIcons.radio, color: Colors.white, size: 12), SizedBox(width: 4), Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))]))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    // Current Location card
                    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(LucideIcons.mapPin, color: AppTheme.primaryColor, size: 18),
                        const SizedBox(width: 8),
                        const Text('Current Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        GestureDetector(onTap: _calibrateGPS, child: Row(children: const [Icon(LucideIcons.refreshCw, color: AppTheme.primaryColor, size: 14), SizedBox(width: 4), Text('Refresh', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12))])),
                      ]),
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Latitude', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)), Text('${_latitude.toStringAsFixed(4)}° ${_latitude >= 0 ? "N" : "S"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]),
                      const Divider(height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Longitude', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)), Text('${_longitude.toStringAsFixed(4)}° ${_longitude >= 0 ? "E" : "W"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]),
                      const SizedBox(height: 12),
                      Row(children: [const Icon(LucideIcons.mapPin, size: 14, color: AppTheme.textSecondary), const SizedBox(width: 6), Expanded(child: Text(_currentLocationName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)))]),
                    ])),

                    // GPS toggle
                    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(12)), child: Row(children: [
                      const Icon(LucideIcons.navigation, color: AppTheme.primaryColor, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Include GPS Coordinates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text('Exact lat/long in message', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11))])),
                      Switch(value: includeGps, onChanged: (v) => setModalState(() => includeGps = v), activeColor: AppTheme.primaryColor),
                    ])),
                    const SizedBox(height: 24),
                    // Share button
                    SizedBox(width: double.infinity, child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                      onPressed: () {
                        Navigator.pop(context);
                        final msg = includeGps
                            ? 'I\'m sharing my live location via EAWS:\n📍 $_currentLocationName\nLat: ${_latitude.toStringAsFixed(4)}°, Lon: ${_longitude.toStringAsFixed(4)}°\nhttps://maps.google.com/?q=$_latitude,$_longitude'
                            : 'I\'m sharing my location via EAWS:\n📍 $_currentLocationName';
                        Share.share(msg);
                      },
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(LucideIcons.share2, color: Colors.white, size: 18), SizedBox(width: 8), Text('Share My Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white))]),
                    )),
                  ])),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // Interactive Action: Emergency Contacts Modal Sheet
  void _showEmergencyContactsSheet() {

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickContact() async {
              if (_contacts.length >= 5) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 contacts allowed'), backgroundColor: AppTheme.warningColor));
                return;
              }
              try {
                final permissionStatus = await FlutterContacts.permissions.request(PermissionType.readWrite);
                if (permissionStatus == PermissionStatus.granted) {
                  // showPicker returns a contact ID (String?), not a Contact
                  final String? contactId = await FlutterContacts.native.showPicker();
                  if (contactId != null) {
                    // Fetch the full contact with phone numbers
                    final Contact? contact = await FlutterContacts.get(contactId, properties: {ContactProperty.phone});
                    if (contact == null) return;

                    // Try to get phone number
                    String phone = '';
                    if (contact.phones.isNotEmpty) {
                      phone = contact.phones.first.number;
                    }
                    if (phone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected contact has no phone number'), backgroundColor: AppTheme.errorColor));
                      return;
                    }
                    
                    String name = contact.displayName ?? 'Unknown';
                    if (name.isEmpty) name = 'Unknown';
                    String initials = name.trim().split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() : '').take(2).join();
                    if (initials.isEmpty) initials = '?';
                    
                    setModalState(() {
                      _contacts.add({'name': name, 'phone': phone, 'initials': initials});
                    });
                    setState(() {}); // Update the home screen count
                    _saveContacts(); // Persist to disk
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts permission denied'), backgroundColor: AppTheme.errorColor));
                }
              } catch (e) {
                print('Error picking contact: $e');
              }
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(color: Color(0xFFF6F7F9), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                children: [
                  // White Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      InkWell(onTap: () => Navigator.pop(context), child: const Icon(LucideIcons.chevronLeft, color: Colors.black, size: 24)),
                      const Text('SMS Contacts', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                      GestureDetector(onTap: pickContact, child: const Icon(LucideIcons.userPlus, color: AppTheme.primaryColor, size: 24)),
                    ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
                        child: Text('${_contacts.length}/5 Saved', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary)),
                      ),
                      const SizedBox(height: 24),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('EMERGENCY SMS CONTACTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.0)),
                      ]),
                      const SizedBox(height: 12),
                      
                      if (_contacts.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E7EB))),
                          child: Column(
                            children: _contacts.asMap().entries.map((entry) {
                              int idx = entry.key;
                              var c = entry.value;
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(children: [
                                      Container(width: 44, height: 44, decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                                        child: Center(child: Text(c['initials'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)))),
                                      const SizedBox(width: 16),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                                        const SizedBox(height: 4),
                                        Text(c['phone'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                      ])),
                                      GestureDetector(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          setModalState(() {
                                            _contacts.removeAt(idx);
                                          });
                                          setState(() {});
                                          _saveContacts(); // Persist to disk
                                        },
                                        child: const Icon(LucideIcons.trash2, color: Color(0xFFD1D5DB), size: 20),
                                      ),
                                    ]),
                                  ),
                                  if (idx != _contacts.length - 1) const Divider(height: 1, indent: 76, color: Color(0xFFF3F4F6)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      if (_contacts.isEmpty)
                         Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E7EB))),
                          child: Center(child: Column(children: [const Icon(LucideIcons.users, size: 40, color: Color(0xFFD1D5DB)), const SizedBox(height: 12), const Text('No contacts added', style: TextStyle(color: AppTheme.textSecondary))])),
                        ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: pickContact,
                        child: Container(
                          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5), borderRadius: BorderRadius.circular(16)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                            Icon(LucideIcons.userPlus, color: AppTheme.primaryColor, size: 28),
                            SizedBox(height: 12),
                            Text('Add Emergency Contact', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('SMS TEST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.0)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E7EB))),
                        child: Row(children: [
                          Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Color(0xFFFEF2F2), borderRadius: BorderRadius.all(Radius.circular(12))), child: const Icon(LucideIcons.send, color: AppTheme.primaryColor, size: 20)),
                          const SizedBox(width: 16),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                            Text('Send Test SMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                            SizedBox(height: 4),
                            Text('Verify contacts receive alerts', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                          ])),
                          GestureDetector(
                            onTap: () async {
                              HapticFeedback.mediumImpact();
                              if (_contacts.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contacts to test'), backgroundColor: AppTheme.errorColor));
                                return;
                              }
                              String separator = Platform.isAndroid ? ';' : ',';
                              final nums = _contacts.map((e) => e['phone']).join(separator);
                              final encodedBody = Uri.encodeComponent('[EAWS TEST] This is a test emergency message from the EAWS app. You are listed as an emergency contact.');
                              
                              // iOS requires &body= when multiple comma-separated numbers are present
                              String bodyPrefix = Platform.isIOS ? '&body=' : '?body=';
                              final String urlString = 'sms:$nums$bodyPrefix$encodedBody';
                              
                              final smsUri = Uri.parse(urlString);
                              if (await canLaunchUrl(smsUri)) {
                                await launchUrl(smsUri);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open SMS app'), backgroundColor: AppTheme.errorColor));
                              }
                            },
                            child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(border: Border.all(color: AppTheme.primaryColor), borderRadius: BorderRadius.circular(8)), child: const Text('Test', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13))),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(width: double.infinity, child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts saved successfully!'), backgroundColor: AppTheme.successColor));
                        },
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                          Icon(LucideIcons.checkCircle, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Save Contacts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                        ]),
                      )),
                      const SizedBox(height: 24),
                    ])),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Interactive Action: Offline SMS Sheet
  void _showOfflineSmsSheet() {
    bool includeGps = true;
    bool includeProfile = true;
    final smsBody = '[EAWS SOS] User needs emergency help. Location: ${_latitude.toStringAsFixed(4)}°N, ${_longitude.toStringAsFixed(4)}°W.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: const BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  InkWell(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(LucideIcons.chevronLeft, color: Colors.white, size: 20))),
                  const Expanded(child: Text('Offline SMS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 36),
                ]),
              ),
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(LucideIcons.wifiOff, color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('No Internet Detected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
                      Text('SMS fallback mode is active', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),
                const Text('SMS MESSAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))),
                  child: Text(smsBody, style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 20),
                const Text('SENDING TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.0)),
                const SizedBox(height: 12),
                ..._contacts.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(r['initials'] as String, style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 14)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(r['phone'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ])),
                  ]),
                )),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                  onPressed: () {
                    String separator = Platform.isAndroid ? ';' : ',';
                    final nums = _contacts.map((e) => e['phone']).join(separator);
                    final encodedBody = Uri.encodeComponent(smsBody);
                    
                    String bodyPrefix = Platform.isIOS ? '&body=' : '?body=';
                    final String urlString = 'sms:$nums$bodyPrefix$encodedBody';
                    
                    launchUrl(Uri.parse(urlString));
                  },
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Icon(LucideIcons.send, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Send SOS via SMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  ]),
                )),
              ]))),
            ]),
          );
        });
      },
    );
  }

  // Bell Notifications Sheet
  void _showNotificationsSheet() {
    final systemAlerts = _activeAlerts.map((a) => {
      'title': a.title,
      'desc': a.description,
      'time': a.minutesRemaining != null ? 'Impact in ${a.minutesRemaining}m' : 'Active Now',
      'warning': a.severity == AlertSeverity.warning,
    }).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Regional Active Alerts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Clear All', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: systemAlerts.length,
                  itemBuilder: (context, index) {
                    final item = systemAlerts[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (item['warning'] as bool) ? AppTheme.warningColor.withOpacity(0.15) : Colors.blue.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              (item['warning'] as bool) ? LucideIcons.alertTriangle : LucideIcons.info,
                              color: (item['warning'] as bool) ? AppTheme.warningColor : Colors.blue,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text(item['desc'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3)),
                                const SizedBox(height: 4),
                                Text(item['time'] as String, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Evacuation Interactive Map Sheet — now uses real safe zone data
  void _showEvacuationMapSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          maxChildSize: 0.97,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48, height: 5,
                              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(100)),
                            ),
                            const SizedBox(height: 16),
                            const Text('Safe Zone Directory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${_safeZones.where((z) => z.isOpen).length} shelters currently open near you',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                          ],
                        ),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Full Google Map
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 260,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_latitude, _longitude),
                          zoom: 11.5,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        markers: _safeZones.map((zone) {
                          return Marker(
                            markerId: MarkerId(zone.id),
                            position: LatLng(zone.latitude, zone.longitude),
                            infoWindow: InfoWindow(
                              title: zone.name,
                              snippet: zone.isOpen
                                  ? 'OPEN · ${zone.distanceFrom(_latitude, _longitude).toStringAsFixed(1)}km away'
                                  : 'CLOSED',
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              zone.isOpen ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
                            ),
                          );
                        }).toSet(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Shelter directory list
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('SHELTER DIRECTORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.1)),
                  ),
                  const SizedBox(height: 12),
                  
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _safeZones.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      itemBuilder: (context, i) {
                        final zone = _safeZones[i];
                        final distKm = zone.distanceFrom(_latitude, _longitude);
                        final capacityText = zone.capacity != null && zone.currentCount != null
                            ? '${((zone.currentCount! / zone.capacity!) * 100).toStringAsFixed(0)}% full'
                            : 'Open';
                        return _buildShelterTile(zone, distKm, capacityText);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShelterTile(SafeZoneModel zone, double distKm, String detail) {
    final isOpen = zone.isOpen;
    return InkWell(
      onTap: () async {
        // Launch directions to this shelter
        final availableMaps = await ml.MapLauncher.installedMaps;
        if (availableMaps.isNotEmpty) {
          final googleMap = availableMaps.firstWhere(
            (m) => m.mapType == ml.MapType.google,
            orElse: () => availableMaps.first,
          );
          await googleMap.showDirections(
            destination: ml.Coords(zone.latitude, zone.longitude),
            destinationTitle: zone.name,
            origin: ml.Coords(_latitude, _longitude),
            originTitle: 'My Location',
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isOpen ? AppTheme.successColor.withOpacity(0.1) : AppTheme.errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOpen ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${distKm.toStringAsFixed(1)} km away • $detail',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOpen ? AppTheme.successColor.withOpacity(0.08) : AppTheme.errorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    isOpen ? 'OPEN' : 'CLOSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isOpen ? AppTheme.successColor : AppTheme.errorColor,
                    ),
                  ),
                ),
                if (isOpen) ...[
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.chevronRight, color: AppTheme.textSecondary, size: 16),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Alert card builder (color-coded by severity) ──────────────────────────
  Widget _buildAlertCard(AlertModel alert) {
    Color bgColor;
    Color borderColor;
    Color textColor;
    Color iconColor;
    Color progressColor;
    IconData icon;

    switch (alert.severity) {
      case AlertSeverity.warning:
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFCA5A5);
        textColor = const Color(0xFF991B1B);
        iconColor = AppTheme.errorColor;
        progressColor = AppTheme.errorColor;
        icon = LucideIcons.alertOctagon;
        break;
      case AlertSeverity.watch:
        bgColor = const Color(0xFFFFF7ED);
        borderColor = const Color(0xFFFDBA74);
        textColor = const Color(0xFF9A3412);
        iconColor = const Color(0xFFF97316);
        progressColor = const Color(0xFFF97316);
        icon = LucideIcons.alertTriangle;
        break;
      case AlertSeverity.advisory:
      default:
        bgColor = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFFCD34D);
        textColor = const Color(0xFF78350F);
        iconColor = AppTheme.warningColor;
        progressColor = AppTheme.warningColor;
        icon = LucideIcons.wind;
        break;
    }

    return GestureDetector(
      onTap: () => _showAlertDetail(alert),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(alert.title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                ),
                if (alert.severity == AlertSeverity.warning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('URGENT',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.description,
                style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.85))),
            if (alert.minutesRemaining != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Time to impact', style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12)),
                  Text('${alert.minutesRemaining} min',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: alert.urgencyProgress,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
            ],
            if (alert.checklist.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Tap for safety checklist →',
                  style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }

  void _showAlertDetail(AlertModel alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 48, height: 5,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(100)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(alert.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(alert.description, style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.5)),
                  if (alert.checklist.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('SAFETY CHECKLIST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1)),
                    const SizedBox(height: 12),
                    ...alert.checklist.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: Center(child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 13))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                    )),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {

    final String userPhone = AuthService.instance.currentUserPhone ?? '+233 26 624 1278';
    // Clean formatted welcome label (phone number summary)
    final String formattedUser = userPhone.length > 8 ? userPhone.substring(0, 7) + '...' : userPhone;
    final String displayName = AuthService.instance.currentUserName ?? formattedUser;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          // Scrollable Body Content
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Spacer height pushes content down so it sits perfectly below the fixed header,
                  // taking safe area padding into account.
                  SizedBox(height: MediaQuery.of(context).padding.top + 210),
                  

                  // Bottom Form Body Content
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status Telemetry Banner Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.9, end: 1.1).animate(_pulseController),
                                  child: const Icon(LucideIcons.checkCircle, color: AppTheme.successColor),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('All Zones Secure', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text('GPS: ${_latitude.toStringAsFixed(4)}° ${_latitude >= 0 ? "N" : "S"}, ${_longitude.toStringAsFixed(4)}° ${_longitude >= 0 ? "E" : "W"} • ±${_accuracy.toStringAsFixed(0)}m', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(LucideIcons.clock, size: 14, color: AppTheme.textSecondary),
                              const SizedBox(width: 6),
                              const Text('Last updated: just now', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              const Spacer(),
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: _isOffline ? AppTheme.errorColor : AppTheme.successColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(_isOffline ? 'Offline' : 'Online', style: TextStyle(color: _isOffline ? AppTheme.errorColor : AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Giant Hold-to-SOS emergency button
                    Center(
                      child: GestureDetector(
                        onLongPressStart: (_) => _onSosHoldStart(),
                        onLongPressEnd: (_) => _onSosHoldEnd(),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Sweeping outer border showing hold completion build-up
                            SizedBox(
                              width: 230,
                              height: 230,
                              child: CircularProgressIndicator(
                                value: _sosHoldController.value,
                                strokeWidth: 8,
                                backgroundColor: AppTheme.primaryColor.withOpacity(0.08),
                                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                              ),
                            ),
                            
                            // Concentric container background (pulse green if online, static red if offline)
                            ScaleTransition(
                              scale: _isOffline 
                                  ? const AlwaysStoppedAnimation(1.0) 
                                  : Tween<double>(begin: 0.95, end: 1.05).animate(_pulseController),
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isOffline 
                                      ? AppTheme.primaryColor.withOpacity(0.08) 
                                      : AppTheme.successColor.withOpacity(0.12),
                                ),
                              ),
                            ),
                            
                            // Center premium gradient round button
                            AnimatedScale(
                              scale: _isSosHolding ? 0.92 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                width: 170,
                                height: 170,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFEF4444),
                                      Color(0xFFDC2626),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withOpacity(0.4),
                                      blurRadius: _isSosHolding ? 28 : 20,
                                      spreadRadius: _isSosHolding ? 8 : 4,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(LucideIcons.siren, color: Colors.white, size: 44),
                                    SizedBox(height: 8),
                                    Text(
                                      'SOS',
                                      style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1),
                                    ),
                                    Text(
                                      'EMERGENCY',
                                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isOffline ? AppTheme.errorColor.withOpacity(0.1) : AppTheme.successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _isOffline ? AppTheme.errorColor.withOpacity(0.3) : AppTheme.successColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isOffline ? LucideIcons.wifiOff : LucideIcons.radioReceiver, 
                              size: 14, 
                              color: _isOffline ? AppTheme.errorColor : AppTheme.successColor
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOffline ? 'Offline • SMS Fallback Active' : 'Connected • Live Tracking',
                              style: TextStyle(
                                color: _isOffline ? AppTheme.errorColor : AppTheme.successColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _isSosHolding ? 'HOLDING SOS...' : 'Press and hold for 3 seconds',
                        style: TextStyle(
                          color: _isSosHolding ? AppTheme.primaryColor : AppTheme.textSecondary,
                          fontWeight: _isSosHolding ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recent Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: _showNotificationsSheet,
                          child: const Text('View all', style: TextStyle(color: AppTheme.textSecondary)),
                        ),
                      ],
                    ),
                    
                    // ── Dynamic Alert Cards ──
                    if (_alertsLoading)
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(color: AppTheme.primaryColor),
                      ))
                    else if (_activeAlerts.isEmpty)
                      // "All Clear" state — no active alerts
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF6EE7B7).withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.shieldCheck, color: AppTheme.successColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('All Clear', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF065F46))),
                                  const SizedBox(height: 4),
                                  Text(
                                    'No active alerts in your area. EAWS is actively monitoring.',
                                    style: TextStyle(fontSize: 13, color: const Color(0xFF065F46).withOpacity(0.7)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._activeAlerts.map((alert) => _buildAlertCard(alert)),
                    
                    const SizedBox(height: 16),
                    
                    // ── Nearest Safe Zone Card ──
                    GestureDetector(
                      onTap: () async {
                        if (_nearestZone != null) {
                          final availableMaps = await ml.MapLauncher.installedMaps;
                          if (availableMaps.isNotEmpty) {
                            // Prefer Google Maps, fallback to first available
                            final googleMap = availableMaps.firstWhere(
                              (m) => m.mapType == ml.MapType.google,
                              orElse: () => availableMaps.first,
                            );
                            await googleMap.showDirections(
                              destination: ml.Coords(_nearestZone!.latitude, _nearestZone!.longitude),
                              destinationTitle: _nearestZone!.name,
                              origin: ml.Coords(_latitude, _longitude),
                              originTitle: 'My Location',
                            );
                          } else {
                            // Fallback: open Google Maps web URL
                            final url = 'https://www.google.com/maps/dir/?api=1&origin=$_latitude,$_longitude&destination=${_nearestZone!.latitude},${_nearestZone!.longitude}';
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.navigation, color: Color(0xFF16A34A), size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Nearest Safe Zone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _nearestZone != null
                                        ? '${_nearestZone!.name} • ${_nearestZoneDistance?.toStringAsFixed(1)} km away'
                                        : 'Locating nearest shelter...',
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(LucideIcons.mapPin, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Route', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // ── Evacuation Map (Google Maps) ──
                    const Text('Evacuation Map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_latitude, _longitude),
                              zoom: 12.0,
                            ),
                            myLocationEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                            markers: _safeZones.map((zone) {
                              return Marker(
                                markerId: MarkerId(zone.id),
                                position: LatLng(zone.latitude, zone.longitude),
                                infoWindow: InfoWindow(
                                  title: zone.name,
                                  snippet: zone.isOpen ? 'OPEN' : 'CLOSED',
                                ),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  zone.isOpen ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
                                ),
                              );
                            }).toSet(),
                          ),
                          // Overlay label
                          if (_nearestZone != null)
                            Positioned(
                              bottom: 12,
                              left: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.navigation, color: AppTheme.primaryColor, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_nearestZone!.name}: ${_nearestZoneDistance?.toStringAsFixed(1)}km away',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Open map action button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _showEvacuationMapSheet,
                        icon: const Icon(LucideIcons.map),
                        label: const Text('View All Safe Zones', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Quick Action grid cards
                    const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: [
                        _buildActionCard(LucideIcons.flag, 'Report Incident', 'Notify authorities', AppTheme.errorColor.withOpacity(0.1), AppTheme.errorColor, _showReportIncidentSheet),
                        _buildActionCard(LucideIcons.mapPin, 'Share Location', 'Send to contacts', AppTheme.primaryColor.withOpacity(0.1), AppTheme.primaryColor, _showShareLocationSheet),
                        _buildActionCard(LucideIcons.contact, 'Emergency Contacts', '${_contacts.length} saved', AppTheme.primaryColor.withOpacity(0.1), AppTheme.primaryColor, _showEmergencyContactsSheet),
                        _buildActionCard(LucideIcons.messageSquare, 'Offline SMS', 'No signal mode', AppTheme.primaryColor.withOpacity(0.1), AppTheme.primaryColor, _showOfflineSmsSheet),
                      ],
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    
    // Fixed Top Red Header Section (drawn on top of the scrollable content)
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: AppTheme.primaryColor,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          left: 20,
          right: 20,
          bottom: 32,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      // Tap avatar to quickly prompt location copy
                      _showShareLocationSheet();
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: const Icon(LucideIcons.user, color: Colors.white, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(LucideIcons.mapPin, color: Colors.white70, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Current Location',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentLocationName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Hello, $displayName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Stay safe today',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            
            // Notifications bell trigger
            GestureDetector(
              onTap: _showNotificationsSheet,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.bell, color: Colors.white, size: 24),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _activeAlerts.length.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    ),
  ],
),
    );
  }

  Widget _buildActionCard(IconData icon, String title, String subtitle, Color bgColor, Color iconColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
