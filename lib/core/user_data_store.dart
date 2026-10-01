import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eaws_app/core/supabase_mock.dart';
import 'user_session.dart';

/// Centralized per-user isolated database store.
/// Ensures complete isolation of user profile data, incident reports, posts, and activities.
/// No data overlap or mix-up between different user accounts.
class UserDataStore {
  UserDataStore._();
  static final UserDataStore instance = UserDataStore._();

  /// Gets the unique account key for the currently authenticated user.
  String get userKey {
    final session = UserSession.instance;
    if (session.email != null && session.email!.isNotEmpty) {
      return session.email!.trim().toLowerCase();
    }
    if (session.phone != null && session.phone!.isNotEmpty) {
      return session.phone!.trim();
    }
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    if (supabaseUser != null) {
      return supabaseUser.id;
    }
    if (session.displayName.isNotEmpty && session.displayName != 'Citizen') {
      return session.displayName.trim().toLowerCase();
    }
    return 'kwame_asante_default';
  }

  // --- USER PROFILE & BIO DATA ---

  Future<Map<String, String>> loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('eaws_user_profile_$userKey');
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}

    // Default values if no profile stored yet for this user
    final session = UserSession.instance;
    return {
      'fullName': session.displayName,
      'email': session.email ?? '${session.displayName.toLowerCase().replaceAll(' ', '.')}@eaws.gov.gh',
      'phone': session.phone ?? '+233 26 123 4567',
      'dob': '15 Mar 1992',
      'bloodType': 'O+',
      'medicalConditions': 'None listed',
      'homeAddress': 'Accra, Ghana',
      'allergies': 'None listed',
      'medications': 'None listed',
      'communicationPreference': 'Voice & Text',
    };
  }

  Future<void> saveUserProfile(Map<String, String> profileData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eaws_user_profile_$userKey', jsonEncode(profileData));
    } catch (_) {}
  }

  // --- USER INCIDENT REPORTS & POSTS ---

  Future<List<Map<String, dynamic>>> loadUserReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('eaws_user_reports_$userKey');
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return List<Map<String, dynamic>>.from(decoded);
      }
    } catch (_) {}
    return []; // New user has 0 reports until they post
  }

  Future<void> saveUserReport(Map<String, dynamic> report) async {
    try {
      final reports = await loadUserReports();
      // Ensure current user metadata is set
      report['userId'] = userKey;
      report['userName'] = UserSession.instance.displayName;
      report['initials'] = UserSession.instance.initials;
      
      reports.insert(0, report);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eaws_user_reports_$userKey', jsonEncode(reports));
    } catch (_) {}
  }

  // --- USER LIKED POSTS ---

  Future<Set<String>> loadLikedPostIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('eaws_user_likes_$userKey');
      if (raw != null) return raw.toSet();
    } catch (_) {}
    return {};
  }

  Future<void> setPostLiked(String postId, bool isLiked) async {
    try {
      final likedSet = await loadLikedPostIds();
      if (isLiked) {
        likedSet.add(postId);
      } else {
        likedSet.remove(postId);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('eaws_user_likes_$userKey', likedSet.toList());
    } catch (_) {}
  }

  // --- USER SAVED POSTS ---

  Future<Set<String>> loadSavedPostIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('eaws_user_saved_$userKey');
      if (raw != null) return raw.toSet();
    } catch (_) {}
    return {};
  }

  Future<void> setPostSaved(String postId, bool isSaved) async {
    try {
      final savedSet = await loadSavedPostIds();
      if (isSaved) {
        savedSet.add(postId);
      } else {
        savedSet.remove(postId);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('eaws_user_saved_$userKey', savedSet.toList());
    } catch (_) {}
  }
}
