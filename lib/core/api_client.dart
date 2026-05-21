import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class EawsApiClient {
  EawsApiClient._();

  static final EawsApiClient instance = EawsApiClient._();

  static const String baseUrl = String.fromEnvironment(
    'EAWS_API_BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );

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
      if (session?.accessToken != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${session!.accessToken}');
      }

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

