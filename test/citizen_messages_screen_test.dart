import 'dart:convert';

import 'package:eaws_app/core/api_client.dart';
import 'package:eaws_app/features/messages/citizen_messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('citizen can reopen a retained TEST thread and reply', (
    tester,
  ) async {
    final messages = <Map<String, dynamic>>[
      {
        'id': 'TEST-MESSAGE-0001',
        'content': 'TEST dispatcher update',
        'sender': 'TEST Operator',
        'sender_role': 'operator',
        'delivery_state': 'fetched_by_citizen_app',
        'read_state': 'not_read',
        'created_at': '2026-10-01T15:00:00.000Z',
      },
    ];
    var postedBody = <String, dynamic>{};
    EawsApiClient.instance.configureForTesting(
      baseUrl: 'http://127.0.0.1:5001/api',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/citizen/messages/threads')) {
          return http.Response(
            jsonEncode({
              'threads': [
                {
                  'incident_id': 'TEST-INC-0011',
                  'citizen_id': 'TEST-USER-MOBILE',
                  'incident_title': 'TEST: mobile SOS chat',
                  'incident_status': 'sent',
                  'last_message': {
                    'id': messages.last['id'],
                    'text': messages.last['content'],
                    'sender': messages.last['sender_role'],
                    'time': messages.last['created_at'],
                  },
                  'unread_count': 0,
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(jsonEncode({'messages': messages}), 200);
        }

        postedBody = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map<String, dynamic>,
        );
        final message = {
          'id': 'TEST-MESSAGE-0002',
          'client_message_id': postedBody['client_message_id'],
          'content': postedBody['content'],
          'sender': 'TEST Ama Mensah',
          'sender_role': 'citizen',
          'delivery_state': 'received_by_dispatch',
          'read_state': 'not_read',
          'created_at': '2026-10-01T15:01:00.000Z',
        };
        messages.add(message);
        return http.Response(jsonEncode({'message': message}), 201);
      }),
    );

    await tester.pumpWidget(
      const MaterialApp(home: CitizenMessagesScreen(demoMode: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('TEST: mobile SOS chat'), findsOneWidget);
    await tester.tap(find.text('TEST: mobile SOS chat'));
    await tester.pumpAndSettle();
    expect(find.text('TEST dispatcher update'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'TEST citizen reply');
    await tester.pump();
    await tester.tap(find.byTooltip('Send TEST message'));
    await tester.pumpAndSettle();

    expect(find.text('TEST citizen reply'), findsOneWidget);
    expect(postedBody['content'], 'TEST citizen reply');
    expect(postedBody['client_message_id'], startsWith('TEST-MOBILE-MESSAGE-'));
  });
}
