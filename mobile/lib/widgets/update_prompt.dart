import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_update_provider.dart';

/// Wraps the app's home so the in-app update prompt can appear on top of
/// whichever screen the member lands on.
///
/// The prompt is shown at most once per launch. An optional update offers
/// "Later" (remembered across launches); a force update cannot be dismissed.
class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  bool _shownThisLaunch = false;

  @override
  Widget build(BuildContext context) {
    final update = context.watch<AppUpdateProvider>();
    if (update.shouldPrompt && !_shownThisLaunch) {
      _shownThisLaunch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showUpdatePromptDialog(context, update);
      });
    }
    return widget.child;
  }
}

/// Shows the update dialog for [update]. Shared by the launch-time host and the
/// "Check for updates" settings row so both paths behave identically.
Future<void> showUpdatePromptDialog(BuildContext context, AppUpdateProvider update) {
  final force = update.forceUpdate;
  return showDialog<void>(
    context: context,
    barrierDismissible: !force,
    builder: (dialogContext) {
      final dark = Theme.of(dialogContext).brightness == Brightness.dark;
      return PopScope(
        canPop: !force,
        child: AlertDialog(
          title: Text(force ? 'Update required' : 'Update available'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CBLREP ${update.latestVersionName} is ready to install.'),
                if (update.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(update.notes.trim()),
                ],
                const SizedBox(height: 12),
                Text(
                  force
                      ? 'This version is no longer supported. Please update to continue.'
                      : 'Tap Update to download the new APK, then install it when your '
                          'device asks.',
                  style: TextStyle(
                    fontSize: 12,
                    color: dark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () {
                  update.dismiss();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Later'),
              ),
            FilledButton.icon(
              onPressed: () async {
                final opened = await update.openDownload();
                if (!dialogContext.mounted) return;
                if (!opened) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Could not open the download link.')),
                  );
                } else if (!force) {
                  update.dismiss();
                  Navigator.of(dialogContext).pop();
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Update'),
            ),
          ],
        ),
      );
    },
  );
}
