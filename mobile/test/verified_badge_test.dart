import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/widgets/verified_badge.dart';

/// Phase 2 — the verification payoff mark.
///
/// The compact form is a bare tick for a listing card's author line; the
/// default form is the labelled "Verified resident" pill used on the profile
/// and a listing's detail panel. These tests pin both so a refactor cannot
/// silently turn the labelled payoff back into an unlabelled icon.
void main() {
  Future<void> pumpBadge(WidgetTester tester, Widget badge) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: badge))),
    );
  }

  group('VerifiedBadge', () {
    testWidgets('compact form is just a tick with no label', (tester) async {
      await pumpBadge(tester, const VerifiedBadge(compact: true));

      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.text('Verified resident'), findsNothing);
    });

    testWidgets('default form shows the labelled pill', (tester) async {
      await pumpBadge(tester, const VerifiedBadge());

      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.text('Verified resident'), findsOneWidget);
    });

    testWidgets('the label can be overridden', (tester) async {
      await pumpBadge(tester, const VerifiedBadge(label: 'Verified'));

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Verified resident'), findsNothing);
    });
  });
}
