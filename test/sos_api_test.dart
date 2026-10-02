import 'dart:convert';

import 'package:eaws_app/features/sos/sos_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eaws_app/core/api_client.dart';

void main() {
  test('SOS creation propagates backend initialization failures', () async {
    EawsApiClient.instance.configureForTesting(
      baseUrl: 'https://test.invalid/api',
      httpClient: MockClient(
        (_) async => http.Response('test backend unavailable', 503),
      ),
    );
    await expectLater(
      SosApi.instance.createSos(
        clientEventId: 'TEST-SOS-EVENT-001',
        latitude: 5.6,
        longitude: -0.2,
        accuracy: 5,
        locationName: 'Test location',
      ),
      throwsA(anything),
    );
  });

  test('SOS creation sends an unconfirmed idempotent event', () async {
    Map<String, dynamic>? requestBody;
    EawsApiClient.instance.configureForTesting(
      baseUrl: 'https://test.invalid/api',
      httpClient: MockClient((request) async {
        requestBody = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map<String, dynamic>,
        );
        return http.Response(
          jsonEncode({
            'incident': {
              'id': 'TEST-INC-0001',
              'status': 'sent',
              'client_event_id': 'TEST-SOS-EVENT-001',
            },
          }),
          201,
        );
      }),
    );

    final incident = await SosApi.instance.createSos(
      clientEventId: 'TEST-SOS-EVENT-001',
      latitude: 5.6,
      longitude: -0.2,
    );

    expect(requestBody?['client_event_id'], 'TEST-SOS-EVENT-001');
    expect(requestBody?['status'], 'sent');
    expect(incident['id'], 'TEST-INC-0001');
    expect(incident['status'], 'sent');
  });

  test(
    'citizen chat reads and writes are scoped to the TEST citizen client',
    () async {
      final requests = <http.Request>[];
      EawsApiClient.instance.configureForTesting(
        baseUrl: 'http://127.0.0.1:5001/api',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET' &&
              request.url.path.endsWith('/messages/threads')) {
            return http.Response(
              jsonEncode({
                'threads': [
                  {
                    'incident_id': 'TEST-INC-0011',
                    'citizen_id': 'TEST-USER-MOBILE',
                    'incident_title': 'TEST SOS chat',
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'messages': [
                  {
                    'id': 'TEST-MESSAGE-0001',
                    'content': 'TEST dispatcher reply',
                    'sender_role': 'operator',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'message': {
                'id': 'TEST-MESSAGE-0002',
                'content': 'TEST citizen reply',
                'sender_role': 'citizen',
              },
            }),
            201,
          );
        }),
      );

      final threads = await SosApi.instance.getMessageThreads();
      final messages = await SosApi.instance.getMessages('TEST-INC-0011');
      final sent = await SosApi.instance.sendMessage(
        incidentId: 'TEST-INC-0011',
        content: 'TEST citizen reply',
        clientMessageId: 'TEST-CLIENT-MESSAGE-001',
      );

      expect(threads.single['citizen_id'], 'TEST-USER-MOBILE');
      expect(messages.single['content'], 'TEST dispatcher reply');
      expect(sent['sender_role'], 'citizen');
      expect(requests, hasLength(3));
      expect(
        requests.every(
          (request) => request.headers['x-eaws-test-client'] == 'citizen',
        ),
        isTrue,
      );
      expect(
        jsonDecode(requests.last.body)['client_message_id'],
        'TEST-CLIENT-MESSAGE-001',
      );
    },
  );
}
