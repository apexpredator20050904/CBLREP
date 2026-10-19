import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/providers/live_hub_provider.dart';
import 'package:untitled1/screens/home_feed_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';
import 'package:untitled1/widgets/listing_card.dart';
import 'package:untitled1/widgets/listing_skeleton.dart';

/// The redesigned home feed.
///
/// The feed is the screen every member sees first, so the things that
/// matter here are: the greeting and the barangay quick-filter (the hero),
/// the sticky search-and-filter bar, the card's contents, the empty and
/// loading states, and the report action that runs from the card's menu.
///
/// The listings themselves are replayed from a local stub, so the card is
/// rendered from the same payload the backend actually sends.
/// The state a [HomeFeedScreen] is rendered in.
class _FeedState {
  final List<ListingModel> listings;
  final bool loading;
  const _FeedState(this.listings, {this.loading = false});
}

/// A provider that never touches the network — used by the tests that only
/// care about how the feed renders a given state.
class _StaticListingsProvider extends ListingsProvider {
  _StaticListingsProvider(this._state) : super(ApiService.instance);

  final _FeedState _state;

  @override
  void startAutoRefresh({Duration interval = const Duration(seconds: 12)}) {}

  @override
  Future<void> load({
    String? query,
    String? barangay,
    String? category,
    bool showSpinner = true,
  }) async {
    if (_state.loading) {
      loading = true;
    } else {
      listings = _state.listings;
      loading = false;
    }
    error = null;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with
  // 400; these tests talk to a real socket.
  HttpOverrides.global = null;

  late HttpServer server;

  /// The bodies the stub received, so the test can assert the payload.
  final received = <Map<String, dynamic>>[];

  /// How many listings the stub returns.
  int listingCount = 1;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    received.clear();
    listingCount = 1;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8171);
    ApiService.instance.setBaseUrlForTesting('http://127.0.0.1:8171/api');
    server.listen((request) async {
      final path = request.uri.path;
      final method = request.method;
      final raw = await utf8.decoder.bind(request).join();

      if (path == '/api/platform/status') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"status":"ok","maintenance":false}');
        await request.response.close();
        return;
      }

