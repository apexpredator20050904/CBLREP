import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/api_service.dart';

/// Single live-data hub for exchanges, notifications,
/// conversations and dashboard stats. Every stream polls on a timer so
/// lists update without manual refresh, and exposes `refreshAll()`.
class LiveHubProvider extends ChangeNotifier {
  final ApiService api;
  LiveHubProvider(this.api);

  List<dynamic> exchanges = const [];
  List<dynamic> notifications = const [];
  int unreadCount = 0;
  List<dynamic> conversations = const [];
  Map<String, dynamic>? dashboard;
  String? error;
  DateTime? lastUpdated;

  Timer? _timer;
  bool _fetching = false;

  Future<void> _safe(Future<void> Function() fn) async {
    if (_fetching) return;
    _fetching = true;
    final before = _fingerprint;
    try {
      await fn();
      lastUpdated = DateTime.now();
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (unexpected) {
      // catchError() inside refreshAll() only covers the awaited API calls;
      // anything raised by the shaping code below used to escape as an
      // unhandled async error from a Timer callback, silently killing the
      // live poll for the rest of the session.
      debugPrint('[CBLREP] live hub refresh failed: $unexpected');
      error = 'Live updates paused. Pull to refresh.';
    } finally {
      _fetching = false;
      // The 20s poll usually returns identical data — skip the notify so the
      // shell and home feed don't re-render when nothing visible changed.
      if (error != null || _fingerprint != before) notifyListeners();
    }
  }

  /// Cheap fingerprint of everything the UI renders from this provider.
  String get _fingerprint => [
        exchanges.length,
        exchanges
            .map((e) => '${(e as Map)['id']}:${(e as Map)['raw_status'] ?? (e as Map)['status']}')
            .join(','),
        notifications.length,
        unreadCount,
        conversations.length,
        dashboard?.values.join('|'),
      ].join('§');

  Future<void> refreshAll() => _safe(() async {
        final results = await Future.wait([
          api.exchanges().catchError((_) => <dynamic>[]),
          api.notifications().catchError((_) => <String, dynamic>{}),
          api.conversations().catchError((_) => <dynamic>[]),
          api.dashboardStats().catchError((_) => <String, dynamic>{}),
        ]);
        exchanges = (results[0] as List).toList();
        final notif = Map<String, dynamic>.from(results[1] as Map);
        notifications = List<dynamic>.from(notif['notifications'] ?? const []);
        unreadCount = (notif['unread_count'] as num?)?.toInt() ?? 0;
        conversations = (results[2] as List).toList();
        dashboard = Map<String, dynamic>.from(results[3] as Map);
      });

  void startLive({Duration interval = const Duration(seconds: 10)}) {
    stopLive();
    unawaited(refreshAll());
    _timer = Timer.periodic(interval, (_) => refreshAll());
  }

  void stopLive() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> markNotificationRead(int id) async {
    await api.markNotificationRead(id);
    await refreshAll();
  }

  /// Mark every unread notification as read.
  ///
  /// The badge is cleared immediately so the bell does not keep a stale count
  /// while the request is in flight; the refresh then reconciles the list.
  Future<void> markAllNotificationsRead() async {
    unreadCount = 0;
    notifyListeners();
    await api.markAllNotificationsRead();
    await refreshAll();
  }

  /// Delete one notification.
  ///
  /// The row is dropped from the list straight away and put back if the server
  /// refuses, so a failed delete never leaves a ghost behind.
  Future<void> deleteNotification(int id) async {
    final index = notifications.indexWhere((n) => (n as Map)['id'] == id);
    Map<dynamic, dynamic>? removed;

    if (index >= 0) {
      removed = Map<dynamic, dynamic>.from(notifications[index] as Map);
      final wasUnread = removed['read_at'] == null;
      notifications = List<dynamic>.from(notifications)..removeAt(index);
      if (wasUnread && unreadCount > 0) unreadCount--;
      notifyListeners();
    }

    try {
      await api.deleteNotification(id);
    } catch (_) {
      if (removed != null) {
        notifications = List<dynamic>.from(notifications)..insert(index, removed);
        if (removed['read_at'] == null) unreadCount++;
        notifyListeners();
      }
      rethrow;
    }

    await refreshAll();
  }

  /// Clear the whole inbox.
  Future<void> deleteAllNotifications() async {
    notifications = const [];
    unreadCount = 0;
    notifyListeners();
    await api.deleteAllNotifications();
    await refreshAll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
