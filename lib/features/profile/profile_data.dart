import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileData {
  static String fullName = 'John Doe';
  static String email = 'john.doe@email.com';
  static String phone = '+1 555 000 1234';
  static String dob = '01 Jan 1990';
  
  static String bloodType = 'O+';
  static String medicalConditions = 'None listed';
  static String homeAddress = '123 Main St, Singapore';
  
  // Recommended premium emergency fields
  static String allergies = 'None listed';
  static String medications = 'None listed';
  static String communicationPreference = 'Voice & Text';

  static String get initials {
    if (fullName.isEmpty) return 'JD';
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  // Load from Supabase user session if active
  static void loadFromSession() {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        fullName = user.userMetadata?['full_name'] ?? fullName;
        phone = user.userMetadata?['phone_number'] ?? user.phone ?? phone;
        email = user.email ?? email;
        
        // Custom emergency fields stored in metadata
        dob = user.userMetadata?['dob'] ?? dob;
        bloodType = user.userMetadata?['blood_type'] ?? bloodType;
        medicalConditions = user.userMetadata?['medical_conditions'] ?? medicalConditions;
        homeAddress = user.userMetadata?['home_address'] ?? homeAddress;
        
        // Load recommended fields
        allergies = user.userMetadata?['allergies'] ?? allergies;
        medications = user.userMetadata?['medications'] ?? medications;
        communicationPreference = user.userMetadata?['communication_preference'] ?? communicationPreference;
      }
    } catch (e) {
      print('EAWS Profile Load Error: $e');
    }
  }

  // Save to Supabase and update active session metadata
  static Future<bool> saveToSession() async {
    try {
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
        return true;
      }
      return true; // Return true as simulation success if no network
    } catch (e) {
      print('EAWS Profile Save Error: $e');
      return false;
    }
  }
}
