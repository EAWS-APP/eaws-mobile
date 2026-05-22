// This is a basic Flutter widget test for the EAWS Citizen application.
import 'package:flutter_test/flutter_test.dart';
import 'package:eaws_app/main.dart';
import 'package:eaws_app/features/auth/splash_screen.dart';

void main() {
  testWidgets('App starts with SplashScreen test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EAWSApp());

    // Verify that the SplashScreen starts first
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
