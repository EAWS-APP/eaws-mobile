import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class InsForgeApiException implements Exception {
  const InsForgeApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'InsForge request failed ($statusCode): $message';
}

class InsForgeClient {
  InsForgeClient._();

  static final InsForgeClient instance = InsForgeClient._();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _accessTokenKey = 'insforge_access_token';
  static const String _refreshTokenKey = 'insforge_refresh_token';
  static const String _userKey = 'insforge_current_user';

  final http.Client _http = http.Client();
  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _profile;
  Future<bool>? _refreshInProgress;

  static String get baseUrl =>
      const String.fromEnvironment('INSFORGE_BASE_URL');
  static String get anonKey =>
      const String.fromEnvironment('INSFORGE_ANON_KEY');
  static bool get isConfigured => baseUrl.isNotEmpty && anonKey.isNotEmpty;

  String? get accessToken => _accessToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  Map<String, dynamic>? get currentProfile => _profile;

  Future<void> restoreSession() async {
    if (!isConfigured) return;
    _accessToken = await _secureStorage.read(key: _accessTokenKey);
    _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    final userJson = await _secureStorage.read(key: _userKey);
    if (userJson != null) {
      final decoded = jsonDecode(userJson);
      if (decoded is Map) _currentUser = Map<String, dynamic>.from(decoded);
    }
    final profileJson = await _secureStorage.read(
      key: 'insforge_current_profile',
    );
    if (profileJson != null) {
      final decoded = jsonDecode(profileJson);
      if (decoded is Map) _profile = Map<String, dynamic>.from(decoded);
    }
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    return request('GET', path, query: query);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) {
    return request('POST', path, body: body);
  }

  Future<dynamic> postWithQuery(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) {
    return request('POST', path, body: body, query: query);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return request('PATCH', path, body: body);
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    _requireConfiguration();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse(
      '$baseUrl/api$normalizedPath',
    ).replace(queryParameters: query);
    var response = await _send(method, uri, body: body);

    if (response.statusCode == 401 &&
        _refreshToken != null &&
        normalizedPath != '/auth/refresh') {
      final refreshed = await refreshSession();
      if (refreshed) response = await _send(method, uri, body: body);
    }

    return _decodeResponse(response);
  }

  Future<void> setSession(Map<String, dynamic> response) async {
    final accessToken = response['accessToken'];
    final refreshToken = response['refreshToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException(
        'InsForge response did not include an access token.',
      );
    }
    _accessToken = accessToken;
    _currentUser = response['user'] is Map
        ? Map<String, dynamic>.from(response['user'] as Map)
        : null;
    _profile = _currentUser?['profile'] is Map
        ? Map<String, dynamic>.from(_currentUser!['profile'] as Map)
        : null;
    if (_currentUser != null) {
      await _secureStorage.write(
        key: _userKey,
        value: jsonEncode(_currentUser),
      );
    }
    if (_profile != null) {
      await _secureStorage.write(
        key: 'insforge_current_profile',
        value: jsonEncode(_profile),
      );
    } else {
      await _secureStorage.delete(key: 'insforge_current_profile');
    }

    if (refreshToken is String && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<bool> refreshSession() {
    final inProgress = _refreshInProgress;
    if (inProgress != null) return inProgress;
    final refresh = _refreshSession();
    _refreshInProgress = refresh;
    return refresh.whenComplete(() => _refreshInProgress = null);
  }

  Future<bool> _refreshSession() async {
    _refreshToken ??= await _secureStorage.read(key: _refreshTokenKey);
    final refreshToken = _refreshToken;
    if (refreshToken == null || !isConfigured) return false;

    try {
      final uri = Uri.parse(
        '$baseUrl/api/auth/refresh',
      ).replace(queryParameters: const {'client_type': 'mobile'});
      final response = await _send(
        'POST',
        uri,
        body: {'refreshToken': refreshToken},
        includeAccessToken: false,
      );
      final decoded = _decodeResponse(response);
      if (decoded is! Map<String, dynamic>) return false;
      await setSession(decoded);
      return true;
    } on InsForgeApiException {
      return false;
    } on FormatException {
      return false;
    }
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    _profile = null;
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userKey);
    await _secureStorage.delete(key: 'insforge_current_profile');
  }

  Future<void> cacheProfile(Map<String, dynamic> profile) async {
    _profile = Map<String, dynamic>.from(profile);
    await _secureStorage.write(
      key: 'insforge_current_profile',
      value: jsonEncode(_profile),
    );
  }

  Future<Map<String, dynamic>> uploadFile({
    required String bucket,
    required File file,
    required String filename,
    required String contentType,
  }) async {
    _requireConfiguration();
    final fileSize = await file.length();
    final strategy = await post(
      '/storage/buckets/${Uri.encodeComponent(bucket)}/upload-strategy',
      body: {
        'filename': filename,
        'contentType': contentType,
        'size': fileSize,
      },
    );
    if (strategy is! Map<String, dynamic> ||
        strategy['uploadUrl'] is! String ||
        strategy['method'] is! String) {
      throw const FormatException(
        'InsForge returned an invalid upload strategy.',
      );
    }

    final uploadUri = Uri.parse(
      baseUrl,
    ).resolve(strategy['uploadUrl'] as String);
    final method = strategy['method'] == 'presigned' ? 'POST' : 'PUT';
    final request = http.MultipartRequest(method, uploadUri);
    if (strategy['fields'] is Map) {
      request.fields.addAll(
        Map<String, String>.from(strategy['fields'] as Map),
      );
    }
    if (uploadUri.host == Uri.parse(baseUrl).host) {
      request.headers['authorization'] = 'Bearer ${_accessToken ?? anonKey}';
    }
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path, filename: filename),
    );
    final response = await _http.send(request);
    final uploaded = await http.Response.fromStream(response);
    if (uploaded.statusCode < 200 || uploaded.statusCode >= 300) {
      throw InsForgeApiException(
        uploaded.statusCode,
        uploaded.body.isEmpty ? 'File upload failed.' : uploaded.body,
      );
    }
    final decoded = uploaded.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(uploaded.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'InsForge returned an invalid upload response.',
      );
    }

    if (strategy['confirmRequired'] == true) {
      final key = strategy['key']?.toString() ?? filename;
      await post(
        '/storage/buckets/${Uri.encodeComponent(bucket)}/objects/${Uri.encodeComponent(key)}/confirm-upload',
        body: {'size': fileSize, 'contentType': contentType},
      );
    }
    return decoded;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    bool includeAccessToken = true,
  }) {
    final token = includeAccessToken ? _accessToken : null;
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      'authorization': 'Bearer ${token ?? anonKey}',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return _http.put(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return _http.delete(uri, headers: headers, body: encodedBody);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  dynamic _decodeResponse(http.Response response) {
    final responseBody = utf8.decode(response.bodyBytes);
    dynamic decoded;
    if (responseBody.isNotEmpty) {
      try {
        decoded = jsonDecode(responseBody);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return responseBody;
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['message'] ??
                    decoded['error'] ??
                    decoded['error_description'])
                ?.toString()
          : null;
      throw InsForgeApiException(
        response.statusCode,
        message ?? (responseBody.isEmpty ? 'Request failed.' : responseBody),
      );
    }
    return decoded;
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw StateError(
        'InsForge is not configured. Provide INSFORGE_BASE_URL and INSFORGE_ANON_KEY.',
      );
    }
  }
}
