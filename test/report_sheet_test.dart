import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/theme/cblrep_theme.dart';
import 'package:untitled1/widgets/report_sheet.dart';

/// The community safety report sheet.
///
/// A report is the member's one lever against a scam, so the sheet has to do
/// three things without ever leaving the member stuck: offer every reason
/// the backend accepts, refuse to send an incomplete report, and survive a
/// server failure by showing the problem IN the sheet instead of crashing
/// or closing.
///
/// The submission itself is replayed against a local stub, so the test
/// proves the exact payload the backend receives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with
  // 400; these tests talk to a real socket.
  HttpOverrides.global = null;

  late HttpServer server;

  /// The bodies the stub received, so the test can assert the payload.
  final received = <Map<String, dynamic>>[];

  /// When set, the stub answers with this status and body instead of 201.
  int? failWithStatus;
  String failWithBody = '{"message":"You have already reported this."}';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    received.clear();
    failWithStatus = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8151);
    ApiService.instance.setBaseUrlForTesting('http://127.0.0.1:8151/api');
    server.listen((request) async {
      final path = request.uri.path;
      // The body is read ONCE — reading it and then draining the request
      // again would consume the same stream twice and kill the handler
      // before it could answer.
      final raw = await utf8.decoder.bind(request).join();

      if (path == '/api/reports' && request.method == 'POST') {
        if (failWithStatus != null) {
          request.response.statusCode = failWithStatus!;
          request.response.headers.contentType = ContentType.json;
          request.response.write(failWithBody);
          await request.response.close();
          return;
        }

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
            'reportable_id': 42,
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

  Widget host({String type = ReportTarget.listing}) => MaterialApp(
        theme: CblrepTheme.lightCream,
        home: Scaffold(
          body: ReportSheet(
            reportableType: type,
            reportableId: 42,
            subjectName: 'Second-hand rice cooker',
          ),
        ),
      );

  /// The sheet is taller than the default 800x600 test surface, so the
  /// reasons, the detail field and the submit button all have to be on
  /// screen for the taps to land.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  group('ReportSheet', () {
    testWidgets('offers every reason the backend accepts', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('Report this posting'), findsOneWidget);
      expect(find.text('Second-hand rice cooker'), findsOneWidget);

      for (final reason in ReportReason.all) {
        expect(
          find.text(ReportReason.label(reason)),
          findsOneWidget,
          reason: 'The sheet must offer "${ReportReason.label(reason)}".',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('titles itself for an account report', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host(type: ReportTarget.user));
      await tester.pumpAndSettle();

      expect(find.text('Report this account'), findsOneWidget);
    });

    testWidgets('refuses to send an incomplete report', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please choose a reason for your report.'),
        findsOneWidget,
        reason: 'A report without a reason cannot be grouped by a moderator.',
      );
      expect(received, isEmpty, reason: 'Nothing may be sent without a reason.');
    });

    testWidgets('sends the chosen reason and the optional detail',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scam or fraud'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Asked me to send a down payment first.',
      );
      await tester.pumpAndSettle();

      // The socket round trip has to happen in the real async zone.
      await tester.runAsync(() async {
        await tester.tap(find.text('Submit report'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      expect(received, hasLength(1));
      expect(received.single['reportable_type'], 'listing');
      expect(received.single['reportable_id'], 42);
      expect(received.single['reason'], 'scam');
      expect(
        received.single['description'],
        'Asked me to send a down payment first.',
      );
    });

    testWidgets('sends a report without a description when none was typed',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Harassment or abuse'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Submit report'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      expect(received, hasLength(1));
      expect(
        received.single.containsKey('description'),
        isFalse,
        reason: 'An empty description must be omitted, not sent as "".',
      );
    });

    testWidgets('shows a server failure inside the sheet', (tester) async {
      failWithStatus = 409;
      failWithBody = '{"message":"You have already reported this."}';

      await useTallSurface(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Counterfeit or fake'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Submit report'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      expect(
        find.text('You have already reported this.'),
        findsOneWidget,
        reason: 'The sheet must explain the failure where the member can see it.',
      );
      expect(
        find.text('Submit report'),
        findsOneWidget,
        reason: 'The sheet must stay open so the member can try again.',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
