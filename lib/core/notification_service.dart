import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'api_client.dart';
import '../features/responder/responder_screen.dart';
import '../features/sos/sos_screen.dart';

/// Categories of real-time emergency events pushed to the device
enum AlertCategory {
  responderAssignment,
  sosUpdate,
  criticalBroadcast,
}

/// Represents an emergency push notification or in-app CAD broadcast event
class EmergencyAlertEvent {
  final String id;
  final String title;
  final String body;
  final AlertCategory category;
  final String? incidentId;
  final String? assignmentId;
  final String? agencyType;
  final String? callsign;
  final String? status;
  final int? etaMinutes;
  final DateTime timestamp;
  final Map<String, dynamic> rawPayload;

  EmergencyAlertEvent({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    this.incidentId,
    this.assignmentId,
    this.agencyType,
    this.callsign,
    this.status,
    this.etaMinutes,
    DateTime? timestamp,
    this.rawPayload = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  factory EmergencyAlertEvent.fromPayload(Map<String, dynamic> data) {
    final typeStr = data['type']?.toString().toLowerCase() ?? '';
    AlertCategory cat = AlertCategory.criticalBroadcast;
    if (typeStr.contains('assign') || typeStr.contains('dispatch') || typeStr.contains('responder')) {
      cat = AlertCategory.responderAssignment;
    } else if (typeStr.contains('sos') || typeStr.contains('status') || typeStr.contains('en_route')) {
      cat = AlertCategory.sosUpdate;
    }

    return EmergencyAlertEvent(
      id: data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: data['title']?.toString() ?? 'EAWS Emergency Alert',
      body: data['body']?.toString() ?? data['message']?.toString() ?? 'High-priority alert received.',
      category: cat,
      incidentId: data['incident_id']?.toString(),
      assignmentId: data['assignment_id']?.toString(),
      agencyType: data['agency_type']?.toString().toLowerCase(),
      callsign: data['callsign']?.toString() ?? data['unit_callsign']?.toString(),
      status: data['status']?.toString(),
      etaMinutes: data['eta_minutes'] is num ? (data['eta_minutes'] as num).toInt() : null,
      rawPayload: data,
    );
  }
}

/// NotificationService: Centralized device token registrar and emergency dispatch listener
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  GlobalKey<NavigatorState>? navigatorKey;

  String? _deviceToken;
  String? get deviceToken => _deviceToken;

  bool _isRegistered = false;
  bool get isRegistered => _isRegistered;

  DateTime? _lastRegisteredAt;
  DateTime? get lastRegisteredAt => _lastRegisteredAt;

  final StreamController<EmergencyAlertEvent> _alertStreamController =
      StreamController<EmergencyAlertEvent>.broadcast();
  Stream<EmergencyAlertEvent> get onAlertReceived => _alertStreamController.stream;

  final ValueNotifier<EmergencyAlertEvent?> latestAlert = ValueNotifier(null);

  OverlayEntry? _activeOverlayEntry;

  /// Initializes device identifier and attempts backend registration
  Future<void> init({GlobalKey<NavigatorState>? key}) async {
    if (key != null) navigatorKey = key;

    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceToken = prefs.getString('eaws_device_token');

      if (_deviceToken == null || _deviceToken!.isEmpty) {
        _deviceToken = await _generateStableDeviceToken();
        await prefs.setString('eaws_device_token', _deviceToken!);
      }

      final lastRegMillis = prefs.getInt('eaws_device_token_registered_at');
      if (lastRegMillis != null) {
        _lastRegisteredAt = DateTime.fromMillisecondsSinceEpoch(lastRegMillis);
      }

      // Automatically register token with backend in background
      unawaited(registerDeviceToken());
    } catch (e) {
      debugPrint('[NotificationService] Initialization error: $e');
    }
  }

