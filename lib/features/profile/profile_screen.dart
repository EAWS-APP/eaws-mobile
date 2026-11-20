import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/login_screen.dart';
import 'profile_data.dart';
import 'edit_profile_screen.dart';
import 'messages_screen.dart';
import '../responder/responder_screen.dart';
import '../../core/notification_service.dart';


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
  int _contactCount = 0;

  @override
  void initState() {
    super.initState();
    _initProfile();
  }

  Future<void> _initProfile() async {
    await ProfileData.loadFromSession();
    
    // Load dynamic contacts count
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? contactsJson = prefs.getString('eaws_emergency_contacts');
      if (contactsJson != null) {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        _contactCount = decoded.length;
      }
    } catch (e) {
      print('Failed to load contacts count: $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _showEmergencyContactsSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('eaws_emergency_contacts');
    List<Map<String, dynamic>> contacts = [];
    if (raw != null) {
      try {
        final List decoded = jsonDecode(raw);
        contacts = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void addContactDialog() {
              final nameController = TextEditingController();
              final phoneController = TextEditingController();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('Add Emergency Contact', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Contact Name',
                          hintText: 'e.g. Papa, Sister, Kwame',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+233 24 000 0000',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final phone = phoneController.text.trim();
                        if (name.isNotEmpty && phone.isNotEmpty) {
                          String initials = name.trim().split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() : '').take(2).join();
                          if (initials.isEmpty) initials = name.substring(0, 1).toUpperCase();
                          setModalState(() {
                            contacts.add({'name': name, 'phone': phone, 'initials': initials});
                          });
                          await prefs.setString('eaws_emergency_contacts', jsonEncode(contacts));
                          try {
                            await EawsApiClient.instance.patch('/me', body: {'emergency_contacts': contacts});
                          } catch (_) {}
                          setState(() {
                            _contactCount = contacts.length;
                          });
                          Navigator.pop(ctx);
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Emergency Contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(LucideIcons.userPlus, color: AppTheme.primaryColor),
                          onPressed: addContactDialog,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: contacts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(LucideIcons.users, size: 48, color: Colors.grey),
                                const SizedBox(height: 12),
                                const Text('No emergency contacts added yet', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: addContactDialog,
                                  icon: const Icon(LucideIcons.plus),
                                  label: const Text('Add First Contact'),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: contacts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, idx) {
                              final c = contacts[idx];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                                    child: Text(c['initials'] ?? 'EC', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(c['name'] ?? 'Contact', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(c['phone'] ?? ''),
                                  trailing: IconButton(
                                    icon: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 20),
                                    onPressed: () async {
                                      setModalState(() {
                                        contacts.removeAt(idx);
                                      });
                                      await prefs.setString('eaws_emergency_contacts', jsonEncode(contacts));
                                      try {
                                        await EawsApiClient.instance.patch('/me', body: {'emergency_contacts': contacts});
                                      } catch (_) {}
                                      setState(() {
                                        _contactCount = contacts.length;
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
                                subtitle: '$_contactCount contacts added',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _showEmergencyContactsSheet();
                                },
                              ),
                              const Divider(height: 1),
                              _buildMenuTile(
                                icon: LucideIcons.messageCircle,
                                title: 'Control Room Messages',
                                subtitle: 'Direct line to dispatch operators',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen()));
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

                        // FIELD OPERATIONS SECTION (Sprint D)
                        const Text(
                          'FIELD OPERATIONS',
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
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                HapticFeedback.heavyImpact();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ResponderScreen(),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB).withOpacity(0.25),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                                      ),
                                      child: const Icon(
                                        LucideIcons.shieldCheck,
                                        color: Color(0xFF38BDF8),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'Responder Mode',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF059669),
                                                  borderRadius: BorderRadius.all(Radius.circular(4)),
                                                ),
                                                child: const Text(
                                                  'LIVE',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          const Text(
                                            'Field unit terminal: Accept CAD calls & stream GPS',
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      LucideIcons.chevronRight,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // CAD PUSH & REALTIME NOTIFICATIONS CARD (Sprint E)
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF334155), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        LucideIcons.bellRing,
                                        color: Color(0xFF38BDF8),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'CAD Push & Realtime Engine',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: NotificationService.instance.isRegistered
                                            ? const Color(0xFF059669).withOpacity(0.2)
                                            : const Color(0xFFD97706).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: NotificationService.instance.isRegistered
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFF59E0B),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: NotificationService.instance.isRegistered
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFFF59E0B),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            NotificationService.instance.isRegistered ? 'REGISTERED' : 'SYNCED',
                                            style: TextStyle(
                                              color: NotificationService.instance.isRegistered
                                                  ? const Color(0xFF34D399)
                                                  : const Color(0xFFFBBF24),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF020617),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(LucideIcons.smartphone, color: Color(0xFF64748B), size: 14),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          NotificationService.instance.deviceToken ?? 'Generating token...',
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          final token = NotificationService.instance.deviceToken ?? '';
                                          Clipboard.setData(ClipboardData(text: token));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Device push token copied to clipboard'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Icon(LucideIcons.copy, color: Color(0xFF38BDF8), size: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'SIMULATE DISPATCH TRIGGERS (TESTING):',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () {
                                          NotificationService.instance.simulateIncomingDispatch(
                                            agency: 'police',
                                            callsign: 'POL-KMS-04',
                                            incidentTitle: 'Armed Robbery at Adum',
                                            location: 'Kumasi Metro',
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Color(0xFF38BDF8), width: 1),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text(
                                          '🚨 Responder CAD',
                                          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () {
                                          NotificationService.instance.simulateCitizenStatusUpdate(
                                            status: 'en_route',
                                            callsign: 'AMB-KMS-02',
                                            etaMinutes: 4,
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text(
                                          '🚑 Citizen ETA',
                                          style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
                        backgroundImage: ProfileData.avatarUrl.isNotEmpty
                            ? NetworkImage(ProfileData.avatarUrl.startsWith('http')
                                ? ProfileData.avatarUrl
                                : '${EawsApiClient.baseUrl.replaceAll('/api', '')}${ProfileData.avatarUrl}')
                            : null,
                        child: ProfileData.avatarUrl.isEmpty
                            ? Text(
                                ProfileData.initials,
                                style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
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
