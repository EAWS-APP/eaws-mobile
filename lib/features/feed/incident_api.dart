import '../../core/api_client.dart';
import '../../core/insforge_client.dart';
import '../../models/incident.dart';
import 'dart:io';

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

    final items = data is List
        ? data
        : (data['incidents'] as List? ?? data['items'] as List? ?? []);
    return items
        .map((item) => Incident.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getCommunityPosts() async {
    final data = await EawsApiClient.instance.get('/community/posts');
    final items = data is List
        ? data
        : (data['posts'] as List? ?? data['items'] as List? ?? []);
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> createCommunityPost(String content) async {
    final data = await EawsApiClient.instance.post(
      '/community/posts',
      body: {'content': content},
    );
    final post = data is Map ? (data['post'] ?? data) : null;
    if (post is! Map) {
      throw const FormatException('Community post response was invalid.');
    }
    return Map<String, dynamic>.from(post);
  }

  Future<Incident> createIncident({
    required String category,
    required String title,
    required String description,
    required bool isAnonymous,
    required String locationName,
    required String clientEventId,
    double? latitude,
    double? longitude,
    String? mediaType,
    bool testPlaceholderMedia = false,
  }) async {
    final data = await EawsApiClient.instance.postWithIdempotencyKey(
      '/incidents',
      idempotencyKey: clientEventId,
      body: {
        'category': category,
        'title': title,
        'description': description,
        'is_anonymous': isAnonymous,
        'severity_confidence': 'unverified',
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        if (mediaType != null) 'media_type': mediaType,
        if (testPlaceholderMedia) 'media_status': 'test_placeholder_only',
      },
    );

    return Incident.fromJson(
      Map<String, dynamic>.from(data['incident'] ?? data),
    );
  }

  Future<void> attachMedia({
    required String incidentId,
    required File file,
    required String mediaType,
  }) async {
    final contentType = mediaType == 'video' ? 'video/mp4' : 'image/jpeg';
    final filename = file.uri.pathSegments.isEmpty
        ? 'evidence'
        : file.uri.pathSegments.last;
    final upload = await InsForgeClient.instance.uploadFile(
      bucket: 'sos_evidence',
      file: file,
      filename: filename,
      contentType: contentType,
    );
    final storagePath = upload['key']?.toString();
    if (storagePath == null || storagePath.isEmpty) {
      throw const FormatException(
        'Evidence storage did not return an object key.',
      );
    }
    await EawsApiClient.instance.post(
      '/incidents/${Uri.encodeComponent(incidentId)}/media',
      body: {
        'media_type': mediaType,
        'storage_bucket': 'sos_evidence',
        'storage_path': storagePath,
        'mime_type': contentType,
        'file_size_bytes': await file.length(),
      },
    );
  }

  Future<void> deleteIncident(String id) {
    return EawsApiClient.instance.delete('/incidents/$id');
  }

  Future<Incident> updateIncident(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final data = await EawsApiClient.instance.patch(
      '/incidents/$id',
      body: payload,
    );
    return Incident.fromJson(
      Map<String, dynamic>.from(data['incident'] ?? data),
    );
  }

  Future<void> react(String id, String type) async {
    await EawsApiClient.instance.post(
      '/community/incidents/$id/reactions',
      body: {'type': type},
    );
  }

  Future<void> addComment(String id, String content) async {
    await EawsApiClient.instance.post(
      '/community/incidents/$id/comments',
      body: {'content': content},
    );
  }

  Future<Map<String, dynamic>> addReply(String id, String content) async {
    final data = await EawsApiClient.instance.post(
      '/community/incidents/$id/comments',
      body: {'content': content},
    );
    final reply = data is Map
        ? (data['comment'] ?? data['reply'] ?? data)
        : null;
    if (reply is! Map) {
      throw const FormatException('Reply response was invalid.');
    }
    return Map<String, dynamic>.from(reply);
  }
}
