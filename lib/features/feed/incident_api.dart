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
        'severity': ?severity,
        if (distanceKm != null) 'distanceKm': distanceKm.toStringAsFixed(1),
        'time_range': ?timeRange,
        if (sort != null) 'sort': _feedSortKey(sort),
      },
    );

    final items = data is List ? data : (data['incidents'] as List? ?? data['items'] as List? ?? []);
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
      },
    );

    final rawIncident = Map<String, dynamic>.from(data['incident'] ?? data);

    if (mediaUrl != null) {
      try {
        await EawsApiClient.instance.post(
          '/incidents/${rawIncident['id']}/media',
          body: {
            'media_type': mediaType ?? 'image',
            'storage_bucket': 'reports',
            'storage_path': 'mobile_${DateTime.now().millisecondsSinceEpoch}',
            'file_url': mediaUrl,
          },
        );
      } catch (e) {
        print('EAWS media attachment failed, keeping incident without media attachment: $e');
      }
    }

    return Incident.fromJson({
      ...rawIncident,
      'media_url': ?mediaUrl,
      'media_type': ?mediaType,
    });
  }

  Future<void> deleteIncident(String id) {
    return EawsApiClient.instance.delete('/incidents/$id');
  }

  Future<Incident> updateIncident(String id, Map<String, dynamic> payload) async {
    final data = await EawsApiClient.instance.patch('/incidents/$id', body: payload);
    return Incident.fromJson(Map<String, dynamic>.from(data['incident'] ?? data));
  }

  Future<void> react(String id, String type) async {
    await EawsApiClient.instance.post('/community/incidents/$id/reactions', body: {'reaction_type': type});
  }

  Future<void> addComment(String id, String content) async {
    await EawsApiClient.instance.post('/community/incidents/$id/comments', body: {'content': content});
  }

  Future<List<Map<String, dynamic>>> getComments(String id) async {
    final data = await EawsApiClient.instance.get('/community/incidents/$id/comments');
    final items = data is List ? data : (data['comments'] as List? ?? []);
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  String _feedSortKey(String sort) {
    switch (sort.toLowerCase()) {
      case 'most reactions':
      case 'popular':
        return 'popular';
      default:
        return 'recent';
    }
  }

  // ── Community Posts (free-form, not incidents) ──────────────────────────────

  Future<List<Map<String, dynamic>>> getCommunityPosts() async {
    try {
      final data = await EawsApiClient.instance.get('/community/posts');
      final items = data is List ? data : (data['posts'] as List? ?? []);
      return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      print('EAWS Community Posts fetch failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> createCommunityPost({
    required String content,
    String? imageUrl,
  }) async {
    final data = await EawsApiClient.instance.post(
      '/community/posts',
      body: {
        'content': content,
        'image_url': ?imageUrl,
      },
    );
    return Map<String, dynamic>.from(data['post'] ?? data);
  }

  Future<Map<String, dynamic>> addReply(String postId, String content) async {
    final data = await EawsApiClient.instance.post(
      '/community/posts/$postId/replies',
      body: {'content': content},
    );
    return Map<String, dynamic>.from(data['reply'] ?? data);
  }

  // ── Direct Messages (Citizen ↔ Control Room) ─────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(String citizenId) async {
    try {
      final data = await EawsApiClient.instance.get('/messages/$citizenId');
      final items = data is List ? data : (data['messages'] as List? ?? []);
      return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      print('EAWS Messages fetch failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> sendMessage(String citizenId, String text, {String? mediaUrl}) async {
    final data = await EawsApiClient.instance.post(
      '/messages/$citizenId',
      body: {
        'text': text,
        'media_url': ?mediaUrl,
      },
    );
    return Map<String, dynamic>.from(data['message'] ?? data ?? {});
  }
}
