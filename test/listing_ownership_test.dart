import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/listing_detail_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// "Close my listing" must be an owner-only affordance.
///
/// The backend already scopes PATCH/DELETE to the owner (404 for everyone
/// else), but the UI used to render the button on *every* listing — so a
/// member opening a neighbour's listing saw "Close my listing" on an item
/// they do not own, and tapping it only produced a confusing 404.
///
/// Same screen, same class of bug: the "Message / Inquire" buttons let you
/// open a chat with yourself. The backend 422s on that, but the buttons
/// should not be offered either.
ListingModel _listing({required int ownerId}) => ListingModel(
      id: 1,
      title: 'A borrowed drill',
      description: 'Works fine.',
      category: 'Tools',
      condition: 'Good',
      location: 'Poblacion, Purok 3',
      barangay: 'Poblacion',
      purokSitio: 'Purok 3',
      imageUrl: null,
      owner: 'Maria',
      ownerId: ownerId,
      type: 'offer',
      compensationType: 'barter',
      compensationLabel: 'BARTER',
      price: null,
      active: true,
    );

UserModel _user(int id) => UserModel(
      id: id,
      name: 'Test Member',
      email: 'member@example.test',
      barangay: 'Poblacion',
      purokSitio: 'Purok 3',
      verified: false,
      verificationStatus: 'Unverified',
      verificationNote: null,
    );

Widget _host(ListingModel listing, UserModel? user) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(ApiService.instance)..user = user,
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
  group('ListingDetailScreen ownership', () {
    const ownerId = 7;

    // The detail screen is a long ListView; buttons past the fold are not
    // built at the default 800x600 test surface. A tall viewport keeps the
    // whole action column in the tree.
    Future<void> useTallSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    testWidgets('shows Close to the owner only', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(_host(_listing(ownerId: ownerId), _user(ownerId)));
      await tester.pumpAndSettle();

      expect(find.text('Close my listing'), findsOneWidget,
          reason: 'The poster must be able to close their own listing.');
      expect(find.text('Message / Inquire'), findsNothing,
          reason: 'You cannot message yourself.');
      expect(find.text('Start a negotiation'), findsNothing,
          reason: 'You cannot negotiate with yourself.');
    });

    testWidgets('hides Close from a non-owner', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(_host(_listing(ownerId: ownerId), _user(99)));
      await tester.pumpAndSettle();

      expect(find.text('Close my listing'), findsNothing,
          reason: 'Only the poster may close the listing.');
      expect(find.text('Message / Inquire'), findsOneWidget,
          reason: 'A non-owner must be able to reach the poster.');
      expect(find.text('Start a negotiation'), findsOneWidget);
    });

    testWidgets('hides Close when signed out', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(_host(_listing(ownerId: ownerId), null));
      await tester.pumpAndSettle();

      expect(find.text('Close my listing'), findsNothing,
          reason: 'A signed-out visitor is never the owner.');
      expect(find.text('Message / Inquire'), findsOneWidget);
    });

    testWidgets('Message / Inquire offers sign-in instead of a 401', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(_host(_listing(ownerId: ownerId), null));
      await tester.pumpAndSettle();

      // The listing feed is public, so a visitor reaches this screen without
      // a session. POST /conversations is authenticated, so tapping the button
      // blind only ever produced the backend's raw "Unauthenticated." string.
      await tester.tap(find.text('Message / Inquire'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in required'), findsOneWidget,
          reason: 'A visitor must be offered the sign-in form, not a '
              'server-side error they cannot act on.');
      expect(find.text('Sign in'), findsOneWidget);
    });
  });
}
