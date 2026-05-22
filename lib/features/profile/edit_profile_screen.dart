import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import 'profile_data.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;
  late TextEditingController _bloodController;
  late TextEditingController _conditionsController;
  late TextEditingController _addressController;
  
  // Recommended premium emergency controllers
  late TextEditingController _allergiesController;
  late TextEditingController _medicationsController;
  late TextEditingController _commPreferenceController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Load existing profile values
    ProfileData.loadFromSession();

    _nameController = TextEditingController(text: ProfileData.fullName);
    _emailController = TextEditingController(text: ProfileData.email);
    _phoneController = TextEditingController(text: ProfileData.phone);
    _dobController = TextEditingController(text: ProfileData.dob);
    _bloodController = TextEditingController(text: ProfileData.bloodType);
    _conditionsController = TextEditingController(text: ProfileData.medicalConditions);
    _addressController = TextEditingController(text: ProfileData.homeAddress);
    
    // Initialize recommended emergency controllers
    _allergiesController = TextEditingController(text: ProfileData.allergies);
    _medicationsController = TextEditingController(text: ProfileData.medications);
    _commPreferenceController = TextEditingController(text: ProfileData.communicationPreference);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _bloodController.dispose();
    _conditionsController.dispose();
    _addressController.dispose();
    
    // Dispose recommended emergency controllers
    _allergiesController.dispose();
    _medicationsController.dispose();
    _commPreferenceController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    // Save to local profile data holder
    ProfileData.fullName = _nameController.text.trim();
    ProfileData.email = _emailController.text.trim();
    ProfileData.phone = _phoneController.text.trim();
    ProfileData.dob = _dobController.text.trim();
    ProfileData.bloodType = _bloodController.text.trim();
    ProfileData.medicalConditions = _conditionsController.text.trim();
    ProfileData.homeAddress = _addressController.text.trim();
    
    // Save recommended emergency values
    ProfileData.allergies = _allergiesController.text.trim();
    ProfileData.medications = _medicationsController.text.trim();
    ProfileData.communicationPreference = _commPreferenceController.text.trim();

    // Persist to Supabase dynamically
    final success = await ProfileData.saveToSession();

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (success) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true); // Return true to trigger state refresh on parent
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Profile Changes Saved!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving changes. Please try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic stationary header height matching Edit Profile content
    final double headerHeight = MediaQuery.of(context).padding.top + 238;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Form(
        key: _formKey,
        child: Stack(
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

                    // Form fields
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // PERSONAL INFO CARD
                          const Text(
                            'PERSONAL INFO',
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
                                _buildInputTile(
                                  icon: LucideIcons.user,
                                  label: 'Full Name',
                                  controller: _nameController,
                                  validator: (val) => val == null || val.isEmpty ? 'Name cannot be empty' : null,
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.mail,
                                  label: 'Email Address',
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return 'Email cannot be empty';
                                    if (!val.contains('@')) return 'Enter a valid email';
                                    return null;
                                  },
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.phone,
                                  label: 'Phone Number',
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  validator: (val) => val == null || val.isEmpty ? 'Phone cannot be empty' : null,
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.calendar,
                                  label: 'Date of Birth',
                                  controller: _dobController,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // EMERGENCY INFO CARD
                          const Text(
                            'EMERGENCY INFO',
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
                                _buildInputTile(
                                  icon: LucideIcons.droplet,
                                  label: 'Blood Type',
                                  controller: _bloodController,
                                  hintText: 'e.g. O+, A-',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.heart,
                                  label: 'Medical Conditions',
                                  controller: _conditionsController,
                                  hintText: 'e.g. Asthma, Diabetes',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.mapPin,
                                  label: 'Home Address',
                                  controller: _addressController,
                                  hintText: 'Enter home address',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.alertOctagon,
                                  label: 'Allergies & Reactions',
                                  controller: _allergiesController,
                                  hintText: 'e.g. Penicillin, Latex, Peanuts',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.pill,
                                  label: 'Current Medications',
                                  controller: _medicationsController,
                                  hintText: 'e.g. Aspirin, Insulin',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.phoneCall,
                                  label: 'Communication Preference',
                                  controller: _commPreferenceController,
                                  hintText: 'e.g. Voice Call, Text Only',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 36),

                          // Big Red Save Button matching Screenshot 1
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _handleSave,
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Save Changes'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                elevation: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text(
                              'Changes are synced to your EAWS profile',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

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
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 20,
                  right: 20,
                  bottom: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Custom Unified White App Bar Row inside the red cover block
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                          },
                        ),
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _isSaving
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: _handleSave,
                                child: const Text(
                                  'Save',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Avatar stack
                    Stack(
                      children: [
                        // White Initials Avatar
                        CircleAvatar(
                          radius: 46, // Extremely clean and compact
                          backgroundColor: Colors.white,
                          child: Text(
                            ProfileData.initials,
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Red Camera Overlay Edit Circle
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Triggering photo gallery access...'),
                                  backgroundColor: AppTheme.primaryColor,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                LucideIcons.camera,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                      },
                      child: const Text(
                        'Change Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputTile({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    FormFieldValidator<String>? validator,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // Styled pink background circle box for left icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          const SizedBox(width: 14),

          // Label + input fields
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  validator: validator,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14.5,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
