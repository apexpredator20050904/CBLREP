import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_update_provider.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../models/models.dart';
import '../widgets/update_prompt.dart';

/// Real-time notification alerts — auto-refreshes via LiveHubProvider.
///
/// The member owns this inbox: every row can be marked read, deleted, and the
/// whole inbox can be cleared.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<LiveHubProvider>().refreshAll();
    });
  }

  /// Mark the whole inbox as read.
  Future<void> _markAllRead(LiveHubProvider hub) async {
    try {
      await hub.markAllNotificationsRead();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark the notifications as read.')),
      );
    }
  }

  /// Delete one notification, straight from the swipe gesture.
  Future<void> _delete(LiveHubProvider hub, NotificationModel n) async {
    try {
      await hub.deleteNotification(n.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification deleted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the notification.')),
      );
    }
  }

  /// Delete one notification from the row menu, after a confirmation.
  ///
  /// The confirm button does the work itself instead of returning a flag the
  /// caller acts on afterwards: the request then leaves the app straight from
  /// the button's own handler, with no continuation in between.
  void _confirmDelete(LiveHubProvider hub, NotificationModel n) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text('This removes the notification from your inbox. It cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _delete(hub, n);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Clear the whole inbox, after a confirmation.
  void _confirmClearAll(LiveHubProvider hub) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('Every notification will be removed from your inbox. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _clearAll(hub);
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  /// Clear the whole inbox for real.
  Future<void> _clearAll(LiveHubProvider hub) async {
    try {
      await hub.deleteAllNotifications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications cleared.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear the notifications.')),
      );
    }
  }

  /// A "a new version is available" notice opens the install prompt.
  Future<void> _openUpdatePrompt(NotificationModel n) async {
    final update = context.read<AppUpdateProvider>();
    if (!update.checked) await update.check();
    if (!mounted) return;
    if (!update.updateAvailable) return;
    await showUpdatePromptDialog(context, update);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<LiveHubProvider>();
    final items = hub.notifications.map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: Text('Notifications${hub.unreadCount > 0 ? ' (${hub.unreadCount})' : ''}'), actions: [
        // Mark the whole inbox as read. Disabled when there is nothing unread.
        IconButton(
          tooltip: 'Mark all as read',
          icon: const Icon(Icons.mark_email_read),
          onPressed: hub.unreadCount > 0 ? () => _markAllRead(hub) : null,
        ),
        // Clear the whole inbox.
        IconButton(
          tooltip: 'Clear all',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: items.isEmpty ? null : () => _confirmClearAll(hub),
        ),
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
                    // Swipe right marks as read, swipe left deletes — the same
                    // pair of gestures every mail app uses.
                    direction: DismissDirection.horizontal,
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      decoration: BoxDecoration(color: CblrepColors.successGreen, borderRadius: BorderRadius.circular(12)),
                      child: const Row(children: [
                        Icon(Icons.mark_email_read, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Read', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(color: CblrepColors.dangerRed, borderRadius: BorderRadius.circular(12)),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        SizedBox(width: 8),
                        Icon(Icons.delete_outline, color: Colors.white),
                      ]),
                    ),
                    onDismissed: (direction) {
                      if (direction == DismissDirection.startToEnd) {
                        hub.markNotificationRead(n.id);
                      } else {
                        _delete(hub, n);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: n.read ? (dark ? CblrepColors.darkCardGreen.withValues(alpha: 0.55) : Colors.white) : (dark ? CblrepColors.darkCardGreen : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: n.read ? null : Border.all(color: CblrepColors.actionOrange, width: 1.2),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 38, height: 38, decoration: BoxDecoration(color: _colorFor(n.type), borderRadius: BorderRadius.circular(10)), child: Icon(_iconFor(n.type), color: Colors.white, size: 20)),
                        const SizedBox(width: 10),
                        Expanded(child: InkWell(
                          onTap: n.type == 'app_update' ? () => _openUpdatePrompt(n) : null,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(n.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dark ? Colors.white : Colors.black)),
                            const SizedBox(height: 2),
                            Text(n.body, style: TextStyle(fontSize: 11, color: dark ? Colors.white : Colors.black87)),
                            if (n.createdAt != null) Text(_ago(n.createdAt!), style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black45)),
                          ]),
                        )),
                        if (!n.read)
                          TextButton(onPressed: () => hub.markNotificationRead(n.id), child: const Text('Read', style: TextStyle(fontSize: 11))),
                        PopupMenuButton<String>(
                          tooltip: 'Notification actions',
                          icon: Icon(Icons.more_vert, size: 18, color: dark ? Colors.white70 : Colors.black45),
                          onSelected: (value) {
                            if (value == 'read') {
                              hub.markNotificationRead(n.id);
                            } else if (value == 'delete') {
                              _confirmDelete(hub, n);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!n.read)
                              const PopupMenuItem(value: 'read', child: Text('Mark as read')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
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
      case 'exchange_request':
      case 'exchange_update': return CblrepColors.actionOrange;
      case 'verification': return CblrepColors.avatarAmber;
      case 'announcement': return CblrepColors.fieldGreen;
      case 'listing':
      case 'account': return CblrepColors.deepForest;
      case 'app_update': return CblrepColors.brandGreen;
      default: return CblrepColors.fieldGreen;
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'message': return Icons.chat_bubble_outline;
      case 'exchange_request':
      case 'exchange_update': return Icons.swap_horiz;
      case 'verification': return Icons.verified_outlined;
      case 'announcement': return Icons.campaign_outlined;
      case 'listing': return Icons.inventory_2_outlined;
      case 'account': return Icons.manage_accounts_outlined;
      case 'app_update': return Icons.system_update;
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
