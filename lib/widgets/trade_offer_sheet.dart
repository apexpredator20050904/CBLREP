import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/input_sanitizer.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';

/// Modal sheet for proposing a direct barter: the return side (one of your own
/// listings, or a short description of a skill/item) plus the handover
/// location. Mirrors `POST /api/exchanges`, which makes a return side mandatory
/// — that requirement is what separates a barter from a one-sided gift.
///
/// It replaces the old detail-screen free-text barter form with something that
/// reflects what really happens: you point at a thing you own, or you name what
/// you can give, and you agree where to hand it over.
///
/// The same sheet serves both directions, with the wording mirrored:
///
///   OFFER → you are the DEMANDER: "I have something, what do you want back?"
///   NEED  → you are the SUPPLIER: "I have what you need — what would you want
///            in return?" The return side is prefilled from what the poster
///            offered to trade.
class TradeOfferSheet extends StatefulWidget {
  final ListingModel listing;
  const TradeOfferSheet({super.key, required this.listing});

  @override
  State<TradeOfferSheet> createState() => TradeOfferSheetState();
}

class TradeOfferSheetState extends State<TradeOfferSheet> {
  final _describe = TextEditingController();
  final _purok = TextEditingController();

  /// 'listing' → offer one of my own listings; 'describe' → free text.
  String _mode = 'describe';
  int? _offeredResourceId;
  String _barangay = trinidadBarangays.first;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      if (trinidadBarangays.contains(user.barangay)) _barangay = user.barangay;
      _purok.text = user.purokSitio;
    }
    // On a NEED the reader is the SUPPLIER: they bring what the poster wants
    // and ask for the poster's side in return, which the poster already named
    // on the listing. Prefilling it saves the member from retyping it.
    if (widget.listing.isNeed && (widget.listing.wantedItem ?? '').isNotEmpty) {
      _describe.text = widget.listing.wantedItem!;
      _mode = 'describe';
    } else if (_ownOfferable().isNotEmpty) {
      // Prefer the pick-a-listing path when the member already has something to
      // offer; otherwise the free-text path is the only one that can work.
      _mode = 'listing';
    }
  }

  @override
  void dispose() {
    _describe.dispose();
    _purok.dispose();
    super.dispose();
  }

  /// The member's own active listings, minus the one being requested — the
  /// backend 422s a self-trade, so it must not be offerable here.
  List<ListingModel> _ownOfferable() {
    final myId = context.read<AuthProvider>().user?.id;
    if (myId == null) return const [];
    return context
        .read<ListingsProvider>()
        .listings
        .where((l) => l.ownerId == myId && l.active && l.id != widget.listing.id)
        .toList();
  }

  /// Validate locally first so a member sees the fix in one line instead of
  /// waiting on a round trip that answers 422 with a server-phrased message.
  String? _validate(String offeredItem) {
    if (_mode == 'listing' && _offeredResourceId == null) {
      return 'Choose which of your listings to offer.';
    }
    if (_mode == 'describe' && offeredItem.isEmpty) {
      return widget.listing.isNeed
          ? 'Say what you would like in return for bringing this.'
          : 'Describe what you will offer in return.';
    }
    final purok = _purok.text.trim();
    if (purok.isEmpty || !isValidPurokSitio(purok)) {
      return 'Enter a pick-up point like "Purok 3" or "Sitio Name".';
    }
    return null;
  }

  Future<void> _send() async {
    final offeredItem = _describe.text.trim();
    final error = _validate(offeredItem);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ApiService.instance.createExchange(
        resourceId: widget.listing.id,
        offeredResourceId: _mode == 'listing' ? _offeredResourceId : null,
        offeredItem: _mode == 'describe' ? InputSanitizer.text(offeredItem, max: 160) : null,
        barangay: _barangay,
        purokSitio: InputSanitizer.clean(_purok.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.statusCode == 401
            ? 'Your session has expired. Please sign in again.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final own = _ownOfferable();
    final foreground = dark ? Colors.white : Colors.black;
    final muted = dark ? Colors.white70 : Colors.black54;
    // On a NEED the reader is the SUPPLIER — they bring what the poster wants
    // and ask for the poster's side in return, so the whole sheet is worded
    // from that side of the table.
    final isNeed = widget.listing.isNeed;
    final quantity = (widget.listing.quantity ?? '').trim();

    return Padding(
      // Lift the sheet above the keyboard so the purok field stays visible.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? CblrepColors.deepForest : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: dark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isNeed ? 'I have this' : 'Make a trade offer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: foreground),
              ),
              const SizedBox(height: 4),
              Text(
                isNeed
                    ? 'They need “${widget.listing.title}”${quantity.isNotEmpty ? ' ($quantity)' : ''}'
                    : 'For “${widget.listing.title}”',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (widget.listing.hasWantedItem) ...[
                const SizedBox(height: 6),
                Text(
                  isNeed
                      ? 'They offered in return: ${widget.listing.wantedItem}'
                      : 'Owner wants: ${widget.listing.wantedItem}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CblrepColors.compBarter),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                isNeed ? 'What you would like in return' : 'What you give in return',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground),
              ),
              const SizedBox(height: 8),
              // Not a required-choice widget: either path alone satisfies the
              // two-sided rule, so a member without a spare listing can still
              // trade a skill.
              //
              // On a NEED the return side belongs to the POSTER, so there is
              // no "my listing" to pick — the supplier states in words what
              // they will take, prefilled from what the poster offered.
              if (!isNeed)
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'listing', label: Text('My listing'), icon: Icon(Icons.inventory_2_outlined, size: 16)),
                    ButtonSegment(value: 'describe', label: Text('Describe it'), icon: Icon(Icons.edit_outlined, size: 16)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => setState(() {
                    _mode = value.first;
                    _error = null;
                  }),
                ),
              const SizedBox(height: 12),
              if (_mode == 'listing')
                if (own.isEmpty)
                  Text(
                    'You have no other active listings. Switch to “Describe it” to name an item or a skill.',
                    style: TextStyle(fontSize: 12, color: muted),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: _offeredResourceId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Choose one of your listings'),
                    items: own
                        .map((l) => DropdownMenuItem(value: l.id, child: Text(l.title, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) => setState(() => _offeredResourceId = value),
                  )
              else
                TextField(
                  controller: _describe,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: isNeed
                        ? 'What the poster offered in return (adjust if you agree to something else)'
                        : 'e.g. 5 kg of rice, or an hour of plumbing help',
                    helperText: isNeed
                        ? 'They named this on the request — change it only if you would rather take something else.'
                        : null,
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _barangay,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Handover barangay'),
                items: trinidadBarangays
                    .map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _barangay = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _purok,
                decoration: const InputDecoration(labelText: 'Purok / Sitio (pick-up point)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: CblrepColors.dangerRed)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 46,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(
                    _sending
                        ? 'Sending…'
                        : (widget.listing.isNeed ? 'Send it' : 'Send offer'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the barter proposal sheet for [listing].
///
/// Resolves true when an offer was actually sent. Shared by the listing
/// detail screen and the home feed's "Propose Barter" action, so the fast
/// action on a card and the button on the details page are the same
/// two-sided proposal — not two different flows.
Future<bool> showTradeOfferSheet(BuildContext context, ListingModel listing) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TradeOfferSheet(listing: listing),
  );
  return sent == true;
}
