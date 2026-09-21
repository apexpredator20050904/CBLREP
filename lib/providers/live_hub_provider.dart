import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/api_service.dart';

/// Single live-data hub for exchanges, notifications, time-bank,
/// conversations and dashboard stats. Every stream polls on a timer so
/// lists update without manual refresh, and exposes `refreshAll()`.
class LiveHubProvider extends ChangeNotifier {
  final ApiService api;
  LiveHubProvider(this.api);

  List<dynamic> exchanges = const [];
  List<dynamic> notifications = const [];
  int unreadCount = 0;
  Map<String, dynamic>? timeBank;
  List<dynamic> timeBankTxns = const [];
  List<dynamic> timeBankServices = const [];
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
        notifications.length,
        unreadCount,
        timeBankTxns.length,
        conversations.length,
        timeBankServices.length,
        timeBank?.values.join('|'),
        dashboard?.values.join('|'),
      ].join('§');

  Future<void> refreshAll() => _safe(() async {
        final results = await Future.wait([
          api.exchanges().catchError((_) => <dynamic>[]),
          api.notifications().catchError((_) => <String, dynamic>{}),
          api.timeBankBalance().catchError((_) => <String, dynamic>{}),
          api.timeBankTransactions().catchError((_) => <dynamic>[]),
          api.conversations().catchError((_) => <dynamic>[]),
          api.dashboardStats().catchError((_) => <String, dynamic>{}),
          api.timeBankServices().catchError((_) => <dynamic>[]),
        ]);
        exchanges = (results[0] as List).toList();
        final notif = Map<String, dynamic>.from(results[1] as Map);
        notifications = List<dynamic>.from(notif['notifications'] ?? const []);
        unreadCount = (notif['unread_count'] as num?)?.toInt() ?? 0;
        timeBank = Map<String, dynamic>.from(results[2] as Map);
        timeBankTxns = (results[3] as List).toList();
        conversations = (results[4] as List).toList();
        dashboard = Map<String, dynamic>.from(results[5] as Map);
        timeBankServices = (results[6] as List).toList();
      });

  void startLive({Duration interval = const Duration(seconds: 20)}) {
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

  /// Claim a listed time-bank service. Refreshing straight away keeps the
  /// credit balance and the transaction ledger in sync.
  Future<void> requestService(int serviceId, {double? hours}) async {
    await api.requestTimeBankService(serviceId: serviceId, hours: hours);
    await refreshAll();
  }

  /// Publish a service the signed-in member can offer to neighbours.
  Future<void> offerService({
    required String title,
    String? description,
    String? category,
    double? estimatedHours,
    String? location,
    String? availability,
  }) async {
    await api.offerTimeBankService(
      title: title,
      description: description,
      category: category,
      estimatedHours: estimatedHours,
      location: location,
      availability: availability,
    );
    await refreshAll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
