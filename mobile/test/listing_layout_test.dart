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

/// Builds a listing with deliberately hostile text — long author name, long
/// purok/sitio, long title — which is what previously drove the card and the
/// detail header past their bounds.
ListingModel _hostile({String type = 'offer', String compensation = 'paid'}) {
  return ListingModel(
    id: 1,
    title: 'Vintage wooden dining table with six matching chairs and a hand-carved '
        'bunga ornament that survived two typhoons',
    description: 'Long description. ' * 40,
    category: 'Furniture & Home Accessories',
    condition: 'Good condition, minor scratches',
    location: 'Barangay Poblacion, Purok 3',
    barangay: 'Manuel M. Roxas',
    purokSitio: 'Purok Poblacion Norte Maliksi Compound',
    imageUrl: null,
    owner: 'Maria Concepcion Dela Cruz Santos Jr.',
    ownerId: 7,
    type: type,
    compensationType: compensation,
    compensationLabel: compensation == 'paid'
        ? 'PAID'
        : (compensation == 'free' ? 'FREE SHARING' : 'BARTER'),
    price: compensation == 'paid' ? 125000.5 : null,
    active: true,
  );
}

Widget _host(ListingModel listing, double width) => MaterialApp(
      theme: CblrepTheme.lightCream,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ListingCard(listing: listing),
          ),
        ),
      ),
    );

/// Detail-screen host. ListingDetailScreen reads the signed-in member from
/// AuthProvider, so these tests must supply one — a bare MaterialApp makes
/// `context.select<AuthProvider, …>` throw.
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

void main() {
  group('ListingCard layout', () {
    // Widths covering a small Galaxy A-series (320dp), a mid-range phone in
    // portrait, and a large device in the 3-column grid.
    for (final width in [150.0, 165.0, 200.0, 260.0]) {
      testWidgets('lays out without overflow at ${width}dp', (tester) async {
        for (final compensation in ['free', 'barter', 'paid']) {
          await tester.pumpWidget(_host(_hostile(compensation: compensation), width));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}dp for $compensation');
        }
      });
    }

    testWidgets('long title and author truncate instead of overlapping',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_hostile(), 160));
      await tester.pumpAndSettle();

      final title = find.textContaining('Vintage wooden dining table');
      final owner = find.textContaining('Maria Concepcion');

      expect(title, findsOneWidget);
      expect(owner, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the hyper-local tag and compensation caption',
        (tester) async {
      await tester.pumpWidget(_host(_hostile(), 180));
      await tester.pumpAndSettle();

      expect(find.textContaining('Manuel M. Roxas'), findsOneWidget);
      expect(find.textContaining('PAID'), findsOneWidget);
    });
  });

  group('ListingDetailScreen layout', () {
    testWidgets('renders hostile content without overflow on a narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_detailHost(_hostile()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Item details'), findsOneWidget);
    });

    testWidgets('needs/offers and compensation badges do not collide',
        (tester) async {
      await tester.pumpWidget(_detailHost(_hostile(type: 'request', compensation: 'free')));
      await tester.pumpAndSettle();

      expect(find.text('NEED'), findsOneWidget);
      expect(find.textContaining('FREE SHARING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}