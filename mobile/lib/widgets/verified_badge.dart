import 'package:flutter/material.dart';

import '../theme/cblrep_theme.dart';

/// The visible payoff for completing residency verification.
///
/// Two shapes so the mark fits every layout:
///  * [compact] — the bare green tick, for a listing card's author line where
///    a label would crowd the name.
///  * the default labelled pill ("Verified resident") — for the profile and a
///    listing's detail panel, where the member should *see* what verification
///    means rather than decode a lone icon.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    this.compact = false,
    this.label = 'Verified resident',
  });

  final bool compact;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Icon(Icons.verified, size: 13, color: CblrepColors.successGreen);
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = CblrepColors.successGreen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified, size: 13, color: tint),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: dark ? const Color(0xFF7FD8A0) : CblrepColors.successGreen,
          ),
        ),
      ]),
    );
  }
}
