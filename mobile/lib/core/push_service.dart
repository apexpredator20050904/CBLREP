import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';

/// Android notification channel used when the app shows a notification itself
/// (foreground) and by FCM when the app is backgrounded/closed.
///
/// The app now creates one channel per category so a member can mute barter
/// alerts at the OS level without also silencing chat. The ids must match the
/// `CHANNELS` map in the backend `NotificationService`, and the *messages* id
/// must match `com.google.firebase.messaging.default_notification_channel_id`
/// in `AndroidManifest.xml` (the fallback FCM uses when a push arrives with no
/// explicit channel).
const String kCblrepChannelMessages = 'cblrep_messages';
const String kCblrepChannelExchanges = 'cblrep_exchanges';
const String kCblrepChannelAnnouncements = 'cblrep_announcements';
const String kCblrepChannelAccount = 'cblrep_account';

/// Channel for "a new version of the app is available".
///
/// Its own channel so a member can silence release pings at the OS level
/// without also muting barangay announcements. An older build that does not
/// know this channel falls back to the manifest's default channel, so the
/// notice still reaches the members who need it most.
const String kCblrepChannelUpdates = 'cblrep_updates';

/// Backwards-compatible aliases for the original single channel.
const String kCblrepNotificationChannelId = kCblrepChannelMessages;
const String kCblrepNotificationChannelName = 'CBLREP updates';

/// Display name + description per channel id.
const Map<String, String> _channelNames = {
  kCblrepChannelMessages: 'Messages',
  kCblrepChannelExchanges: 'Barter activity',
  kCblrepChannelAnnouncements: 'Announcements',
  kCblrepChannelAccount: 'Account & verification',
  kCblrepChannelUpdates: 'App updates',
};

const Map<String, String> _channelDescriptions = {
  kCblrepChannelMessages: 'Chat messages and admin replies.',
  kCblrepChannelExchanges: 'Barter requests, approvals and completions.',
  kCblrepChannelAnnouncements: 'Barangay and municipal announcements.',
  kCblrepChannelAccount: 'Verification decisions and listing moderation.',
  kCblrepChannelUpdates: 'New builds of the app and what changed.',
};

/// A notification the member tapped.
///
/// The widget layer decides what to do with it — the service has no
/// navigation of its own.
class PushAction {
  /// The backend's `type` value, e.g. `app_update`, `message`, `exchange_request`.
  final String type;

  /// The structured payload the backend sent alongside the notification.
  final Map<String, dynamic> data;

  const PushAction(this.type, this.data);

  /// True when the tap was on a "there is a new build" notice.
  bool get isAppUpdate => type == 'app_update';
}

/// Maps a backend `channel` value onto a channel this device actually created,
/// falling back to the messages channel so a push is never dropped just because
/// it names a channel the app does not know.
String resolveChannelId(String? raw) =>
    _channelNames.containsKey(raw) ? raw! : kCblrepChannelMessages;

/// Human-friendly name for a resolved channel id.
String channelNameFor(String id) =>
    _channelNames[id] ?? _channelNames[kCblrepChannelMessages]!;

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

  final StreamController<PushAction> _actions =
      StreamController<PushAction>.broadcast();

  /// A tap that arrived before anything was listening (a cold start from the
  /// notification). It is replayed to the first listener.
  PushAction? _pendingAction;

  /// Taps on notifications, for the widget layer to act on.
  ///
  /// A tap that arrives while nobody is listening — the app was closed and is
  /// now starting from the notification — is held and handed to the first
  /// listener instead of being lost.
  Stream<PushAction> get actions async* {
    final pending = _pendingAction;
    if (pending != null) {
      _pendingAction = null;
      yield pending;
    }
    yield* _actions.stream;
  }

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

      // A cold start from a notification: the app was closed and the member
      // tapped the notification, so the message never reaches
      // onMessageOpenedApp. Without this the tap is silently lost.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleNotificationTap(initial);
    } catch (e) {
      debugPrint('[CBLREP] FCM listeners failed: $e');
    }
  }

  Future<void> _createChannel() async {
    final android = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // One channel per category. createNotificationChannel is idempotent, so
    // re-running on every launch is safe and picks up description changes.
    for (final id in _channelNames.keys) {
      await android?.createNotificationChannel(AndroidNotificationChannel(
        id,
        _channelNames[id]!,
        description: _channelDescriptions[id],
        importance: Importance.high,
      ));
    }
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
      await api.registerDeviceToken(
        token: token,
        platform: _platform,
        // The build this device runs, so the server can tell who is behind
        // when a new release is announced.
        buildNumber: await _buildNumber(),
      );
    } catch (e) {
      // A backend without the /device-tokens route (older deploy) answers 404;
      // that must not surface to the member.
      debugPrint('[CBLREP] device token registration failed: $e');
    }
  }

  /// The versionCode of the running build, or null when it cannot be read.
  Future<int?> _buildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber);
    } catch (_) {
      return null;
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

    final channelId = resolveChannelId(message.data['channel']?.toString());
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelNameFor(channelId),
        channelDescription: _channelDescriptions[channelId],
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
        // Carry the structured data so a future tap handler can deep-link into
        // the right thread/listing. Kept as JSON so nothing is lost.
        payload: _encodePayload(message.data),
      );
    } catch (e) {
      debugPrint('[CBLREP] failed to display push notification: $e');
    }
  }

  /// Serialises an FCM data map to a JSON string payload (values are already
  /// strings on the wire), dropping empties so the payload stays small.
  static String? _encodePayload(Map<String, dynamic> data) {
    final clean = <String, String>{};
    data.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        clean[key] = value.toString();
      }
    });
    if (clean.isEmpty) return null;
    return jsonEncode(clean);
  }

  void _handleNotificationTap(RemoteMessage message) {
    // The shell already refreshes notifications on resume/foreground; the
    // payload now carries `type` + the relevant ids so the widget layer can
    // deep-link into the exact thread/listing.
    final type = message.data['type']?.toString() ?? 'general';
    debugPrint('[CBLREP] notification opened (type=$type): ${message.data}');

    final action = PushAction(type, Map<String, dynamic>.from(message.data));

    if (_actions.hasListener) {
      _actions.add(action);
    } else {
      // Nothing is listening yet (the app is starting from this tap), so the
      // action waits for the first listener instead of being dropped.
      _pendingAction = action;
    }
  }

  String get _platform => Platform.isAndroid ? 'android' : 'ios';

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    await _actions.close();
  }
}
