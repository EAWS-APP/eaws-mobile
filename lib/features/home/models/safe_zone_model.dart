import 'dart:math';

/// Represents a physical safe-zone / shelter that citizens can evacuate to.
class SafeZoneModel {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String status;       // 'open', 'full', 'closed'
  final int? capacity;       // Total capacity (optional)
  final int? currentCount;   // Current occupancy (optional)
  final DateTime updatedAt;

  const SafeZoneModel({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.status = 'open',
    this.capacity,
    this.currentCount,
    required this.updatedAt,
  });

  /// Construct from a Supabase row (Map).
  factory SafeZoneModel.fromMap(Map<String, dynamic> map) {
    return SafeZoneModel(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? 'Unknown Shelter',
      address: map['address'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'open',
      capacity: map['capacity'] as int?,
      currentCount: map['current_count'] as int?,
      updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isOpen => status.toLowerCase() == 'open';

  /// Calculates the distance in km from the user's current location using
  /// the Haversine formula.
  double distanceFrom(double userLat, double userLon) {
    const earthRadius = 6371.0; // km
    final dLat = _degToRad(latitude - userLat);
    final dLon = _degToRad(longitude - userLon);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(userLat)) *
            cos(_degToRad(latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);
}
