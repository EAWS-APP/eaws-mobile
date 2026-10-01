import 'dart:convert';
import 'dart:io';

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
  }
}

class SupabaseClient {
  final GoTrueClient auth = GoTrueClient();
  final SupabaseStorageClient storage = SupabaseStorageClient();
  
  PostgrestQueryBuilder from(String table) {
    return PostgrestQueryBuilder(table);
  }
}

String get _baseUrl {
  try {
    if (Platform.isAndroid) return 'http://10.0.2.2:5001/api';
  } catch (_) {}
  return 'http://localhost:5001/api';
}

Future<dynamic> _postApi(String path, Map<String, dynamic> body) async {
  final uri = Uri.parse('\$_baseUrl\$path');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) throw Exception(responseBody);
    return jsonDecode(responseBody);
  } finally {
    client.close(force: true);
  }
}

class GoTrueClient {
  User? currentUser;
  Session? currentSession;
  
  Future<AuthResponse> signUp({required String email, required String password, Map<String, dynamic>? data}) async {
    final res = await _postApi('/auth/signup', {'email': email, 'password': password, 'metadata': data});
    currentUser = User(id: res['user']?['id'] ?? 'mock-uuid', email: email, userMetadata: data);
    currentSession = Session(accessToken: res['user']?['id'] ?? 'mock-token');
    return AuthResponse(user: currentUser, session: currentSession);
  }
  
  Future<AuthResponse> signInWithPassword({required String email, required String password}) async {
    final res = await _postApi('/auth/signin', {'email': email, 'password': password});
    currentUser = User(
      id: res['user']?['id'] ?? 'mock-uuid', 
      email: email, 
      userMetadata: res['user']?['user_metadata']
    );
    currentSession = Session(accessToken: res['session']?['access_token'] ?? res['user']?['id'] ?? 'mock-token');
    return AuthResponse(user: currentUser, session: currentSession);
  }
  
  Future<void> signInWithOtp({required String phone}) async {}
  
  Future<AuthResponse> verifyOTP({required String phone, required String token, required OtpType type}) async {
    return AuthResponse(user: currentUser, session: currentSession);
  }
  
  Future<void> resetPasswordForEmail(String email) async {}
  
  Future<UserResponse> updateUser(UserAttributes attributes) async {
    return UserResponse(user: currentUser!);
  }
  
  Future<void> signOut() async {
    currentUser = null;
    currentSession = null;
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
  
  Future<dynamic> single() async { return data ?? {}; }
  PostgrestFilterBuilder select([String columns = '*']) => this;
  PostgrestTransformBuilder eq(String column, dynamic value) => PostgrestTransformBuilder(table);
  PostgrestTransformBuilder or(String filter) => PostgrestTransformBuilder(table);
  
  Future<List<dynamic>> then<T>(Future<List<dynamic>> Function(List<dynamic>) onValue, {Function? onError}) async {
    return onValue([]);
  }
  
  Future<dynamic> get asFuture async => data != null ? data : [];
}

class PostgrestTransformBuilder {
  final String table;
  PostgrestTransformBuilder(this.table);
  
  Future<dynamic> single() async => {};
  PostgrestTransformBuilder order(String column, {bool ascending = false}) => this;
  Future<List<dynamic>> then<T>(Future<List<dynamic>> Function(List<dynamic>) onValue, {Function? onError}) async => onValue([]);
}

class SupabaseStorageClient {
  StorageFileApi from(String bucket) => StorageFileApi(bucket);
}

class StorageFileApi {
  final String bucket;
  StorageFileApi(this.bucket);
  
  Future<String> upload(String path, File file, {FileOptions? fileOptions}) async => path;
  String getPublicUrl(String path) => 'https://mock.url/\$bucket/\$path';
}

class FileOptions {
  final String? cacheControl;
  final bool upsert;
  const FileOptions({this.cacheControl, this.upsert = false});
}
