import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';

/// Time-Banking credits tracking — live balance + transaction ledger.
class TimeBankScreen extends StatefulWidget {
  const TimeBankScreen({super.key});
  @override
  State<TimeBankScreen> createState() => _TimeBankScreenState();
}

class _TimeBankScreenState extends State<TimeBankScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<LiveHubProvider>().refreshAll());
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<LiveHubProvider>();
    final bank = hub.timeBank != null ? TimeBankModel.fromJson(hub.timeBank!) : const TimeBankModel(balance: 0, earned: 0, spent: 0, pending: 0);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Time Bank'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => hub.refreshAll()),
      ]),
      body: RefreshIndicator(
        onRefresh: () => hub.refreshAll(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          CblrepGradientHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [CblrepLogo(radius: 18), SizedBox(width: 10), Text('TIME-BANK CREDITS', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4))]),
              const SizedBox(height: 8),
              Text('${bank.balance.toStringAsFixed(1)} hrs', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Row(children: [
                _mini('Earned', '${bank.earned.toStringAsFixed(1)}'),
                const SizedBox(width: 8),
                _mini('Spent', '${bank.spent.toStringAsFixed(1)}'),
                const SizedBox(width: 8),
                _mini('Pending', '${bank.pending.toStringAsFixed(1)}'),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (hub.timeBankTxns.isEmpty)
            Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)), child: const Text('No time-bank transactions yet.', style: TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center))
          else
            ...hub.timeBankTxns.take(30).map((e) {
              final t = Map<String, dynamic>.from(e as Map);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: CblrepColors.brandGreen, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.timelapse, color: Colors.white)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['service_title'] ?? t['title'] ?? 'Service'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                    Text('${t['status'] ?? 'pending'}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  ])),
                  Text('${t['hours'] ?? t['credits'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                ]),
              );
            }),
        ]),
      ),
    );
  }

  Widget _mini(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ]),
        ),
      );
}
