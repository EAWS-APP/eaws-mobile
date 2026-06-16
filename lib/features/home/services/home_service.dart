import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/alert_model.dart';
import '../models/safe_zone_model.dart';

/// Service responsible for fetching live alerts and safe-zone data
/// from the Supabase backend, with built-in mock-data fallbacks.
class HomeService {
  static final HomeService _instance = HomeService._internal();
  factory HomeService() => _instance;
  HomeService._internal();

  final _supabase = Supabase.instance.client;

  // ──────────────────────────── ALERTS ────────────────────────────

  /// Fetch active alerts from Supabase. Falls back to mock data
  /// if the table does not exist or the query fails.
  Future<List<AlertModel>> getActiveAlerts() async {
    try {
      final response = await _supabase
          .from('alerts')
          .select()
          .order('created_at', ascending: false);

      if (response.isEmpty) return [];

      return (response as List)
          .map((e) => AlertModel.fromMap(e))
          .where((a) => a.isActive)
          .toList();
    } catch (e) {
      print('EAWS HomeService: alerts table not available, using fallback – $e');
      return _mockAlerts();
    }
  }

  // ──────────────────────────── SAFE ZONES ────────────────────────

  /// Fetch safe zones from Supabase. Falls back to Accra-area mock
  /// shelters if the table does not exist.
  Future<List<SafeZoneModel>> getSafeZones() async {
    try {
      final response = await _supabase
          .from('safe_zones')
          .select()
          .order('name', ascending: true);

      if (response.isEmpty) return _mockSafeZones();

      return (response as List)
          .map((e) => SafeZoneModel.fromMap(e))
          .toList();
    } catch (e) {
      print('EAWS HomeService: safe_zones table not available, using fallback – $e');
      return _mockSafeZones();
    }
  }

  /// Returns the nearest open safe zone given the user's current position.
  Future<SafeZoneModel?> getNearestSafeZone(double userLat, double userLon) async {
    final zones = await getSafeZones();
    final openZones = zones.where((z) => z.isOpen).toList();
    if (openZones.isEmpty) return null;

    openZones.sort((a, b) =>
        a.distanceFrom(userLat, userLon).compareTo(b.distanceFrom(userLat, userLon)));

    return openZones.first;
  }

  // ────────────────────── MOCK DATA FALLBACKS ────────────────────

  List<AlertModel> _mockAlerts() {
    return [
      // Return empty – "All Clear" state shown by default
    ];
  }

  List<SafeZoneModel> _mockSafeZones() {
    // Real shelters and community centers in Accra, Ghana
    return [
      SafeZoneModel(
        id: 'sz-1',
        name: 'Accra Sports Stadium Shelter',
        address: 'Liberation Rd, Accra',
        latitude: 5.5494,
        longitude: -0.1876,
        status: 'open',
        capacity: 500,
        currentCount: 42,
        updatedAt: DateTime.now(),
      ),
      SafeZoneModel(
        id: 'sz-2',
        name: 'National Theatre Relief Centre',
        address: 'Independence Ave, Accra',
        latitude: 5.5471,
        longitude: -0.2037,
        status: 'open',
        capacity: 300,
        currentCount: 18,
        updatedAt: DateTime.now(),
      ),
      SafeZoneModel(
        id: 'sz-3',
        name: 'University of Ghana Safe Point',
        address: 'Legon Campus, Accra',
        latitude: 5.6505,
        longitude: -0.1862,
        status: 'open',
        capacity: 800,
        currentCount: 5,
        updatedAt: DateTime.now(),
      ),
      SafeZoneModel(
        id: 'sz-4',
        name: 'Korle-Bu Teaching Hospital',
        address: 'Guggisberg Ave, Accra',
        latitude: 5.5348,
        longitude: -0.2267,
        status: 'open',
        capacity: 200,
        currentCount: 90,
        updatedAt: DateTime.now(),
      ),
      SafeZoneModel(
        id: 'sz-5',
        name: 'Tema Community Centre',
        address: 'Tema, Greater Accra',
        latitude: 5.6698,
        longitude: -0.0166,
        status: 'open',
        capacity: 350,
        currentCount: 12,
        updatedAt: DateTime.now(),
      ),
    ];
  }
}
