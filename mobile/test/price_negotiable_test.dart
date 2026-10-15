import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/listing_detail_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// Phase 4 — negotiable pricing on a paid listing.
///
/// The backend normalises `price_negotiable` to false for free/barter, and the
/// model re-guards it, so the UI can never invite a price negotiation on a
/// listing that has no price. A negotiable sale shows the "Make an offer" route,
/// and the offer is delivered through the listing's own chat thread (the
/// Exchange model is deliberately a two-sided barter, so a counter-offer is a
/// conversation, not a recorded exchange).
void main() {
  ListingModel listing({
    String compensation = 'paid',
    double? price = 250,
    bool negotiable = true,
    int ownerId = 7,
  }) =>
      ListingModel(
        id: 1,
        title: 'A rice cooker',
        description: 'Works fine.',
        category: 'Electronics',
        condition: 'Good',
        location: 'Poblacion, Purok 3',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        owner: 'Maria',
        ownerId: ownerId,
        type: 'offer',
        compensationType: compensation,
        compensationLabel: switch (compensation) {
          'free' => 'FREE SHARING',
          'paid' => 'PAID',
          _ => 'BARTER',
        },
        price: price,
        priceNegotiable: negotiable,
        active: true,
      );

  UserModel user(int id) => UserModel(
        id: id,
        name: 'Buyer',
        email: 'buyer@example.test',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        verified: true,
        verificationStatus: 'Verified',
      );

  Widget host(ListingModel l, UserModel? u) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(ApiService.instance)..user = u,
          ),
          ChangeNotifierProvider(
            create: (_) => ListingsProvider(ApiService.instance),
          ),
        ],
        child: MaterialApp(
          theme: CblrepTheme.lightCream,
          home: ListingDetailScreen(listing: l),
        ),
      );

  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  test('the model only treats a paid listing as negotiable', () {
    ListingModel from(String compensation) => ListingModel.fromJson({
          'id': 1,
          'title': 'x',
          'compensation_type': compensation,
          'price': 100,
          'price_negotiable': true,
        });

    expect(from('paid').isNegotiable, isTrue);
    // A stray flag on a gift or a trade is ignored — there is no price to
    // negotiate, and the server strips it anyway.
    expect(from('free').isNegotiable, isFalse);
    expect(from('barter').isNegotiable, isFalse);
  });

  testWidgets('offers Make an offer on a negotiable sale', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(host(listing(), user(99)));
    await tester.pumpAndSettle();

    expect(find.text('Negotiable'), findsOneWidget);
    expect(find.text('Make an offer'), findsOneWidget);
    expect(find.text('Message / Buy'), findsOneWidget);
  });

  testWidgets('hides the offer route on a fixed-price sale', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(host(listing(negotiable: false), user(99)));
    await tester.pumpAndSettle();

    expect(find.text('Negotiable'), findsNothing);
    expect(find.text('Make an offer'), findsNothing);
    expect(find.text('Message / Buy'), findsOneWidget);
  });

  testWidgets('Make an offer opens the offer dialog', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(host(listing(), user(99)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Make an offer'));
    await tester.pumpAndSettle();

    expect(find.text('Send offer'), findsOneWidget);
    // Prefilled with the listed price so a buyer can nudge it up or down.
    expect(find.widgetWithText(TextField, '250'), findsOneWidget);
  });

  testWidgets('an owner is not offered the route on their own sale',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(host(listing(ownerId: 7), user(7)));
    await tester.pumpAndSettle();

    expect(find.text('Make an offer'), findsNothing);
    expect(find.text('Negotiable'), findsOneWidget,
        reason: 'The owner still sees that their sale is negotiable.');
  });
}
