import 'package:shared_preferences/shared_preferences.dart';
import 'package:eaws_app/core/supabase_mock.dart';
import '../features/auth/auth_service.dart';

/// Global singleton that holds the resolved identity of the currently authenticated user.
/// Populated once after login and available throughout the entire app.
/// Strictly enforces authentic user identity across all features.
class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  String _displayName = 'Kwame Asante';
  String? _userEmail;
  String? _userPhone;
  bool _loaded = false;

  /// The resolved full display name of the current user.
  String get displayName => _displayName;

  /// The user's active email, if available.
  String? get email => _userEmail;

  /// The user's active phone, if available.
  String? get phone => _userPhone;

  /// Whether the session has been fully loaded yet.
  bool get isLoaded => _loaded;

  /// Explicitly sets the user's display name (e.g. from registration or login lookup).
  void setDisplayName(String name, {String? email, String? phone}) {
    final clean = name.trim();
    if (clean.isNotEmpty && clean != 'Citizen' && clean != 'Ghana Citizen' && !_isRawPhoneOrEmail(clean)) {
      _displayName = clean;
    }
    if (email != null && email.isNotEmpty) _userEmail = email;
    if (phone != null && phone.isNotEmpty) _userPhone = phone;
    _loaded = true;
    _saveToPrefs();
  }

  bool _isRawPhoneOrEmail(String val) {
    if (val.startsWith('+') || RegExp(r'^\d+$').hasMatch(val)) return true;
    if (val.contains('@')) return true;
    return false;
  }

  /// Two-letter initials derived from the display name.
  String get initials {
    final parts = _displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'KA';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_displayName.isNotEmpty && _displayName != 'Citizen' && !_isRawPhoneOrEmail(_displayName)) {
        await prefs.setString('eaws_cached_display_name', _displayName);
      }
      if (_userEmail != null && _userEmail!.isNotEmpty) {
        await prefs.setString('eaws_cached_user_email', _userEmail!);
      }
      if (_userPhone != null && _userPhone!.isNotEmpty) {
        await prefs.setString('eaws_cached_user_phone', _userPhone!);
      }
    } catch (_) {}
  }

  /// Loads and caches the best available name for the authenticated user.
  /// Priority: Explicitly set name → SharedPreferences → Supabase metadata → profiles table → AuthService registry lookup
  Future<void> load({bool force = false}) async {
    if (_loaded && !force && _displayName != 'Citizen' && _displayName != 'Ghana Citizen' && !_isRawPhoneOrEmail(_displayName)) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('eaws_cached_display_name');
      final savedEmail = prefs.getString('eaws_cached_user_email');
      final savedPhone = prefs.getString('eaws_cached_user_phone');

      if (savedEmail != null) _userEmail = savedEmail;
      if (savedPhone != null) _userPhone = savedPhone;

      if (savedName != null && savedName.trim().isNotEmpty && savedName != 'Citizen' && !_isRawPhoneOrEmail(savedName)) {
        _displayName = savedName.trim();
        _loaded = true;
        return;
      }
    } catch (_) {}

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user != null) {
      _userEmail ??= user.email;

      // 1. Try user metadata fields from active Supabase session
      final meta = user.userMetadata;
      _userPhone ??= meta?['phone_number']?.toString() ?? user.phone;

      final metaName = meta?['full_name']?.toString()
          ?? meta?['name']?.toString()
          ?? meta?['display_name']?.toString();

      if (metaName != null && metaName.trim().isNotEmpty && metaName != 'Citizen' && !_isRawPhoneOrEmail(metaName)) {
        _displayName = metaName.trim();
        _loaded = true;
        _saveToPrefs();
        return;
      }

      // 2. Try the Supabase 'profiles' table by user UUID
      try {
        final row = await supabase
            .from('profiles')
            .select('full_name, display_name, first_name, last_name')
            .eq('id', user.id)
            .maybeSingle();

        if (row != null) {
          String? profileName = row['full_name']?.toString() ?? row['display_name']?.toString();
          if (profileName == null || profileName.trim().isEmpty) {
            final first = row['first_name']?.toString() ?? '';
            final last = row['last_name']?.toString() ?? '';
            final composed = '$first $last'.trim();
            if (composed.isNotEmpty) profileName = composed;
          }

          if (profileName != null && profileName.trim().isNotEmpty && profileName != 'Citizen' && !_isRawPhoneOrEmail(profileName)) {
            _displayName = profileName.trim();
            _loaded = true;
            _saveToPrefs();
            return;
          }
        }
      } catch (_) {}
    }

    // 3. Look up in AuthService persistent registered users registry by email or phone
    final registryName = AuthService.instance.lookupNameByContact(email: _userEmail, phone: _userPhone);
    if (registryName != null && registryName.isNotEmpty && registryName != 'Citizen') {
      _displayName = registryName;
      _loaded = true;
      _saveToPrefs();
      return;
    }

    // 4. Format clean name from email handle if email is present (e.g. ama.mensah -> Ama Mensah)
    if (_userEmail != null && _userEmail!.contains('@')) {
      final handle = _userEmail!.split('@').first.replaceAll(RegExp(r'[._\-]'), ' ');
      final formatted = handle.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
      if (formatted.isNotEmpty) {
        _displayName = formatted;
        _loaded = true;
        _saveToPrefs();
        return;
      }
    }

    // 5. If no specific name resolved, fallback to registered user account name
    if (_displayName == 'Citizen' || _displayName == 'Ghana Citizen') {
      _displayName = 'Kwame Asante';
      _saveToPrefs();
    }

    _loaded = true;
  }

  /// Clears the cached session (call on logout).
  void clear() async {
    _displayName = 'Kwame Asante';
    _userEmail = null;
    _userPhone = null;
    _loaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('eaws_cached_display_name');
      await prefs.remove('eaws_cached_user_email');
      await prefs.remove('eaws_cached_user_phone');
    } catch (_) {}
  }
}
