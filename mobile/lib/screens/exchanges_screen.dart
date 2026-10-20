import 'dart:async';
import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/empty_state.dart';

/// Exchanges tab — live data from /api/exchanges.
///
/// Dual-Confirmation Model:
///   pending  → owner Accept / Decline, proposer Cancel
///   accepted → BOTH parties tap "Confirm Trade Completed"
///              (POST /api/exchanges/{id}/confirm-completion).
///              First confirm → "Waiting for other party's confirmation".
///              Second confirm → status flips to `completed` server-side.
/// No single party can mark a trade completed on their own.
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

  /// Accept / decline / cancel via PATCH /api/exchanges/{id}.
  /// (`completed` is intentionally NOT sent here — it must go through
  /// confirmCompletion() below so both parties confirm independently.)
  Future<void> update(Map<String, dynamic> item, String status) async {
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final label = '${item['item'] ?? item['title'] ?? 'this exchange'}';

    final verb = switch (status) {
      'accepted' => 'Accept',
      'rejected' => 'Decline',
      _ => 'Cancel',
    };
    final detail = switch (status) {
      'accepted' => 'The other member will be notified that you accepted "$label".',
      'rejected' => 'This declines "$label" for both members.',
      _ => 'This cancels "$label" for both members.',
    };

    final confirmed = await Feedback.confirm(
      context,
      title: '$verb?',
      message: detail,
      confirmLabel: verb,
      danger: status == 'cancelled' || status == 'rejected',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy.add(id));
    try {
      final res = await ApiService.instance.updateExchange(id, status);
      if (mounted) {
        Feedback.success(context, '${res['message'] ?? 'Exchange $status.'}');
      }
      await context.read<LiveHubProvider>().refreshAll();
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: () => update(item, status));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Dual-confirmation: record MY half of the completion.
  /// Server answers either partial ("Waiting for other party's
  /// confirmation") or final ("Both confirmed - Exchange completed").
  Future<void> confirmCompletion(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final label = '${item['item'] ?? item['title'] ?? 'this exchange'}';
    final isFulfilment = item['kind'] == 'fulfilment';

    final confirmed = await Feedback.confirm(
      context,
      title: isFulfilment ? 'Confirm Handover?' : 'Confirm Trade Completed?',
      message: isFulfilment
          ? 'Confirm that you handed over "$label". '
              'It only counts once BOTH neighbours confirm.'
          : 'Confirm that the handover for "$label" really took place. '
              'The trade only completes once BOTH members confirm.',
      confirmLabel: isFulfilment ? 'Confirm Handover' : 'Confirm Completed',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy.add(id));
    try {
      final res = await ApiService.instance.confirmExchangeCompletion(id);
      if (mounted) {
        Feedback.success(context, '${res['message'] ?? 'Confirmation recorded.'}');
      }
      await context.read<LiveHubProvider>().refreshAll();
    } on ApiException catch (e) {
      if (mounted) {
        Feedback.error(context, e.message, onRetry: () => confirmCompletion(item));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<LiveHubProvider>();
    final items = hub.exchanges.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    bool isActive(Map<String, dynamic> e) {
      final raw = '${e['raw_status'] ?? e['status']}'.toLowerCase();
      return raw == 'pending' || raw == 'accepted';
    }

    final active = items.where(isActive).toList();
    final history = items.where((e) => !isActive(e)).toList();
    final shown = tab == 0 ? active : history;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SegmentedButton<int>(
          segments: const [ButtonSegment(value: 0, label: Text('Active')), ButtonSegment(value: 1, label: Text('History'))],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
      ),
      if (hub.lastUpdated != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Live · updated just now', style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black45))),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => hub.refreshAll(),
          child: shown.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 40),
                  EmptyState(
                    icon: tab == 0 ? Icons.swap_horiz_outlined : Icons.verified_outlined,
                    title: tab == 0 ? 'No active exchanges' : 'No completed exchanges',
                    subtitle: tab == 0 ? 'Propose a direct barter from any listing to get started.' : 'Finished exchanges will be recorded here.',
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final item = shown[i];
                    final raw = '${item['raw_status'] ?? item['status']}'.toLowerCase();
                    final isPending = raw == 'pending';
                    final isAccepted = raw == 'accepted';
                    final isCompleted = raw == 'completed';
                    final busy = _busy.contains(item['id']);
                    final role = '${item['role'] ?? ''}';
                    final canRespond = item['can_respond'] == true;
                    final canCancel = item['can_cancel'] == true;
                    final proposerOk = item['proposer_confirmed'] == true;
                    final ownerOk = item['owner_confirmed'] == true;
                    final iConfirmed = item['i_confirmed'] == true;
                    // A FULFILMENT answers a NEED ("I have what you want"):
                    // the proposer is the supplier and the listing owner is
                    // the requester. The state machine is the same, the words
                    // are not.
                    final isFulfilment = item['kind'] == 'fulfilment';
                    final proposerLabel = isFulfilment ? 'Supplier' : 'Proposer';
                    final ownerLabel = isFulfilment ? 'Requester' : 'Owner';
                    // Fallback keeps the button visible for older payloads
                    // that lack can_confirm_completion.
                    final canConfirm =
                        (item['can_confirm_completion'] == true) ||
                            (isAccepted && !iConfirmed && !busy);
                    var confirmLabel = '${item['confirmation_label'] ?? ''}';
                    if (confirmLabel.isEmpty) {
                      if (isCompleted) {
                        confirmLabel = 'Both confirmed - Exchange completed';
                      } else if (proposerOk || ownerOk) {
                        confirmLabel = "Waiting for other party's confirmation";
                      } else if (isAccepted) {
                        confirmLabel = 'Awaiting both confirmations';
                      }
                    }
                    final bannerBg = isCompleted
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFF8E1);
                    final bannerFg = isCompleted
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFF57F17);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: dark ? CblrepColors.darkCardGreen : Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: CblrepColors.actionOrange, borderRadius: BorderRadius.circular(12)), child: Text(isFulfilment ? 'SUPPLYING' : '${item['type'] ?? 'Exchange'}'.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${item['item'] ?? item['title'] ?? 'Exchange'}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dark ? Colors.white : Colors.black), overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                           isFulfilment
                               ? 'They need: ${item['item'] ?? '—'}  ·  In return: ${item['offered'] ?? '—'}'
                               : 'Giving: ${item['offered'] ?? '—'}',
                           style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54),
                         ),
                        if ((item['barangay'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('${item['barangay']}${(item['purok_sitio'] ?? '').toString().isNotEmpty ? ' · ${item['purok_sitio']}' : ''}', style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black45)),
                        ],
                        const SizedBox(height: 4),
                        Text("${item['withUser'] ?? ''} · ${item['status'] ?? ''}${item['dueCompleted'] != null && '${item['dueCompleted']}' != '—' ? ' · ${item['dueCompleted']}' : ''}", style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54)),
                        if (isAccepted || isCompleted) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(color: bannerBg, borderRadius: BorderRadius.circular(8)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(isCompleted ? Icons.verified : Icons.hourglass_empty, size: 14, color: bannerFg),
                                const SizedBox(width: 6),
                                Expanded(child: Text(confirmLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: bannerFg))),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(proposerOk ? Icons.check_circle : Icons.radio_button_unchecked, size: 12, color: proposerOk ? Colors.green : Colors.grey),
                                const SizedBox(width: 4),
                                Text('$proposerLabel ${proposerOk ? '✓' : '·'}', style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54)),
                                const SizedBox(width: 10),
                                Icon(ownerOk ? Icons.check_circle : Icons.radio_button_unchecked, size: 12, color: ownerOk ? Colors.green : Colors.grey),
                                const SizedBox(width: 4),
                                Text('$ownerLabel ${ownerOk ? '✓' : '·'}', style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54)),
                              ]),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (busy)
                          Row(children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Updating…', style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54)),
                          ])
                        else if (isPending) ...[
                          if (canRespond)
                            Row(children: [
                              Expanded(child: SizedBox(height: 32, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: CblrepColors.brandGreen, foregroundColor: Colors.white), onPressed: () => update(item, 'accepted'), child: Text('Accept', style: TextStyle(fontSize: 10))))),
                              const SizedBox(width: 8),
                              Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: () => update(item, 'rejected'), child: Text('Decline', style: TextStyle(fontSize: 10))))),
                              const SizedBox(width: 8),
                              Expanded(child: SizedBox(height: 32, child: OutlinedButton(onPressed: () => update(item, 'cancelled'), child: Text('Cancel', style: TextStyle(fontSize: 10))))),
                            ])
                          else
                            Row(children: [
                              Expanded(child: Text(isFulfilment ? 'Waiting for the poster to respond…' : 'Waiting for owner response…', style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54))),
                              if (canCancel || role == 'proposer')
                                SizedBox(height: 32, child: OutlinedButton(onPressed: () => update(item, 'cancelled'), child: Text('Cancel', style: TextStyle(fontSize: 10)))),
                            ]),
                        ] else if (isAccepted) ...[
                          if (canConfirm)
                            SizedBox(width: double.infinity, height: 36, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: CblrepColors.brandGreen, foregroundColor: Colors.white), onPressed: () => confirmCompletion(item), child: Text(isFulfilment ? 'Confirm Handover' : 'Confirm Trade Completed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
                          if (iConfirmed)
                            Row(children: [
                              Icon(Icons.check_circle, size: 14, color: Colors.green),
                              SizedBox(width: 6),
                              Expanded(child: Text("You confirmed. Waiting for other party's confirmation.", style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54))),
                            ]),
                          if (canCancel) ...[
                            const SizedBox(height: 6),
                            SizedBox(width: double.infinity, height: 32, child: OutlinedButton(onPressed: () => update(item, 'cancelled'), child: Text('Cancel exchange', style: TextStyle(fontSize: 10)))),
                          ],
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
