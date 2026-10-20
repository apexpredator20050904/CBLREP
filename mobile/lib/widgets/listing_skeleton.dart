import 'package:flutter/material.dart';
import '../theme/cblrep_theme.dart';
import 'shimmer.dart';

/// The skeleton that stands in for a [ListingCard] while the feed loads.
///
/// It mirrors the real card's geometry — a photo block, two title lines, a
/// location chip, an author row and the action row — so the feed does not
/// jump when the real cards replace the placeholders. A spinner would do
/// neither: it says "something is happening" but not "this is what you are
/// about to get".
class ListingSkeletonCard extends StatelessWidget {
  const ListingSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? CblrepColors.darkCardGreen : Colors.white;

    return Container(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The photo block — the same height the real card uses.
          const SizedBox(height: 168, child: _SkeletonPhoto()),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SkeletonLine(width: 0.9),
                const SizedBox(height: 8),
                const _SkeletonLine(width: 0.55),
                const SizedBox(height: 12),
                // The location chip.
                const _SkeletonLine(width: 0.62, height: 20, radius: 8),
                const SizedBox(height: 12),
                // The author row: avatar plus name.
                Row(
                  children: [
                    const ShimmerBox(width: 18, height: 18, borderRadius: 9),
                    const SizedBox(width: 6),
                    // Expanded bounds the width: a FractionallySizedBox in a
                    // Row would otherwise be handed an infinite width.
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.6,
                          child: ShimmerBox(height: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // The action row: two buttons.
                Row(
                  children: [
                    const Expanded(child: _SkeletonButton()),
                    const SizedBox(width: 8),
                    const Expanded(child: _SkeletonButton()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The shimmering photo area.
class _SkeletonPhoto extends StatelessWidget {
  const _SkeletonPhoto();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox.expand(),
      ),
    );
  }
}

/// A shimmering text line. [width] is a fraction of the available width.
class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonLine({
    this.width = 1,
    this.height = 13,
    this.radius = 5,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: ShimmerBox(height: height, borderRadius: radius),
    );
  }
}

/// A shimmering action button.
class _SkeletonButton extends StatelessWidget {
  const _SkeletonButton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 38,
      child: Shimmer(
        child: ColoredBox(
          color: Colors.white,
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
