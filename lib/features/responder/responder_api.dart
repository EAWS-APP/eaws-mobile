import '../../core/api_client.dart';

class ResponderApi {
  ResponderApi._();
  static final ResponderApi instance = ResponderApi._();

  /// Fetches assignments for the officer's agency scoped by region/district
  Future<List<Map<String, dynamic>>> fetchAgencyAssignments(String agencyType) async {
    try {
      final cleanType = agencyType.toLowerCase();
      final res = await EawsApiClient.instance.get('/agencies/$cleanType/assignments');
      if (res is Map && res['assignments'] is List) {
        return List<Map<String, dynamic>>.from(
          (res['assignments'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      print('ResponderApi fetchAgencyAssignments error: $e');
      return [];
    }
  }

  /// Updates an assignment's status (accepted, en_route, on_scene, resolved, declined)
  Future<Map<String, dynamic>?> updateAssignmentStatus(
    String assignmentId, {
    required String status,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': status,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (notes != null && notes.isNotEmpty) 'remarks': notes,
      };

      // Try /incidents/assignments/:id/status first, fallback to /agencies/assignments/:id/status
      dynamic res;
      try {
        res = await EawsApiClient.instance.patch(
          '/incidents/assignments/$assignmentId/status',
          body: body,
        );
      } catch (_) {
        res = await EawsApiClient.instance.patch(
          '/agencies/assignments/$assignmentId/status',
          body: body,
        );
      }

      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      print('ResponderApi updateAssignmentStatus error: $e');
      return null;
    }
  }

  /// Pings unit's live telemetry to POST /api/units/me/location
  /// This feeds the responder_location_updates audit table and recalculates road ETA for the victim.
  Future<bool> sendLocationPing({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? heading,
    double? speedKmh,
    String? assignmentId,
    String? unitId,
  }) async {
    try {
      final body = <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracy,
        'heading': heading,
        'bearing_degrees': heading,
        'speed_kmh': speedKmh,
        if (assignmentId != null) 'assignment_id': assignmentId,
        if (unitId != null) 'unit_id': unitId,
      };

      final res = await EawsApiClient.instance.post(
        '/units/me/location',
        body: body,
      );

      return res is Map && (res['success'] == true || res['status'] == 'success');
    } catch (e) {
      print('ResponderApi sendLocationPing error: $e');
      return false;
    }
  }
}
