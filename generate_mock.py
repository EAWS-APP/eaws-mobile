import os

mock_code = """
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

class GoTrueClient {
  User? currentUser = User(id: 'mock-user-123', userMetadata: {'full_name': 'Mock User'}, phone: '1234567890');
  Session? currentSession = Session();
  
  Future<AuthResponse> signUp({required String email, required String password, Map<String, dynamic>? data}) async {
    return AuthResponse(user: currentUser, session: currentSession);
  }
  
  Future<AuthResponse> signInWithPassword({required String email, required String password}) async {
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
  final Map<String, dynamic>? userMetadata;
  final String? phone;
  
  User({required this.id, this.userMetadata, this.phone});
}

class Session {}
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
  
  PostgrestFilterBuilder select([String columns = '*']) {
    return PostgrestFilterBuilder(table);
  }
  
  PostgrestFilterBuilder insert(Map<String, dynamic> data) {
    return PostgrestFilterBuilder(table);
  }
  
  PostgrestFilterBuilder upsert(Map<String, dynamic> data) {
    return PostgrestFilterBuilder(table);
  }
  
  PostgrestFilterBuilder update(Map<String, dynamic> data) {
    return PostgrestFilterBuilder(table);
  }
}

class PostgrestFilterBuilder {
  final String table;
  PostgrestFilterBuilder(this.table);
  
  PostgrestFilterBuilder select([String columns = '*']) {
    return this;
  }
  
  PostgrestTransformBuilder eq(String column, dynamic value) {
    return PostgrestTransformBuilder(table);
  }
  
  PostgrestTransformBuilder or(String filter) {
    return PostgrestTransformBuilder(table);
  }
  
  Future<List<dynamic>> then<T>(Future<List<dynamic>> Function(List<dynamic>) onValue, {Function? onError}) async {
    return onValue([]);
  }
  
  Future<dynamic> get asFuture async => [];
}

class PostgrestTransformBuilder {
  final String table;
  PostgrestTransformBuilder(this.table);
  
  Future<dynamic> single() async {
    return {};
  }
  
  PostgrestTransformBuilder order(String column, {bool ascending = false}) {
    return this;
  }
  
  Future<List<dynamic>> then<T>(Future<List<dynamic>> Function(List<dynamic>) onValue, {Function? onError}) async {
    return onValue([]);
  }
}

class SupabaseStorageClient {
  StorageFileApi from(String bucket) {
    return StorageFileApi(bucket);
  }
}

class StorageFileApi {
  final String bucket;
  StorageFileApi(this.bucket);
  
  Future<String> upload(String path, File file, {FileOptions? fileOptions}) async {
    return path;
  }
  
  String getPublicUrl(String path) {
    return 'https://mock.url/$bucket/$path';
  }
}

class FileOptions {
  final String? cacheControl;
  final bool upsert;
  const FileOptions({this.cacheControl, this.upsert = false});
}
"""

with open('lib/core/supabase_mock.dart', 'w') as f:
    f.write(mock_code)
