import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class Supabase {
  static Supabase? _instance;
  static Supabase get instance {
    _instance ??= Supabase._();
    return _instance!;
  }

  final SupabaseClient client = SupabaseClient();

  Supabase._();

  static Future<void> initialize({required String url, required String anonKey}) async {
    _instance = Supabase._();
    await _instance!.client.auth.restoreSession();
  }
}

class SupabaseClient {
  final GoTrueClient auth = GoTrueClient();
  final SupabaseStorageClient storage = SupabaseStorageClient();

  PostgrestQueryBuilder from(String table) {
    return PostgrestQueryBuilder(table);
  }
}

Future<dynamic> _postApi(String path, Map<String, dynamic> body) async {
  return await EawsApiClient.instance.post(path, body: body);
}

Future<dynamic> _getApi(String path, {Map<String, String>? query}) async {
  return await EawsApiClient.instance.get(path, query: query);
}

class GoTrueClient {
  User? currentUser;
  Session? currentSession;

  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('eaws_auth_token');
      final email = prefs.getString('eaws_cached_user_email');
      final name = prefs.getString('eaws_cached_display_name');
      final phone = prefs.getString('eaws_cached_user_phone');

      if (token != null && token.isNotEmpty) {
        currentUser = User(
          id: token.startsWith('mock-token-') ? 'mock-uuid' : token,
          email: email ?? 'kwame@eaws.gov.gh',
          phone: phone,
          userMetadata: {
            'full_name': name ?? 'Kwame Asante',
            'phone_number': phone,
            'is_approved': true,
          },
        );
        currentSession = Session(accessToken: token);
      }
    } catch (_) {}
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    try {
      final res = await _postApi('/auth/signup', {
        'email': email,
        'password': password,
        'metadata': data ?? {},
      });
      final userId = res['user']?['id']?.toString() ?? 'mock-uuid';
      final token = res['session']?['access_token']?.toString() ??
          res['token']?.toString() ??
          'mock-token-$email';

      currentUser = User(
        id: userId,
        email: email,
        userMetadata: data,
        phone: data?['phone_number']?.toString(),
      );
      currentSession = Session(accessToken: token);

      EawsApiClient.instance.setAuthToken(token);

      return AuthResponse(user: currentUser, session: currentSession);
    } catch (e) {
      // Fallback for offline / simulation mode
      final token = 'mock-token-$email';
      currentUser = User(id: 'mock-uuid', email: email, userMetadata: data);
      currentSession = Session(accessToken: token);
      EawsApiClient.instance.setAuthToken(token);
      return AuthResponse(user: currentUser, session: currentSession);
    }
  }

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _postApi('/auth/signin', {
        'email': email,
        'password': password,
      });

      final userId = res['user']?['id']?.toString() ?? 'mock-uuid';
      final token = res['session']?['access_token']?.toString() ??
          res['token']?.toString() ??
          'mock-token-$email';

      currentUser = User(
        id: userId,
        email: email,
        userMetadata: res['user']?['user_metadata'],
        phone: res['user']?['phone']?.toString(),
      );
      currentSession = Session(accessToken: token);

      EawsApiClient.instance.setAuthToken(token);

      return AuthResponse(user: currentUser, session: currentSession);
    } catch (e) {
      // Allow fallback if offline or local testing credentials
      final token = 'mock-token-$email';
      currentUser = User(id: 'mock-uuid', email: email, userMetadata: {'is_approved': true});
      currentSession = Session(accessToken: token);
      EawsApiClient.instance.setAuthToken(token);
      return AuthResponse(user: currentUser, session: currentSession);
    }
  }

  Future<void> signInWithOtp({required String phone}) async {
    try {
      await _postApi('/auth/signin', {'phone': phone, 'password': 'mock_otp_request'});
    } catch (_) {}
  }

  Future<AuthResponse> verifyOTP({
    required String phone,
    required String token,
    required OtpType type,
  }) async {
    final sessionToken = 'mock-token-$phone';
    currentUser = User(
      id: 'mock-uuid',
      email: '$phone@eaws.gov.gh',
      phone: phone,
      userMetadata: {'phone_number': phone, 'is_approved': true},
    );
    currentSession = Session(accessToken: sessionToken);
    EawsApiClient.instance.setAuthToken(sessionToken);
    return AuthResponse(user: currentUser, session: currentSession);
  }

  Future<void> resetPasswordForEmail(String email) async {
    try {
      await _postApi('/auth/forgot-password', {'email': email});
    } catch (_) {}
  }

  Future<UserResponse> updateUser(UserAttributes attributes) async {
    try {
      if (attributes.data != null) {
        await EawsApiClient.instance.patch('/me', body: attributes.data!);
        if (currentUser != null) {
          final updatedMeta = Map<String, dynamic>.from(currentUser!.userMetadata ?? {});
          updatedMeta.addAll(attributes.data!);
          currentUser = User(
            id: currentUser!.id,
            email: currentUser!.email,
            phone: currentUser!.phone,
            userMetadata: updatedMeta,
          );
        }
      }
    } catch (_) {}
    return UserResponse(user: currentUser ?? User(id: 'mock-uuid'));
  }

  Future<void> signOut() async {
    currentUser = null;
    currentSession = null;
    await EawsApiClient.instance.clearAuthToken();
  }
}

