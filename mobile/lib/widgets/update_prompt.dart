import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/push_service.dart';
import '../providers/app_update_provider.dart';

/// Wraps the app's home so the in-app update prompt can appear on top of
/// whichever screen the member lands on.
///
/// The prompt is shown at most once per launch. An optional update offers
/// "Later" (remembered across launches); a force update cannot be dismissed.
///
/// It also listens for the member tapping a "a new version is available"
/// push, so the announcement the server sends reaches the install screen
/// instead of stopping at the notification shade.
class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  bool _shownThisLaunch = false;
  StreamSubscription<PushAction>? _actions;

  @override
  void initState() {
    super.initState();
    _actions = PushService.instance.actions.listen(_onAction);
  }

  @override
  void dispose() {
    _actions?.cancel();
    super.dispose();
  }

  /// A tapped "new build" notice opens the install prompt.
  Future<void> _onAction(PushAction action) async {
    if (!action.isAppUpdate) return;
    if (!mounted) return;

    final update = context.read<AppUpdateProvider>();

    // The push may have arrived before the release channel was read, so make
    // sure the dialog shows the version the notice was about.
    if (!update.checked) {
      await update.check();
      if (!mounted) return;
    }

    if (!update.updateAvailable) {
      // The member is already on that build; nothing to install.
      return;
    }

    _shownThisLaunch = true;
    await showUpdatePromptDialog(context, update);
  }

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
