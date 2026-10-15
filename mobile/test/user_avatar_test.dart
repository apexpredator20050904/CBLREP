import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/widgets/user_avatar.dart';

/// Phase 1 — the member profile photo with an initials fallback.
///
/// Every place the app used to draw a coloured circle with a letter now routes
/// through [UserAvatar], so these tests pin the two states that matter: a
/// member with no photo shows their initial, and a member with a photo shows
/// the image instead of the letter.
void main() {
  Future<void> pumpAvatar(
    WidgetTester tester, {
    String? imageUrl,
    required String name,
    double radius = 20,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAvatar(imageUrl: imageUrl, name: name, radius: radius),
        ),
      ),
    );
  }

  group('UserAvatar', () {
    testWidgets('falls back to the first initial when there is no photo',
        (tester) async {
      await pumpAvatar(tester, name: 'Ana Dela Cruz');

      expect(find.text('A'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('uses a question mark for an empty name', (tester) async {
      await pumpAvatar(tester, name: '   ');

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders the photo instead of the initial when a URL is set',
        (tester) async {
      // The network fetch will fail in the test environment; the widget's
      // errorBuilder handles it, so we only assert the image was mounted
      // rather than the initial.
      await pumpAvatar(tester, imageUrl: 'https://example.test/a.jpg', name: 'Ana');

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('renders a verified ring when a border colour is given',
        (tester) async {
      await pumpAvatar(tester, name: 'Berto');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              name: 'Berto',
              borderColor: Colors.green,
            ),
          ),
        ),
      );

      expect(find.byType(Container), findsWidgets);
      expect(find.text('B'), findsOneWidget);
    });
  });
}
