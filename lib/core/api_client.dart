import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eaws_app/core/supabase_mock.dart';

class EawsApiClient {
  EawsApiClient._();

  static final EawsApiClient instance = EawsApiClient._();

  static String? customBaseUrl;
  String? _authToken;

  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) {
      return customBaseUrl!;
    }
    if (kIsWeb) {
      if (Uri.base.scheme == 'https') {
        return '${Uri.base.origin}/api';
      }
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      return 'http://$host:5000/api';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000/api';
    }
    return 'http://localhost:5000/api';
  }

  void setAuthToken(String token) {
    _authToken = token;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('eaws_auth_token', token);
    }).catchError((_) {});
  }

  Future<void> clearAuthToken() async {
    _authToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('eaws_auth_token');
    } catch (_) {}
  }

  Future<String?> getAuthToken() async {
    if (_authToken != null && _authToken!.isNotEmpty) {
      return _authToken;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _authToken = prefs.getString('eaws_auth_token');
    } catch (_) {}
    return _authToken;
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
    final persistedToken = await getAuthToken();

    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);

    String token;
    if (persistedToken != null && persistedToken.isNotEmpty && persistedToken != 'mock-token') {
      token = persistedToken;
    } else if (session?.accessToken != null && session!.accessToken != 'mock-token') {
      token = session!.accessToken;
    } else {
      final userEmail = Supabase.instance.client.auth.currentUser?.email ?? 'kwame@eaws.gov.gh';
      token = 'mock-token-$userEmail';
    }

    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    req.headers['Content-Type'] = 'application/json';
    req.headers['Authorization'] = 'Bearer $token';

    if (body != null) {
      req.body = jsonEncode(body);
    }

    final streamed = await req.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        response.body.isNotEmpty
            ? response.body
            : 'EAWS API request failed ($method $path -> ${response.statusCode})',
      );
    }

    if (response.statusCode == 204 || response.body.isEmpty) {
      return null;
    }

    return jsonDecode(response.body);
  }
}
