import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import 'profile_data.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Photo & Picker state
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedAvatarFile;
  Uint8List? _avatarBytes;

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

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? img = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (img != null) {
        final bytes = await img.readAsBytes();
        setState(() {
          _pickedAvatarFile = img;
          _avatarBytes = bytes;
        });
        // Upload immediately in background
        ProfileData.uploadAvatar(img);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick photo: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _showPhotoOptions() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.camera, color: AppTheme.primaryColor),
                title: const Text('Take a Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.image, color: AppTheme.primaryColor),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhoto(ImageSource.gallery);
                },
              ),
              if (_avatarBytes != null || ProfileData.avatarUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(LucideIcons.trash2, color: AppTheme.errorColor),
                  title: const Text('Remove Photo', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _pickedAvatarFile = null;
                      _avatarBytes = null;
                      ProfileData.avatarUrl = '';
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateOfBirth() async {
    HapticFeedback.lightImpact();
    final DateTime initial = DateTime(1995, 1, 1);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      setState(() {
        _dobController.text = '${picked.day} ${months[picked.month - 1]} ${picked.year}';
      });
    }
  }

  Future<void> _pickBloodType() async {
    HapticFeedback.lightImpact();
    const types = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Blood Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: types.map((t) {
                final isSelected = _bloodController.text == t;
                return ChoiceChip(
                  label: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppTheme.textPrimary)),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryColor,
                  backgroundColor: Colors.grey.shade100,
                  onSelected: (_) => Navigator.pop(ctx, t),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _bloodController.text = chosen;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    if (_pickedAvatarFile != null) {
      await ProfileData.uploadAvatar(_pickedAvatarFile);
    }

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
                                  readOnly: true,
                                  onTap: _pickDateOfBirth,
                                  hintText: 'Tap to select Date of Birth',
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
                                  readOnly: true,
                                  onTap: _pickBloodType,
                                  hintText: 'Tap to select Blood Type (e.g. O+, A-)',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.heart,
                                  label: 'Medical Conditions',
                                  controller: _conditionsController,
                                  hintText: 'e.g. Asthma, Hypertension, or None',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.mapPin,
                                  label: 'Home Address',
                                  controller: _addressController,
                                  hintText: 'Enter your residential address',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.alertOctagon,
                                  label: 'Allergies & Reactions',
                                  controller: _allergiesController,
                                  hintText: 'e.g. Penicillin, Latex, Peanuts, or None',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.pill,
                                  label: 'Current Medications',
                                  controller: _medicationsController,
                                  hintText: 'e.g. Aspirin, Insulin, or None',
                                ),
                                const Divider(height: 1),
                                _buildInputTile(
                                  icon: LucideIcons.phoneCall,
                                  label: 'Communication Preference',
                                  controller: _commPreferenceController,
                                  hintText: 'e.g. Voice & Text, SMS Only',
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
                        CircleAvatar(
                          radius: 46, // Extremely clean and compact
                          backgroundColor: Colors.white,
                          backgroundImage: _avatarBytes != null
                              ? MemoryImage(_avatarBytes!)
                              : (ProfileData.avatarUrl.isNotEmpty
                                  ? NetworkImage(ProfileData.avatarUrl.startsWith('http')
                                      ? ProfileData.avatarUrl
                                      : '${EawsApiClient.baseUrl.replaceAll('/api', '')}${ProfileData.avatarUrl}')
                                  : null) as ImageProvider<Object>?,
                          child: (_avatarBytes == null && ProfileData.avatarUrl.isEmpty)
                              ? Text(
                                  ProfileData.initials,
                                  style: const TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        // Red Camera Overlay Edit Circle
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showPhotoOptions,
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
                      onTap: _showPhotoOptions,
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
    bool readOnly = false,
    VoidCallback? onTap,
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
                  readOnly: readOnly,
                  onTap: onTap,
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
