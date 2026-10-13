import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';

/// Regression test for: "Message / Inquire says Unauthenticated".
///
/// THE BUG
/// -------
/// Dio answers requests whenever the network delivers them, so a request that
/// was issued BEFORE the member signed in (a live-hub poll that was still in
/// flight, a fail-over retry from [ApiService._recover]) can land AFTER the
/// fresh token has been applied. That stale response is a 401, and the
/// interceptor used to read *any* 401 as "the session is dead": it dropped the
/// Authorization header and wiped the stored token.
///
/// The member was therefore left sitting in the dashboard looking signed in,
/// while every authenticated call — including POST /conversations behind the
/// "Message / Inquire" button — went out with no token at all and came back
/// "Unauthenticated."
///
/// THE TEST
/// --------
/// A local stub server replays exactly that ordering:
///
///   1. a stale GET /conversations goes out with no token and its 401 reply is
///      deliberately held back;
///   2. the member signs in (fresh token applied);
///   3. the held-back 401 is released and must NOT strip the new token;
///   4. POST /conversations (the Message / Inquire call) must arrive carrying
///      the new bearer token.
///
/// The stub fails the test if the outgoing request is missing the token, so
/// this reproduces the reported symptom precisely instead of hoping for it.
/// It runs as part of the ordinary `flutter test` suite — the client is
/// pointed at the stub with [ApiService.setBaseUrlForTesting].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that answers every request with
  // 400; this test talks to a real socket.
  HttpOverrides.global = null;

  late HttpServer server;

  /// Released once the fresh token has been applied, so the stale 401 lands
  /// after the sign-in — the exact ordering that used to wipe the session.
  final heldBack = Completer<void>();

  final seen = <List<String?>>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8123);
    ApiService.instance.setBaseUrlForTesting('http://127.0.0.1:8123/api');
    server.listen((request) async {
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      final path = request.uri.path;
      await request.drain<void>();

      if (path == '/api/platform/status') {
        request.response.statusCode = 200;
        request.response.write('{"status":"ok"}');
        await request.response.close();
        return;
      }

      if (path == '/api/login' && request.method == 'POST') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"access_token":"99|fresh-token","token_type":"Bearer",'
          '"expires_in":2592000,"remembered":true,'
          '"user":{"id":2,"name":"Member","email":"member@example.test",'
          '"role":"General Member","raw_role":"user","is_verified":false,'
          '"verification_status":"Unverified","account_status":"Active",'
          '"barangay_or_location":"Poblacion","barangay":"Poblacion",'
          '"purok_sitio":"Purok 1"}}',
        );
        await request.response.close();
        return;
      }

      // The stale call: held until the new token is in place, then answered
      // with the 401 a token-less request always gets.
      if (path == '/api/conversations' && request.method == 'GET') {
        await heldBack.future;
        request.response.statusCode = 401;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"message":"Unauthenticated."}');
        await request.response.close();
        return;
      }

      // The Message / Inquire call itself.
      if (path == '/api/conversations' && request.method == 'POST') {
        seen.add([auth, path]);
        final ok = auth == 'Bearer 99|fresh-token';
        request.response.statusCode = ok ? 201 : 401;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          ok
              ? '{"conversation":{"id":7,"member":{"id":3,"name":"Owner",'
                  '"email":"owner@example.test"},"listing":null,'
                  '"last_message_at":null,"unread_count":0}}'
              : '{"message":"Unauthenticated."}',
        );
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
    if (!heldBack.isCompleted) heldBack.complete();
    await server.close(force: true);
  });

  test('a stale 401 must not strip the token issued by a fresh sign-in', () async {
    final api = ApiService.instance;

    // 1. A request from before the sign-in, still in flight.
    final stale = api.conversations().catchError((_) => <dynamic>[]);

    // 2. Sign in while that request is pending.
    await api.login('member@example.test', 'password123', rememberMe: true);

    // 3. Its 401 now arrives — this used to clear the brand-new session.
    heldBack.complete();
    await stale;

    // 4. "Message / Inquire": must still be authenticated.
    final result = await api.startConversation(3);

    expect(
      seen.single.first,
      'Bearer 99|fresh-token',
      reason: 'POST /conversations (Message / Inquire) went out without the '
          'token a just-signed-in member holds — it can only answer '
          '"Unauthenticated."',
    );
    expect(result['conversation'], isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
