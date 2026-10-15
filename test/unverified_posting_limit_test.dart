import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';

/// Phase 3 — progressive trust: an unverified member may keep only a few
/// listings live at once, and completing residency verification lifts the cap.
///
/// The cap itself is enforced server-side (see UnverifiedPostingLimitTest in
/// the backend suite). These tests cover the client half: the getters the Post
/// and Profile screens read to warn a member before the server has to reject
/// them, and that the `/api/my-listings` `limits` envelope is actually parsed
/// rather than silently dropped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with 400;
  // the integration case below talks to a real socket.
  HttpOverrides.global = null;

  group('ListingsProvider posting limits', () {
    test('an unverified envelope exposes the cap and current usage', () {
      final provider = ListingsProvider(ApiService.instance)
        ..myLimits = {
          'verified': false,
          'active_used': 2,
          'active_max': 3,
        };

      expect(provider.postingIsUnlimited, isFalse);
      expect(provider.activePostLimit, 3);
      expect(provider.activePostCount, 2);
    });

    test('a verified envelope is unlimited (active_max is null)', () {
      final provider = ListingsProvider(ApiService.instance)
        ..myLimits = {'verified': true, 'active_used': 5, 'active_max': null};

      expect(provider.postingIsUnlimited, isTrue);
      expect(provider.activePostLimit, isNull);
    });

    test('an empty envelope is treated as unlimited, not capped', () {
      // Before the first load the app must not nag a member whose real status
      // it has not fetched yet.
      final provider = ListingsProvider(ApiService.instance);

      expect(provider.postingIsUnlimited, isTrue);
      expect(provider.activePostLimit, isNull);
    });

    test('active usage falls back to the counts when the envelope omits it', () {
      final provider = ListingsProvider(ApiService.instance)
        ..myLimits = {'verified': false, 'active_max': 3}
        ..myCounts = {'active': 1};

      expect(provider.activePostCount, 1);
    });
  });

  test('loadMine parses the limits envelope from /api/my-listings', () async {
    SharedPreferences.setMockInitialValues({});

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8130);
    ApiService.instance.setBaseUrlForTesting('http://127.0.0.1:8130/api');
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"listings":[],"data":[],"counts":{"all":2,"active":2},'
        '"limits":{"verified":false,"active_used":2,"active_max":3}}',
      );
      await request.response.close();
    });

    try {
      final provider = ListingsProvider(ApiService.instance);
      await provider.loadMine();

      expect(provider.myLimits['verified'], isFalse);
      expect(provider.activePostLimit, 3);
      expect(provider.activePostCount, 2);
      expect(provider.postingIsUnlimited, isFalse);
    } finally {
      await server.close(force: true);
    }
  });

  group('CreateListingScreen notice', () {
    Widget host({required UserModel user, Map<String, dynamic>? limits}) =>
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => AuthProvider(ApiService.instance)..user = user,
            ),
            ChangeNotifierProvider(
              create: (_) => ListingsProvider(ApiService.instance)
                ..myLimits = limits ?? const <String, dynamic>{},
            ),
          ],
          child: const MaterialApp(home: CreateListingScreen()),
        );

    const unverified = UserModel(
      id: 9,
      name: 'New Member',
      email: 'new@example.test',
      barangay: 'Poblacion',
      purokSitio: 'Purok 3',
      verified: false,
      verificationStatus: 'Unverified',
    );

    const verified = UserModel(
      id: 10,
      name: 'Verified Member',
      email: 'verified@example.test',
      barangay: 'Poblacion',
      purokSitio: 'Purok 3',
      verified: true,
      verificationStatus: 'Verified',
    );

    testWidgets('warns an unverified member how many slots they have used',
        (tester) async {
      await tester.pumpWidget(host(
        user: unverified,
        limits: const {'verified': false, 'active_used': 2, 'active_max': 3},
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 of 3 active listings used'), findsOneWidget);
      expect(find.text('Get verified'), findsOneWidget);
    });

    testWidgets('does not nag a verified member', (tester) async {
      await tester.pumpWidget(host(user: verified));
      await tester.pumpAndSettle();

      expect(find.text('Get verified'), findsNothing);
      expect(find.textContaining('active listings'), findsNothing);
    });
  });
}
