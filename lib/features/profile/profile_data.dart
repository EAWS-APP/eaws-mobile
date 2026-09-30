import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/user_session.dart';
import '../../core/user_data_store.dart';

class ProfileData {
  static String fullName = UserSession.instance.displayName;
  static String email = UserSession.instance.email ?? 'kwame.asante@eaws.gov.gh';
  static String phone = UserSession.instance.phone ?? '+233 26 123 4567';
  static String dob = '15 Mar 1992';
  
  static String bloodType = 'O+';
  static String medicalConditions = 'None listed';
  static String homeAddress = 'Accra, Ghana';
  
  // Recommended premium emergency fields
  static String allergies = 'None listed';
  static String medications = 'None listed';
  static String communicationPreference = 'Voice & Text';

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

      // 3. Sync with active Supabase user metadata if connected
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
      });

      // Update UserSession
      UserSession.instance.setDisplayName(fullName, email: email, phone: phone);

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
}
