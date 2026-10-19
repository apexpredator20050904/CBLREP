import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart';
import '../core/input_sanitizer.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/member_profile_sheet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/trade_offer_sheet.dart';
import '../widgets/user_avatar.dart';
import '../widgets/verified_badge.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

/// Item details — full listing info, the owner's return wish, one chat entry
/// point, a barter trade-offer form, and the owner's lifecycle controls
/// (pause / resume / mark traded / archive).
class ListingDetailScreen extends StatefulWidget {
  final ListingModel listing;
  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  bool busy = false;

  /// Move this listing to a new lifecycle state.
  ///
  /// Nothing is ever destroyed: pause hides it (reversible), traded records a
  /// completed swap, archive files it away. That is why the words are "pause"
  /// and "archive", never "delete". A listing a moderator has held back is
  /// read-only for the owner, and the API refuses the write (403).
  Future<void> _setStatus(String status) async {
    final title = switch (status) {
      'paused' => 'Pause',
      'active' => 'Resume',
      'traded' => 'Mark as traded',
      'archived' => 'Archive',
      _ => 'Update',
    };
    final done = switch (status) {
      'paused' => 'paused',
      'active' => 'resumed',
      'traded' => 'marked as traded',
      'archived' => 'archived',
      _ => 'updated',
    };
    final confirm = await Feedback.confirm(
      context,
      title: '$title listing?',
      message: switch (status) {
        'paused' =>
          'Hide "${widget.listing.title}" from the feed? You can resume it anytime.',
        'active' => '"${widget.listing.title}" will show in the community feed again.',
        'traded' =>
          'Mark "${widget.listing.title}" as traded? It moves to your Traded list.',
        'archived' =>
          '"${widget.listing.title}" moves to your archive. You can restore it anytime.',
        _ => '"${widget.listing.title}" will be updated.',
      },
      confirmLabel: title,
      danger: status == 'archived',
    );
    if (!confirm || !mounted) return;
    setState(() => busy = true);
    try {
      await context.read<ListingsProvider>().setMyListingStatus(widget.listing.id, status);
      if (!mounted) return;
      Feedback.success(context, 'Listing $done.');
      Navigator.pop(context, status);
    } on ApiException catch (e) {
      if (mounted) {
        Feedback.error(context, e.message, onRetry: () => _setStatus(status));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// True when a session exists; otherwise offers the sign-in form and always
  /// resolves false. [action] names what the member was trying to do, so the
  /// prompt reads naturally for chat ("message the owner") and for a trade
  /// offer alike.
  ///
  /// The public listing feed does not need a session, so this screen is
  /// reachable signed out — and a session can also die mid-run. Any action
  /// that needs a session asks first instead of sending a request that can
  /// only answer 401 and putting the raw server string ("Unauthenticated.")
  /// in front of the member.
  Future<bool> _ensureSignedIn(String action) async {
    if (context.read<AuthProvider>().isAuthenticated) return true;
    return _promptSignIn('Sign in to $action.');
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

  /// The single entry point for reaching the owner: open (or resume) the
  /// listing-scoped thread.
  ///
  /// This replaces the old pair of buttons that both opened the same chat
  /// ("Message / Inquire" and "Start a negotiation"). A tailored opener is
  /// seeded only on a brand-new thread, so returning to an ongoing
  /// conversation never re-injects a greeting. [opener] overrides that default
  /// (used by "Make an offer", which names the buyer's price).
  Future<void> _contactOwner({String? opener}) async {
    if (widget.listing.ownerId <= 0) {
      if (mounted) {
        Feedback.info(context, 'Owner chat is unavailable for this listing.');
      }
      return;
    }
    if (!await _ensureSignedIn('message the owner about this listing')) return;
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
      // `last_message_at` stays null until the first message is sent, so it
      // distinguishes a brand-new thread from an ongoing one without an extra
      // request.
      final isNewThread = conv['last_message_at'] == null;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: id,
            title: widget.listing.owner,
            initialDraft: isNewThread ? (opener ?? _suggestedOpener(widget.listing)) : null,
          ),
        ),
      );
    } on ApiException catch (e) {
      _reportFailure(e, _contactOwner);
    }
  }

  /// A ready-made first message tailored to how the owner wants to share, so a
  /// member can start talking in one tap.
  String _suggestedOpener(ListingModel listing) =>
      switch (listing.compensationType) {
        'free' => 'Hi! Is "${listing.title}" still available for free? I can pick it up.',
        'paid' => 'Hi! I am interested in "${listing.title}"'
            '${listing.price != null ? ' (listed at ₱${listing.price!.toStringAsFixed(listing.price == listing.price!.roundToDouble() ? 0 : 2)})' : ''}. '
            'Is the price negotiable?',
        _ => 'Hi! I would like to trade for "${listing.title}". What would you like in return?',
      };

