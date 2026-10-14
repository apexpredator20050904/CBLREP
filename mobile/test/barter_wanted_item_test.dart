import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/screens/create_listing_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// A barter is two-sided: the poster states what they want in return and the
/// neighbour answers by offering something. These tests pin both halves of
/// that contract at the edges the UI owns:
///
///  1. `ListingModel` reads `wanted_item` from the API and treats a free/paid
///     listing (which has no return side) as having none.
///  2. The post form only asks for the return wish on a barter listing, so a
///     "free" or "paid" post never sends a meaningless `wanted_item`.
Map<String, dynamic> _json({String compensation = 'barter', Object? wanted}) => {
      'id': 1,
      'title': 'A borrowed drill',
      'description': 'Works fine.',
      'type': 'offer',
      'compensation_type': compensation,
      'wanted_item': ?wanted,
      'category': 'Tools',
      'condition': 'Good',
      'barangay': 'Poblacion',
      'purok_sitio': 'Purok 3',
      'owner': {'id': 5, 'name': 'Maria'},
    };

void main() {
  group('ListingModel.wantedItem', () {
    test('reads and trims the return wish', () {
      final model = ListingModel.fromJson(_json(wanted: '  A sack of rice  '));
      expect(model.wantedItem, 'A sack of rice');
      expect(model.hasWantedItem, isTrue);
    });

    test('is absent when the owner did not name one', () {
      final model = ListingModel.fromJson(_json());
      expect(model.wantedItem, isNull);
      expect(model.hasWantedItem, isFalse);
    });

    test('a free listing has no return side', () {
      // The backend nulls wanted_item for non-barter listings; the model must
      // not invent one if a stale payload carries it anyway.
      final model = ListingModel.fromJson(_json(compensation: 'free', wanted: 'nothing'));
      expect(model.isBarter, isFalse);
      expect(model.hasWantedItem, isFalse,
          reason: 'free listings render no return-wish row and no trade CTA.');
    });
  });

  group('CreateListingScreen barter return field', () {
    Future<void> useTallSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    Widget host() => MaterialApp(theme: CblrepTheme.lightCream, home: const CreateListingScreen());

    testWidgets('asks for the return wish by default (barter)', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('In return, I would like (optional)'), findsOneWidget);
    });

    testWidgets('hides the return wish for a free listing', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Free'));
      await tester.pumpAndSettle();

      expect(find.text('In return, I would like (optional)'), findsNothing,
          reason: 'A free gift has no return side to ask about.');
    });
  });
}
