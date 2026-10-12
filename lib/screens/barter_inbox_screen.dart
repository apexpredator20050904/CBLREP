import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/empty_state.dart';

/// Barter Inbox — negotiations for item-for-item trades, reactive to the
/// LiveHubProvider poll so status badges refresh without manual reload.
class BarterInboxScreen extends StatefulWidget {
  const BarterInboxScreen({super.key});
  @override
  State<BarterInboxScreen> createState() => _BarterInboxScreenState();
}

class _BarterInboxScreenState extends State<BarterInboxScreen> {
  int tab = 0; // 0 = incoming, 1 = outgoing
  final _busy = <int>{};

  Future<void> _act(int id, String status) async {
    setState(() => _busy.add(id));
    try {
      await ApiService.instance.updateBarterProposalStatus(id, status);
      if (!mounted) return;
      await context.read<LiveHubProvider>().refreshAll();
      if (!mounted) return;
      Feedback.success(context, 'Trade ${status == 'accepted' ? 'accepted' : status == 'rejected' ? 'declined' : 'completed'}.');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reactive: rebuilds whenever the live poll delivers new barter data.
    final hub = context.watch<LiveHubProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = tab == 0 ? hub.barterProposalsIncoming : hub.barterProposalsOutgoing;

    return Scaffold(
      appBar: AppBar(title: const Text('Barter Inbox', style: TextStyle(fontSize: 16))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text('Incoming (${hub.barterProposalsIncoming.length})')),
              ButtonSegment(value: 1, label: Text('Outgoing (${hub.barterProposalsOutgoing.length})')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(
                  icon: Icons.handshake_outlined,
                  title: 'No ${tab == 0 ? 'incoming' : 'outgoing'} barter requests',
                  subtitle: tab == 0
                      ? 'When neighbours propose a trade on your items, it will show up here.'
                      : 'Trades you propose to others will appear here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = Map<String, dynamic>.from(rows[i] as Map);
                    final status = '${p['status'] ?? 'Pending'}';
                    final raw = '${p['raw_status'] ?? 'pending'}';
                    final offered = p['offered_item'] is Map ? Map<String, dynamic>.from(p['offered_item'] as Map) : null;
                    final requested = p['requested_item'] is Map ? Map<String, dynamic>.from(p['requested_item'] as Map) : null;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: dark ? CblrepColors.darkCardGreen : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: dark ? Colors.white12 : Colors.black12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${tab == 0 ? 'From' : 'To'} ${p['counterparty'] ?? 'Member'} · ${p['created_at'] ?? ''}', style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black45))),
                          _StatusBadge(status: status),
                        ]),
                        const SizedBox(height: 8),
                        Text('Offers: ${offered?['title'] ?? '—'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? Colors.white : Colors.black)),
                        Text('Wants: ${requested?['title'] ?? '—'}', style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54)),
                        if (raw == 'pending' && tab == 0) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: FilledButton.tonal(
                              onPressed: _busy.contains(p['id']) ? null : () => _act(p['id'] as int, 'accepted'),
                              child: const Text('Accept'),
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: OutlinedButton(
                              onPressed: _busy.contains(p['id']) ? null : () => _act(p['id'] as int, 'rejected'),
                              child: const Text('Decline'),
                            )),
                          ]),
                        ],
                        if (raw == 'accepted') ...[
                          const SizedBox(height: 10),
                          SizedBox(width: double.infinity, child: FilledButton(
                            onPressed: _busy.contains(p['id']) ? null : () => _act(p['id'] as int, 'completed'),
                            child: const Text('Mark Completed'),
                          )),
                        ],
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Accepted' => Colors.blue,
      'Rejected' => Colors.red,
      'Completed' => Colors.green,
      _ => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}
