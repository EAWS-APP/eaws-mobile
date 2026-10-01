import 'package:flutter/material.dart';
import 'package:eaws_app/core/supabase_mock.dart';
import 'core/theme.dart';
import 'features/auth/splash_screen.dart';

import 'features/dashboard/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase using the credentials from the linked citizen_app setup
  await Supabase.initialize(
    url: 'https://sswwdizgwctfwirhmroj.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzd3dkaXpnd2N0Zndpcmhtcm9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY5NDg1MjcsImV4cCI6MjA5MjUyNDUyN30.QS9S21U3d2fX2OTvO79dPKxFryyolw3HonOaMecd-50',
  );

  runApp(const EAWSApp());
}

class EAWSApp extends StatelessWidget {
  const EAWSApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'EAWS Citizen App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: session != null ? const DashboardScreen() : const SplashScreen(),
    );
  }
}
