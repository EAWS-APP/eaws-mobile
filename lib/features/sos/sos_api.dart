import '../../core/api_client.dart';

class SosApi {
  SosApi._();

  static final SosApi instance = SosApi._();

  Future<Map<String, dynamic>> createSos({
    required double latitude,
    required double longitude,
    required double accuracy,
    required String locationName,
  }) async {
    final data = await EawsApiClient.instance.post(
      '/incidents/sos',
      body: {
        'category': 'SOS',
        'title': 'Emergency SOS',
        'description': 'Citizen triggered emergency SOS broadcast.',
        'is_anonymous': false,
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracy,
      },
    );

    return Map<String, dynamic>.from(data);
  }

  Future<void> cancelSos(String incidentId) async {
    await EawsApiClient.instance.post('/incidents/sos/$incidentId/cancel');
  }
}

