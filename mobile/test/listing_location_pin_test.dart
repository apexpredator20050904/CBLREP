import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';

/// Phase 4 — pin an exact location on a listing.
///
/// The barangay + purok already place a listing on the community map (the API
/// fills a barangay anchor when no coordinates are stored). A pin is an optional
/// refinement: the gate, the store, the exact corner a neighbour must find. The
/// Post form must offer it without forcing it, and the model must round-trip the
/// coordinates the backend returns.
void main() {
  UserModel member() => const UserModel(
        id: 1,
        name: 'Member',
        email: 'member@example.test',
        barangay: 'Bongbong',
        purokSitio: 'Purok 3',
        verified: true,
        verificationStatus: 'Verified',
      );

  Widget host(UserModel user) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(ApiService.instance)..user = user,
          ),
          ChangeNotifierProvider(
            create: (_) => ListingsProvider(ApiService.instance),
          ),
        ],
        child: const MaterialApp(home: CreateListingScreen()),
      );

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  test('the model round-trips stored coordinates', () {
    final pinned = ListingModel.fromJson({
      'id': 1,
      'title': 'x',
      'latitude': 10.08123,
      'longitude': 124.34211,
    });
    expect(pinned.latitude, closeTo(10.08123, 1e-9));
    expect(pinned.longitude, closeTo(124.34211, 1e-9));

    // No coordinates stored → the API's barangay anchor is applied server-side,
    // so the model simply has none.
    final anchored = ListingModel.fromJson({'id': 2, 'title': 'y'});
    expect(anchored.latitude, isNull);
    expect(anchored.longitude, isNull);
  });

  testWidgets('the Post form offers an optional exact pin', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host(member()));
    await tester.pumpAndSettle();

    expect(find.text('Pin the exact spot (optional)'), findsOneWidget);
    expect(find.text('Set'), findsOneWidget);
  });

  testWidgets('tapping Set opens the map picker', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host(member()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set'));
    // Explicit pumps rather than pumpAndSettle: the picker embeds a slippy map
    // whose tiles the test HTTP layer rejects, so we only wait for the route
    // transition instead of for the map to "settle".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pin exact location'), findsOneWidget);
    expect(find.text('Use this point'), findsWidgets);
  });
}
