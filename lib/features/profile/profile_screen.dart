import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import 'profile_data.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Preferences switch states matching Screenshot 2
  bool _receiveNotifications = true;
  bool _backgroundLocation = true;
  bool _offlineSMS = true;

  @override
  void initState() {
    super.initState();
    // Load from supabase or local session
    ProfileData.loadFromSession();
  }

  Future<void> _handleSignOut() async {
    // Show premium processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
        ),
      ),
    );

    // Trigger auth logout
    await AuthService.instance.signOut();

    if (mounted) {
      Navigator.pop(context); // Close loader
      // Clear navigation history back to Login screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Top fixed compact notch height calculation dynamically (adjusted from 225 to 238 to prevent dynamic scale pixel overflows)
    final double headerHeight = MediaQuery.of(context).padding.top + 238;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          // 1. Scrollable Body Content (placed underneath the fixed header notch)
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top padding spacer matching the header height so cards sit perfectly below it
                  SizedBox(height: headerHeight + 8),

                  // Profile Sections List
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ACCOUNT SECTION
                        const Text(
                          'ACCOUNT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                          ),
                          child: Column(
                            children: [
                              _buildMenuTile(
                                icon: LucideIcons.pencil,
                                title: 'Edit Profile',
                                subtitle: 'Name, email, address',
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const EditProfileScreen(),
                                    ),
                                  );
                                  // Refresh layout state if settings returned save confirm
                                  if (result == true) {
                                    setState(() {
                                      ProfileData.loadFromSession();
                                    });
                                  }
                                },
                              ),
                              const Divider(height: 1),
                              _buildMenuTile(
                                icon: LucideIcons.users,
                                title: 'Emergency Contacts',
                                subtitle: '3 contacts added',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                              ),
                              const Divider(height: 1),
                              _buildMenuTile(
                                icon: LucideIcons.smartphone,
                                title: 'Linked Devices',
                                subtitle: '2 devices',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // PREFERENCES SECTION
                        const Text(
                          'PREFERENCES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                          ),
                          child: Column(
                            children: [
                              _buildSwitchTile(
                                icon: LucideIcons.bell,
                                title: 'Notifications',
                                subtitle: 'Alerts & updates',
                                value: _receiveNotifications,
                                onChanged: (val) {
                                  setState(() {
                                    _receiveNotifications = val;
                                  });
                                },
                              ),
                              const Divider(height: 1),
                              _buildSwitchTile(
                                icon: LucideIcons.mapPin,
                                title: 'Background Location',
                                subtitle: 'For accurate SOS',
                                value: _backgroundLocation,
                                onChanged: (val) {
                                  setState(() {
                                    _backgroundLocation = val;
                                  });
                                },
                              ),
                              const Divider(height: 1),
                              _buildSwitchTile(
                                icon: LucideIcons.messageSquare,
                                title: 'Offline SMS Fallback',
                                subtitle: 'When no internet',
                                value: _offlineSMS,
                                onChanged: (val) {
                                  setState(() {
                                    _offlineSMS = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // SUPPORT SECTION
                        const Text(
                          'SUPPORT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                          ),
                          child: Column(
                            children: [
                              _buildMenuTile(
                                icon: LucideIcons.helpCircle,
                                title: 'Help & FAQ',
                                subtitle: '',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                              ),
                              const Divider(height: 1),
                              _buildMenuTile(
                                icon: LucideIcons.shieldAlert,
                                title: 'Report a Bug',
                                subtitle: '',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),

                        // White outline sign-out action button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              _showSignOutDialog();
                            },
                            icon: const Icon(LucideIcons.logOut, color: AppTheme.primaryColor, size: 18),
                            label: const Text(
                              'Sign Out',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Center(
                          child: Text(
                            'EAWS v1.0.2 • Build 245',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ], // children of Padding > Column
                    ), // Column
                  ), // Padding
                ], // children of SingleChildScrollView > Column
              ), // Column
            ), // SingleChildScrollView
          ), // Positioned.fill
          
          // 2. Fixed Top Curved Red Header Notch (stationary, stays stiff while list scrolls behind it!)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerHeight,
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                left: 20,
                right: 20,
                bottom: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App Bar Row inside container
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Use the bottom bar to switch screens!'),
                              backgroundColor: AppTheme.primaryColor,
                            ),
                          );
                        },
                      ),
                      const Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 48), // Invisible spacer to balance the back arrow and keep title centered perfectly
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Compact Initials Avatar with green verification check badge overlay
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 36, // Highly compact, neat aesthetic guidelines
                        backgroundColor: Colors.white,
                        child: Text(
                          ProfileData.initials,
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981), // Bright emerald green matching screenshot checkmark
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // User Name
                  Text(
                    ProfileData.fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17, // Neat compact size 17
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),

                  // User Phone
                  Text(
                    ProfileData.phone,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Soft light green Verified Citizen capsule matching Screenshot 2
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F7F0), // Soft mint green background
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'Verified Citizen',
                      style: TextStyle(
                        color: Color(0xFF10B981), // Solid emerald green text
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primaryColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
          fontSize: 14.5,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right,
        color: Color(0xFFD1D5DB),
        size: 18,
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primaryColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
          fontSize: 14.5,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: Switch.adaptive(
        value: value,
        activeColor: AppTheme.primaryColor,
        onChanged: (val) {
          HapticFeedback.selectionClick();
          onChanged(val);
        },
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out of the EAWS app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _handleSignOut();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
