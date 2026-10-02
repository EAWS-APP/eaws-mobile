import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'insforge_client.dart';

class EawsApiClient {
  EawsApiClient._();

  static final EawsApiClient instance = EawsApiClient._();
  String? _baseUrlOverride;
  http.Client _httpClient = http.Client();

  String get baseUrl {
    if (_baseUrlOverride != null) return _baseUrlOverride!;
    const configuredUrl = String.fromEnvironment('EAWS_API_URL');
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.endsWith('/')
          ? configuredUrl.substring(0, configuredUrl.length - 1)
          : configuredUrl;
    }
    return 'http://127.0.0.1:5001/api';
  }

  @visibleForTesting
  void configureForTesting({
    required String baseUrl,
    required http.Client httpClient,
  }) {
    _baseUrlOverride = baseUrl;
    _httpClient = httpClient;
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    Map<String, String> headers = const {},
  }) {
    return _send('GET', path, query: query, additionalHeaders: headers);
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) {
    return _send('POST', path, body: body, additionalHeaders: headers);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _send('PATCH', path, body: body);
  }

  Future<dynamic> postWithIdempotencyKey(
    String path, {
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) {
    return _send(
      'POST',
      path,
      body: {...body, 'client_event_id': idempotencyKey},
    );
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Map<String, String> additionalHeaders = const {},
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final token = InsForgeClient.instance.accessToken;
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    if (token != null) headers['authorization'] = 'Bearer $token';
    headers.addAll(additionalHeaders);
    final encodedBody = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'GET' => await _httpClient.get(uri, headers: headers),
      'POST' => await _httpClient.post(
        uri,
        headers: headers,
        body: encodedBody,
      ),
      'PATCH' => await _httpClient.patch(
        uri,
        headers: headers,
        body: encodedBody,
      ),
      'DELETE' => await _httpClient.delete(
        uri,
        headers: headers,
        body: encodedBody,
      ),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Unsupported HTTP method',
      ),
    };
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InsForgeApiException(
        response.statusCode,
        responseBody.isNotEmpty ? responseBody : 'EAWS API request failed',
      );
    }

    if (response.statusCode == 204 || responseBody.isEmpty) return null;
    return jsonDecode(responseBody);
  }
}
