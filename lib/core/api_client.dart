import 'dart:convert';
import 'dart:io';

import 'package:eaws_app/core/supabase_mock.dart';

class EawsApiClient {
  EawsApiClient._();

  static final EawsApiClient instance = EawsApiClient._();

  static String get baseUrl {
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:5001/api';
      }
    } catch (_) {}
    return 'http://localhost:5001/api';
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    return _send('GET', path, query: query);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) {
    return _send('POST', path, body: body);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _send('PATCH', path, body: body);
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final client = HttpClient();

    try {
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // Use real Supabase token if logged in; otherwise fall back to user-specific mock token
      // so the backend can resolve the correct registered name from its user registry.
      String token;
      if (session?.accessToken != null) {
        token = session!.accessToken;
      } else {
        // Embed the user's email in the mock token so the server's resolveAuthorName()
        // can look up their real full name (e.g. kwame@eaws.gov.gh → Kwame Asante).
        final userEmail = Supabase.instance.client.auth.currentUser?.email
            ?? 'kwame@eaws.gov.gh';
        token = 'mock-token-$userEmail';
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          responseBody.isNotEmpty ? responseBody : 'EAWS API request failed',
          uri: uri,
        );
      }

      if (response.statusCode == 204 || responseBody.isEmpty) {
        return null;
      }

      return jsonDecode(responseBody);
    } finally {
      client.close(force: true);
    }
  }
}