  /// Generates a unique, persistent hardware fingerprint token
  Future<String> _generateStableDeviceToken() async {
    String platform = 'android';
    String hardwareId = 'device-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        platform = 'web';
        hardwareId = '${webInfo.browserName.name}-${webInfo.userAgent.hashCode.abs()}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        platform = 'android';
        hardwareId = '${androidInfo.manufacturer}-${androidInfo.model}-${androidInfo.id}'
            .replaceAll(RegExp(r'\s+'), '-');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        platform = 'ios';
        hardwareId = (iosInfo.identifierForVendor ?? 'ios-device')
            .replaceAll(RegExp(r'\s+'), '-');
      }
    } catch (_) {}

    return 'eaws-tok-$platform-$hardwareId';
  }

  /// Resolves current platform name for backend schema
  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Registers the device token with the backend `POST /api/devices/token`
  Future<bool> registerDeviceToken({bool force = false}) async {
    if (_deviceToken == null) {
      await init();
    }
    if (_deviceToken == null) return false;

    // Throttle repeat calls unless forced (e.g. post-login)
    if (!force && _isRegistered && _lastRegisteredAt != null) {
      final diff = DateTime.now().difference(_lastRegisteredAt!);
      if (diff.inHours < 4) return true;
    }

    try {
      debugPrint('[NotificationService] Registering device token: $_deviceToken ($platformName)...');

      final res = await EawsApiClient.instance.post(
        '/devices/token',
        body: {
          'token': _deviceToken,
          'platform': platformName,
        },
      );

      if (res != null && res['success'] == true) {
        _isRegistered = true;
        _lastRegisteredAt = DateTime.now();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('eaws_device_token_registered_at', _lastRegisteredAt!.millisecondsSinceEpoch);
        debugPrint('[NotificationService] Device token successfully registered with CAD server.');
        return true;
      } else {
        debugPrint('[NotificationService] Device token registration response: $res');
      }
    } catch (e) {
      debugPrint('[NotificationService] Could not sync device token: $e');
    }
    return false;
  }

  /// Dispatches an emergency alert into the app, triggering haptics and the Heads-Up Banner
  void dispatchInAppAlert(EmergencyAlertEvent alert) {
    _alertStreamController.add(alert);
    latestAlert.value = alert;

    // Haptic pulse sequence for high priority
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());

    _showHeadsUpBanner(alert);
  }

  /// Renders a dynamic, tactile emergency Heads-Up Display (HUD) overlay banner
  void _showHeadsUpBanner(EmergencyAlertEvent alert) {
    final overlayState = navigatorKey?.currentState?.overlay;
    if (overlayState == null) return;

    _activeOverlayEntry?.remove();
    _activeOverlayEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _HeadsUpAlertBanner(
        alert: alert,
        onDismiss: () {
          entry.remove();
          if (_activeOverlayEntry == entry) {
            _activeOverlayEntry = null;
          }
        },
        onAction: () {
          entry.remove();
          if (_activeOverlayEntry == entry) {
            _activeOverlayEntry = null;
          }
          _handleAlertNavigation(alert);
        },
      ),
    );

    _activeOverlayEntry = entry;
    overlayState.insert(entry);

    // Auto-dismiss after 12 seconds if untouched
    Future.delayed(const Duration(seconds: 12), () {
      if (_activeOverlayEntry == entry) {
        entry.remove();
        _activeOverlayEntry = null;
      }
    });
  }

  /// Handles action tap routing based on alert category
  void _handleAlertNavigation(EmergencyAlertEvent alert) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    switch (alert.category) {
      case AlertCategory.responderAssignment:
        nav.push(
          MaterialPageRoute(
            builder: (_) => ResponderScreen(
              initialAgency: alert.agencyType ?? 'police',
            ),
          ),
        );
        break;

      case AlertCategory.sosUpdate:
        globalSosActiveNotifier.value = true;
        nav.push(
          MaterialPageRoute(
            builder: (_) => const SOSScreen(),
          ),
        );
        break;

      case AlertCategory.criticalBroadcast:
        // Modal dialog with complete broadcast details
        showDialog(
          context: nav.context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(LucideIcons.alertTriangle, color: Color(0xFFF59E0B), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alert.title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              alert.body,
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ACKNOWLEDGE', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Demo & Field Testing Simulation Triggers
  // ---------------------------------------------------------------------------

  /// Simulates a high-priority CAD case assignment arriving at a field responder device
  void simulateIncomingDispatch({
    String agency = 'police',
    String callsign = 'POL-KMS-04',
    String incidentTitle = 'Armed Robbery in Progress',
    String location = 'Adum Commercial Sector, Kumasi Metro',
  }) {
    dispatchInAppAlert(
      EmergencyAlertEvent(
        id: 'sim-${DateTime.now().millisecondsSinceEpoch}',
        title: '🚨 CAD EMERGENCY ASSIGNMENT',
        body: 'Unit $callsign assigned to "$incidentTitle" at $location. Acknowledge and proceed immediately.',
        category: AlertCategory.responderAssignment,
        agencyType: agency,
        callsign: callsign,
        status: 'assigned',
      ),
    );
  }

  /// Simulates a citizen SOS telemetry update when a responder starts moving
  void simulateCitizenStatusUpdate({
    String status = 'en_route',
    String callsign = 'AMB-KMS-02',
    int etaMinutes = 4,
  }) {
    dispatchInAppAlert(
      EmergencyAlertEvent(
        id: 'sim-citizen-${DateTime.now().millisecondsSinceEpoch}',
        title: '🚑 RESPONDER EN ROUTE',
        body: 'Ambulance Unit $callsign is moving to your location. Estimated arrival in $etaMinutes minutes. Keep your phone active.',
        category: AlertCategory.sosUpdate,
        callsign: callsign,
        status: status,
        etaMinutes: etaMinutes,
      ),
    );
  }

  /// Simulates a national/regional disaster warning broadcast (NADMO/Hydrological)
  void simulateCriticalBroadcast({
    String title = '⚠️ FLASH FLOOD ALERT — KUMASI METRO',
    String message = 'Severe rainfall detected in Subin basin. Rapid flash flooding reported on Harper Road. Move to higher ground.',
  }) {
    dispatchInAppAlert(
      EmergencyAlertEvent(
        id: 'sim-broadcast-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: message,
        category: AlertCategory.criticalBroadcast,
      ),
    );
  }
}

/// Tactical Heads-Up Display Alert Banner Widget
class _HeadsUpAlertBanner extends StatefulWidget {
  final EmergencyAlertEvent alert;
  final VoidCallback onDismiss;
  final VoidCallback onAction;

  const _HeadsUpAlertBanner({
    required this.alert,
    required this.onDismiss,
    required this.onAction,
  });

  @override
  State<_HeadsUpAlertBanner> createState() => _HeadsUpAlertBannerState();
}

class _HeadsUpAlertBannerState extends State<_HeadsUpAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _getHeaderColor() {
    switch (widget.alert.category) {
      case AlertCategory.responderAssignment:
        return const Color(0xFF1E3A8A); // Deep Navy Blue
      case AlertCategory.sosUpdate:
        return const Color(0xFFDC2626); // Emergency Red
      case AlertCategory.criticalBroadcast:
        return const Color(0xFFB45309); // Warning Amber
    }
  }

  IconData _getIcon() {
    switch (widget.alert.category) {
      case AlertCategory.responderAssignment:
        return LucideIcons.radio;
      case AlertCategory.sosUpdate:
        return LucideIcons.navigation;
      case AlertCategory.criticalBroadcast:
        return LucideIcons.alertTriangle;
    }
  }

  String _getActionText() {
    switch (widget.alert.category) {
      case AlertCategory.responderAssignment:
        return 'OPEN RESPONDER TERMINAL';
      case AlertCategory.sosUpdate:
        return 'TRACK UNIT ON MAP';
      case AlertCategory.criticalBroadcast:
        return 'VIEW WARNING DETAILS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: EdgeInsets.fromLTRB(12, topPadding + 6, 12, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _getHeaderColor().withOpacity(0.8), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.55),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: _getHeaderColor().withOpacity(0.35),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      color: _getHeaderColor(),
                      child: Row(
                        children: [
                          Icon(_getIcon(), color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.alert.title.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Text(
                            'NOW',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onDismiss,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.x, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Content Body
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.alert.body,
                            style: const TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          // Action Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: widget.onAction,
                              icon: const Icon(LucideIcons.arrowRight, size: 14),
                              label: Text(
                                _getActionText(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _getHeaderColor(),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
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
        ),
      ),
    );
  }
}
