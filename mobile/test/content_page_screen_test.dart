import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/screens/content_page_screen.dart';

/// Public content pages on mobile — `GET /api/page/{slug}`.
///
/// The Laravel endpoint serves only `status = published AND published_at IS
/// NOT NULL` rows; a draft slug and an unknown slug are deliberately
/// indistinguishable (both 404). These tests replay both sides against a local
/// stub so the screen's two states are proven end to end:
///
///   1. a published page arrives → its HTML body renders;
///   2. a 404 (draft or typo) arrives → the error card shows and NO body text
///      is ever rendered.
///
/// The widget is pumped inside `tester.runAsync` on purpose: `initState`
/// creates the HttpClient, and real socket I/O issued from the fake-async test
/// zone never reaches the network — only code running in the real async zone
/// can complete an HTTP round trip (the same reason the stub-server tests in
/// this suite are plain `test()`s).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with
  // 400; these tests talk to a real socket.
  HttpOverrides.global = null;

  late HttpServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8141);
    ApiService.instance.setBaseUrlForTesting('http://127.0.0.1:8141/api');
    server.listen((request) async {
      await request.drain<void>();
      final path = request.uri.path;

      if (path == '/api/page/waste-segregation-guide') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'page': {
            'id': 1,
            'title': 'Waste Segregation Guide',
            'slug': 'waste-segregation-guide',
            'body': '<h2>Waste Segregation Guide</h2>'
                '<p>Sort into <strong>three bins</strong>.</p>'
                '<ul><li>Green bin</li><li>Blue bin</li><li>Black bin</li></ul>',
            'published_at': '2026-10-18T16:16:59+00:00',
            'updated_at': '2026-10-18T16:16:59+00:00',
          },
        }));
        await request.response.close();
        return;
      }

      // Draft / unknown slug — exactly what Laravel's firstOrFail() returns.
      request.response.statusCode = 404;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"message":"Not Found."}');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  testWidgets('a published page renders its HTML body', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: ContentPageScreen(slug: 'waste-segregation-guide'),
      ));
      // Give the real socket round trip time to complete.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    // The AppBar shows the fetched title (plain Text), the body's <h2> and
    // <p> render through flutter_widget_from_html (RenderParagraph — matched
    // with findRichText), and the publication date line is present.
    expect(find.text('Waste Segregation Guide'), findsWidgets);
    expect(find.textContaining('three bins', findRichText: true), findsOneWidget);
    expect(find.textContaining('Published '), findsOneWidget);
    expect(find.text('Could not load page'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a 404 (draft or unknown slug) shows the error card only',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: ContentPageScreen(slug: 'secret-draft'),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.text('Could not load page'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // No page content may leak into the error state.
    expect(find.textContaining('three bins', findRichText: true), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
