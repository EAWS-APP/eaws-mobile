import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../sos/sos_screen.dart';

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

    _initLocationService();
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
    final descriptionController = TextEditingController();
    String selectedCategory = 'Fire & Smoke';
    final categories = ['Fire & Smoke', 'Flooding', 'Medical Emergency', 'Earthquake', 'Hazardous Spill'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Report an Incident',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, color: AppTheme.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Directly notify regional emergency dispatch services. Please supply accurate information.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  
                  const Text('INCIDENT CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.1)),
                  const SizedBox(height: 10),
                  
                  // Category Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        icon: const Icon(LucideIcons.chevronDown),
                        items: categories.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat, style: const TextStyle(fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedCategory = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('DETAILS / DESCRIPTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.1)),
                  const SizedBox(height: 10),
                  
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Describe details (e.g., Fire active on 3rd floor, visible smoke...)',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.normal),
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        HapticFeedback.mediumImpact();
                        
                        // Show success alert
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            icon: const Icon(LucideIcons.checkCircle2, color: AppTheme.successColor, size: 48),
                            title: const Text('Incident Reported Successfully'),
                            content: const Text(
                              'EAWS emergency control has received your report. Response units are processing coordinates.',
                              textAlign: TextAlign.center,
                            ),
                            actions: [
                              Center(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.send),
                      label: const Text('Dispatch Incident Report', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Interactive Action: Share Location Dialog
  void _showShareLocationSheet() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(LucideIcons.mapPin, color: AppTheme.primaryColor),
            SizedBox(width: 10),
            Text('Share Telemetry Location', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your highly precise telemetry coordinates are loaded:',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Latitude: ${_latitude.toStringAsFixed(4)}° ${_latitude >= 0 ? "N" : "S"}', style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('Longitude: ${_longitude.toStringAsFixed(4)}° ${_longitude >= 0 ? "E" : "W"}', style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('Accuracy Radius: ±${_accuracy.toStringAsFixed(1)}m', style: const TextStyle(color: AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: 'EAWS Coordinates: GPS ${_latitude.toStringAsFixed(4)} N, ${_longitude.toStringAsFixed(4)} E. All safe.'));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Coordinates successfully copied to clipboard!'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            },
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('Copy to Share', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Interactive Action: Emergency Contacts Modal Sheet
  void _showEmergencyContactsSheet() {
    final hotlines = [
      {'name': 'National Police Rescue', 'number': '999', 'icon': LucideIcons.shieldCheck},
      {'name': 'Fire & Ambulance', 'number': '995', 'icon': LucideIcons.flame},
      {'name': 'National Security Hotlines', 'number': '1800-2626-262', 'icon': LucideIcons.phoneCall},
      {'name': 'EAWS Support Response', 'number': '+233-26-624-1278', 'icon': LucideIcons.helpCircle},
    ];

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
                    'Emergency Dispatch Hotlines',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hotlines.length,
                  itemBuilder: (context, index) {
                    final line = hotlines[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(line['icon'] as IconData, color: AppTheme.primaryColor, size: 20),
                      ),
                      title: Text(line['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Text(
                        line['number'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          fontSize: 16,
                        ),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        // Mock dial action
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dialing ${line['name']} (${line['number']})...'),
                            backgroundColor: AppTheme.primaryColor,
                          ),
                        );
                      },
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

  // Interactive Action: Offline SMS Sheet
  void _showOfflineSmsSheet() {
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
                    'Offline SOS Message',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Transmit pre-composed telemetry coordinates using SMS networks in areas with no cellular data coverage.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              
              const Text('PRE-FILLED MESSAGE BODY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  'EAWS SOS ALERT:\nMy current GPS is ${_latitude.toStringAsFixed(4)} N, ${_longitude.toStringAsFixed(4)} E ($_currentLocationName).\nI need urgent rescue assistance.',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, height: 1.4),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    HapticFeedback.lightImpact();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Opening native SMS composer...'),
                        backgroundColor: AppTheme.successColor,
                      ),
                    );
                  },
                  icon: const Icon(LucideIcons.messageSquare),
                  label: const Text('Open System Composer', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // Bell Notifications Sheet
  void _showNotificationsSheet() {
    final systemAlerts = [
      {'title': 'High Wind Advisory', 'desc': 'Gusts up to 65 km/h expected in southern regions.', 'time': '42 mins ago', 'warning': true},
      {'title': 'Shelter Opening', 'desc': 'Marina Bay Center is officially open as a storm shelter.', 'time': '2 hrs ago', 'warning': false},
      {'title': 'System Active Check', 'desc': 'EAWS network ping successful on all satellite layers.', 'time': 'Just now', 'warning': false},
    ];

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

  // Evacuation Interactive Map Sheet
  void _showEvacuationMapSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(100)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Interactive Evacuation Routes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x))
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Real-time updates of local civilian shelters and secure evacuation paths.', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 24),

                  // Large Mock Map
                  Container(
                    height: 280,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(16),
                      image: const DecorationImage(
                        image: NetworkImage('https://images.unsplash.com/photo-1524661135-423995f22d0b?w=600&auto=format&fit=crop'),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // pulsing user dot
                        Positioned(
                          left: 100,
                          top: 130,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue.withOpacity(0.3),
                                ),
                              ),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // shelter dot
                        const Positioned(
                          left: 200,
                          top: 80,
                          child: Icon(LucideIcons.shieldCheck, color: AppTheme.primaryColor, size: 28),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('SHELTER DIRECTORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.1)),
                  const SizedBox(height: 12),

                  _buildShelterTile('Marina Bay Community Center', '2.1 km away • 84% capacity', true),
                  const Divider(height: 20),
                  _buildShelterTile('Central Sector Sports Complex', '4.2 km away • 12% capacity', true),
                  const Divider(height: 20),
                  _buildShelterTile('Downtown Underground Shelter C', '0.8 km away • FULL', false),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShelterTile(String name, String detail, bool isOpen) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
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
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(detail, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      ],
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
                              Text('Last updated: just now', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
                            
                            // Concentric container background
                            Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primaryColor.withOpacity(0.08),
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
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        _isSosHolding ? 'HOLDING SOS...' : 'Press and hold for 3 seconds',
                        style: TextStyle(
                          color: _isSosHolding ? AppTheme.primaryColor : AppTheme.textSecondary,
                          fontWeight: _isSosHolding ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
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
                    
                    // High wind warning banner card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: AppTheme.warningColor.withOpacity(0.2), shape: BoxShape.circle),
                                child: const Icon(LucideIcons.wind, color: AppTheme.warningColor),
                              ),
                              const SizedBox(width: 12),
                              const Text('High Wind Advisory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Sustained gusts up to 65 km/h expected in southern areas.', style: TextStyle(fontSize: 14, color: Color(0xFF78350F))),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Time to impact', style: TextStyle(color: Colors.brown[400], fontSize: 12)),
                              const Text('42 min', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF78350F))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: 0.65,
                            backgroundColor: Colors.white,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.warningColor),
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Shelter update info card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(LucideIcons.info, color: Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Shelter Update', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('Marina Bay Centre now open • 2.1 km away', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.chevronRight, color: AppTheme.textSecondary),
                            onPressed: _showEvacuationMapSheet,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Map preview card
                    const Text('Evacuation Map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(16),
                        image: const DecorationImage(
                          image: NetworkImage('https://images.unsplash.com/photo-1524661135-423995f22d0b?w=600&auto=format&fit=crop'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(LucideIcons.navigation, color: AppTheme.primaryColor, size: 18),
                              SizedBox(width: 8),
                              Text('Active shelter: 2.1km away', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
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
                        label: const Text('Open Full Interactive Map', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        _buildActionCard(LucideIcons.contact, 'Emergency Contacts', '5 saved', AppTheme.primaryColor.withOpacity(0.1), AppTheme.primaryColor, _showEmergencyContactsSheet),
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
                      child: const Text(
                        '2',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
