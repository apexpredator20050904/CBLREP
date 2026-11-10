import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/core/greeting.dart';
import 'package:untitled1/widgets/welcome_header.dart';

/// The profile header greets the member in English, with the same time-of-day
/// wording as the home hero — not a fixed "Good day".
void main() {
  testWidgets('welcomes the member with the English time-of-day greeting',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WelcomeHeader(
          name: 'Juan Dela Cruz',
          subtitle: 'juan@example.com',
        ),
      ),
    ));

    expect(find.text('${greetingForNow()}, Juan Dela Cruz!'), findsOneWidget);
    expect(find.text('juan@example.com'), findsOneWidget);
  });
}
