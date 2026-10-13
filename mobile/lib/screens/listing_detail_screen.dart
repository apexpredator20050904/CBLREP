import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

/// Item details — full listing info, a direct-barter proposal form, message
/// owner, and manage (close) for owners.
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

  /// True when it is worth firing the inquiry request at all.
  ///
  /// The public listing feed does not need a session, so this screen is
  /// reachable signed out — and a session can also die mid-run. Opening a
  /// thread needs both, so ask first instead of sending a request that can
  /// only answer 401 and putting the raw server string ("Unauthenticated.")
  /// in front of the member.
  Future<bool> _canMessage() async {
    if (context.read<AuthProvider>().isAuthenticated) return true;
    return _promptSignIn(
      'Sign in to message the owner about this listing.',
    );
  }

  /// Offers the sign-in form and always resolves false: the form replaces the
  /// whole stack with a fresh dashboard, so nothing should continue afterwards.
  Future<bool> _promptSignIn(String message) async {
    if (!mounted) return false;
    final goToSignIn = await Feedback.confirm(
      context,
      title: 'Sign in required',
      message: message,
      confirmLabel: 'Sign in',
    );
    if (!goToSignIn || !mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    return false;
  }

  /// Surfaces an API failure without ever leaking the backend's phrasing for
  /// a rejected session, and without offering a RETRY that cannot succeed.
  void _reportFailure(ApiException e, VoidCallback onRetry) {
    if (!mounted) return;
    if (e.statusCode == 401) {
      // The session died while the member was reading the listing. AuthProvider
      // has already been told, so the shell returns them to the sign-in form;
      // this only explains why the screen is going away.
      Feedback.error(context, 'Your session has expired. Please sign in again.');
      return;
    }
    Feedback.error(context, e.message, onRetry: onRetry);
  }

  /// Open the direct-inquiry chat. This is the single negotiation channel for
  /// every compensation type — claim a gift, arrange a trade, or agree a price
  /// and pickup — replacing the old fixed barter-proposal forms.
  Future<void> _messageOwner() async {
    if (widget.listing.ownerId <= 0) {
      if (mounted) {
        Feedback.info(context, 'Owner chat is unavailable for this listing.');
      }
      return;
    }
    if (!await _canMessage()) return;
    try {
      // Scope the thread to this listing so the conversation shows which post
      // the inquiry is about, and each listing gets its own chat.
      final res = await ApiService.instance.startConversation(
        widget.listing.ownerId,
        listingId: widget.listing.id,
      );
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
      _reportFailure(e, _messageOwner);
    }
  }

  /// Open the inquiry chat pre-filled with a suggested opener tailored to the
  /// listing's compensation type, so a member can start negotiating in one tap.
  Future<void> _inquireWithOpening() async {
    final listing = widget.listing;
    final opener = switch (listing.compensationType) {
      'free' => 'Hi! Is "${listing.title}" still available for free? I can pick it up.',
      'paid' => 'Hi! I am interested in "${listing.title}"'
          '${listing.price != null ? ' (listed at ₱${listing.price!.toStringAsFixed(listing.price == listing.price!.roundToDouble() ? 0 : 2)})' : ''}. '
          'Is the price negotiable?',
      _ => 'Hi! I would like to trade for "${listing.title}". What would you like in return?',
    };
    await _openChat(opener);
  }

  /// Open (or resume) the listing thread, optionally seeding [prefill] the
  /// first time so the member lands in the chat with a ready message.
  Future<void> _openChat(String prefill) async {
    if (widget.listing.ownerId <= 0) {
      if (mounted) Feedback.info(context, 'Owner chat is unavailable for this listing.');
      return;
    }
    if (!await _canMessage()) return;
    try {
      final res = await ApiService.instance.startConversation(
        widget.listing.ownerId,
        listingId: widget.listing.id,
      );
      final conv = res['conversation'] is Map
          ? Map<String, dynamic>.from(res['conversation'] as Map)
          : <String, dynamic>{'id': widget.listing.ownerId};
      final id = (conv['id'] as num?)?.toInt() ?? 0;
      if (!mounted || id <= 0) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: id,
            title: widget.listing.owner,
            initialDraft: prefill,
          ),
        ),
      );
    } on ApiException catch (e) {
      _reportFailure(e, () => _openChat(prefill));
    }
  }

  /// Primary CTA wording depends on how the owner wants to share.
  String get _inquireLabel => switch (widget.listing.compensationType) {
        'free' => 'Message to claim',
        'paid' => 'Message / Buy',
        _ => 'Message / Inquire',
      };

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final need = listing.type == 'request';
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Owner-only affordances: "Close my listing" and the self-message guard.
    // The backend enforces both (404 on PATCH/DELETE, 422 on self-chat), but
    // the UI must not offer actions that can only fail.
    final myId = context.select<AuthProvider, int?>((p) => p.user?.id);
    final isOwner = myId != null && listing.ownerId == myId;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Item details', style: TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          height: 200,
          decoration: BoxDecoration(color: const Color(0xFF9AA5A0), borderRadius: BorderRadius.circular(14)),
          child: listing.imageUrl != null
              ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(listing.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(need ? Icons.help_outline : Icons.volunteer_activism, size: 72, color: Colors.white54)))
              : Icon(need ? Icons.help_outline : Icons.volunteer_activism, size: 72, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: dark ? CblrepColors.darkCardGreen : Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Wrap, not Row: a "FREE SHARING" badge beside the OFFER/NEED pill must
            // move to the next line rather than overflow the card.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ModeTag(
                  label: need ? 'NEED' : 'OFFER',
                  color: need ? CblrepColors.brandGreen : CblrepColors.actionOrange,
                ),
                _CompBadge(listing: listing),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              listing.title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                height: 1.3,
                color: dark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text('${listing.category} · ${listing.condition}', style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54)),
            if (listing.isPaid && listing.price != null) ...[
              const SizedBox(height: 6),
              Text('₱${listing.price!.toStringAsFixed(listing.price == listing.price!.roundToDouble() ? 0 : 2)}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: CblrepColors.compPaid)),
            ],
            const SizedBox(height: 8),
            Text(listing.description.isEmpty ? 'No description provided.' : listing.description, style: TextStyle(fontSize: 13, color: dark ? Colors.white : Colors.black87)),
            const Divider(height: 24),
            // Hyper-local context: the exact barangay + purok/sitio the item
            // is in, shown as explicit tags.
            _LocationTags(barangay: listing.barangay, purokSitio: listing.purokSitio, fallback: listing.location),
            const SizedBox(height: 10),
            // Author on its own row with the label outside the flexible area,
            // so a long name truncates inside the remaining width rather than
            // overlapping the icon or the card edge.
            _row(Icons.person_outline, listing.owner, label: 'Posted by'),
          ]),
        ),
        const SizedBox(height: 12),
        // Primary action: open the direct-inquiry chat about this listing.
        // This is the Facebook-Marketplace-style negotiation channel and works
        // for every compensation type (claim a gift, arrange a trade, or buy).
        // Hidden for the owner — you cannot message yourself.
        if (!isOwner) ...[
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _messageOwner,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(_inquireLabel),
            ),
          ),
          const SizedBox(height: 8),
          // One-tap negotiation: opens the same thread with a tailored opener,
          // so members skip the rigid proposal forms entirely.
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _inquireWithOpening,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Start a negotiation'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (isOwner)
          SizedBox(height: 42, width: double.infinity, child: OutlinedButton(onPressed: _close, child: const Text('Close my listing'))),
      ]),
    );
  }

  /// Icon + label + value row. The label is fixed width so the values line up,
