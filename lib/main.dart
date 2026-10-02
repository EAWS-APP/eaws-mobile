import 'package:flutter/material.dart';

import 'core/insforge_client.dart';
import 'core/theme.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/auth/splash_screen.dart';

const bool _demoMode = bool.fromEnvironment('EAWS_DEMO_MODE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await InsForgeClient.instance.restoreSession();
  runApp(const EAWSApp());
}

class EAWSApp extends StatelessWidget {
  const EAWSApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_demoMode && !InsForgeClient.isConfigured) {
      return MaterialApp(
        title: 'EAWS Citizen App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'EAWS is not configured. Provide INSFORGE_BASE_URL and '
                'INSFORGE_ANON_KEY with --dart-define to connect the app.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'EAWS Citizen App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _demoMode ? const DashboardScreen() : const SplashScreen(),
      builder: (context, child) {
        if (!_demoMode) return child ?? const SizedBox.shrink();
        return Column(
          children: [
            Material(
              color: const Color(0xFF8A1C1C),
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'DEMO MODE · TEST DATA ONLY · TEST chat only · No real calls, SMS, or dispatch',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}
