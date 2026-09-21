import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../models/models.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';
import 'chat_screen.dart';

/// Item details — full listing info, exchange request (freecycle / barter /
/// lending with return date), message owner, manage (close) for owners.
class ListingDetailScreen extends StatefulWidget {
  final ListingModel listing;
  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  bool busy = false;

  Future<void> _close() async {
    final confirm = await Feedback.confirm(
      context,
      title: 'Close listing?',
      message: 'Close "${widget.listing.title}" so members stop seeing it? '
          'This cannot be undone.',
      confirmLabel: 'Close listing',
      danger: true,
    );
    if (!confirm || !mounted) return;
    setState(() => busy = true);
    try {
      await context.read<ListingsProvider>().close(widget.listing.id);
      if (!mounted) return;
      Feedback.success(context, 'Listing closed.');
      Navigator.pop(context, 'closed');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: _close);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _requestExchange() async {
    String mode = widget.listing.exchangeType.toLowerCase().contains('barter')
        ? 'barter'
        : widget.listing.exchangeType.toLowerCase().contains('lend')
            ? 'lending'
            : 'freecycle';
    DateTime? returnDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setS) => AlertDialog(
            title: const Text('Request exchange'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Exchange type'),
                items: const [
                  DropdownMenuItem(value: 'freecycle', child: Text('Freecycle (gift)')),
                  DropdownMenuItem(value: 'barter', child: Text('Direct barter')),
                  DropdownMenuItem(value: 'lending', child: Text('Temporary lending')),
                ],
                onChanged: (v) => setS(() => mode = v ?? mode),
              ),
              if (mode == 'lending') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined, size: 16),
                  label: Text(returnDate == null ? 'Pick return date' : '${returnDate!.year}-${returnDate!.month.toString().padLeft(2, '0')}-${returnDate!.day.toString().padLeft(2, '0')}'),
                  onPressed: () async {
                    final picked = await showDatePicker(context: c, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setS(() => returnDate = picked);
                  },
                ),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send request')),
            ],
          )),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ApiService.instance.createExchange(
        resourceId: widget.listing.id,
        exchangeType: mode,
        returnDate: returnDate == null ? null : '${returnDate!.year}-${returnDate!.month.toString().padLeft(2, '0')}-${returnDate!.day.toString().padLeft(2, '0')}',
      );
      if (!mounted) return;
      await Feedback.alert(
        context,
        title: 'Request sent',
        message: 'Your ${mode == 'freecycle' ? 'freecycle claim' : mode == 'barter' ? 'barter offer' : 'lending request'} '
            'for "${widget.listing.title}" was sent to ${widget.listing.owner}.',
        icon: Icons.handshake_outlined,
      );
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: _requestExchange);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _messageOwner() async {
    if (widget.listing.ownerId <= 0) {
      if (mounted) {
        Feedback.info(context, 'Owner chat is unavailable for this listing.');
      }
      return;
    }
    try {
      final res = await ApiService.instance.startConversation(widget.listing.ownerId);
      final conv = res['conversation'] is Map
          ? Map<String, dynamic>.from(res['conversation'] as Map)
          : <String, dynamic>{'id': widget.listing.ownerId};
      final id = (conv['id'] as num?)?.toInt() ?? 0;
      if (!mounted || id <= 0) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id, title: widget.listing.owner)),
      );
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: _messageOwner);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final need = listing.type == 'request';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Item details', style: TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          height: 200,
          decoration: BoxDecoration(color: const Color(0xFF9AA5A0), borderRadius: BorderRadius.circular(14)),
          child: listing.imageUrl != null
              ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(listing.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(need ? Icons.help_outline : Icons.volunteer_activism, size: 72, color: Colors.black38)))
              : Icon(need ? Icons.help_outline : Icons.volunteer_activism, size: 72, color: Colors.black38),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: need ? CblrepColors.brandGreen : CblrepColors.actionOrange, borderRadius: BorderRadius.circular(20)), child: Text(need ? 'NEED' : 'OFFER', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Text(listing.exchangeType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
            ]),
            const SizedBox(height: 8),
            Text(listing.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
            const SizedBox(height: 4),
            Text('${listing.category} · ${listing.condition}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Text(listing.description.isEmpty ? 'No description provided.' : listing.description, style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const Divider(height: 24),
            _row(Icons.location_on_outlined, listing.location),
            _row(Icons.person_outline, listing.owner),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 46, width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : _requestExchange, icon: const Icon(Icons.swap_horiz, size: 18), label: Text(busy ? 'Sending…' : 'Request this resource'))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: SizedBox(height: 42, child: OutlinedButton.icon(onPressed: _messageOwner, icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('Message owner')))),
          const SizedBox(width: 8),
          Expanded(child: SizedBox(height: 42, child: OutlinedButton(onPressed: _close, child: const Text('Close my listing')))),
        ]),
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87))),
        ]),
      );
}
