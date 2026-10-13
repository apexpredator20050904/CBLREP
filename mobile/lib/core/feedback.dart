import 'package:flutter/material.dart';
import '../theme/cblrep_theme.dart';

/// Centralized action feedback: success / error / info snackbars, retry
/// prompts for network failures, and confirm dialogs.
class Feedback {
  Feedback._();

  static void success(BuildContext context, String message) {
    _show(context, message, icon: Icons.check_circle, color: CblrepColors.successGreen);
  }

  static void error(BuildContext context, String message, {VoidCallback? onRetry}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: CblrepColors.dangerRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        // Keep floating bars inset from the screen edges / bottom padding so
        // they sit cleanly instead of butting against them.
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: Duration(seconds: onRetry == null ? 4 : 6),
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
        ]),
        action: onRetry == null
            ? null
            : SnackBarAction(label: 'RETRY', textColor: Colors.white, onPressed: onRetry),
      ),
    );
  }

  static void info(BuildContext context, String message) {
    _show(context, message, icon: Icons.info_outline, color: CblrepColors.brandGreen);
  }

  static void _show(BuildContext context, String message,
      {required IconData icon, required Color color}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(seconds: 3),
        content: Row(children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
        ]),
      ),
    );
  }

  /// Friendly retry prompt for network/API failures.
  static void networkError(BuildContext context, String message, {required VoidCallback onRetry}) {
    error(context, message, onRetry: onRetry);
  }

  /// Blocking result modal for critical outcomes (password reset, account
  /// creation, irreversible exchange actions) where a snackbar is too easy to
  /// miss. Resolves once the member dismisses it.
  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    String buttonLabel = 'Got it',
    IconData icon = Icons.check_circle,
    Color? color,
  }) async {
    final accent = color ?? CblrepColors.successGreen;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: Icon(icon, size: 40, color: accent),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  /// Confirm dialog returning true when the user accepts.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: CblrepColors.dangerRed)
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }
}
