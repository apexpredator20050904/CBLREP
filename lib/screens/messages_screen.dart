import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/empty_state.dart';
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
              ? ListView(children: const [
                  SizedBox(height: 40),
                  EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'No conversations yet',
                    subtitle: 'Message a listing owner to start your first chat.',
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: dark ? CblrepColors.darkCardGreen : Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: CblrepColors.brandGreen, child: Text(c.memberName.isEmpty ? '?' : c.memberName.characters.take(1).toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        title: Text(c.memberName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: dark ? Colors.white : Colors.black)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (c.hasListing)
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              child: Row(children: [
                                _InboxCompBadge(type: c.compensationType, label: c.compensationLabel, price: c.listingPrice),
                                const SizedBox(width: 6),
                                Flexible(child: Text(c.listingTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dark ? Colors.white70 : Colors.black54))),
                              ]),
                            )
                          else
                            Text(c.memberEmail, style: TextStyle(fontSize: 11, color: dark ? Colors.white70 : Colors.black54)),
                        ]),
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

/// Small compensation badge for an inbox row: FREE SHARING / BARTER /
/// PAID · ₱n, colour-matched to the listing cards.
class _InboxCompBadge extends StatelessWidget {
  final String? type;
  final String? label;
  final double? price;
  const _InboxCompBadge({this.type, this.label, this.price});

  @override
  Widget build(BuildContext context) {
    final key = type ?? 'barter';
    final color = CblrepColors.compensationColor(key);
    final text = key == 'paid' && price != null
        ? 'PAID · ₱${price!.toStringAsFixed(price == price!.roundToDouble() ? 0 : 2)}'
        : (label ?? 'BARTER');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}
