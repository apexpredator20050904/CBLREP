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
  List<dynamic> barterProposalsIncoming = const [];
  List<dynamic> barterProposalsOutgoing = const [];
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
        barterProposalsIncoming.length + barterProposalsOutgoing.length,
        [...barterProposalsIncoming, ...barterProposalsOutgoing]
            .map((p) => '${(p as Map)['id']}:${(p as Map)['status']}')
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
          api.barterProposals().catchError((_) => <String, dynamic>{}),
        ]);
        exchanges = (results[0] as List).toList();
        final notif = Map<String, dynamic>.from(results[1] as Map);
        notifications = List<dynamic>.from(notif['notifications'] ?? const []);
        unreadCount = (notif['unread_count'] as num?)?.toInt() ?? 0;
        conversations = (results[2] as List).toList();
        dashboard = Map<String, dynamic>.from(results[3] as Map);
        final barter = Map<String, dynamic>.from(results[4] as Map);
        barterProposalsIncoming = List<dynamic>.from(barter['incoming'] ?? const []);
        barterProposalsOutgoing = List<dynamic>.from(barter['outgoing'] ?? const []);
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
