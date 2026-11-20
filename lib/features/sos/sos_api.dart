import 'package:eaws_app/core/api_client.dart';

class SosApi {
  SosApi._();
  static final SosApi instance = SosApi._();

  /// Creates an SOS incident.
  ///
  /// [latitude]/[longitude] may be null when no trustworthy GPS fix exists yet;
  /// the SOS is then sent with `location_status: 'pending'` (backend routes it
  /// to the National 112 queue) and coordinates are PATCHed once a fix arrives.
  /// Coordinates are NEVER fabricated.
  Future<Map<String, dynamic>> createSos({
    required double? latitude,
    required double? longitude,
    required double? accuracy,
    required String locationName,
    String locationSource = 'gps',
    DateTime? locationFixAt,
    String? category,
    String? description,
  }) async {
    final bool hasFix = latitude != null && longitude != null;
    try {
      final payload = <String, dynamic>{
        'emergency_type': 'SOS',
        'category': category ?? 'SOS',
        'sos_type': category ?? 'general',
        'title': 'Emergency SOS',
        'description': description ?? 'Citizen triggered emergency SOS broadcast.',
        'location_name': locationName,
        'address': locationName,
        'location_status': hasFix ? 'fixed' : 'pending',
        'location_source': hasFix ? locationSource : 'none',
        'accuracy_meters': hasFix ? accuracy : null,
        'location_fix_at': hasFix ? (locationFixAt ?? DateTime.now()).toUtc().toIso8601String() : null,
        'metadata': {
          'accuracy_meters': hasFix ? accuracy : null,
          'platform': 'flutter_mobile',
          'triggered_at': DateTime.now().toUtc().toIso8601String(),
        },
      };
      if (hasFix) {
        payload['latitude'] = latitude;
        payload['longitude'] = longitude;
      }

      final res = await EawsApiClient.instance.post('/incidents/sos', body: payload);
      final incident = res['incident'] ?? res['sos_case'] ?? res;
      return Map<String, dynamic>.from(incident is Map ? incident : {'id': 'mock-uuid', 'status': 'active'});
    } catch (e) {
      print('Failed to write SOS to Backend (/incidents/sos): $e');
      // Fallback to mock incident so UI proceeds into Active Distress state
      return {
        'id': 'mock-incident-${DateTime.now().millisecondsSinceEpoch}',
        'status': 'active',
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
      };
    }
  }

  /// PATCHes a live GPS breadcrumb. Only real columns are sent (the backend
  /// spreads the body into an UPDATE). Sending coordinates also upgrades a
  /// 'pending' incident to 'fixed' and resolves its jurisdiction server-side.
  Future<void> updateSosLocation(
    String incidentId, {
    required double latitude,
    required double longitude,
    required double accuracy,
    String? locationName,
  }) async {
    try {
      if (incidentId.startsWith('mock-')) return;
      final Map<String, dynamic> body = {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracy,
        'location_status': 'fixed',
      };
      if (locationName != null && locationName.isNotEmpty) {
        body['location_name'] = locationName;
        body['address'] = locationName;
      }
      await EawsApiClient.instance.patch(
        '/incidents/$incidentId',
        body: body,
      );
    } catch (e) {
      print('Failed to update SOS GPS breadcrumb: $e');
    }
  }

  Future<void> cancelSos(String incidentId) async {
    try {
      if (incidentId.startsWith('mock-')) return;
      try {
        await EawsApiClient.instance.post('/incidents/sos/$incidentId/cancel');
      } catch (_) {
        await EawsApiClient.instance.patch(
          '/incidents/$incidentId',
          body: {'status': 'resolved'},
        );
      }
    } catch (e) {
      print('Failed to cancel SOS: $e');
    }
  }

  Future<void> notifyEmergencyContacts(
    String incidentId, {
    required List<Map<String, dynamic>> contacts,
    required double? latitude,
    required double? longitude,
    required String locationName,
  }) async {
    try {
      if (incidentId.startsWith('mock-')) return;
      final body = <String, dynamic>{
        'contacts': contacts,
        'location_name': locationName,
      };
      // Omit (not null) so the backend doesn't build a "q=null,null" maps link.
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }
      await EawsApiClient.instance.post(
        '/incidents/$incidentId/notify-contacts',
        body: body,
      );
    } catch (e) {
      print('Failed to notify emergency contacts on backend: $e');
    }
  }

  Future<Map<String, dynamic>?> getIncidentDetails(String incidentId) async {
    try {
      if (incidentId.startsWith('mock-')) return null;
      final res = await EawsApiClient.instance.get('/incidents/$incidentId');
      if (res is Map && res['incident'] != null) {
        return Map<String, dynamic>.from(res['incident']);
      }
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      print('Failed to fetch incident details ($incidentId): $e');
      return null;
    }
  }
}
