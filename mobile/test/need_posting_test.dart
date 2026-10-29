import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// Posting a NEED is not the same act as posting an OFFER.
///
/// The two share every column but read them from opposite ends: on an offer
/// the price is what you ask and the condition is the item's state; on a need
/// the price is your budget ceiling and the condition is what you can accept.
/// A need also cannot be free — asking for something for nothing is not a want
/// ad, posting a gift is what an offer is for.
///
/// These tests pin the form at the edges the UI owns:
///   1. the Free option disappears on a need (and the form cannot be left in
///      the illegal cell);
///   2. the shared fields are worded for the direction they are read in;
///   3. an offer form is unchanged.
Map<String, dynamic> _needJson() => {
      'id': 9,
      'title': 'Rice',
      'description': 'For the weekend meal.',
      'type': 'request',
      'compensation_type': 'barter',
      'wanted_item': '2 hours of childcare',
      'wanted_item_role': 'offers_in_return',
      'price_role': 'budget',
      'condition_role': 'acceptable_condition',
      'images_role': 'reference_photos',
      'quantity': '5 kg',
      'category': 'Food',
      'condition': 'Any',
      'barangay': 'Poblacion',
      'purok_sitio': 'Purok 3',
      'owner': {'id': 5, 'name': 'Maria'},
    };

void main() {
  group('ListingModel direction', () {
    test('a need reads the shared columns from the other end', () {
      final model = ListingModel.fromJson(_needJson());
      expect(model.isNeed, isTrue);
      expect(model.isBudget, isTrue);
      expect(model.wantedIsOffer, isTrue);
      expect(model.conditionIsRequirement, isTrue);
      expect(model.photosAreReferences, isTrue);
      expect(model.quantity, '5 kg');
    });

    test('an offer keeps its own reading', () {
      final model = ListingModel.fromJson({
        'id': 1,
        'title': 'Rice',
        'type': 'offer',
        'compensation_type': 'barter',
        'category': 'Food',
        'condition': 'Good',
        'barangay': 'Poblacion',
        'purok_sitio': 'Purok 3',
        'owner': {'id': 5, 'name': 'Maria'},
      });
      expect(model.isNeed, isFalse);
      expect(model.isBudget, isFalse);
      expect(model.wantedIsOffer, isFalse);
      expect(model.conditionIsRequirement, isFalse);
      expect(model.photosAreReferences, isFalse);
      expect(model.quantity, isNull);
    });
  });

  group('CreateListingScreen direction', () {
    Future<void> useTallSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    Widget host() => MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => AuthProvider(ApiService.instance)
                ..user = const UserModel(
                  id: 1,
                  name: 'Verified Tester',
                  email: 'verified@example.test',
                  barangay: 'Poblacion',
                  purokSitio: 'Purok 3',
                  verified: true,
                  verificationStatus: 'Verified',
                ),
            ),
            ChangeNotifierProvider(
              create: (_) => ListingsProvider(ApiService.instance),
            ),
          ],
          child: MaterialApp(
              theme: CblrepTheme.lightCream, home: const CreateListingScreen()),
        );

    /// Switch the form to the NEED direction.
    Future<void> switchToNeed(WidgetTester tester) async {
      await tester.tap(find.text('Need'));
      await tester.pumpAndSettle();
    }

    testWidgets('an offer keeps the Free option and the offer wording',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsOneWidget);
      expect(find.text('In return, I would like (optional)'), findsOneWidget);
      expect(find.text('I can pay up to (₱)'), findsNothing);
      expect(find.text('How much do you need?'), findsNothing);
    });

    testWidgets('a need hides Free and moves the form into the legal cell',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // "Free" is a segment of the compensation button, and "Need" is a
      // segment of the direction button — count only the compensation one.
      expect(find.text('Free'), findsOneWidget);

      await switchToNeed(tester);

      expect(find.text('Free'), findsNothing,
          reason: 'A need cannot be free — it is answered with a trade or a payment.');
      expect(find.text('Barter'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('a need asks for the quantity and rewords the shared fields',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await switchToNeed(tester);

      expect(find.text('How much do you need?'), findsOneWidget);
      expect(find.text('In return, I can offer (optional)'), findsOneWidget);
      expect(find.text('In return, I would like (optional)'), findsNothing);
      expect(find.text('Posting a NEED — you are looking for this.'),
          findsOneWidget);
      // The quick-select unit picker and urgency chips are NEED-only.
      expect(find.text('Unit'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('How soon do you need it?'), findsOneWidget);
      expect(find.text('Urgent / Today'), findsOneWidget);
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('Flexible'), findsOneWidget);
    });

    testWidgets('a paid need asks for a budget, not a price', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await switchToNeed(tester);
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();

      expect(find.text('I can pay up to (₱)'), findsOneWidget);
      expect(find.text('Price (₱)'), findsNothing);
      expect(find.text('Price is negotiable'), findsNothing,
          reason: 'A budget ceiling is not negotiable against itself.');
    });
  });
}
