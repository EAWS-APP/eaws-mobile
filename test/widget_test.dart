// This is a basic Flutter widget test for the EAWS Citizen application.
import 'package:flutter_test/flutter_test.dart';
import 'package:eaws_app/main.dart';
import 'package:eaws_app/features/auth/splash_screen.dart';

void main() {
  testWidgets('App requires InsForge configuration before opening', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const EAWSApp());

    expect(find.textContaining('EAWS is not configured'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });
}
