import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/cblrep_theme.dart';

/// Reusable resource card for the home feed, profile and map previews.
///
/// Layout contract — the card is given an exact box by the parent (a
/// [SliverGrid] cell or a list tile), so every part sizes itself defensively:
///
///  * The photo area is [Flexible], not a fixed 140px. It absorbs whatever
///    height the body does not claim, which is what keeps the card free of
///    `RenderFlex overflowed` stripes on narrow Galaxy devices where a fixed
///    image height left less room for the text than the text needed.
///  * Every text run lives inside an [Expanded]/[Flexible] with
///    [TextOverflow.ellipsis], so a long author name or purok tag truncates
///    cleanly instead of colliding with the element beside it.
///  * Hyper-local tag and author sit on their own lines rather than sharing a
///    row, which removes the collision entirely and gives a clearer hierarchy:
///    title → category · condition → location chip → author.
class ListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback? onTap;
  final VoidCallback? onManage;

  const ListingCard({super.key, required this.listing, this.onTap, this.onManage});

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
            // Photo: flexible rather than fixed height. `flex: 5` against the
            // body's `flex: 0` keeps the image as tall as the space allows
            // while the text keeps its intrinsic height — no overflow, and no
            // wasted space on short cards.
            Flexible(
              flex: 5,
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
                      cacheWidth: 480,
                      errorBuilder: (_, _, _) => _placeholder(isNeed),
                    )
                  else
                    _placeholder(isNeed),
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row also hosts the optional manage affordance, so
                  // the card needs one fewer line than before.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.25,
                            color: strong,
                          ),
                        ),
                      ),
                      if (onManage != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onManage,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.more_vert, size: 16, color: muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${listing.category} · ${listing.condition}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                  const SizedBox(height: 8),
                  // Hyper-local tag on its own line. The chip sizes to the
                  // card width and its text ellipsizes, so
                  // "Barangay Poblacion · Purok 3" degrades to "Barangay
                  // Poblaci…" rather than running past the card edge.
                  LocationChip(
                    label: _locationTag,
                    dark: dark,
                  ),
                  const SizedBox(height: 6),
                  // Author on its own line, sharing a row with a person icon.
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 12, color: muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          listing.owner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ),
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