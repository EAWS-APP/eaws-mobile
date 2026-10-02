import 'package:flutter/foundation.dart';

import '../../core/insforge_client.dart';

class AuthService {
  AuthService._privateConstructor();

  static final AuthService instance = AuthService._privateConstructor();

  final InsForgeClient _client = InsForgeClient.instance;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic>? _pendingRegistrationProfile;

  String? get currentUserName =>
      _profile['full_name']?.toString() ??
      _client.currentUser?['name']?.toString();

  String? get currentUserPhone => _profile['phone_number']?.toString();
  String? get currentUserGhanaCard => _profile['ghana_card']?.toString();
  String? get currentUserEmail => _client.currentUser?['email']?.toString();
  Map<String, dynamic> get currentProfile =>
      Map<String, dynamic>.unmodifiable(_profile);
  bool get isAuthenticated => _client.accessToken != null;

  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String ghanaCard,
  }) async {
    try {
      final response = await _client.postWithQuery(
        '/auth/users',
        body: {
          'email': email.trim(),
          'password': password,
          'name': fullName.trim(),
        },
        query: const {'client_type': 'mobile'},
      );
      if (response is! Map<String, dynamic>) {
        throw const FormatException(
          'InsForge returned an invalid registration response.',
        );
      }
      _pendingRegistrationProfile = {
        'full_name': fullName.trim(),
        'phone_number': phoneNumber.trim(),
        'ghana_card': ghanaCard.trim(),
      };
      final accessToken = response['accessToken'];
      if (accessToken is String && accessToken.isNotEmpty) {
        await _client.setSession(response);
        await updateUserProfile(_pendingRegistrationProfile!);
      }
      return response['requireEmailVerification'] == true ||
          _client.accessToken != null;
    } catch (error, stackTrace) {
      debugPrint('InsForge signup failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.postWithQuery(
        '/auth/sessions',
        body: {
          'method': 'password',
          'email': email.trim(),
          'password': password,
        },
        query: const {'client_type': 'mobile'},
      );
      if (response is! Map<String, dynamic>) {
        throw const FormatException(
          'InsForge returned an invalid sign-in response.',
        );
      }
      await _client.setSession(response);
      await _loadCurrentProfile();
      return true;
    } catch (error, stackTrace) {
      debugPrint('InsForge sign-in failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> sendOTP(String email) async {
    try {
      await _client.post('/auth/email/send-otp', body: {'email': email.trim()});
      return true;
    } catch (error, stackTrace) {
      debugPrint('InsForge email OTP request failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> sendEmailVerificationCode(String email) async {
    try {
      await _client.post(
        '/auth/email/send-verification',
        body: {'email': email.trim()},
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'InsForge email verification request failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  Future<bool> verifyOTP(String email, String otpCode) async {
    try {
      final response = await _client.postWithQuery(
        '/auth/sessions',
        body: {'method': 'otp', 'email': email.trim(), 'otp': otpCode.trim()},
        query: const {'client_type': 'mobile'},
      );
      if (response is! Map<String, dynamic>) {
        throw const FormatException(
          'InsForge returned an invalid OTP response.',
        );
      }
      await _client.setSession(response);
      await _loadCurrentProfile();
      return true;
    } catch (error, stackTrace) {
      debugPrint('InsForge OTP verification failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> verifyEmailCode(String email, String otpCode) async {
    try {
      final response = await _client.postWithQuery(
        '/auth/email/verify',
        body: {'email': email.trim(), 'otp': otpCode.trim()},
        query: const {'client_type': 'mobile'},
      );
      if (response is! Map<String, dynamic>) {
        throw const FormatException(
          'InsForge returned an invalid verification response.',
        );
      }
      await _client.setSession(response);
      final pendingProfile = _pendingRegistrationProfile;
      if (pendingProfile != null) {
        await updateUserProfile(pendingProfile);
        _pendingRegistrationProfile = null;
      } else {
        await _loadCurrentProfile();
      }
      return true;
    } catch (error, stackTrace) {
      debugPrint('InsForge email verification failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> resetPasswordForEmail(String email) async {
    try {
      await _client.post(
        '/auth/email/send-reset-password',
        body: {'email': email.trim()},
      );
      return true;
    } catch (error, stackTrace) {
      debugPrint('InsForge password reset request failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<bool> updateUserProfile(Map<String, dynamic> profile) async {
    try {
      await _client.patch('/auth/profiles/current', body: {'profile': profile});
      _profile = {..._profile, ...profile};
      await _client.cacheProfile(_profile);
      return true;
    } catch (error, stackTrace) {
      debugPrint('InsForge profile update failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<void> _loadCurrentProfile() async {
    final userId = _client.currentUser?['id'];
    if (userId == null) return;
    final response = await _client.get(
      '/auth/profiles/${Uri.encodeComponent(userId.toString())}',
    );
    if (response is Map && response['profile'] is Map) {
      _profile = Map<String, dynamic>.from(response['profile'] as Map);
      await _client.cacheProfile(_profile);
    }
  }

  Future<void> signOut() async {
    try {
      if (_client.accessToken != null) {
        await _client.post('/auth/logout');
      }
    } finally {
      _profile = {};
      _pendingRegistrationProfile = null;
      await _client.clearSession();
    }
  }
}
