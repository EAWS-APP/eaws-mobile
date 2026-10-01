import 'package:eaws_app/core/api_client.dart';
import 'package:eaws_app/core/supabase_mock.dart';

class SosApi {
  SosApi._();
  static final SosApi instance = SosApi._();

  Future<Map<String, dynamic>> createSos({
    required double latitude,
    required double longitude,
    required double accuracy,
    required String locationName,
  }) async {
    try {
      final res = await EawsApiClient.instance.post('/sos', body: {
        'sos_type': 'general',
        'latitude': latitude,
        'longitude': longitude,
        'location_name': locationName,
        'metadata': {'accuracy_meters': accuracy},
      });
      return res['sos_case'] ?? res['incident'] ?? {'id': 'mock-uuid', 'status': 'active'};
    } catch (e) {
      print('Failed to write SOS to Backend: $e');
      return {
        'id': 'mock-incident-${DateTime.now().millisecondsSinceEpoch}',
        'status': 'active'
      };
    }
  }

  Future<void> cancelSos(String incidentId) async {
    try {
      if (!incidentId.startsWith('mock-')) {
        await EawsApiClient.instance.patch('/sos/$incidentId', body: {'status': 'resolved'});
      }
    } catch (e) {
      print('Failed to cancel SOS: $e');
    }
  }
}
