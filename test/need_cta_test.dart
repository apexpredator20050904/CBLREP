import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/listing_detail_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';
import 'package:untitled1/widgets/listing_card.dart';

/// A NEED is answered from the other side of the table.
///
/// On an OFFER the neighbour is the demander, so the actions are "make a
/// trade offer" and "make an offer". On a NEED they are the SUPPLIER — they
/// have what the poster is looking for — so the actions become "I have this"
/// and "I can supply it". Showing the offer-side wording on a need would ask
/// someone to trade FOR the very thing they are bringing.
///
/// These tests pin that mirroring on the detail screen and the feed card.
ListingModel _listing({
  String type = 'offer',
  String compensation = 'barter',
  double? price,
  bool negotiable = false,
  String? wanted,
}) =>
    ListingModel(
      id: 1,
      title: 'Rice',
      description: 'For the weekend meal.',
      owner: 'Maria',
      ownerId: 7,
      type: type,
      compensationType: compensation,
      compensationLabel: compensation == 'paid'
          ? 'PAID'
          : (compensation == 'free' ? 'FREE SHARING' : 'BARTER'),
      price: price,
      priceNegotiable: negotiable,
      wantedItem: wanted,
      quantity: type == 'request' ? '5 kg' : null,
      priceRole: type == 'request' ? 'budget' : 'asking',
      wantedItemRole:
          type == 'request' ? 'offers_in_return' : 'wants_in_return',
      conditionRole:
          type == 'request' ? 'acceptable_condition' : 'item_state',
      imagesRole: type == 'request' ? 'reference_photos' : 'item_photos',
      category: 'Food',
      condition: type == 'request' ? 'Any' : 'Good',
      location: 'Poblacion, Purok 3',
      barangay: 'Poblacion',
      purokSitio: 'Purok 3',
      active: true,
    );

/// ListingDetailScreen reads the signed-in member from AuthProvider, so the
/// host must supply one.
Widget _detailHost(ListingModel listing) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(ApiService.instance),
        ),
        ChangeNotifierProvider<ListingsProvider>(
          create: (_) => ListingsProvider(ApiService.instance),
        ),
      ],
      child: MaterialApp(
        theme: CblrepTheme.lightCream,
        home: ListingDetailScreen(listing: listing),
      ),
    );

Widget _cardHost(ListingModel listing) => MaterialApp(
      theme: CblrepTheme.lightCream,
      home: Scaffold(body: ListingCard(listing: listing)),
    );

void main() {
  /// The detail screen is a ListView, so the action buttons at the bottom
  /// are only built when the viewport is tall enough to include them.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('a barter need offers "I have this", not a trade offer',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(_detailHost(_listing(type: 'request')));
    await tester.pumpAndSettle();

    expect(find.text('I have this'), findsOneWidget);
    expect(find.text('Make a trade offer'), findsNothing,
        reason: 'On a need the neighbour already has the wanted item.');
  });

  testWidgets('a barter offer still offers a trade offer', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(_detailHost(_listing()));
    await tester.pumpAndSettle();

    expect(find.text('Make a trade offer'), findsOneWidget);
    expect(find.text('I have this'), findsNothing);
  });

  testWidgets('a paid need offers "I can supply it"', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(
        _detailHost(_listing(type: 'request', compensation: 'paid', price: 300)));
    await tester.pumpAndSettle();

    expect(find.text('I can supply it'), findsOneWidget);
    expect(find.text('Budget up to'), findsOneWidget,
        reason: 'The figure on a need is the poster\'s ceiling, not an asking price.');
  });

  testWidgets('a paid offer keeps the offer wording', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(_detailHost(
        _listing(compensation: 'paid', price: 300, negotiable: true)));
    await tester.pumpAndSettle();

    expect(find.text('Make an offer'), findsOneWidget);
    expect(find.text('I can supply it'), findsNothing);
  });

  testWidgets('the feed card names the action by direction', (tester) async {
    await tester.pumpWidget(_cardHost(_listing(type: 'request')));
    await tester.pumpAndSettle();
    expect(find.text('I Have This'), findsOneWidget);

    await tester.pumpWidget(_cardHost(_listing()));
    await tester.pumpAndSettle();
    expect(find.text('Propose Barter'), findsOneWidget);

    await tester.pumpWidget(
        _cardHost(_listing(type: 'request', compensation: 'paid', price: 300)));
    await tester.pumpAndSettle();
    expect(find.text('I Can Supply'), findsOneWidget);
  });
}
