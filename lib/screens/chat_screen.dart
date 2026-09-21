import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/cblrep_theme.dart';

/// Secure 1:1 chat thread with 3s live polling and optimistic sending.
class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String title;
  const ChatScreen({super.key, required this.conversationId, required this.title});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;
  int _knownCount = -1;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<ChatProvider>().bindSelf(
            context.read<AuthProvider>().user?.id ?? 0,
          );
      context.read<ChatProvider>().open(widget.conversationId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final count = context.watch<ChatProvider>().messages.length;
    if (count != _knownCount && count > 0) {
      _knownCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await context.read<ChatProvider>().send(text);
      input.clear();
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: send);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final me = context.watch<AuthProvider>().user?.id ?? 0;
    final msgs = chat.messages.map((e) => ChatMessageModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 15))),
      body: Column(children: [
        Expanded(
          child: chat.loading
              ? const Center(child: CircularProgressIndicator())
              : msgs.isEmpty
                  ? const Center(child: Text('Say hello to start the exchange chat.'))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final mine = m.senderId == me;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: mine ? CblrepColors.actionOrange : (dark ? CblrepColors.cardGrey : Colors.white),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (!mine) Text(m.sender, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                              Text(m.body, style: TextStyle(fontSize: 13, color: mine ? Colors.white : Colors.black87)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(child: TextField(controller: input, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Type a secure message…'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: sending ? null : send, child: sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 18)),
            ]),
          ),
        ),
      ]),
    );
  }
}
