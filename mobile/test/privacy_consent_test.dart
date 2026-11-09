import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/screens/register_screen.dart';
import 'package:untitled1/screens/verification_screen.dart';

void main() {
  late AuthProvider auth;

  setUp(() {
    auth = AuthProvider(ApiService.instance)..loading = false;
  });

  tearDown(() {
    auth.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('registration stays disabled until privacy consent is checked',
      (tester) async {
    await pumpScreen(tester, const RegisterScreen());
    await tester.scrollUntilVisible(
      find.text('Register'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final register = find.widgetWithText(FilledButton, 'Register');
    expect(tester.widget<FilledButton>(register).onPressed, isNull);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(tester.widget<FilledButton>(register).onPressed, isNotNull);
  });

  testWidgets('verification stays disabled until privacy consent is checked',
      (tester) async {
    await pumpScreen(tester, const VerificationScreen());
    await tester.scrollUntilVisible(
      find.text('Submit for review'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final submit = find.widgetWithText(FilledButton, 'Submit for review');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });
}
