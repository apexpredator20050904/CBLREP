import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../models/models.dart';

/// Real-time notification alerts — auto-refreshes via LiveHubProvider.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<LiveHubProvider>().refreshAll());
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<LiveHubProvider>();
    final items = hub.notifications.map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: Text('Notifications${hub.unreadCount > 0 ? ' (${hub.unreadCount})' : ''}'), actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => hub.refreshAll()),
      ]),
      body: RefreshIndicator(
        onRefresh: () => hub.refreshAll(),
        child: items.isEmpty
            ? ListView(children: [
                const SizedBox(height: 80),
                Center(child: Column(children: [
                  Container(width: 72, height: 72, decoration: BoxDecoration(color: CblrepColors.actionOrange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.notifications_none, size: 36, color: CblrepColors.actionOrange)),
                  const SizedBox(height: 12),
                  const Text("You're all caught up", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text('Exchange and message alerts appear here.', style: TextStyle(fontSize: 11)),
                ])),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final n = items[i];
                  return Dismissible(
                    key: ValueKey(n.id),
                    direction: DismissDirection.endToStart,
                    background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), decoration: BoxDecoration(color: CblrepColors.successGreen, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.mark_email_read, color: Colors.white)),
                    onDismissed: (_) => hub.markNotificationRead(n.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: n.read ? (dark ? CblrepColors.cardGrey.withValues(alpha: 0.55) : Colors.white) : (dark ? CblrepColors.cardGrey : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: n.read ? null : Border.all(color: CblrepColors.actionOrange, width: 1.2),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 38, height: 38, decoration: BoxDecoration(color: _colorFor(n.type), borderRadius: BorderRadius.circular(10)), child: Icon(_iconFor(n.type), color: Colors.white, size: 20)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                          const SizedBox(height: 2),
                          Text(n.body, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                          if (n.createdAt != null) Text(_ago(n.createdAt!), style: const TextStyle(fontSize: 10, color: Colors.black45)),
                        ])),
                        if (!n.read) TextButton(onPressed: () => hub.markNotificationRead(n.id), child: const Text('Read', style: TextStyle(fontSize: 11))),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'message': return CblrepColors.brandGreen;
      case 'exchange_request': return CblrepColors.actionOrange;
      case 'verification': return CblrepColors.avatarAmber;
      default: return CblrepColors.fieldGreen;
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'message': return Icons.chat_bubble_outline;
      case 'exchange_request': return Icons.swap_horiz;
      case 'verification': return Icons.verified_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
