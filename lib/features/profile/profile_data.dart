import '../auth/auth_service.dart';

class ProfileData {
  static String fullName = '';
  static String email = '';
  static String phone = '';
  static String dob = '';
  static String bloodType = '';
  static String medicalConditions = '';
  static String homeAddress = '';
  static String allergies = '';
  static String medications = '';
  static String communicationPreference = '';

  static String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'EA';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static void loadFromSession() {
    final user = AuthService.instance.currentProfile;
    fullName =
        user['full_name']?.toString() ??
        AuthService.instance.currentUserName ??
        '';
    email = AuthService.instance.currentUserEmail ?? '';
    phone =
        user['phone_number']?.toString() ??
        AuthService.instance.currentUserPhone ??
        '';
    dob = user['dob']?.toString() ?? '';
    bloodType = user['blood_type']?.toString() ?? '';
    medicalConditions = user['medical_conditions']?.toString() ?? '';
    homeAddress = user['home_address']?.toString() ?? '';
    allergies = user['allergies']?.toString() ?? '';
    medications = user['medications']?.toString() ?? '';
    communicationPreference =
        user['communication_preference']?.toString() ?? '';
  }

  static Future<bool> saveToSession() {
    return AuthService.instance.updateUserProfile({
      'full_name': fullName,
      'phone_number': phone,
      'dob': dob,
      'blood_type': bloodType,
      'medical_conditions': medicalConditions,
      'home_address': homeAddress,
      'allergies': allergies,
      'medications': medications,
      'communication_preference': communicationPreference,
    });
  }
}
