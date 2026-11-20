import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Readiness of the device to produce a trustworthy GPS fix.
enum GpsReadiness {
  /// Precise permission granted, services on, and a fresh fix is available.
  ready,

  /// Permission + services OK but still waiting for the first fix.
  acquiring,

  /// Location services (GPS toggle) are switched off.
  serviceDisabled,

  /// Permission denied (can be requested again).
  denied,

  /// Permission permanently denied — user must open app settings.
  deniedForever,

  /// Android 12+/iOS 14+ "Approximate location" granted (1–3 km error).
  reducedAccuracy,
}

/// Where a coordinate came from — sent to the backend as `location_source`.
enum FixSource { gps, lastKnown, none }

extension FixSourceWire on FixSource {
  String get wire => switch (this) {
        FixSource.gps => 'gps',
        FixSource.lastKnown => 'last_known',
        FixSource.none => 'none',
      };
}

/// A location fix plus its provenance.
class LocationFix {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double heading;
  final double speed;
  final DateTime timestamp;
  final FixSource source;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.heading = 0.0,
    this.speed = 0.0,
    required this.timestamp,
    required this.source,
  });

  factory LocationFix.fromPosition(Position p, FixSource source) => LocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        heading: p.heading,
        speed: p.speed,
        timestamp: p.timestamp,
        source: source,
      );

  Duration get age => DateTime.now().difference(timestamp);
}

/// Single source of truth for device location across the app.
///
/// Design rules (see MVP_EXECUTION_ROADMAP.md §6 / §10):
///  * NEVER fabricate coordinates. If there is no fix, callers get `null`.
///  * Use a continuous position stream (not periodic one-shot reads) so the
///    GPS chip stays warm and tracking survives screen-lock when the Android
///    foreground service is enabled.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// A last-known fix older than this is not trusted for dispatch.
  static const Duration maxLastKnownAge = Duration(minutes: 5);

  final ValueNotifier<GpsReadiness> readiness =
      ValueNotifier<GpsReadiness>(GpsReadiness.acquiring);
  final ValueNotifier<LocationFix?> latestFix = ValueNotifier<LocationFix?>(null);

  StreamSubscription<Position>? _sub;
  bool _foregroundMode = false;

  /// Checks services + permission + precision, requesting permission if
  /// needed. Updates [readiness] and returns it.
  Future<GpsReadiness> ensureReady({bool requestIfNeeded = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _setReadiness(GpsReadiness.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestIfNeeded) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return _setReadiness(GpsReadiness.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return _setReadiness(GpsReadiness.denied);
      }

      final accuracyStatus = await Geolocator.getLocationAccuracy();
      if (accuracyStatus == LocationAccuracyStatus.reduced) {
        return _setReadiness(GpsReadiness.reducedAccuracy);
      }

      final fix = latestFix.value;
      return _setReadiness(
        fix != null && fix.source == FixSource.gps
            ? GpsReadiness.ready
            : GpsReadiness.acquiring,
      );
    } catch (e) {
      debugPrint('EAWS LocationService.ensureReady error: $e');
      return readiness.value;
    }
  }

  /// Asks the user to upgrade from approximate to precise location.
  /// Android re-shows the system dialog with the "Precise" option; iOS uses a
  /// one-time temporary full-accuracy prompt.
  Future<bool> requestPreciseAccuracy() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        final status = await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: 'EmergencySOS',
        );
        return status == LocationAccuracyStatus.precise;
      }
      await Geolocator.requestPermission();
      final status = await Geolocator.getLocationAccuracy();
      await ensureReady(requestIfNeeded: false);
      return status == LocationAccuracyStatus.precise;
    } catch (e) {
      debugPrint('EAWS requestPreciseAccuracy error: $e');
      return false;
    }
  }

  /// Opens the right settings page for the current [readiness] problem.
  Future<void> openFixSettings() async {
    if (readiness.value == GpsReadiness.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// Starts (or upgrades) the continuous position stream.
  ///
  /// [foreground] = true runs an Android foreground service with a persistent
  /// notification, so tracking continues when the screen is locked or the app
  /// is backgrounded. Use it only while an SOS is active.
  Future<void> start({bool foreground = false}) async {
    if (_sub != null && _foregroundMode == foreground) return;
    await stop();

    final ready = await ensureReady();
    if (ready == GpsReadiness.serviceDisabled ||
        ready == GpsReadiness.denied ||
        ready == GpsReadiness.deniedForever) {
      return;
    }

    // Seed with a fresh last-known fix so the UI isn't empty while the chip warms up.
    await _seedFromLastKnown();

    _foregroundMode = foreground;
    final LocationSettings settings;
    if (!kIsWeb && Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: foreground ? 0 : 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: foreground
            ? const ForegroundNotificationConfig(
                notificationTitle: 'EAWS SOS active',
                notificationText:
                    'Sharing your live location with emergency responders.',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    } else if (!kIsWeb && Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: foreground ? 0 : 5,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: foreground,
        showBackgroundLocationIndicator: foreground,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );
    }

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        latestFix.value = LocationFix.fromPosition(p, FixSource.gps);
        if (readiness.value == GpsReadiness.acquiring) {
          readiness.value = GpsReadiness.ready;
        }
      },
      onError: (Object e) {
        debugPrint('EAWS position stream error: $e');
        // Service toggled off / permission revoked mid-stream.
        ensureReady(requestIfNeeded: false);
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _foregroundMode = false;
  }

  /// Best trustworthy fix available right now, or `null`.
  /// Live GPS beats last-known; stale fixes (> [maxLastKnownAge]) are rejected.
  LocationFix? bestFix() {
    final fix = latestFix.value;
    if (fix == null) return null;
    if (fix.age > maxLastKnownAge) return null;
    return fix;
  }

  /// Waits up to [timeout] for a live GPS fix (useful right before sending).
  Future<LocationFix?> waitForFix({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final current = latestFix.value;
    if (current != null && current.source == FixSource.gps) return current;
    final completer = Completer<LocationFix?>();
    void listener() {
      final f = latestFix.value;
      if (f != null && f.source == FixSource.gps && !completer.isCompleted) {
        completer.complete(f);
      }
    }

    latestFix.addListener(listener);
    try {
      return await completer.future.timeout(timeout, onTimeout: bestFix);
    } finally {
      latestFix.removeListener(listener);
    }
  }

  Future<void> _seedFromLastKnown() async {
    if (latestFix.value != null) return;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp) <= maxLastKnownAge) {
        latestFix.value = LocationFix.fromPosition(last, FixSource.lastKnown);
      }
    } catch (_) {}
  }

  GpsReadiness _setReadiness(GpsReadiness r) {
    readiness.value = r;
    return r;
  }
}