  /// Open the structured barter offer: choose or describe what you give in
  /// return, confirm the handover location, and send a proposal the owner can
  /// accept or decline in the Exchanges tab.
  ///
  /// This is deliberately *not* the chat — a recorded, two-sided offer is a
  /// different real-world act from haggling in messages, and only barter
  /// listings have a return side to offer.
  Future<void> _openTradeOffer() async {
    if (widget.listing.ownerId <= 0) {
      if (mounted) Feedback.info(context, 'Owner chat is unavailable for this listing.');
      return;
    }
    if (!await _ensureSignedIn('send a trade offer for this listing')) return;
    if (!mounted) return;
    final sent = await showTradeOfferSheet(context, widget.listing);
    if (sent && mounted) {
      Feedback.success(context, 'Trade offer sent. Track it in Exchanges.');
    }
  }

  /// Paid + negotiable: let a buyer name a price without haggling blind.
  ///
  /// The offer is sent as the first message of the listing's own thread. The
  /// Exchange model is deliberately a two-sided barter (see App\Models\Exchange),
  /// so a monetary counter-offer is — correctly — a conversation the owner can
  /// answer, not a recorded exchange.
  Future<void> _makeOffer() async {
    if (widget.listing.ownerId <= 0) {
      if (mounted) Feedback.info(context, 'Owner chat is unavailable for this listing.');
      return;
    }
    if (!await _ensureSignedIn('make an offer for this listing')) return;
    if (!mounted) return;
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _OfferDialog(listedPrice: widget.listing.price),
    );
    if (amount == null || !mounted) return;
    final formatted = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    await _contactOwner(
      opener: 'Hi! I would like to offer ₱$formatted for "${widget.listing.title}". Would that work?',
    );
  }

  /// Primary CTA wording depends on how the owner wants to share.
  String get _inquireLabel => switch (widget.listing.compensationType) {
        'free' => 'Message to claim',
        'paid' => 'Message / Buy',
        _ => 'Message / Inquire',
      };

  /// Report the posting from the details screen's three-dot menu.
  Future<void> _reportListing() async {
    final sent = await showReportSheet(
      context,
      reportableType: ReportTarget.listing,
      reportableId: widget.listing.id,
      subjectName: widget.listing.title,
    );
    if (sent && mounted) {
      Feedback.success(
        context,
        'Thank you for helping keep our community safe. '
        'Our team will review this listing.',
      );
    }
  }

  /// Report the owner from the details screen's three-dot menu.
  Future<void> _reportOwner() async {
    final listing = widget.listing;
    if (listing.ownerId <= 0) {
      if (mounted) Feedback.info(context, 'This listing has no owner to report.');
      return;
    }
    final sent = await showReportSheet(
      context,
      reportableType: ReportTarget.user,
      reportableId: listing.ownerId,
      subjectName: listing.owner,
    );
    if (sent && mounted) {
      Feedback.success(
        context,
        'Thank you for helping keep our community safe. '
        'Our team will review this account.',
      );
    }
  }

  /// Open the owner's profile — their name, photo, verification status and
  /// the action to report them.
  Future<void> _openOwner() async {
    final listing = widget.listing;
    final myId = context.read<AuthProvider>().user?.id;
    await showMemberProfileSheet(
      context,
      name: listing.owner,
      avatarUrl: listing.ownerAvatarUrl,
      verified: listing.ownerVerified,
      userId: listing.ownerId,
      canReport: myId == null || myId != listing.ownerId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final need = listing.type == 'request';
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Owner-only affordances: the lifecycle controls below and the
    // self-message guard. The backend enforces both (404 on PATCH/DELETE for a
    // listing you do not own, 403 while a moderator holds it, 422 on
    // self-chat), but the UI must not offer actions that can only fail.
    final myId = context.select<AuthProvider, int?>((p) => p.user?.id);
    final isOwner = myId != null && listing.ownerId == myId;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(
        title: const Text('Item details', style: TextStyle(fontSize: 16)),
        // The three-dot menu: report the posting, and report the owner.
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: Icon(Icons.more_vert, size: 20, color: dark ? Colors.white70 : null),
            onSelected: (value) {
              if (value == 'report_listing') _reportListing();
              if (value == 'report_user') _reportOwner();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'report_listing',
                enabled: !isOwner,
                child: Row(
                  children: [
                    Icon(
                      Icons.report_gmailerrorred_outlined,
                      size: 18,
                      color: isOwner ? Colors.black26 : CblrepColors.dangerRed,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Report posting',
                      style: TextStyle(
                        fontSize: 13,
                        color: isOwner ? Colors.black26 : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'report_user',
                enabled: !isOwner && listing.ownerId > 0,
                child: Row(
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      size: 18,
                      color: (isOwner || listing.ownerId <= 0)
                          ? Colors.black26
                          : CblrepColors.dangerRed,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Report user',
                      style: TextStyle(
                        fontSize: 13,
                        color: (isOwner || listing.ownerId <= 0) ? Colors.black26 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _ListingGallery(
          images: listing.imageUrls.isNotEmpty
              ? listing.imageUrls
              : (listing.imageUrl != null ? [listing.imageUrl!] : const []),
          placeholderIcon: need ? Icons.help_outline : Icons.volunteer_activism,
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
              Row(children: [
                Text('₱${listing.price!.toStringAsFixed(listing.price == listing.price!.roundToDouble() ? 0 : 2)}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: CblrepColors.compPaid)),
                if (listing.isNegotiable) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: CblrepColors.compPaid.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Negotiable',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: CblrepColors.compPaid)),
                  ),
                ],
              ]),
            ],
            const SizedBox(height: 8),
            Text(listing.description.isEmpty ? 'No description provided.' : listing.description, style: TextStyle(fontSize: 13, color: dark ? Colors.white : Colors.black87)),
            // The return side of a barter, spelled out so a member knows what
            // the owner will actually trade for before they offer anything.
            if (listing.isBarter && listing.hasWantedItem) ...[
              const SizedBox(height: 10),
              _row(Icons.swap_horiz, listing.wantedItem!, label: 'Wants in return'),
            ],
            const Divider(height: 24),
            // Hyper-local context: the exact barangay + purok/sitio the item
            // is in, shown as explicit tags.
            _LocationTags(barangay: listing.barangay, purokSitio: listing.purokSitio, fallback: listing.location),
            const SizedBox(height: 10),
            // Author on its own row with the label outside the flexible area,
            // so a long name truncates inside the remaining width rather than
            // overlapping the icon or the card edge.
            // Author with their photo and (when confirmed) a verified tick, so
            // a member can size up who they are dealing with at a glance.
            Builder(builder: (context) {
              final rowDark = Theme.of(context).brightness == Brightness.dark;
              final rowMuted = rowDark ? Colors.white60 : Colors.black45;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    UserAvatar(
                      imageUrl: listing.ownerAvatarUrl,
                      name: listing.owner,
                      radius: 14,
                    ),
                    const SizedBox(width: 8),
                    Text('Posted by', style: TextStyle(fontSize: 12, color: rowMuted)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: InkWell(
                        onTap: _openOwner,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            listing.owner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: rowDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  // The verification payoff, spelled out. On its own line so a
                  // long owner name can never push it off the card edge.
                  if (listing.ownerVerified) ...[
                    const SizedBox(height: 6),
                    const VerifiedBadge(),
                  ],
                ]),
              );
            }),
          ]),
        ),
        const SizedBox(height: 12),
        // Primary action for everyone else: open the single direct-inquiry
        // chat about this listing. This is the Facebook-Marketplace-style
        // negotiation channel and works for every compensation type (claim a
        // gift, arrange a trade, or buy). Hidden for the owner — you cannot
        // message yourself.
        if (!isOwner) ...[
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _contactOwner,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(_inquireLabel),
            ),
          ),
          // Barter only: a recorded, two-sided offer is a different act from
          // chatting, so it gets its own CTA. Free/paid listings have no
          // return side, so this is omitted rather than shown disabled.
          if (listing.isBarter) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openTradeOffer,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Make a trade offer'),
              ),
            ),
          ],
          // Paid + negotiable: name a price up front instead of haggling blind.
          if (listing.isNegotiable) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _makeOffer,
                icon: const Icon(Icons.local_offer_outlined, size: 18),
                label: const Text('Make an offer'),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
        if (isOwner) _ownerPanel(listing, dark),
      ]),
    );
  }

  /// Owner lifecycle controls. Every action here is reversible, and a listing
  /// a moderator has held is shown read-only rather than with a menu that the
  /// API would reject.
  Widget _ownerPanel(ListingModel listing, bool dark) {
    final muted = dark ? Colors.white70 : Colors.black54;

    if (listing.underReview) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CblrepColors.dangerRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CblrepColors.dangerRed.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.lock_outline, color: CblrepColors.dangerRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This listing is under review by a moderator, so it is hidden '
              'from the feed and cannot be changed here.',
              style: TextStyle(fontSize: 12, color: dark ? Colors.white : Colors.black87),
            ),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: CblrepColors.actionOrange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            listing.statusLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CblrepColors.actionOrange,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_ownerHint(listing), style: TextStyle(fontSize: 11, color: muted)),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (listing.isActiveStatus)
          OutlinedButton.icon(
            onPressed: busy ? null : () => _setStatus('paused'),
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: const Text('Pause'),
          )
        else
          FilledButton.icon(
            onPressed: busy ? null : () => _setStatus('active'),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Put back in feed'),
          ),
        if (!listing.isTraded)
          OutlinedButton.icon(
            onPressed: busy ? null : () => _setStatus('traded'),
            icon: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('Mark as traded'),
          ),
        if (!listing.isArchived)
          OutlinedButton.icon(
            onPressed: busy ? null : () => _setStatus('archived'),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: const Text('Archive'),
          ),
      ]),
    ]);
  }

  String _ownerHint(ListingModel listing) => switch (listing.status) {
        'active' => 'Live in the community feed.',
        'paused' => 'Hidden from the feed. Resume it whenever you are ready.',
        'traded' => 'Kept as a record of a completed swap.',
        'archived' => 'Filed away. Restore it to post again.',
        _ => '',
      };

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