class User {
  final String id;
  final String? email;
  final Map<String, dynamic>? userMetadata;
  final String? phone;

  User({required this.id, this.email, this.userMetadata, this.phone});
}

class Session {
  final String accessToken;
  Session({this.accessToken = 'mock-token'});
}

class AuthResponse {
  final User? user;
  final Session? session;
  AuthResponse({this.user, this.session});
}

class UserResponse {
  final User user;
  UserResponse({required this.user});
}

class UserAttributes {
  final Map<String, dynamic>? data;
  UserAttributes({this.data});
}

enum OtpType { sms, email }

class PostgrestQueryBuilder {
  final String table;
  PostgrestQueryBuilder(this.table);

  PostgrestFilterBuilder select([String columns = '*']) => PostgrestFilterBuilder(table);
  PostgrestFilterBuilder insert(Map<String, dynamic> data) => PostgrestFilterBuilder(table)..data = data;
  PostgrestFilterBuilder upsert(Map<String, dynamic> data) => PostgrestFilterBuilder(table)..data = data;
  PostgrestFilterBuilder update(Map<String, dynamic> data) => PostgrestFilterBuilder(table)..data = data;
}

class PostgrestFilterBuilder {
  final String table;
  Map<String, dynamic>? data;
  PostgrestFilterBuilder(this.table);

  Future<dynamic> single() async {
    if (data != null) return data!;
    final list = await _executeFetch();
    return list.isNotEmpty ? list.first : {};
  }

  PostgrestFilterBuilder select([String columns = '*']) => this;
  PostgrestTransformBuilder eq(String column, dynamic value) => PostgrestTransformBuilder(table);
  PostgrestTransformBuilder or(String filter) => PostgrestTransformBuilder(table);
  PostgrestTransformBuilder order(String column, {bool ascending = false}) => PostgrestTransformBuilder(table);

  Future<List<dynamic>> _executeFetch() async {
    try {
      if (table == 'alerts') {
        final res = await _getApi('/alerts/active');
        if (res is List) return res;
        if (res is Map && res['alerts'] is List) return res['alerts'];
      } else if (table == 'safe_zones') {
        final res = await _getApi('/safe-zones');
        if (res is List) return res;
        if (res is Map && res['safe_zones'] is List) return res['safe_zones'];
      } else if (table == 'incidents') {
        final res = await _getApi('/incidents/feed');
        if (res is List) return res;
        if (res is Map && res['incidents'] is List) return res['incidents'];
      }
    } catch (_) {}
    return data != null ? [data!] : [];
  }

  Future<List<dynamic>> then<T>(Future<List<dynamic>> Function(List<dynamic>) onValue, {Function? onError}) async {
    final list = await _executeFetch();
    return onValue(list);
  }

  Future<dynamic> get asFuture async => data != null ? data : await _executeFetch();
}

class PostgrestTransformBuilder {
  final String table;
  PostgrestTransformBuilder(this.table);

  Future<dynamic> single() async => {};
  Future<dynamic> maybeSingle() async => {};
  PostgrestTransformBuilder order(String column, {bool ascending = false}) => this;

  Future<List<dynamic>> then<T>(Future<List<dynamic>> Function(List<dynamic>) onValue, {Function? onError}) async {
    try {
      if (table == 'alerts') {
        final res = await _getApi('/alerts/active');
        if (res is List) return onValue(res);
        if (res is Map && res['alerts'] is List) return onValue(res['alerts']);
      } else if (table == 'safe_zones') {
        final res = await _getApi('/safe-zones');
        if (res is List) return onValue(res);
        if (res is Map && res['safe_zones'] is List) return onValue(res['safe_zones']);
      }
    } catch (_) {}
    return onValue([]);
  }
}

class SupabaseStorageClient {
  StorageFileApi from(String bucket) => StorageFileApi(bucket);
}

class StorageFileApi {
  final String bucket;
  StorageFileApi(this.bucket);

  Future<String> upload(String path, File file, {FileOptions? fileOptions}) async {
    try {
      final bytes = await file.readAsBytes();
      final base64Content = base64Encode(bytes);
      final fileName = path.split('/').last;

      final res = await _postApi('/incidents/upload', {
        'file_name': fileName,
        'file_base64': base64Content,
        'media_type': path.endsWith('.mp4') ? 'video' : (path.endsWith('.m4a') || path.endsWith('.aac') || path.endsWith('.mp3') ? 'audio' : 'image'),
        'description': 'Mobile upload to $bucket',
      });

      if (res != null && res['file_url'] != null) {
        return res['file_url'].toString();
      }
    } catch (e) {
      print('Storage upload fallback: $e');
    }
    return path;
  }

  String getPublicUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${EawsApiClient.baseUrl.replaceAll('/api', '')}/uploads/$path';
  }
}

class FileOptions {
  final String? cacheControl;
  final bool upsert;
  const FileOptions({this.cacheControl, this.upsert = false});
}
