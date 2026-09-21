import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../core/input_sanitizer.dart';

/// Live conversation thread: polls messages for one conversation so chat
/// feels real-time without manual refresh.
class ChatProvider extends ChangeNotifier {
  final ApiService api;
  ChatProvider(this.api);

  int? conversationId;
  Map<String, dynamic>? conversation;
  List<dynamic> messages = const [];
  bool loading = false;
  String? error;
  Timer? _timer;

  /// Id of the signed-in member, injected by ChatScreen on open, used to
  /// align optimistic bubbles on the correct side of the thread.
  int _selfId = 0;

  /// Called by [ChatScreen] so optimistic messages render as "mine".
  void bindSelf(int userId) => _selfId = userId;

  static String _lastId(List<dynamic> list) =>
      list.isEmpty ? '' : '${(list.last as Map?)?['id'] ?? ''}';

  Future<void> open(int id, {bool live = true}) async {
    conversationId = id;
    await load();
    if (live) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (conversationId == id) load(silent: true);
      });
    }
  }

  Future<void> load({bool silent = false}) async {
    if (conversationId == null) return;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final data = await api.conversationMessages(conversationId!);
      conversation = data['conversation'] is Map ? Map<String, dynamic>.from(data['conversation'] as Map) : null;
      final fresh = List<dynamic>.from(data['messages'] ?? const []);
      error = null;
      if (fresh.length != messages.length || _lastId(messages) != _lastId(fresh)) {
        messages = fresh;
        notifyListeners();
      } else {
        messages = fresh;
        if (!silent) notifyListeners();
      }
    } on ApiException catch (e) {
      error = e.message;
      if (!silent) notifyListeners();
    } finally {
      if (!silent) loading = false;
    }
  }

  /// Optimistic send: the bubble appears immediately, then the poller
  /// reconciles with the server copy — zero perceived latency.
  Future<void> send(String body) async {
    if (conversationId == null || body.trim().isEmpty) return;
    // Neutralise markup/control characters before the message is stored.
    final clean = InputSanitizer.text(body, max: 2000);
    messages = [...messages, {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'body': clean,
      'sender_id': _selfId,
      'sender': 'You',
      'created_at': DateTime.now().toIso8601String(),
    }];
    notifyListeners();
    try {
      await api.sendConversationMessage(conversationId!, clean);
      await load(silent: true);
    } on ApiException {
      await load(silent: true);
      rethrow;
    }
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    conversationId = null;
    conversation = null;
    messages = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
