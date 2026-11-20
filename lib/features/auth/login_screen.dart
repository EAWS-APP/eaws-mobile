import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme.dart';
import '../../core/eaws_logo.dart';
import '../../core/user_session.dart';
import '../dashboard/dashboard_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'register_screen.dart';
import 'phone_login_screen.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _showError('Please enter your email address');
      return;
    }
    if (password.isEmpty) {
      _showError('Please enter your password');
      return;
    }

    // Show dynamic loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    final bool success = await AuthService.instance.signInWithEmail(
      email: email,
      password: password,
    );

    if (context.mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    if (success) {
      await UserSession.instance.load(force: true);
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      }
    } else {
      _showError('Invalid email or password. Please try again.');
    }
  }

  Future<void> _handleFaceIdLogin() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (photo == null || !mounted) return;

      // Show the Ghana Card suffix confirmation sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final suffixController = TextEditingController();
          bool isAuthenticating = false;

          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(LucideIcons.scanFace, color: AppTheme.primaryColor),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Face ID Authentication',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Live face captured. To confirm access, enter the last 3 characters of your registered Ghana Card PIN (e.g. 9-0 or 452).',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: suffixController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'e.g. 9-0',
                          prefixIcon: const Icon(LucideIcons.creditCard, color: AppTheme.textSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isAuthenticating
                              ? null
                              : () async {
                                  final suffix = suffixController.text.trim();
                                  if (suffix.length < 2) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter at least 2 or 3 characters of your Ghana Card PIN suffix.'),
                                        backgroundColor: AppTheme.errorColor,
                                      ),
                                    );
                                    return;
                                  }

                                  setSheetState(() => isAuthenticating = true);

                                  final result = await AuthService.instance.verifyFaceId(
                                    cardSuffix: suffix,
                                  );

                                  if (!context.mounted) return;
                                  setSheetState(() => isAuthenticating = false);

                                  if (result != null && result['success'] == true) {
                                    Navigator.pop(context); // Close sheet
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Biometric verification successful! Welcome back.'),
                                        backgroundColor: AppTheme.successColor,
                                      ),
                                    );
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => const DashboardScreen()),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Face ID and Ghana Card suffix could not be matched. Please check the 3 digits or use password login.'),
                                        backgroundColor: AppTheme.errorColor,
                                      ),
                                    );
                                  }
                                },
                          child: isAuthenticating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Verify & Sign In'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        _showError('Face capture error: $e');
      }
    }
  }

  void _showForgotPasswordSheet() {
    final resetEmailController = TextEditingController(text: _emailController.text);
    bool isResetting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Reset Password',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your email address and we will send you a link to reset your password.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Email Address',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'Enter your email',
                        prefixIcon: Icon(LucideIcons.mail, color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isResetting
                            ? null
                            : () async {
                                final email = resetEmailController.text.trim();
                                if (email.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter an email address'),
                                      backgroundColor: AppTheme.errorColor,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() {
                                  isResetting = true;
                                });

                                final success = await AuthService.instance.resetPasswordForEmail(email);

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  if (success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Password reset link sent to your email!'),
                                        backgroundColor: AppTheme.successColor,
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to send reset link. Please check your email and try again.'),
                                        backgroundColor: AppTheme.errorColor,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isResetting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Send Reset Link'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
            // Top red section
            Expanded(
              flex: isKeyboardVisible ? 1 : 2,
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
                      'Emergency Alert & Warning System',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Bottom white section
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
                      const SizedBox(height: 8),
                      Text(
                        'Welcome Back',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to your account',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Email Address',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          hintText: 'Email Address',
                          prefixIcon: Icon(LucideIcons.mail, color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Password',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: const Icon(LucideIcons.lock, color: AppTheme.textSecondary),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordSheet,
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleSignIn,
                          child: const Text('Sign In'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR', style: TextStyle(color: AppTheme.textSecondary)),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PhoneLoginScreen(),
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.phone, color: AppTheme.textPrimary),
                          label: const Text(
                            'Continue with Phone Number',
                            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _handleFaceIdLogin,
                          icon: const Icon(LucideIcons.scanFace, color: AppTheme.primaryColor),
                          label: const Text(
                            'Sign In with Face ID & Ghana Card',
                            style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: AppTheme.primaryColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Don\'t have an account? ', style: TextStyle(color: AppTheme.textSecondary)),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Register',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),
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