/// and the value gets the remaining space with an ellipsis — no overlap, ever.
Widget _row(IconData icon, String text, {String? label}) => Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final muted = dark ? Colors.white60 : Colors.black45;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: dark ? Colors.white70 : Colors.black54),
                const SizedBox(width: 8),
                if (label != null) ...[
                  Text(label, style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// NEED/OFFER pill on the detail header.
class _ModeTag extends StatelessWidget {
  final String label;
  final Color color;
  const _ModeTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
}

/// Distinct compensation badge for the detail header — FREE SHARING / BARTER /
/// PAID, colour-coded to match the listing cards. With the price appended for
/// a paid sale so the amount is visible without scrolling back to the card.
class _CompBadge extends StatelessWidget {
  final ListingModel listing;
  const _CompBadge({required this.listing});

  @override
  Widget build(BuildContext context) {
    final color = switch (listing.compensationType) {
      'free' => CblrepColors.compFree,
      'paid' => CblrepColors.compPaid,
      _ => CblrepColors.compBarter,
    };
    final price = listing.isPaid && listing.price != null
        ? ' · ₱${listing.price == listing.price!.roundToDouble() ? listing.price!.toStringAsFixed(0) : listing.price!.toStringAsFixed(2)}'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(
        '${listing.compensationLabel}$price',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
      ),
    );
  }
}

/// Explicit hyper-local context on the detail screen.
///
/// The two values share one bounded row (barangay fixed, purok/sitio takes the
/// remainder and ellipsizes) so a long "Purok Poblacion Norte" can never push
/// the card's right edge past the viewport. Previously each value was a
/// `Wrap` chip containing a `mainAxisSize.min` row with an unbounded `Text`,
/// which overflowed once the labels exceeded the available width.
class _LocationTags extends StatelessWidget {
  final String barangay;
  final String purokSitio;
  final String fallback;
  const _LocationTags({required this.barangay, required this.purokSitio, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? Colors.white70 : Colors.black54;
    final background = dark ? CblrepColors.fieldGreen : const Color(0xFFEFE9DA);

    final parts = [
      if (barangay.trim().isNotEmpty) (Icons.location_city_outlined, 'Brgy. $barangay'),
      if (purokSitio.trim().isNotEmpty) (Icons.holiday_village_outlined, purokSitio),
    ];

    if (parts.isEmpty) {
      return _tag(
        context,
        icon: Icons.location_on_outlined,
        label: fallback.trim().isEmpty ? 'Trinidad, Bohol' : fallback,
        muted: muted,
        background: background,
      );
    }

    // One chip per line: guaranteed no horizontal overflow, and each value
    // keeps the room it needs to read.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, label) in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _tag(
              context,
              icon: icon,
              label: label,
              muted: muted,
              background: background,
            ),
          ),
      ],
    );
  }

  /// Full-width bounded chip: icon + ellipsized label.
  Widget _tag(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color muted,
    required Color background,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dark(context) ? Colors.white12 : Colors.black12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
              ),
            ),
          ],
        ),
      );

  bool dark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
}
