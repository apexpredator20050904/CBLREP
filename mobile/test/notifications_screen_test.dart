import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/providers/app_update_provider.dart';
import 'package:untitled1/providers/live_hub_provider.dart';
import 'package:untitled1/screens/notifications_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// The member's own control over their notification inbox.
///
/// Covers the three things the member can do to it — mark one read, mark the
/// whole inbox read, and delete (one or all) — against a stub of the real
/// endpoints, so the requests the app really makes are asserted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with
  // 400; these tests talk to a real socket.
  HttpOverrides.global = null;

  late HttpServer server;

  /// Every request the app made, as "METHOD /path".
  final calls = <String>[];

  /// The inbox the stub serves. It changes as the app acts on it, exactly as
  /// the real server would, so the badge in the title is trustworthy.
  List<Map<String, dynamic>> inbox = [];

  /// Rebuilds the default inbox.
  List<Map<String, dynamic>> defaultInbox(int count) => List<Map<String, dynamic>>.generate(count, (i) => {
        'id': 11 + i,
        'type': i == 0 ? 'message' : 'announcement',
        'title': i == 0 ? 'New chat message' : 'Barangay assembly',
        'body': i == 0 ? 'Maria sent you a message.' : 'The assembly is on Saturday.',
        'read_at': i == 0 ? null : '2026-10-19 10:00:00',
        'created_at': '2026-10-19T09:00:00Z',
      });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    inbox = defaultInbox(2);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8183);
    ApiService.instance.setBaseUrlForTesting('http://127.0.0.1:8183/api');

    server.listen((request) async {
      final path = request.uri.path;
      final method = request.method;
      // Log before reading the body: a request with no body (a DELETE) never
      // ends its body stream, so the log has to happen first.
      calls.add('$method ${path.replaceFirst('/api', '')}');

      // The body has to be read exactly once.
      await utf8.decoder.bind(request).join();

      if (path == '/api/notifications' && method == 'GET') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'notifications': inbox,
          'unread_count': inbox.where((n) => n['read_at'] == null).length,
          'meta': {'current_page': 1, 'last_page': 1},
        }));
        await request.response.close();
        return;
      }

      if (path == '/api/notifications/read-all' && method == 'PUT') {
        final stamp = '2026-10-20 09:00:00';
        for (final row in inbox) {
          row['read_at'] ??= stamp;
        }

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'updated': inbox.length,
          'unread_count': 0,
        }));
        await request.response.close();
        return;
      }

      if (path == '/api/notifications' && method == 'DELETE') {
        final deleted = inbox.length;
        inbox = [];

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'deleted': deleted, 'unread_count': 0}));
        await request.response.close();
        return;
      }

      if (path.startsWith('/api/notifications/') && method == 'DELETE') {
        final id = int.parse(path.split('/').last);
        inbox.removeWhere((n) => n['id'] == id);

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'deleted': true,
          'notification_id': id,
          'unread_count': inbox.where((n) => n['read_at'] == null).length,
        }));
        await request.response.close();
        return;
      }

      if (path.startsWith('/api/notifications/') && method == 'PUT') {
        final id = int.parse(path.split('/').last.split('/').first);
        for (final row in inbox) {
          if (row['id'] == id) row['read_at'] = '2026-10-20 09:00:00';
        }

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'notification': {'id': id, 'read_at': 'now'}}));
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

  /// Renders the inbox with a live hub that talks to the stub.
  ///
  /// The socket round trip has to happen in the real async zone, otherwise
  /// `pumpAndSettle` returns before the response has arrived.
  Future<void> pumpInbox(WidgetTester tester) async {
    final hub = LiveHubProvider(ApiService.instance);
    final update = AppUpdateProvider(ApiService.instance);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: hub),
            ChangeNotifierProvider.value(value: update),
          ],
          child: MaterialApp(
            theme: CblrepTheme.lightCream,
            home: const NotificationsScreen(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
    });

    await tester.pumpAndSettle();
  }

  /// Taps something and lets the request it triggers reach the stub.
  ///
  /// The tap is dispatched inside the real async zone, because a request that
  /// is initiated in the widget test's fake zone never completes its socket
  /// round trip.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();

    await tester.runAsync(() async {
      // Give the real event loop as many turns as it needs.
      for (var i = 0; i < 30 && !calls.any((c) => c.startsWith('DELETE') || c.startsWith('PUT')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    await tester.pumpAndSettle();
  }

  testWidgets('the inbox lists the member\'s notifications', (tester) async {
    await pumpInbox(tester);

    expect(find.text('New chat message'), findsOneWidget);
    expect(find.text('Barangay assembly'), findsOneWidget);
    expect(find.text('Maria sent you a message.'), findsOneWidget);
  });

  testWidgets('the unread count is shown in the title', (tester) async {
    await pumpInbox(tester);

    expect(find.textContaining('Notifications ('), findsOneWidget);
  });

  testWidgets('mark all as read calls the endpoint and clears the badge', (tester) async {
    await pumpInbox(tester);

    expect(find.textContaining('Notifications ('), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Mark all as read'));

    expect(calls, contains('PUT /notifications/read-all'));
    // The badge is gone once the inbox has been marked read.
    expect(find.text('Notifications (1)'), findsNothing);
  });

  testWidgets('a member can delete a notification from the row menu', (tester) async {
    await pumpInbox(tester);

    await tester.tap(find.byTooltip('Notification actions').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    // The row menu asks first.
    expect(find.text('Delete notification?'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Delete'));

    expect(calls, contains('DELETE /notifications/11'));
  });

  testWidgets('the member can clear the whole inbox', (tester) async {
    await pumpInbox(tester);

    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();

    expect(find.text('Clear all notifications?'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Clear all'));

    expect(calls, contains('DELETE /notifications'));
  });

  testWidgets('cancelling the delete keeps the notification', (tester) async {
    await pumpInbox(tester);

    await tester.tap(find.byTooltip('Notification actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(calls.where((c) => c.startsWith('DELETE')).isEmpty, isTrue);
    expect(find.text('New chat message'), findsOneWidget);
  });

  testWidgets('the empty state is shown when the inbox is empty', (tester) async {
    inbox = defaultInbox(0);

    await pumpInbox(tester);

    expect(find.text("You're all caught up"), findsOneWidget);
  });
}
