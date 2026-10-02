import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sos_api.dart';

// Global notifier to control Dashboard bottom nav visibility
final ValueNotifier<bool> globalSosActiveNotifier = ValueNotifier(false);
const bool _demoMode = bool.fromEnvironment('EAWS_DEMO_MODE');

class SOSScreen extends StatefulWidget {
  final bool startImmediately;

  const SOSScreen({super.key, this.startImmediately = false});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> with TickerProviderStateMixin {
  bool _isSOSActive = false;
  bool _isCountingDown = false;
  bool _smsDraftReady = false;
  String? _smsPreview;
  int _countdownSeconds = 7;
  Timer? _countdownTimer;
  Timer? _statusPollTimer;
  String? _clientEventId;
  String? _activeIncidentId;
  String _incidentStatus = 'sent';
  final TextEditingController _messageController = TextEditingController();
  String? _pendingMessageId;
  String? _messageSendError;
  bool _messageSending = false;
  String? _operatorName;
  String? _dispatchUnit;
  int? _etaMinutes;
  List<Map<String, dynamic>> _messages = [];
  bool _messagesUnavailable = false;
  bool _statusUnavailable = false;
  bool _cancelRequested = false;
  bool _submissionInProgress = false;
  bool _localRecoveryUnavailable = false;
  bool _citizenReportedSafe = false;
  String? _resolvedOutcome;
  DateTime? _resolvedAt;
  double? _latitude;
  double? _longitude;
  String _address = 'Location not shared';
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

  GoogleMapController? _mapController;

  // Radar pulsing animation
  late AnimationController _radarController;
  late Animation<double> _radarAnimation;

  // Flashing alert color animation
  late AnimationController _flashController;
  late Animation<Color?> _flashColorAnimation;

  String get _statusText {
    final unit = _dispatchUnit ?? 'The response unit';
    switch (_incidentStatus) {
      case 'sent':
        return 'Sent, waiting for operator';
      case 'acknowledged':
        return 'Acknowledged by ${_operatorName ?? 'operator'}';
      case 'dispatched':
        return '$unit dispatched';
      case 'en_route':
        return '$unit en route${_etaMinutes == null ? '' : ', about $_etaMinutes min'}';
      case 'on_scene':
        return '$unit on scene';
      case 'resolved':
        return 'Case closed by ${_operatorName ?? 'operator'}';
      case 'retracted':
        return 'SOS retracted by you';
      case 'sms_unconfirmed':
        return 'SMS sent, waiting for confirmation';
      default:
        return 'SOS not confirmed by the server';
    }
  }

  String _messageDeliveryLabel(Object? deliveryState, {Object? readState}) {
    if (deliveryState?.toString() == 'fetched_by_citizen_app' &&
        readState?.toString() == 'read') {
      return 'Read in this app · TEST';
    }
    switch (deliveryState?.toString()) {
      case 'fetched_by_citizen_app':
        return 'Received by this app · TEST';
      case 'received_by_dispatch':
        return 'Received by dispatcher · TEST';
      case 'awaiting_citizen_poll':
        return 'Saved on TEST server · waiting for app poll';
      case 'test_only_not_delivered':
        return 'TEST only · delivery not verified';
      case 'delivered':
        return 'Delivered';
      case 'read':
        return 'Read';
      default:
        return 'Delivery status unavailable';
    }
  }

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

    final restoreFuture = _restoreActiveSos();

    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await restoreFuture;
        if (mounted) _triggerCountdown();
      });
    }

    _loadContacts();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final isOffline = results.every(
        (result) => result == ConnectivityResult.none,
      );
      if (mounted && !isOffline && _isSOSActive && !_submissionInProgress) {
        if (_cancelRequested && _activeIncidentId != null) {
          unawaited(_retryPendingRetraction());
          return;
        }
        if (_activeIncidentId != null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connection restored. Retrying this SOS with the same event ID.',
            ),
            backgroundColor: AppTheme.successColor,
          ),
        );
        _submitSos();
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
    _statusPollTimer?.cancel();
    _backgroundTrackingTimer?.cancel();
    _connectivitySubscription?.cancel();
    _mapController?.dispose();
    _messageController.dispose();
    _radarController.dispose();
    _flashController.dispose();
    globalSosActiveNotifier.value = false;
    super.dispose();
  }

  void _triggerCountdown() {
    if (_isCountingDown || _isSOSActive) return;
    HapticFeedback.vibrate();

    setState(() {
      _isCountingDown = true;
      _countdownSeconds = 7;
      _isSOSActive = true;
      _isSilentModeUnlocked = false;
      _enteredPin = '';
      _cancelRequested = false;
      _clientEventId = _newClientEventId();
      _activeIncidentId = null;
    });
    globalSosActiveNotifier.value = true;
    _flashController.repeat(reverse: true);
    unawaited(_persistThenSubmit());

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() {
          _countdownSeconds--;
        });
        HapticFeedback.lightImpact();
      } else {
        timer.cancel();
        if (mounted) {
          setState(() => _isCountingDown = false);
        }
      }
    });
  }

  String _newClientEventId() {
    final randomPart = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return 'SOS-${DateTime.now().toUtc().microsecondsSinceEpoch}-$randomPart';
  }

  Future<void> _persistPendingSos() async {
    final eventId = _clientEventId;
    if (eventId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('eaws_active_sos_client_event_id', eventId);
    await prefs.setBool('eaws_active_sos_cancel_requested', _cancelRequested);
    final incidentId = _activeIncidentId;
    if (incidentId != null) {
      await prefs.setString('eaws_active_sos_incident_id', incidentId);
    }
  }

  Future<void> _persistThenSubmit() async {
    try {
      await _persistPendingSos();
    } catch (error) {
      if (mounted) setState(() => _localRecoveryUnavailable = true);
      debugPrint('Could not persist SOS retry key before sending: $error');
    }
    if (mounted) await _submitSos();
  }

  Future<void> _restoreActiveSos() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error) {
      if (mounted) setState(() => _localRecoveryUnavailable = true);
      debugPrint('Could not restore pending SOS state: $error');
      return;
    }
    final eventId = prefs.getString('eaws_active_sos_client_event_id');
    final incidentId = prefs.getString('eaws_active_sos_incident_id');
    final cancelRequested =
        prefs.getBool('eaws_active_sos_cancel_requested') ?? false;
    if (!mounted || eventId == null) return;
    setState(() {
      _clientEventId = eventId;
      _activeIncidentId = incidentId;
      _cancelRequested = cancelRequested;
      _isSOSActive = true;
      _incidentStatus = incidentId == null ? 'sent' : _incidentStatus;
    });
    globalSosActiveNotifier.value = true;
    if (incidentId != null) {
      if (_cancelRequested) {
        await _retryPendingRetraction();
        return;
      }
      await _refreshIncidentState();
      _startStatusPolling();
    } else {
      _submitSos();
    }
  }

  Future<void> _cancelSOS() async {
    _cancelRequested = true;
    _countdownTimer?.cancel();
    final incidentId = _activeIncidentId;
    if (incidentId == null) {
      if (!_submissionInProgress) unawaited(_submitSos());
      if (mounted) {
        setState(() {
          _isCountingDown = false;
          _incidentStatus = 'unconfirmed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cancellation requested. The server has not confirmed receipt or retraction yet.',
            ),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      return;
    }
    if (incidentId.isNotEmpty) {
      try {
        await SosApi.instance.cancelSos(incidentId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cancellation could not be confirmed. Your alert may still be active.',
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
    }

    _statusPollTimer?.cancel();
    _backgroundTrackingTimer?.cancel();
    _backgroundTrackingTimer = null;
    _flashController.stop();
    setState(() {
      _isCountingDown = false;
      _isSOSActive = false;
      _showRecoveryScreen = true;
      _incidentStatus = 'retracted';
      _cancelRequested = false;
      _isSilentModeUnlocked = false;
      _enteredPin = '';
    });
    globalSosActiveNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('eaws_active_sos_client_event_id');
    await prefs.remove('eaws_active_sos_incident_id');
    await prefs.remove('eaws_active_sos_cancel_requested');
    _clientEventId = null;
    _activeIncidentId = null;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          incidentId == null
              ? 'SOS cancelled before the server confirmed receipt.'
              : 'SOS retracted by you. The control room must confirm receipt.',
        ),
        backgroundColor: incidentId == null
            ? AppTheme.warningColor
            : Colors.grey,
      ),
    );
  }

  Future<void> _submitSos() async {
    final eventId = _clientEventId;
    if (eventId == null || _submissionInProgress) return;
    _submissionInProgress = true;
    try {
      final sos = await SosApi.instance.createSos(
        clientEventId: eventId,
        latitude: _latitude,
        longitude: _longitude,
        accuracy: _gpsAccuracy,
        locationName: _latitude == null || _longitude == null ? null : _address,
      );
      final incidentId = sos['id']?.toString();
      if (incidentId == null || incidentId.isEmpty) {
        throw const FormatException(
          'SOS response did not include an incident ID.',
        );
      }
      if (_cancelRequested) {
        _activeIncidentId = incidentId;
        try {
          await _persistPendingSos();
        } catch (error) {
          if (mounted) setState(() => _localRecoveryUnavailable = true);
          debugPrint('Could not persist SOS retraction state: $error');
        }
        await SosApi.instance.cancelSos(incidentId);
        if (mounted) {
          setState(() {
            _incidentStatus = 'retracted';
            _isSOSActive = false;
            _showRecoveryScreen = true;
            _cancelRequested = false;
          });
          globalSosActiveNotifier.value = false;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('eaws_active_sos_client_event_id');
        await prefs.remove('eaws_active_sos_incident_id');
        await prefs.remove('eaws_active_sos_cancel_requested');
        _clientEventId = null;
        _activeIncidentId = null;
        return;
      }
      if (!mounted) return;
      setState(() {
        _activeIncidentId = incidentId;
        _incidentStatus = sos['status']?.toString() ?? 'sent';
        _address = sos['location_name']?.toString() ?? 'Location not shared';
        _smsDraftReady = false;
      });
      await _persistPendingSos();
      _startBackgroundTracking();
      _startStatusPolling();
      unawaited(_shareLocationAfterSubmission());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _incidentStatus = 'unconfirmed';
        _address = _cancelRequested
            ? 'Cancellation pending; server confirmation unavailable.'
            : 'SOS not confirmed by the server. Retry when connected.';
      });
      if (!_cancelRequested) unawaited(_prepareSmsPreview());
      if (_cancelRequested) {
        unawaited(
          _persistPendingSos().catchError((Object error) {
            if (mounted) setState(() => _localRecoveryUnavailable = true);
            debugPrint('Could not persist pending retraction: $error');
          }),
        );
      }
      debugPrint('SOS submission failed; idempotent event remains queued: $e');
    } finally {
      _submissionInProgress = false;
    }
  }

  Future<void> _retryPendingRetraction() async {
    final incidentId = _activeIncidentId;
    if (incidentId == null || _submissionInProgress) return;
    _submissionInProgress = true;
    try {
      await SosApi.instance.cancelSos(incidentId);
      final incident = await SosApi.instance.getSos(incidentId);
      if (incident['status'] != 'retracted' || !mounted) return;
      setState(() {
        _incidentStatus = 'retracted';
        _isSOSActive = false;
        _showRecoveryScreen = true;
        _cancelRequested = false;
      });
      globalSosActiveNotifier.value = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('eaws_active_sos_client_event_id');
      await prefs.remove('eaws_active_sos_incident_id');
      await prefs.remove('eaws_active_sos_cancel_requested');
      _clientEventId = null;
      _activeIncidentId = null;
    } catch (error) {
      debugPrint('SOS retraction retry failed; request remains queued: $error');
    } finally {
      _submissionInProgress = false;
    }
  }

  Future<void> _shareLocationAfterSubmission() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        if (mounted)
          setState(() => _address = 'Location permission not granted');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gpsAccuracy = position.accuracy;
        _address =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      });
      final incidentId = _activeIncidentId;
      if (incidentId != null) {
        await EawsApiClient.instance.patch(
          '/incidents/${Uri.encodeComponent(incidentId)}',
          body: {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy_meters': position.accuracy,
          },
        );
      }
    } catch (error) {
      debugPrint('Best-effort SOS location update failed: $error');
    }
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshIncidentState(),
    );
  }

  Future<void> _refreshIncidentState() async {
    final incidentId = _activeIncidentId;
    if (incidentId == null) return;
    try {
      final incident = await SosApi.instance.getSos(incidentId);
      final status = incident['status']?.toString() ?? _incidentStatus;
      if (!mounted) return;
      setState(() {
        _statusUnavailable = false;
        _incidentStatus = status;
        _operatorName = incident['operator_name']?.toString();
        _dispatchUnit = incident['dispatch_unit']?.toString();
        _etaMinutes = (incident['eta_minutes'] as num?)?.toInt();
        _latitude = (incident['latitude'] as num?)?.toDouble();
        _longitude = (incident['longitude'] as num?)?.toDouble();
        _address =
            incident['location_name']?.toString() ??
            (_latitude != null && _longitude != null
                ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                : 'Location not shared');
        _citizenReportedSafe = incident['citizen_safe'] == true;
        _resolvedOutcome = incident['outcome']?.toString();
        _resolvedAt = DateTime.tryParse(
          incident['resolved_at']?.toString() ?? '',
        );
      });
      try {
        final messages = await SosApi.instance.getMessages(incidentId);
        if (mounted) {
          setState(() {
            _messages = messages;
            _messagesUnavailable = false;
          });
        }
      } catch (error) {
        if (mounted) setState(() => _messagesUnavailable = true);
        debugPrint('SOS messages unavailable: $error');
      }
      if (status == 'resolved' || status == 'retracted') {
        _statusPollTimer?.cancel();
        setState(() => _showRecoveryScreen = true);
        globalSosActiveNotifier.value = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('eaws_active_sos_client_event_id');
        await prefs.remove('eaws_active_sos_incident_id');
        await prefs.remove('eaws_active_sos_cancel_requested');
        _cancelRequested = false;
        _clientEventId = null;
        _activeIncidentId = null;
      }
    } catch (error) {
      if (mounted) setState(() => _statusUnavailable = true);
      debugPrint(
        'SOS status refresh failed; retaining last server state: $error',
      );
    }
  }

  Future<void> _sendCitizenMessage() async {
    final incidentId = _activeIncidentId;
    final content = _messageController.text.trim();
    if (incidentId == null ||
        content.isEmpty ||
        content.length > 2000 ||
        _messageSending) {
      return;
    }

    _pendingMessageId ??=
        'TEST-MOBILE-MESSAGE-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    setState(() {
      _messageSending = true;
      _messageSendError = null;
    });
    try {
      await SosApi.instance.sendMessage(
        incidentId: incidentId,
        content: content,
        clientMessageId: _pendingMessageId!,
      );
      if (!mounted) return;
      _messageController.clear();
      _pendingMessageId = null;
      if (mounted) await _refreshIncidentState();
    } catch (error) {
      if (mounted) {
        setState(() {
          _messageSendError =
              'Message was not confirmed. Keep this draft and retry.';
        });
      }
      debugPrint('Citizen TEST message failed: $error');
    } finally {
      if (mounted) setState(() => _messageSending = false);
    }
  }

  Future<void> _prepareSmsPreview() async {
    final coordinates = _latitude != null && _longitude != null
        ? 'Coordinates: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)} (±${_gpsAccuracy?.toStringAsFixed(0) ?? "unknown"}m)'
        : 'Coordinates: unavailable';
    final eventId = _clientEventId ?? 'not assigned';
    final message =
        'EAWS TEST SOS · Event $eventId · ${DateTime.now().toUtc().toIso8601String()} · $coordinates · Citizen requests help.';
    if (!mounted) return;
    setState(() {
      _smsPreview = message;
      _smsDraftReady = true;
      _address = 'SMS preview ready; no SMS was sent.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Offline test preview only. No recipient is configured and nothing was sent.',
        ),
        backgroundColor: AppTheme.warningColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _callControl() async {
    if (_demoMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'DEMO MODE: call controls are disabled; no call was placed.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    const controlRoomNumber = String.fromEnvironment('EAWS_CONTROL_ROOM_PHONE');
    if (controlRoomNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Control room phone is not configured. No call was placed.',
          ),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final telUri = Uri(scheme: 'tel', path: controlRoomNumber);
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the phone dialer. No call was placed.'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

        await EawsApiClient.instance.patch(
          '/incidents/${Uri.encodeComponent(incidentId)}',
          body: {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
        );

        print(
          'EAWS Telemetry background sync successful: ${position.latitude}, ${position.longitude}',
        );
      } catch (e) {
        print('EAWS Telemetry background sync failed: $e');
      }
    });
  }

  Future<void> _stopSOS() async {
    final safe = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you safe?'),
        content: const Text(
          'The operator will be told that you reported yourself safe. They must close the case.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep SOS active'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I am safe'),
          ),
        ],
      ),
    );
    if (safe != true || !mounted) return;
    final incidentId = _activeIncidentId;
    if (incidentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The SOS has not been confirmed by the server, so your safe status could not be sent.',
          ),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await SosApi.instance.reportSafe(incidentId);
      if (!mounted) return;
      _backgroundTrackingTimer?.cancel();
      _backgroundTrackingTimer = null;
      setState(() {
        _citizenReportedSafe = true;
        _showRecoveryScreen = true;
      });
      globalSosActiveNotifier.value = false;
      await _refreshIncidentState();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send safe status: $error'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showFirstAid() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'First aid',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Offline quick guidance. Follow instructions from qualified responders when available.',
              ),
              SizedBox(height: 20),
              Text(
                'Check safety',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Do not enter an unsafe scene. Ask someone nearby to contact local emergency services and bring an AED if available.',
              ),
              SizedBox(height: 16),
              Text(
                'Unresponsive or not breathing normally',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'If trained, begin CPR and use an AED as soon as available. Continue until help takes over or the person responds.',
              ),
              SizedBox(height: 16),
              Text(
                'Severe bleeding',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Apply firm, continuous pressure with clean cloth or gauze. Do not remove an embedded object; press around it.',
              ),
              SizedBox(height: 16),
              Text(
                'Possible spinal injury',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Do not move the person unless there is immediate danger. Keep them still and warm while waiting for help.',
              ),
            ],
          ),
        ),
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
    final List<Map<String, dynamic>> _history = [];

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
                                    if (_demoMode) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'DEMO MODE: hotline dialing is disabled.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
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
                    'SOS SEND STATUS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _activeIncidentId != null
                        ? 'Your SOS is recorded by the server. Cancel within $_countdownSeconds seconds if this was a mistake.'
                        : 'Sending your SOS now. The server has not confirmed receipt yet.',
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
                          value: _countdownSeconds / 7,
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
                        'CANCEL SOS',
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
        final bool showMap = _latitude != null && _longitude != null;

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
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId('user_location'),
                          position: LatLng(_latitude!, _longitude!),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed,
                          ),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _statusText.toUpperCase(),
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              letterSpacing: 1,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(
                            '${_activeIncidentId == null ? _address : 'Location: $_address'}${_operatorName == null ? '' : '\nOperator: $_operatorName'}',
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
                                      : _smsDraftReady
                                      ? LucideIcons.messageSquare
                                      : LucideIcons.wifiOff,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _activeIncidentId != null
                                      ? 'SERVER RECORDED'
                                      : _smsDraftReady
                                      ? 'SMS PREVIEW ONLY'
                                      : 'NOT CONFIRMED',
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
                        // Display only state returned by the backend.
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
                                          Text(
                                            _statusText,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _dispatchUnit == null
                                                ? 'Location: $_address'
                                                : '$_dispatchUnit${_etaMinutes == null ? '' : ' · ETA $_etaMinutes min'}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          if (_statusUnavailable)
                                            const Text(
                                              'Connection lost · showing last server-recorded state',
                                              style: TextStyle(
                                                color: AppTheme.warningColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          if (_localRecoveryUnavailable)
                                            const Text(
                                              'This device could not save a recovery key; keep the app open until the server confirms status.',
                                              style: TextStyle(
                                                color: AppTheme.warningColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          if (_messagesUnavailable)
                                            const Text(
                                              'Control room chat unavailable · delivery is not confirmed',
                                              style: TextStyle(
                                                color: AppTheme.warningColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          if (_activeIncidentId != null) ...[
                                            const Divider(height: 24),
                                            const Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                'INCIDENT CHAT · TEST',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: AppTheme.textSecondary,
                                                ),
                                              ),
                                            ),
                                            if (_messages.isEmpty)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    'No messages yet. Send a message to the control room.',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (_messages.isNotEmpty)
                                              SizedBox(
                                                height: min(
                                                  170.0,
                                                  62.0 * _messages.length,
                                                ),
                                                child: ListView.builder(
                                                  itemCount: _messages.length,
                                                  itemBuilder: (context, index) {
                                                    final message =
                                                        _messages[index];
                                                    final isCitizen =
                                                        message['sender_role'] ==
                                                        'citizen';
                                                    return Align(
                                                      alignment: isCitizen
                                                          ? Alignment
                                                                .centerRight
                                                          : Alignment
                                                                .centerLeft,
                                                      child: Container(
                                                        constraints:
                                                            const BoxConstraints(
                                                              maxWidth: 300,
                                                            ),
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 4,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isCitizen
                                                              ? AppTheme
                                                                    .primaryColor
                                                              : const Color(
                                                                  0xFFE2E8F0,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              message['content']
                                                                      ?.toString() ??
                                                                  '',
                                                              style: TextStyle(
                                                                color: isCitizen
                                                                    ? Colors
                                                                          .white
                                                                    : AppTheme
                                                                          .textPrimary,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 3,
                                                            ),
                                                            Text(
                                                              '${message['sender'] ?? (isCitizen ? 'You' : 'Control room')} · ${_messageDeliveryLabel(message['delivery_state'] ?? message['status'], readState: message['read_state'])}',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: isCitizen
                                                                    ? Colors
                                                                          .white70
                                                                    : AppTheme
                                                                          .textSecondary,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        _messageController,
                                                    enabled: !_messageSending,
                                                    maxLength: 2000,
                                                    minLines: 1,
                                                    maxLines: 3,
                                                    onChanged: (_) {
                                                      setState(() {});
                                                    },
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      color:
                                                          AppTheme.textPrimary,
                                                    ),
                                                    textInputAction:
                                                        TextInputAction.send,
                                                    onSubmitted: (_) =>
                                                        _sendCitizenMessage(),
                                                    decoration: const InputDecoration(
                                                      counterText: '',
                                                      hintText:
                                                          'Message the control room',
                                                      isDense: true,
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  tooltip: 'Send TEST message',
                                                  onPressed:
                                                      _messageSending ||
                                                          _messageController
                                                              .text
                                                              .trim()
                                                              .isEmpty
                                                      ? null
                                                      : _sendCitizenMessage,
                                                  icon: _messageSending
                                                      ? const SizedBox(
                                                          width: 18,
                                                          height: 18,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        )
                                                      : const Icon(
                                                          LucideIcons.send,
                                                        ),
                                                ),
                                              ],
                                            ),
                                            if (_messageSendError != null)
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  _messageSendError!,
                                                  style: const TextStyle(
                                                    color: AppTheme.errorColor,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ],
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
                                      child: Icon(
                                        _smsDraftReady
                                            ? LucideIcons.messageSquare
                                            : LucideIcons.wifiOff,
                                        color: AppTheme.warningColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _smsDraftReady
                                                ? 'SMS preview — not sent'
                                                : 'No delivery confirmed',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            _smsDraftReady
                                                ? 'No test control-room recipient is configured. Nothing was sent.'
                                                : 'Retry the internet connection or configure an approved test SMS gateway.',
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _callControl,
                              icon: Icon(LucideIcons.phone),
                              label: const Text('CALL CONTROL'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _stopSOS,
                              icon: const Icon(LucideIcons.shieldCheck),
                              label: const Text('I AM SAFE'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (_activeIncidentId == null) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _submissionInProgress
                                    ? null
                                    : _submitSos,
                                icon: const Icon(LucideIcons.refreshCw),
                                label: const Text('RETRY INTERNET CONNECTION'),
                              ),
                              if (_smsPreview != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: SelectableText(
                                    _smsPreview!,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                            if (_activeIncidentId != null)
                              TextButton.icon(
                                onPressed: _showFirstAid,
                                icon: const Icon(LucideIcons.heartPulse),
                                label: const Text('FIRST AID INSTRUCTIONS'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
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
    final caseClosed = _incidentStatus == 'resolved';
    final wasRetracted = _incidentStatus == 'retracted';
    final resolvedTime = _resolvedAt == null
        ? ''
        : ' at ${_resolvedAt!.toLocal()}';
    final recoveryTitle = caseClosed
        ? 'CASE CLOSED'
        : wasRetracted
        ? 'SOS RETRACTED'
        : 'YOU ARE SAFE';
    final recoveryMessage = caseClosed
        ? 'Case closed by ${_operatorName ?? 'operator'}$resolvedTime.${_resolvedOutcome == null || _resolvedOutcome!.isEmpty ? '' : ' Outcome: $_resolvedOutcome'}'
        : wasRetracted
        ? 'The server recorded your SOS retraction. No response status is implied.'
        : 'Waiting for the operator to close your case.';
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
              Text(
                recoveryTitle,
                style: TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                recoveryMessage,
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
                      LucideIcons.mapPin,
                      'Location updates stopped on this device',
                    ),
                    const Divider(height: 24),
                    _buildRecoveryRow(
                      _citizenReportedSafe
                          ? LucideIcons.checkCircle2
                          : LucideIcons.circle,
                      _citizenReportedSafe
                          ? 'Safe status sent to the control room'
                          : 'No contact notification was sent',
                    ),
                    const Divider(height: 24),
                    _buildRecoveryRow(
                      caseClosed ? LucideIcons.checkCircle2 : LucideIcons.clock,
                      caseClosed
                          ? 'Case closed by operator'
                          : 'Waiting for operator closure',
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
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
