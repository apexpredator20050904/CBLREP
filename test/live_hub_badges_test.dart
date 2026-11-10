import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/providers/live_hub_provider.dart';

/// Bottom-navigation badge counts.
///
/// The counts themselves must be right, but the subtle part is the provider's
/// change fingerprint: a new message inside an *existing* conversation (or a
/// completion confirmation that leaves the status untouched) must still notify
/// listeners, otherwise the badge stays stale until the app restarts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with
  // 400; these tests talk to a real local socket.
  HttpOverrides.global = null;

  late HttpServer server;
  late LiveHubProvider hub;

  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> exchanges = [];

  setUp(() async {
    conversations = [
      {'id': 1, 'unread_count': 0},
    ];
    exchanges = [
      {'id': 1, 'status': 'Pending', 'can_respond': false},
    ];

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiService.instance.setBaseUrlForTesting(
      'http://127.0.0.1:${server.port}/api',
    );

    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;

      switch (request.uri.path) {
        case '/api/conversations':
          request.response.write(jsonEncode({'conversations': conversations}));
        case '/api/exchanges':
          request.response.write(jsonEncode({'exchanges': exchanges}));
        case '/api/notifications':
          request.response.write(
            jsonEncode({'notifications': [], 'unread_count': 0}),
          );
        case '/api/dashboard/stats':
          request.response.write(jsonEncode({}));
      }

      await request.response.close();
    });

    hub = LiveHubProvider(ApiService.instance);
    await hub.refreshAll();
  });

  tearDown(() async {
    hub.dispose();
    await server.close(force: true);
  });

  test('unreadMessages totals unread rows across conversations', () {
    conversations = [
      {'id': 1, 'unread_count': 2},
      {'id': 2, 'unread_count': 0},
      {'id': 3, 'unread_count': 4},
      {'id': 4},
    ];
    hub.conversations = conversations;

    expect(hub.unreadMessages, 6);
  });

  test('exchangeActions counts only exchanges awaiting this member', () {
    exchanges = [
      {'id': 1, 'status': 'pending', 'can_respond': true},
      {'id': 2, 'status': 'accepted', 'can_confirm_completion': true},
      // Sent by this member — nothing to act on.
      {'id': 3, 'status': 'pending', 'can_respond': false},
      {'id': 4, 'status': 'completed'},
    ];
    hub.exchanges = exchanges;

    expect(hub.exchangeActions, 2);
  });

  test('a new message in an existing thread notifies the shell', () async {
    var notifications = 0;
    hub.addListener(() => notifications++);

    // Same conversation count, only the unread count changed.
    conversations = [
      {'id': 1, 'unread_count': 3},
    ];
    await hub.refreshAll();

    expect(hub.unreadMessages, 3);
    expect(
      notifications,
      1,
      reason: 'the Messages badge must refresh without a new conversation row',
    );
  });

  test('a completion confirmation notifies the shell', () async {
    var notifications = 0;
    hub.addListener(() => notifications++);

    // Status is still `accepted`; only the viewer-specific action flag flips.
    exchanges = [
      {'id': 1, 'status': 'accepted', 'can_confirm_completion': true},
    ];
    await hub.refreshAll();
    expect(notifications, 1);

    exchanges = [
      {'id': 1, 'status': 'accepted', 'can_confirm_completion': false},
    ];
    await hub.refreshAll();

    expect(hub.exchangeActions, 0);
    expect(
      notifications,
      2,
      reason: 'the Exchanges badge must clear once this member confirms',
    );
  });
}
