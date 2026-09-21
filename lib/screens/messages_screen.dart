import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import 'chat_screen.dart';

/// Secure in-app messaging inbox — live conversation list.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<LiveHubProvider>().refreshAll());
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<LiveHubProvider>();
    final items = hub.conversations.map((e) => ConversationModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => hub.refreshAll(),
          child: items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 60),
                  Center(child: Column(children: [
                    Container(width: 72, height: 72, decoration: BoxDecoration(color: CblrepColors.actionOrange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.chat_bubble_outline, size: 36, color: CblrepColors.actionOrange)),
                    const SizedBox(height: 12),
                    Text('No conversations yet', style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black87)),
                    Text('Message a listing owner to start.', style: TextStyle(fontSize: 11, color: dark ? Colors.white60 : Colors.black54)),
                  ])),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: CblrepColors.brandGreen, child: Text(c.memberName.isEmpty ? '?' : c.memberName.characters.take(1).toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        title: Text(c.memberName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                        subtitle: Text(c.memberEmail, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        trailing: c.unreadCount > 0
                            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: CblrepColors.actionOrange, borderRadius: BorderRadius.circular(12)), child: Text('${c.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))
                            : const Icon(Icons.chevron_right, color: Colors.black38),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c.id, title: c.memberName))).then((_) => hub.refreshAll()),
                      ),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
