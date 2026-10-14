import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Android notification channel used both when the app shows a notification
/// itself (foreground) and by FCM when the app is backgrounded/closed. The id
/// must match `com.google.firebase.messaging.default_notification_channel_id`
/// in `AndroidManifest.xml`.
const String kCblrepNotificationChannelId = 'cblrep_messages';
const String kCblrepNotificationChannelName = 'CBLREP updates';

/// Entry point for messages delivered while the app is backgrounded or closed.
///
/// FCM runs this in a **fresh isolate**, so Firebase has to be initialised
/// again before any Firebase API is touched. It must stay a top-level function
/// with the `vm:entry-point` pragma, otherwise release builds (AOT) cannot find
/// it and background pushes are silently dropped.
@pragma('vm:entry-point')
Future<void> cblrepBackgroundMessageHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[CBLREP] background Firebase init failed: $e');
  }
  await PushService.instance.showLocalNotification(message);
}

/// Thin wrapper around Firebase Cloud Messaging + local notifications.
///
/// The app keeps its 10-second polling (`LiveHubProvider`) as a fallback, so
/// every method here fails soft: a missing `google-services.json`, a device
/// without Google Play services, or a backend that has no device-token route
/// yet must never break the signed-in experience.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  ApiService? _api;
  bool _initialised = false;
  String? _token;
  StreamSubscription<String>? _tokenRefresh;

  /// Wires up FCM and local notifications once, at app launch.
  ///
  /// Requests the notification permission (Android 13+), creates the
  /// notification channel and subscribes to foreground messages and token
  /// refreshes. Safe to call when Firebase failed to initialise.
  Future<void> init(ApiService api) async {
    _api = api;
    if (_initialised) return;
    _initialised = true;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      debugPrint('[CBLREP] push permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[CBLREP] push permission request failed: $e');
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    try {
      await _local.initialize(settings: initSettings);
      await _createChannel();
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[CBLREP] local notifications init failed: $e');
    }

    try {
      FirebaseMessaging.onMessage.listen(showLocalNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        unawaited(_register(token));
      });
    } catch (e) {
      debugPrint('[CBLREP] FCM listeners failed: $e');
    }
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      kCblrepNotificationChannelId,
      kCblrepNotificationChannelName,
      description: 'Messages and barter activity from CBLREP.',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Pushes this device's FCM token to the backend for the signed-in member.
  ///
  /// Called after sign-in and after a restored session. Idempotent: the server
  /// upserts, so re-registering the same token is harmless.
  Future<void> syncToken() async {
    if (_api == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _token = token;
      await _register(token);
    } catch (e) {
      debugPrint('[CBLREP] push token sync failed: $e');
    }
  }

  Future<void> _register(String token) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.registerDeviceToken(token: token, platform: _platform);
    } catch (e) {
      // A backend without the /device-tokens route (older deploy) answers 404;
      // that must not surface to the member.
      debugPrint('[CBLREP] device token registration failed: $e');
    }
  }

  /// Removes this device's token from the backend on sign-out.
  ///
  /// Must run **before** `ApiService.logout()` clears the auth token — the
  /// delete is an authenticated request.
  Future<void> onSignedOut() async {
    final api = _api;
    if (api == null) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      await api.deleteDeviceToken(token);
    } catch (e) {
      debugPrint('[CBLREP] device token removal failed: $e');
    }
  }

  /// Renders a foreground (or data-only background) message as a system
  /// notification, since Android does not show one automatically while the app
  /// is in the foreground.
  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ??
        (message.data['title'] as String?) ??
        'CBLREP';
    final body = notification?.body ?? (message.data['body'] as String?) ?? '';
    if (title.isEmpty && body.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        kCblrepNotificationChannelId,
        kCblrepNotificationChannelName,
        channelDescription: 'Messages and barter activity from CBLREP.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _local.show(
        id: message.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: details,
        payload: message.data['conversation_id']?.toString(),
      );
    } catch (e) {
      debugPrint('[CBLREP] failed to display push notification: $e');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    // The shell already refreshes notifications on resume/foreground; deep
    // navigation into the exact thread can build on this hook later.
    debugPrint('[CBLREP] notification opened: ${message.data}');
  }

  String get _platform => Platform.isAndroid ? 'android' : 'ios';

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
  }
}
