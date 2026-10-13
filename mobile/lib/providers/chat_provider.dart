import 'dart:async';
import 'dart:io';

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

  /// 0..1 upload progress for the attachment currently streaming, null when
  /// idle. The chat screen binds a linear bar to this so slow networks show a
  /// determinate spinner rather than a dead composer.
  double? uploadProgress;

  /// Sends a photo/document with an optional caption via multipart/form-data.
  ///
  /// Shows an optimistic bubble with the local preview, streams with progress
  /// callbacks, then reconciles with the server copy. Attachments are
  /// text-optional: [caption] may be empty.
  Future<void> sendAttachment(File file, {String caption = ''}) async {
    if (conversationId == null) return;
    final clean = InputSanitizer.text(caption, max: 2000);
    final lower = file.path.toLowerCase();
    final looksImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
    final fileName = file.path.split(Platform.pathSeparator).last;
    messages = [...messages, {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'body': clean,
      'sender_id': _selfId,
      'sender': 'You',
      'created_at': DateTime.now().toIso8601String(),
      'file_type': looksImage ? 'image' : 'document',
      'file_name': fileName,
      // Local preview path until the poll reconciles with the server copy.
      'file_url': file.path,
      'local_path': file.path,
      'uploading': true,
    }];
    uploadProgress = 0;
    notifyListeners();
    try {
      await api.sendConversationMessage(
        conversationId!,
        clean,
        file: file,
        onProgress: (sent, total) {
          if (total > 0) {
            uploadProgress = sent / total;
            notifyListeners();
          }
        },
      );
      uploadProgress = null;
      await load(silent: true);
    } on ApiException {
      uploadProgress = null;
      await load(silent: true);
      rethrow;
    }
  }

  /// Edits a message you sent.
  ///
  /// Optimistic: the bubble shows the new text immediately, then the poller
  /// reconciles. On failure the previous body is restored so the thread never
  /// displays something the server did not accept. [messageId] is the server
  /// id string, so optimistic ("local-...") bubbles cannot be edited — the
  /// caller must wait for the poll to attach the real id.
  Future<void> editMessage(String messageId, String body) async {
    final clean = InputSanitizer.text(body, max: 2000);
    if (clean.isEmpty) {
      throw const ApiException('A message cannot be empty.');
    }

    final index = messages.indexWhere((m) => '${(m as Map)['id']}' == messageId);
    if (index < 0) return;

    final previous = Map<String, dynamic>.from(messages[index] as Map);
    messages = [...messages]..[index] = {...previous, 'body': clean};
    notifyListeners();

    try {
      final saved = await api.editMessage(int.parse(messageId), clean);
      final at = messages.indexWhere((m) => '${(m as Map)['id']}' == messageId);
      if (at >= 0) {
        messages = [...messages]..[at] = {
          ...messages[at] as Map,
          'body': saved['body'] ?? clean,
          'edited_at': saved['edited_at'],
        };
      }
      notifyListeners();
    } on ApiException {
      // Roll back to the server's copy rather than leaving a lie on screen.
      final at = messages.indexWhere((m) => '${(m as Map)['id']}' == messageId);
      if (at >= 0) {
        messages = [...messages]..[at] = previous;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Deletes a message you sent.
  ///
  /// Optimistic with rollback: the bubble disappears at once and returns if
  /// the server refuses. Soft-deleted server-side, so the admin inquiry record
  /// is preserved.
  Future<void> deleteMessage(String messageId) async {
    final index = messages.indexWhere((m) => '${(m as Map)['id']}' == messageId);
    if (index < 0) return;

    final removed = messages[index];
    messages = [...messages]..removeAt(index);
    notifyListeners();

    try {
      await api.deleteMessage(int.parse(messageId));
      await load(silent: true);
    } on ApiException {
      // Put it back where it was, preserving order.
      final restored = index.clamp(0, messages.length);
      messages = [...messages]..insert(restored, removed);
      notifyListeners();
      rethrow;
    }
  }

  /// Tears the open thread down.
  ///
  /// [notify] is false when a screen is being disposed: firing listeners
  /// there would schedule a rebuild of a widget already on its way out,
  /// which Flutter flags as "setState called during dispose". The state is
  /// still cleared either way, so another member's messages are not retained.
  void close({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    conversationId = null;
    conversation = null;
    messages = const [];
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
