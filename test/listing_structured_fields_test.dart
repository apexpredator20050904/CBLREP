import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// Structured quantity + urgency on the Post form.
///
/// A NEED is a shopping-list entry, so it asks for a number and a unit instead
/// of a loose sentence, and how soon it has to be met. An OFFER keeps the
/// sharing wording and hides all three controls.
void main() {
  group('ListingModel structured quantity', () {
    test('reads the numeric pair and urgency from the API payload', () {
      final model = ListingModel.fromJson({
        'id': 9,
        'title': 'Rice',
        'type': 'request',
        'compensation_type': 'barter',
        'quantity': '2.5 bundles',
        'quantity_value': 2.5,
        'quantity_unit': 'bundle',
        'quantity_unit_label': 'bundles',
        'quantity_role': 'needed',
        'urgency': 'urgent',
        'urgency_label': 'Urgent / Today',
        'category': 'Food',
        'condition': 'Any',
        'barangay': 'Poblacion',
        'purok_sitio': 'Purok 3',
        'owner': {'id': 5, 'name': 'Maria'},
      });

      expect(model.quantityValue, 2.5);
      expect(model.quantityUnit, 'bundle');
      expect(model.quantityDisplay, '2.5 bundles');
      expect(model.hasUrgency, isTrue);
      expect(model.urgencyLabel, 'Urgent / Today');
    });

    test('falls back to formatting when only the structured pair is present', () {
      final model = ListingModel.fromJson({
        'id': 10,
        'title': 'Rice',
        'type': 'request',
        'compensation_type': 'barter',
        'quantity_value': 5,
        'quantity_unit': 'kg',
        'quantity_unit_label': 'kg',
        'category': 'Food',
        'condition': 'Any',
        'barangay': 'Poblacion',
        'purok_sitio': 'Purok 3',
        'owner': {'id': 5, 'name': 'Maria'},
      });

      expect(model.quantityDisplay, '5 kg');
    });

    test('a legacy free-text quantity still renders', () {
      final model = ListingModel.fromJson({
        'id': 11,
        'title': 'Rice',
        'type': 'request',
        'compensation_type': 'barter',
        'quantity': 'half a kilo',
        'category': 'Food',
        'condition': 'Any',
        'barangay': 'Poblacion',
        'purok_sitio': 'Purok 3',
        'owner': {'id': 5, 'name': 'Maria'},
      });

      expect(model.quantityDisplay, 'half a kilo');
      expect(model.hasUrgency, isFalse);
    });
  });

  group('CreateListingScreen structured fields', () {
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
            theme: CblrepTheme.lightCream,
            home: const CreateListingScreen(),
          ),
        );

    Future<void> useTallSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    Future<void> switchToNeed(WidgetTester tester) async {
      await tester.tap(find.text('Need'));
      await tester.pumpAndSettle();
    }

    testWidgets('an offer uses sharing copy and hides need-only controls',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('What are you offering?'), findsOneWidget);
      expect(
        find.text('Name the item or skill clearly — neighbours search by it.'),
        findsOneWidget,
      );
      expect(find.text('How much do you need?'), findsNothing);
      expect(find.text('How soon do you need it?'), findsNothing);
    });

    testWidgets('a need reveals the number, unit chips and urgency chips',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await switchToNeed(tester);

      expect(find.text('What do you need?'), findsOneWidget);
      expect(find.text('How much do you need?'), findsOneWidget);
      expect(find.text('Unit'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('sacks'), findsOneWidget);
      expect(find.text('How soon do you need it?'), findsOneWidget);
      expect(find.text('Urgent / Today'), findsOneWidget);

      // The picker is a real selection, not decoration.
      await tester.tap(find.text('sacks'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'sacks')).selected,
        isTrue,
      );

      await tester.tap(find.text('Urgent / Today'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Urgent / Today'))
            .selected,
        isTrue,
      );
    });

    testWidgets('a need cannot be submitted without an amount', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await switchToNeed(tester);
      await tester.tap(find.text('Post resource'));
      await tester.pumpAndSettle();

      expect(find.text('Enter how much you need'), findsOneWidget);
    });

    testWidgets('paid and barter terms slide in for a need', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await switchToNeed(tester);
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();

      expect(find.text('I can pay up to (₱)'), findsOneWidget);
      expect(find.text('Price is negotiable'), findsNothing,
          reason: 'A budget ceiling is not negotiable against itself.');
      expect(find.text('In return, I can offer (optional)'), findsNothing);

      await tester.tap(find.text('Barter'));
      await tester.pumpAndSettle();

      expect(find.text('I can pay up to (₱)'), findsNothing);
      expect(find.text('In return, I can offer (optional)'), findsOneWidget);
    });

    testWidgets('free sharing shows the no-price notice instead of fields',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Free'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No price needed — just add pickup notes so neighbours know where to collect.',
        ),
        findsOneWidget,
      );
      expect(find.text('In return, I would like (optional)'), findsNothing);
      expect(find.text('Price (₱)'), findsNothing);
    });
  });
}
