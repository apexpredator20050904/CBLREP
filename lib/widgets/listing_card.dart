import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/cblrep_theme.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

/// Reusable resource card for the home feed.
///
/// Layout contract — the card sizes itself from its content (a fixed-height
/// photo plus a natural-height body), so it can be dropped into a list or a
/// grid without the parent having to compute a ratio:
///
///  * The photo has a FIXED height rather than a flexible one. A flexible
///    photo only works when the parent hands the card an exact box; a
///    content-sized card cannot. A fixed height also means every card in the
///    feed shows the same amount of the item, which is what makes a
///    marketplace feed scannable.
///  * Every text run lives inside an [Expanded]/[Flexible] with
///    [TextOverflow.ellipsis], so a long owner name or purok tag truncates
///    cleanly instead of colliding with the element beside it.
///  * The action row is built from [Expanded] buttons, so the two fast
///    actions always share the available width evenly — down to a 320dp
///    phone — instead of overflowing.
class ListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback? onTap;

  /// The "View Details" action.
  final VoidCallback? onViewDetails;

  /// The secondary action: propose a barter, claim a gift, or make an offer.
  final VoidCallback? onPropose;

  /// The three-dot menu. When null the menu button is not rendered at all —
  /// a card with an empty menu is worse than no menu.
  final VoidCallback? onReport;

  /// Opens the owner's profile. When null the owner row is not tappable.
  final VoidCallback? onOwnerTap;

  /// How far away the listing is ("≈1.2 km away"), shown when the feed is
  /// sorted by proximity.
  final String? distanceLabel;

  const ListingCard({
    super.key,
    required this.listing,
    this.onTap,
    this.onViewDetails,
    this.onPropose,
    this.onReport,
    this.onOwnerTap,
    this.distanceLabel,
  });

  bool get isNeed => listing.type == 'request';

  /// Accent colour for the compensation family — single source of truth in
  /// [CblrepColors.compensationColor] (green = gift, amber = trade, blue = sale).
  static Color compensationColor(String type) => CblrepColors.compensationColor(type);

  /// "PAID · ₱250" style caption, or the bare label for free/barter.
  String get compensationCaption {
    if (listing.isPaid && listing.price != null) {
      final whole = listing.price == listing.price!.roundToDouble();
      final formatted =
          whole ? listing.price!.toStringAsFixed(0) : listing.price!.toStringAsFixed(2);
      return '${listing.compensationLabel} · ₱$formatted';
    }
    return listing.compensationLabel;
  }

  /// Explicit barangay + purok/sitio tag, falling back to the free-text
  /// location for legacy rows that predate structured location fields.
  String get _locationTag {
    final parts =
        [listing.barangay, listing.purokSitio].where((p) => p.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' · ');
    return listing.location.isEmpty ? 'Trinidad, Bohol' : listing.location;
  }

  /// A short, uniform condition badge.
  ///
  /// The backend stores whatever the member typed ("Good condition, minor
  /// scratches"), but a badge has to be short enough to sit over a photo, so
  /// the common words are mapped onto the three labels a buyer actually
  /// scans for. Anything unrecognised falls back to the member's own words.
  String get _conditionBadge {
    final raw = listing.condition.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('like new') || lower == 'new') return 'Like New';
    if (lower.contains('fair') || lower.contains('poor')) return 'Fair';
    if (lower.contains('good')) return 'Good';
    if (raw.isEmpty) return 'Good';
    return raw.length > 18 ? '${raw.substring(0, 17)}…' : raw;
  }

  /// The label of the secondary action, matched to how the owner shares.
  String get _proposeLabel => switch (listing.compensationType) {
        'free' => 'Claim Item',
        'paid' => 'Make Offer',
        _ => 'Propose Barter',
      };

  /// The icon of the secondary action, matched to how the owner shares.
  IconData get _proposeIcon => switch (listing.compensationType) {
        'free' => Icons.redeem_outlined,
        'paid' => Icons.local_offer_outlined,
        _ => Icons.swap_horiz,
      };

  /// Centered watermark shown while a listing has no usable photo.
  Widget _placeholder(bool need) => Center(
        child: Icon(
          need ? Icons.help_outline : Icons.volunteer_activism,
          size: 44,
          color: Colors.white24,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? Colors.white60 : Colors.black54;
    final strong = dark ? Colors.white : Colors.black;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Photo ──────────────────────────────────────────────────
            // A fixed height keeps every card in the feed the same shape, so
            // the eye can run down the column without re-reading each one.
            SizedBox(
              height: 168,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Branded gradient placeholder instead of a flat grey block
                  // while a listing has no uploaded photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3B6B48), Color(0xFF1B382B)],
                      ),
                    ),
                  ),
                  if (listing.imageUrl != null)
                    Image.network(
                      listing.imageUrl!,
                      fit: BoxFit.cover,
                      // Decode at card resolution instead of full camera size —
                      // a big scroll-smoothness win on 2-core devices.
                      cacheWidth: 640,
                      errorBuilder: (_, _, _) => _placeholder(isNeed),
                    )
                  else
                    _placeholder(isNeed),
                  // A soft scrim under the bottom row of badges so white text
                  // stays readable on a bright photo.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _ModePill(label: isNeed ? 'NEED' : 'OFFER', need: isNeed),
                  ),
                  // Distinct compensation badge — the flexible-sharing signal.
                  // Positioned, so a long "PAID · ₱1,250" caption can never
                  // squeeze the OFFER pill; the stack clips instead.
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _CompensationPill(
                      label: compensationCaption,
                      color: compensationColor(listing.compensationType),
                    ),
                  ),
                  // The item's condition, bottom-left over the scrim.
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _ConditionTag(label: _conditionBadge),
                  ),
                ],
              ),
            ),
            // ── Body ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.25,
                      color: strong,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Hyper-local tag. The chip sizes to the card width and its
                  // text ellipsizes, so "Barangay Poblacion · Purok 3"
                  // degrades to "Barangay Poblaci…" rather than running past
                  // the card edge.
                  LocationChip(
                    label: _locationTag,
                    dark: dark,
                  ),
                  // The owner's wishlist — the return side of a barter. It is
                  // the single most useful thing on the card for a member
                  // scanning for a trade, so it gets its own line.
                  if (listing.hasWantedItem) ...[
                    const SizedBox(height: 6),
                    _WantedTag(item: listing.wantedItem!),
                  ],
                  const SizedBox(height: 8),
                  // Owner on their own line: a small photo (or initials) plus
                  // the name, with a verified tick when the owner's residency
                  // is confirmed, and the distance when the feed is sorted by
                  // proximity. Tapping the owner opens their profile.
                  Row(
                    children: [
                      UserAvatar(
                        imageUrl: listing.ownerAvatarUrl,
                        name: listing.owner,
                        radius: 9,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(children: [
                          Flexible(
                            child: InkWell(
                              onTap: onOwnerTap,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  listing.owner,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (listing.ownerVerified) ...[
                            const SizedBox(width: 3),
                            const VerifiedBadge(compact: true),
                          ],
                        ]),
                      ),
                      if (distanceLabel != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            distanceLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Fast actions ─────────────────────────────────────
                  // The two actions a member reaches for, side by side, plus
                  // the report menu. Expanded buttons so the row fits any
                  // phone width; the ⋮ stays a fixed-size target.
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: OutlinedButton.icon(
                            onPressed: onViewDetails ?? onTap,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              foregroundColor: strong,
                              side: BorderSide(
                                color: dark ? Colors.white24 : Colors.black26,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 16),
                            // The button already lays its label out in a
                            // Flexible, so the label is a plain Text that
                            // ellipsizes rather than a second Flexible (which
                            // would be two competing parent-data widgets).
                            label: const Text(
                              'View Details',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: FilledButton.icon(
                            onPressed: onPropose,
                            style: FilledButton.styleFrom(
                              backgroundColor: CblrepColors.actionOrange,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(_proposeIcon, size: 16),
                            label: Text(
                              _proposeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onReport != null) ...[
                        const SizedBox(width: 4),
                        _ReportMenu(onReport: onReport!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The condition badge overlaid on the listing photo.
class _ConditionTag extends StatelessWidget {
  final String label;
  const _ConditionTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// "WANTED FOR BARTER: 5 kg of rice" — the owner's return wish.
class _WantedTag extends StatelessWidget {
  final String item;
  const _WantedTag({required this.item});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = CblrepColors.compBarter;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'WANTED FOR BARTER: ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: item,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The subtle three-dot menu that carries the report action.
class _ReportMenu extends StatelessWidget {
  final VoidCallback onReport;
  const _ReportMenu({required this.onReport});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: 18, color: dark ? Colors.white60 : Colors.black45),
      onSelected: (value) {
        if (value == 'report') onReport();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              Icon(Icons.report_gmailerrorred_outlined, size: 18, color: CblrepColors.dangerRed),
              SizedBox(width: 10),
              Text('Report posting', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hyper-local chip: a location icon plus the barangay · purok/sitio label.
///
/// Shared by the listing card and the detail screen so the two read
/// identically. The label is wrapped in [Expanded] with an ellipsis inside a
/// bounded box, which is what prevents the overflow the old
/// `Row(mainAxisSize: min)` + unbounded `Text` combination produced.
class LocationChip extends StatelessWidget {
  final String label;
  final bool dark;
  final bool compact;

  const LocationChip({
    super.key,
    required this.label,
    required this.dark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final muted = dark ? Colors.white70 : Colors.black54;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 8, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color: dark ? Colors.white10 : CblrepColors.softCream,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: compact ? 11 : 12, color: muted),
          const SizedBox(width: 4),
          // Expanded (not Flexible) so the row never overflows: the chip's
          // own padding defines the available width and the text takes the
          // remainder, ellipsizing past that.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final bool need;
  const _ModePill({required this.label, required this.need});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: need ? CblrepColors.brandGreen : CblrepColors.actionOrange,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Compensation badge overlaid on the listing photo (FREE SHARING / BARTER /
/// PAID · ₱n), colour-matched to the compensation family.
class _CompensationPill extends StatelessWidget {
  final String label;
  final Color color;
  const _CompensationPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
