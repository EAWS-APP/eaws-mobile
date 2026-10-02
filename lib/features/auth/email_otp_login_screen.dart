import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'auth_service.dart';
import 'otp_verification_screen.dart';

class EmailOtpLoginScreen extends StatefulWidget {
  const EmailOtpLoginScreen({super.key});

  @override
  State<EmailOtpLoginScreen> createState() => _EmailOtpLoginScreenState();
}

class _EmailOtpLoginScreenState extends State<EmailOtpLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@') || email.endsWith('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid email address.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final sent = await AuthService.instance.sendOTP(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not send the sign-in code. Check your connection and try again.',
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OTPVerificationScreen(email: email)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('Sign in with email')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'We’ll email you a one-time sign-in code.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isLoading ? null : _sendCode,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Email me a code'),
            ),
          ],
        ),
      ),
    );
  }
}
