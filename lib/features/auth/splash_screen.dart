import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/eaws_logo.dart';
import '../dashboard/dashboard_screen.dart';
import 'auth_service.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _navigationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AuthService.instance.isAuthenticated
                ? const DashboardScreen()
                : const LoginScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Center(
              child: const EawsLogo(
                size: 120,
                style: EawsLogoStyle.onRed,
                borderRadius: 24,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'EAWS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Emergency Alert & Warning System',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const Spacer(),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              'Initializing...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 48),
            const Text(
              'Powered by EAWS\n  v1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
