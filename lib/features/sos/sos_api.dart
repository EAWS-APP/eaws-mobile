import '../../core/api_client.dart';

const _citizenTestHeaders = {'x-eaws-test-client': 'citizen'};

class SosApi {
  SosApi._();

  static final SosApi instance = SosApi._();

  Future<Map<String, dynamic>> createSos({
    required String clientEventId,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationName,
  }) async {
    final response = await EawsApiClient.instance.postWithIdempotencyKey(
      '/incidents',
      idempotencyKey: clientEventId,
      body: {
        'emergency_type': 'SOS',
        'category': 'SOS',
        'title': 'Emergency SOS',
        'description': 'Citizen triggered emergency SOS broadcast.',
        'is_anonymous': false,
        'location_name': locationName,
        'address': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracy,
        'status': 'sent',
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final incident = response is Map ? response['incident'] ?? response : null;
    if (incident is! Map) {
      throw const FormatException('SOS response did not include an incident.');
    }
    return Map<String, dynamic>.from(incident);
  }

  Future<void> cancelSos(String incidentId) async {
    await EawsApiClient.instance.patch(
      '/incidents/${Uri.encodeComponent(incidentId)}',
      body: {'status': 'retracted', 'action': 'retracted by user'},
    );
  }

  Future<void> reportSafe(String incidentId) async {
    await EawsApiClient.instance.patch(
      '/incidents/${Uri.encodeComponent(incidentId)}',
      body: {
        'citizen_safe': true,
        'action': 'citizen reported safe; operator closure required',
      },
    );
  }

  Future<Map<String, dynamic>> getSos(String incidentId) async {
    final response = await EawsApiClient.instance.get(
      '/incidents/${Uri.encodeComponent(incidentId)}',
    );
    final incident = response is Map ? response['incident'] ?? response : null;
    if (incident is! Map) {
      throw const FormatException('SOS response did not include an incident.');
    }
    return Map<String, dynamic>.from(incident);
  }

  Future<List<Map<String, dynamic>>> getMessages(String incidentId) async {
    final response = await EawsApiClient.instance.get(
      '/incidents/${Uri.encodeComponent(incidentId)}/messages',
      headers: _citizenTestHeaders,
    );
    final messages = response is Map ? response['messages'] : null;
    if (messages is! List) {
      throw const FormatException('Message response was invalid.');
    }
    return messages
        .map((message) => Map<String, dynamic>.from(message as Map))
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage({
    required String incidentId,
    required String content,
    required String clientMessageId,
  }) async {
    final response = await EawsApiClient.instance.post(
      '/incidents/${Uri.encodeComponent(incidentId)}/messages',
      headers: _citizenTestHeaders,
      body: {'content': content, 'client_message_id': clientMessageId},
    );
    final message = response is Map ? response['message'] : null;
    if (message is! Map) {
      throw const FormatException(
        'Message response did not include a message.',
      );
    }
    return Map<String, dynamic>.from(message);
  }

  Future<List<Map<String, dynamic>>> getMessageThreads() async {
    final response = await EawsApiClient.instance.get(
      '/citizen/messages/threads',
      headers: _citizenTestHeaders,
    );
    final threads = response is Map ? response['threads'] : null;
    if (threads is! List) {
      throw const FormatException('Message thread response was invalid.');
    }
    return threads
        .map((thread) => Map<String, dynamic>.from(thread as Map))
        .toList();
  }
}
