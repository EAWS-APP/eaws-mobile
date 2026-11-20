import 'dart:convert';
import 'package:eaws_app/core/supabase_mock.dart';
import '../../core/user_session.dart';
import '../../core/user_data_store.dart';
import '../../core/api_client.dart';

class ProfileData {
  static String fullName = UserSession.instance.displayName;
  static String email = UserSession.instance.email ?? '';
  static String phone = UserSession.instance.phone ?? '';
  static String dob = '';
  
  static String bloodType = '';
  static String medicalConditions = '';
  static String homeAddress = '';
  
  // Recommended premium emergency fields
  static String allergies = '';
  static String medications = '';
  static String communicationPreference = 'Voice & Text';
  static String avatarUrl = '';

  static String get initials {
    if (fullName.isEmpty) return 'KA';
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  /// Load from per-user isolated database store
  static Future<void> loadFromSession() async {
    try {
      // 1. Load active user session name & contact details
      fullName = UserSession.instance.displayName;
      if (UserSession.instance.email != null) email = UserSession.instance.email!;
      if (UserSession.instance.phone != null) phone = UserSession.instance.phone!;

      // 2. Load per-user profile bio data from UserDataStore
      final profile = await UserDataStore.instance.loadUserProfile();
      fullName = profile['fullName'] ?? fullName;
      email = profile['email'] ?? email;
      phone = profile['phone'] ?? phone;
      dob = profile['dob'] ?? dob;
      bloodType = profile['bloodType'] ?? bloodType;
      medicalConditions = profile['medicalConditions'] ?? medicalConditions;
      homeAddress = profile['homeAddress'] ?? homeAddress;
      allergies = profile['allergies'] ?? allergies;
      medications = profile['medications'] ?? medications;
      communicationPreference = profile['communicationPreference'] ?? communicationPreference;
      avatarUrl = profile['avatarUrl'] ?? avatarUrl;

      // 3. Sync with live Express backend GET /api/me
      try {
        final res = await EawsApiClient.instance.get('/me');
        final remoteProfile = res?['profile'] ?? res?['user']?['user_metadata'];
        if (remoteProfile is Map) {
          fullName = remoteProfile['full_name'] ?? remoteProfile['fullName'] ?? fullName;
          email = remoteProfile['email'] ?? email;
          phone = remoteProfile['phone_number'] ?? remoteProfile['phone'] ?? phone;
          dob = remoteProfile['dob'] ?? dob;
          bloodType = remoteProfile['blood_type'] ?? remoteProfile['blood_group'] ?? remoteProfile['bloodType'] ?? bloodType;
          medicalConditions = remoteProfile['medical_conditions'] ?? remoteProfile['chronic_illnesses'] ?? remoteProfile['medicalConditions'] ?? medicalConditions;
          homeAddress = remoteProfile['home_address'] ?? remoteProfile['homeAddress'] ?? homeAddress;
          allergies = remoteProfile['allergies'] ?? allergies;
          medications = remoteProfile['medications'] ?? medications;
          communicationPreference = remoteProfile['communication_preference'] ?? remoteProfile['communicationPreference'] ?? communicationPreference;
          avatarUrl = remoteProfile['avatar_url'] ?? remoteProfile['avatarUrl'] ?? avatarUrl;
        }
      } catch (apiErr) {
        print('EAWS GET /me sync note: $apiErr');
      }

      // 4. Sync with active Supabase user metadata if connected
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        fullName = user.userMetadata?['full_name'] ?? fullName;
        phone = user.userMetadata?['phone_number'] ?? user.phone ?? phone;
        email = user.email ?? email;
      }
    } catch (e) {
      print('EAWS Profile Load Error: $e');
    }
  }

  /// Save to per-user database store and update active session
  static Future<bool> saveToSession() async {
    try {
      // Save to per-user isolated storage
      await UserDataStore.instance.saveUserProfile({
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'dob': dob,
        'bloodType': bloodType,
        'medicalConditions': medicalConditions,
        'homeAddress': homeAddress,
        'allergies': allergies,
        'medications': medications,
        'communicationPreference': communicationPreference,
        'avatarUrl': avatarUrl,
      });

      // Update UserSession
      UserSession.instance.setDisplayName(fullName, email: email, phone: phone);

      // Save to Express backend via PATCH /me
      try {
        await EawsApiClient.instance.patch('/me', body: {
          'full_name': fullName,
          'phone_number': phone,
          'dob': dob,
          'blood_type': bloodType,
          'medical_conditions': medicalConditions,
          'home_address': homeAddress,
          'allergies': allergies,
          'medications': medications,
          'communication_preference': communicationPreference,
          'avatar_url': avatarUrl,
        });
      } catch (patchErr) {
        print('EAWS saveToSession PATCH /me note: $patchErr');
      }

      // Save to Supabase Auth if connected
      final client = Supabase.instance.client;
      if (client.auth.currentUser != null) {
        await client.auth.updateUser(
          UserAttributes(
            data: {
              'full_name': fullName,
              'phone_number': phone,
              'dob': dob,
              'blood_type': bloodType,
              'medical_conditions': medicalConditions,
              'home_address': homeAddress,
              'allergies': allergies,
              'medications': medications,
              'communication_preference': communicationPreference,
              'avatar_url': avatarUrl,
            },
          ),
        );
      }
      return true;
    } catch (e) {
      print('EAWS Profile Save Error: $e');
      return false;
    }
  }

  /// Upload new avatar to backend and update profile
  static Future<String?> uploadAvatar(dynamic fileOrBytes, {String? fileName}) async {
    try {
      String base64Content;
      String name = fileName ?? 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (fileOrBytes is List<int>) {
        base64Content = base64Encode(fileOrBytes);
      } else {
        final bytes = await fileOrBytes.readAsBytes();
        base64Content = base64Encode(bytes);
        try {
          if (fileOrBytes.name != null) name = fileOrBytes.name;
        } catch (_) {}
      }

      final res = await EawsApiClient.instance.post('/me/avatar', body: {
        'file_name': name,
        'file_base64': base64Content,
      });

      if (res != null && res['avatar_url'] != null) {
        avatarUrl = res['avatar_url'].toString();
        await saveToSession();
        return avatarUrl;
      }
    } catch (e) {
      print('EAWS uploadAvatar error: $e');
    }
    return null;
  }
}