      if (path == '/api/listings' && method == 'GET') {
        final rows = List<Map<String, dynamic>>.generate(listingCount, (i) => {
              'id': 100 + i,
              'title': 'Second-hand rice cooker #${i + 1}',
              'description': 'Works perfectly, barely used.',
              'category': 'Tools',
              'condition': 'Like New',
              'location': 'Poblacion, Purok 3',
              'barangay': 'Poblacion',
              'purok_sitio': 'Purok 3',
              'type': 'offer',
              'compensation_type': 'barter',
              'compensation_label': 'BARTER',
              'wanted_item': '5 kg of rice',
              'status': 'active',
              'is_active': true,
              'owner': {
                'id': 9,
                'name': 'Maria Concepcion',
                'avatar_url': null,
                'verified': true,
              },
            });

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'listings': rows,
          'data': rows,
          'meta': {'total': rows.length, 'has_more': false},
        }));
        await request.response.close();
        return;
      }

      if (path == '/api/reports' && method == 'POST') {
        received.add(raw.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw) as Map));

        request.response.statusCode = 201;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'message': 'Report received.',
          'report': {
            'id': 1,
            'reportable_type': 'listing',
            'reportable_id': 100,
            'reason': 'scam',
            'status': 'pending',
          },
          'listing_flagged': false,
        }));
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"message":"Not Found."}');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  UserModel _member() => const UserModel(
        id: 2,
        name: 'Juan Dela Cruz',
        email: 'juan@example.test',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        verified: true,
        verificationStatus: 'Verified',
      );

  ListingModel _listing({int id = 100, String wanted = '5 kg of rice'}) =>
      ListingModel(
        id: id,
        title: 'Second-hand rice cooker',
        description: 'Works perfectly, barely used.',
        category: 'Tools',
        condition: 'Like New',
        location: 'Poblacion, Purok 3',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        owner: 'Maria Concepcion',
        ownerId: 9,
        ownerVerified: true,
        type: 'offer',
        compensationType: 'barter',
        compensationLabel: 'BARTER',
        wantedItem: wanted,
        active: true,
      );

  /// A provider that never touches the network — used by the tests that only
  /// care about how the feed renders a given state.
  Widget _host({
    List<ListingModel> listings = const [],
    bool loading = false,
    bool withProviders = true,
  }) {
    final content = MaterialApp(
      theme: CblrepTheme.lightCream,
      // A Scaffold, exactly like the app shell the feed really lives in: it
      // is what gives the confirmation snackbar somewhere to appear.
      home: const Scaffold(body: HomeFeedScreen()),
    );
    if (!withProviders) return content;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(ApiService.instance)..user = _member(),
        ),
        ChangeNotifierProvider<ListingsProvider>(
          create: (_) => _StaticListingsProvider(
            _FeedState(listings, loading: loading),
          ),
        ),
        ChangeNotifierProvider<LiveHubProvider>(
          create: (_) => LiveHubProvider(ApiService.instance),
        ),
      ],
      child: content,
    );
  }

  /// The home feed loads its listings in `initState`, so the socket round
  /// trip has to happen in the real async zone.
  Future<void> pumpFeed(WidgetTester tester, Widget widget) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });
    await tester.pumpAndSettle();
  }

  /// Pumps a feed that is showing the shimmer skeletons.
  ///
  /// The skeleton shimmers forever by design, so `pumpAndSettle` would never
  /// return — the feed is pumped a fixed number of frames instead.
  Future<void> pumpLoadingFeed(WidgetTester tester, Widget widget) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Home feed', () {
    testWidgets('greets the member and offers the barangay quick filter',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpFeed(tester, _host(listings: [_listing()]));

      expect(find.textContaining('Maayong'), findsOneWidget,
          reason: 'The hero must greet the member in the local language.');
      expect(find.textContaining('What would you like to barter today?'),
          findsOneWidget);
      expect(find.text('Barangay'), findsOneWidget);
      // The quick filter starts on "All of Trinidad" and offers the
      // member's own barangay.
      expect(find.text('All of Trinidad'), findsOneWidget);
      expect(find.text('Poblacion'), findsOneWidget,
          reason: 'The quick filter offers the member\'s own barangay.');
    });

    testWidgets('keeps the search, category and sort controls on screen',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpFeed(tester, _host(listings: [_listing()]));

      expect(find.text('Search offers and needs'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget,
          reason: 'The sort control names the current order.');

      // The category chips are a horizontally scrolling row, so the ones past
      // the fold are only built once they are scrolled into view.
      final chips = find.byKey(const Key('home-filter-chips'));
      final scroller = find.descendant(of: chips, matching: find.byType(Scrollable));
      for (final category in ['Tools', 'Agriculture', 'Electronics', 'Services']) {
        await tester.scrollUntilVisible(find.text(category), 120, scrollable: scroller);
        expect(find.text(category), findsOneWidget,
            reason: 'The filter bar must offer the "$category" chip.');
      }
    });

    testWidgets('shows a shimmer skeleton while the feed loads', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpLoadingFeed(tester, _host(loading: true));

      expect(find.byType(ListingSkeletonCard), findsWidgets,
          reason: 'A loading feed must show skeletons, not a bare spinner.');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a friendly empty state when nothing has been posted',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpFeed(tester, _host());

      expect(find.text('No listings yet'), findsOneWidget);
      expect(find.textContaining('Be the first'), findsOneWidget);
    });

    testWidgets('renders the realistic resource card', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpFeed(tester, _host(listings: [_listing()]));

      expect(find.byType(ListingCard), findsOneWidget);
      // The condition tag.
      expect(find.text('Like New'), findsOneWidget);
      // The owner's wishlist.
      expect(find.textContaining('WANTED FOR BARTER'), findsOneWidget);
      expect(find.textContaining('5 kg of rice'), findsOneWidget);
      // The location and the owner.
      expect(find.textContaining('Poblacion'), findsWidgets);
      expect(find.text('Maria Concepcion'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsWidgets);
      // The two fast actions and the report menu.
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Propose Barter'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('lays out cleanly on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpFeed(tester, _host(listings: [_listing()]));

      expect(tester.takeException(), isNull,
          reason: 'A 320dp phone must not overflow the redesigned feed.');
    });

    testWidgets('lays out cleanly on a large phone', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpFeed(tester, _host(listings: [_listing()]));

      expect(tester.takeException(), isNull);
    });

    testWidgets('reports a listing from the card menu and confirms it',
        (tester) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // The real provider, so the report really travels to the server.
      await pumpFeed(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(ApiService.instance)..user = _member(),
            ),
            ChangeNotifierProvider<ListingsProvider>(
              create: (_) => ListingsProvider(ApiService.instance),
            ),
            ChangeNotifierProvider<LiveHubProvider>(
              create: (_) => LiveHubProvider(ApiService.instance),
            ),
          ],
          child: MaterialApp(
            theme: CblrepTheme.lightCream,
            home: const Scaffold(body: HomeFeedScreen()),
          ),
        ),
      );

      expect(find.byType(ListingCard), findsOneWidget,
          reason: 'The stub must have served the listing.');

      // The card's three-dot menu.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Report posting'), findsOneWidget);

      await tester.tap(find.text('Report posting'));
      await tester.pumpAndSettle();

      // The sheet names the posting and asks why.
      expect(find.text('Report this posting'), findsOneWidget);
      expect(find.text('Second-hand rice cooker #1'), findsWidgets);

      await tester.tap(find.text('Scam or fraud'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Submit report'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pumpAndSettle();

      // The report really reached the server...
      expect(received, hasLength(1));
      expect(received.single['reportable_type'], 'listing');
      expect(received.single['reportable_id'], 100);
      expect(received.single['reason'], 'scam');

      // ...and the member was thanked for it.
      expect(
        find.textContaining('Thank you for helping keep our community safe'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull,
          reason: 'Reporting must never crash the UI.');
    });
  });
}
