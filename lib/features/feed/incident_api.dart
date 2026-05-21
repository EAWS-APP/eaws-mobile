import '../../core/api_client.dart';
import '../../models/incident.dart';

class IncidentApi {
  IncidentApi._();

  static final IncidentApi instance = IncidentApi._();

  Future<List<Incident>> getFeed({
    String? category,
    String? severity,
    double? distanceKm,
    String? timeRange,
    String? sort,
  }) async {
    final data = await EawsApiClient.instance.get(
      '/incidents/feed',
      query: {
        if (category != null && category != 'All') 'category': category,
        if (severity != null) 'severity': severity,
        if (distanceKm != null) 'distance_km': distanceKm.toStringAsFixed(1),
        if (timeRange != null) 'time_range': timeRange,
        if (sort != null) 'sort': sort,
      },
    );

    final items = data is List ? data : (data['items'] as List? ?? []);
    return items.map((item) => Incident.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  Future<Incident> createIncident({
    required String category,
    required String title,
    required String description,
    required bool isAnonymous,
    required String locationName,
    required double latitude,
    required double longitude,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final data = await EawsApiClient.instance.post(
      '/incidents',
      body: {
        'category': category,
        'title': title,
        'description': description,
        'is_anonymous': isAnonymous,
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
      },
    );

    return Incident.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deleteIncident(String id) {
    return EawsApiClient.instance.delete('/incidents/$id');
  }

  Future<Incident> updateIncident(String id, Map<String, dynamic> payload) async {
    final data = await EawsApiClient.instance.patch('/incidents/$id', body: payload);
    return Incident.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> react(String id, String type) async {
    await EawsApiClient.instance.post('/community/incidents/$id/reactions', body: {'type': type});
  }

  Future<void> addComment(String id, String content) async {
    await EawsApiClient.instance.post('/community/incidents/$id/comments', body: {'content': content});
  }
}

