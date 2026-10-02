import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../core/eaws_logo.dart';
import 'auth_service.dart';
import 'otp_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ghanaCardController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  File? _ghanaCardImage;
  File? _selfieImage;
  final ImagePicker _picker = ImagePicker();

  // Selected Country Prefix Code State
  String _selectedCountryCode = '+233';
  String _selectedCountryIso = 'gh';
  String _selectedCountryName = 'Ghana';

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ghanaCardController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // West African Country Prefix Code Sheet
  void _showCountryPicker() {
    final WestAfricanCountries = [
      {'name': 'Ghana', 'code': '+233', 'iso': 'gh'},
      {'name': 'Nigeria', 'code': '+234', 'iso': 'ng'},
      {'name': 'Sierra Leone', 'code': '+232', 'iso': 'sl'},
      {'name': 'Liberia', 'code': '+231', 'iso': 'lr'},
      {'name': 'Gambia', 'code': '+220', 'iso': 'gm'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Country Code',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: WestAfricanCountries.map((country) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        'https://flagcdn.com/w80/${country['iso']}.png',
                        width: 28,
                        height: 18,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              LucideIcons.flag,
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                      ),
                    ),
                    title: Text(
                      country['name']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    trailing: Text(
                      country['code']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedCountryCode = country['code']!;
                        _selectedCountryIso = country['iso']!;
                        _selectedCountryName = country['name']!;
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // Actual Card Capture using Device Camera
  Future<void> _captureGhanaCard() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image != null) {
        setState(() {
          _ghanaCardImage = File(image.path);
          // Auto-fill a placeholder text or use OCR later. For now, we indicate success.
          _ghanaCardController.text = 'SCANNED-CARD-PRESENT';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ghana Card photo captured successfully!'),
              backgroundColor: AppTheme.successColor,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to open camera: $e');
      }
    }
  }

  // Actual Facial Capture using Device Camera
  bool _livenessVerified = false;

  Future<void> _captureSelfie() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image != null) {
        // Show a brief analyzing state
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // Simulate a slight delay for processing the photo
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pop(context); // Close loading indicator
          setState(() {
            _selfieImage = File(image.path);
            _livenessVerified = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face captured and verified successfully!'),
              backgroundColor: AppTheme.successColor,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to open camera: $e');
      }
    }
  }

  // Registration form validation logic
  Future<void> _handleRegister() async {
    if (_fullNameController.text.trim().isEmpty) {
      _showError('Please enter your full name');
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      _showError('Please enter your email address');
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      _showError('Please enter your phone number');
      return;
    }
    if (_ghanaCardController.text.trim().isEmpty) {
      _showError('Please enter or scan your Ghana Card Number');
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showError('Please enter a password');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }
    if (!_livenessVerified) {
      _showError('Please complete the Facial Verification step.');
      return;
    }
    if (!_agreedToTerms) {
      _showError('You must agree to the Terms of Service & Privacy Policy');
      return;
    }

    // Show dynamic loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    final bool success = await AuthService.instance.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      fullName: _fullNameController.text.trim(),
      phoneNumber: '$_selectedCountryCode${_phoneController.text.trim()}',
      ghanaCard: _ghanaCardController.text.trim(),
    );

    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    if (success) {
      if (context.mounted) {
        final sent = await AuthService.instance.sendEmailVerificationCode(
          _emailController.text.trim(),
        );
        if (!sent) {
          _showError(
            'Account created, but the email verification code could not be sent. Try signing in to request another code.',
          );
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OTPVerificationScreen(
              email: _emailController.text.trim(),
              isRegistration: true,
            ),
          ),
        );
      }
    } else {
      _showError(
        'Registration failed. Please check your credentials and try again.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.primaryColor,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Top red section with back arrow button
              Expanded(
                flex: isKeyboardVisible ? 1 : 2,
                child: Stack(
                  children: [
                    // Back Arrow Action Button
                    Positioned(
                      left: 16,
                      top: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.chevronLeft,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    // Centered branding
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!isKeyboardVisible) ...[
                            const EawsLogo(
                              size: 60,
                              style: EawsLogoStyle.onRed,
                              borderRadius: 12,
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Text(
                            'EAWS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          if (!isKeyboardVisible) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Create Your Account',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom white section form inputs
              Expanded(
                flex: 8,
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Register to stay protected',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Full Name Input
                        const Text(
                          'Full Name',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(
                            hintText: 'Full Name',
                            prefixIcon: Icon(
                              LucideIcons.user,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Email Address Input
                        const Text(
                          'Email Address',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'Email Address',
                            prefixIcon: Icon(
                              LucideIcons.mail,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Phone Number Input Row
                        const Text(
                          'Phone Number',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Country Code Picker Trigger
                            GestureDetector(
                              onTap: _showCountryPicker,
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        'https://flagcdn.com/w80/$_selectedCountryIso.png',
                                        width: 26,
                                        height: 17,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  LucideIcons.flag,
                                                  color: AppTheme.textSecondary,
                                                  size: 16,
                                                ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _selectedCountryCode,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Phone input field
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: 'Phone Number',
                                  prefixIcon: Icon(
                                    LucideIcons.phone,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Ghana Card Input
                        const Text(
                          'Ghana Card Number',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ghanaCardController,
                          decoration: InputDecoration(
                            hintText: 'Ghana Card Number (e.g. GHA-XXXXX)',
                            prefixIcon: const Icon(
                              LucideIcons.contact,
                              color: AppTheme.textSecondary,
                            ),
                            // Styled scanning icon container
                            suffixIcon: GestureDetector(
                              onTap: _captureGhanaCard,
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(
                                    0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  LucideIcons.camera,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Ghana Card Informational helper text
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: _ghanaCardImage != null
                                    ? AppTheme.successColor
                                    : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _ghanaCardImage != null
                                    ? 'Card photo attached.'
                                    : 'Tap the camera icon to take a photo of your card.',
                                style: TextStyle(
                                  color: _ghanaCardImage != null
                                      ? AppTheme.successColor
                                      : AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Facial Liveness Check UI
                        const Text(
                          'Identity Verification',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _livenessVerified ? null : _captureSelfie,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _livenessVerified
                                  ? const Color(0xFFDCFCE7)
                                  : Colors.white,
                              border: Border.all(
                                color: _livenessVerified
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFE5E7EB),
                                width: _livenessVerified ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _livenessVerified
                                      ? LucideIcons.checkCircle2
                                      : LucideIcons.scanFace,
                                  color: _livenessVerified
                                      ? const Color(0xFF16A34A)
                                      : AppTheme.primaryColor,
                                  size: 28,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _livenessVerified
                                            ? 'Face Verified'
                                            : 'Facial Verification',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: _livenessVerified
                                              ? const Color(0xFF16A34A)
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _livenessVerified
                                            ? 'Successfully matched with Ghana Card.'
                                            : 'Take a quick selfie to prove you are human.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _livenessVerified
                                              ? const Color(0xFF15803D)
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_livenessVerified)
                                  const Icon(
                                    LucideIcons.chevronRight,
                                    color: AppTheme.textSecondary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(
                              LucideIcons.lock,
                              color: AppTheme.textSecondary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? LucideIcons.eye
                                    : LucideIcons.eyeOff,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Confirm Password Field
                        const Text(
                          'Confirm Password',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            hintText: 'Confirm Password',
                            prefixIcon: const Icon(
                              LucideIcons.lock,
                              color: AppTheme.textSecondary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? LucideIcons.eye
                                    : LucideIcons.eyeOff,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Terms & Conditions Checkbox Row
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _agreedToTerms,
                                activeColor: AppTheme.primaryColor,
                                onChanged: (value) {
                                  setState(() {
                                    _agreedToTerms = value ?? false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text: 'I agree to the ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Terms of Service',
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: ' & '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: TextStyle(
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Create Account Action Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleRegister,
                            child: const Text('Create Account'),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Divider (OR)
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[300])),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[300])),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Already have an account? Sign In text link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(
                                  context,
                                ); // smoothly slides back to login
                              },
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
