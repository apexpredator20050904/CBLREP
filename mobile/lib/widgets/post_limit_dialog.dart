import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';

import '../core/feedback.dart';
import '../providers/listings_provider.dart';
import '../screens/verification_screen.dart';

/// Progressive-trust helper: explain the unverified posting cap and offer the
/// one action that lifts it.
///
/// Shared by the Post screen and the Profile's listing manager so every 403
/// from the cap looks and behaves the same, and so a member who hits the limit
/// while reposting an archived listing is sent to verification just as one who
/// hits it while creating a new listing would be.
Future<void> showUnverifiedPostLimitDialog(
  BuildContext context,
  String message,
) async {
  final proceed = await Feedback.confirm(
    context,
    title: 'Listing limit reached',
    message: '$message\n\nVerify your residency to keep posting.',
    confirmLabel: 'Get verified',
  );
  if (!proceed || !context.mounted) return;

  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const VerificationScreen()),
  );
  // Re-read the envelope: the member may have archived a listing instead of
  // verifying, and the notice should reflect that.
  if (context.mounted) {
    context.read<ListingsProvider>().loadMine(showSpinner: false);
  }
}