/// Modal sheet for proposing a direct barter: the return side (one of your own
/// listings, or a short description of a skill/item) plus the handover
/// location. Mirrors `POST /api/exchanges`, which makes a return side mandatory
/// — that requirement is what separates a barter from a one-sided gift.
///
/// It replaces the old detail-screen free-text barter form with something that
/// reflects what really happens: you point at a thing you own, or you name what
/// you can give, and you agree where to hand it over.
class _TradeOfferSheet extends StatefulWidget {
  final ListingModel listing;
  const _TradeOfferSheet({required this.listing});

  @override
  State<_TradeOfferSheet> createState() => _TradeOfferSheetState();
}

class _TradeOfferSheetState extends State<_TradeOfferSheet> {
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
    // Prefer the pick-a-listing path when the member already has something to
    // offer; otherwise the free-text path is the only one that can work.
    if (_ownOfferable().isNotEmpty) _mode = 'listing';
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
      return 'Describe what you will offer in return.';
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
              Text('Make a trade offer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: foreground)),
              const SizedBox(height: 4),
              Text('For “${widget.listing.title}”', style: TextStyle(fontSize: 12, color: muted)),
              if (widget.listing.hasWantedItem) ...[
                const SizedBox(height: 6),
                Text(
                  'Owner wants: ${widget.listing.wantedItem}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CblrepColors.compBarter),
                ),
              ],
              const SizedBox(height: 16),
              Text('What you give in return', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
              const SizedBox(height: 8),
              // Not a required-choice widget: either path alone satisfies the
              // two-sided rule, so a member without a spare listing can still
              // trade a skill.
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
                  decoration: const InputDecoration(labelText: 'e.g. 5 kg of rice, or an hour of plumbing help'),
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
                  label: Text(_sending ? 'Sending…' : 'Send offer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny dialog for naming a price on a negotiable listing. Returns the parsed
/// amount, or null when the buyer backs out. It never sends anything itself —
/// the caller turns the amount into the chat opener, so the offer flows through
/// the same listing-scoped thread as every other inquiry.
class _OfferDialog extends StatefulWidget {
  final double? listedPrice;
  const _OfferDialog({this.listedPrice});

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.listedPrice == null
        ? ''
        : (widget.listedPrice == widget.listedPrice!.roundToDouble()
            ? widget.listedPrice!.toStringAsFixed(0)
            : widget.listedPrice!.toStringAsFixed(2)),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_amount.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    String money(double v) =>
        '₱${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';
    return AlertDialog(
      title: const Text('Make an offer', style: TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.listedPrice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Listed at ${money(widget.listedPrice!)}. Your offer is sent to the seller as a chat message.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54),
              ),
            ),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Your offer (₱)',
              prefixText: '₱ ',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Send offer')),
      ],
    );
  }
}

/// The listing's photo gallery.
///
/// One photo renders much like before; several become a swipeable pager with a
/// position badge and dots, so a buyer can judge an item's condition from every
/// angle without leaving the screen. No photos falls back to the placeholder
/// icon the detail screen always used.
class _ListingGallery extends StatefulWidget {
  final List<String> images;
  final IconData placeholderIcon;
  const _ListingGallery({required this.images, required this.placeholderIcon});

  @override
  State<_ListingGallery> createState() => _ListingGalleryState();
}

class _ListingGalleryState extends State<_ListingGallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(color: const Color(0xFF9AA5A0), borderRadius: BorderRadius.circular(14)),
        child: Icon(widget.placeholderIcon, size: 72, color: Colors.white54),
      );
    }

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Image.network(
                widget.images[i],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFF9AA5A0),
                  child: Icon(widget.placeholderIcon, size: 72, color: Colors.white54),
                ),
              ),
            ),
          ),
          if (widget.images.length > 1) ...[
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text('${_index + 1}/${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.images.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? Colors.white : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
