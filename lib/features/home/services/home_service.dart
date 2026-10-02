import '../../../core/api_client.dart';
import '../models/alert_model.dart';
import '../models/safe_zone_model.dart';

class HomeService {
  static final HomeService _instance = HomeService._internal();
  factory HomeService() => _instance;
  HomeService._internal();

  Future<List<AlertModel>> getActiveAlerts() async {
    final response = await EawsApiClient.instance.get('/alerts');
    final items = response is List
        ? response
        : response is Map
        ? response['alerts'] as List? ?? response['items'] as List? ?? const []
        : const [];
    return items
        .map(
          (item) => AlertModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .where((alert) => alert.isActive)
        .toList();
  }

  Future<List<SafeZoneModel>> getSafeZones() async {
    final response = await EawsApiClient.instance.get('/safe-zones');
    final items = response is List
        ? response
        : response is Map
        ? response['safe_zones'] as List? ??
              response['safeZones'] as List? ??
              response['items'] as List? ??
              const []
        : const [];
    return items
        .map(
          (item) =>
              SafeZoneModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<SafeZoneModel?> getNearestSafeZone(
    double userLat,
    double userLon,
  ) async {
    final zones = await getSafeZones();
    final openZones = zones.where((zone) => zone.isOpen).toList()
      ..sort(
        (a, b) => a
            .distanceFrom(userLat, userLon)
            .compareTo(b.distanceFrom(userLat, userLon)),
      );
    return openZones.isEmpty ? null : openZones.first;
  }
}
