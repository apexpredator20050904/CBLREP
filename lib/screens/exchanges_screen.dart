import 'dart:async';
import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import 'timebank_screen.dart';

/// Exchanges tab — live data from /api/exchanges with approve/decline,
/// auto-refresh every 20s so transactions update without manual reload.
class ExchangesScreen extends StatefulWidget {
  const ExchangesScreen({super.key});
  @override
  State<ExchangesScreen> createState() => _ExchangesScreenState();
}

class _ExchangesScreenState extends State<ExchangesScreen> {
  int tab = 0;
  Timer? _timer;
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<LiveHubProvider>().refreshAll());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) context.read<LiveHubProvider>().refreshAll();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Accept / complete / cancel an exchange, with a confirmation modal for the
  /// irreversible transitions and inline busy state per row.
  Future<void> update(Map<String, dynamic> item, String status) async {
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final label = '${item['item'] ?? item['title'] ?? 'this exchange'}';

    final verb = switch (status) {
      'accepted' => 'Accept',
      'completed' => 'Mark as completed',
      _ => 'Cancel',
    };
    final detail = switch (status) {
      'accepted' => 'The other member will be notified that you accepted "$label".',
      'completed' => 'This closes "$label" and releases any reserved time-bank credits.',
      _ => 'This cancels "$label" for both members.',
    };

    final confirmed = await Feedback.confirm(
      context,
      title: '$verb?',
      message: detail,
      confirmLabel: verb,
      danger: status == 'cancelled',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy.add(id));
    try {
      await ApiService.instance.updateExchange(id, status);
      if (mounted) {
        Feedback.success(context, 'Exchange ${status == 'completed' ? 'completed' : '$status'}.');
      }
      await context.read<LiveHubProvider>().refreshAll();
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: () => update(item, status));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<LiveHubProvider>();
    final items = hub.exchanges.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final pending = items.where((e) => '${e['status']}'.toLowerCase() == 'pending').toList();
    final done = items.where((e) => '${e['status']}'.toLowerCase() != 'pending').toList();
    final shown = tab == 0 ? pending : done;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(
            child: SegmentedButton<int>(
              segments: const [ButtonSegment(value: 0, label: Text('Active')), ButtonSegment(value: 1, label: Text('Completed'))],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => tab = v.first),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Time Bank', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TimeBankScreen())), icon: const Icon(Icons.timelapse, size: 20)),
        ]),
      ),
      if (hub.lastUpdated != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Live · updated just now', style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black45))),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => hub.refreshAll(),
          child: shown.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 60),
                  Center(child: Text(tab == 0 ? 'No pending exchanges. Freecycle, barter or lend from any listing.' : 'No completed exchanges yet.', textAlign: TextAlign.center, style: TextStyle(color: dark ? Colors.white70 : Colors.black54)))
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final item = shown[i];
                    final isPending = '${item['status']}'.toLowerCase() == 'pending';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: CblrepColors.actionOrange, borderRadius: BorderRadius.circular(12)), child: Text('${item['type'] ?? 'Exchange'}'.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${item['item'] ?? item['title'] ?? 'Exchange'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black), overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 4),
                        Text("${item['withUser'] ?? ''} · ${item['status'] ?? ''}${item['dueCompleted'] != null && '${item['dueCompleted']}' != '—' ? ' · due ${item['dueCompleted']}' : ''}", style: const TextStyle(fontSize: 10, color: Colors.black54)),
                        if (isPending) ...[
                          const SizedBox(height: 8),
                          if (_busy.contains(item['id']))
                            const Row(children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 8),
                              Text('Updating…', style: TextStyle(fontSize: 10, color: Colors.black54)),
                            ])
                          else
                            Row(children: [
                              Expanded(child: SizedBox(height: 32, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: CblrepColors.brandGreen, foregroundColor: Colors.white), onPressed: () => update(item, 'accepted'), child: const Text('Accept', style: TextStyle(fontSize: 10))))),
                              const SizedBox(width: 8),
                              Expanded(child: SizedBox(height: 32, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: CblrepColors.actionOrange, foregroundColor: Colors.white), onPressed: () => update(item, 'completed'), child: const Text('Complete', style: TextStyle(fontSize: 10))))),
                              const SizedBox(width: 8),
                              Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: () => update(item, 'cancelled'), child: const Text('Cancel', style: TextStyle(fontSize: 10))))),
                            ]),
                        ],
                      ]),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
