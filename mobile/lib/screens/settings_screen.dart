import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/cblrep_theme.dart';

/// Professional Settings — appearance, notifications, account, app info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const CblrepLogo(radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(auth.user?.name ?? 'Member', style: Theme.of(context).textTheme.titleMedium),
                Text(auth.user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          _section(context, 'Appearance', [
            SwitchListTile(
              title: const Text('Dark mode'),
              subtitle: const Text('Deep-forest theme for night use'),
              value: settings.darkMode,
              activeColor: CblrepColors.actionOrange,
              onChanged: (v) => settings.setDarkMode(v),
            ),
          ]),
          _section(context, 'Discovery', [
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Hyper-local discovery'),
              subtitle: const Text('Browse by your barangay and purok or sitio — Trinidad, Bohol only.'),
            ),
          ]),
          _section(context, 'Notifications', [
            SwitchListTile(
              title: const Text('Push notifications'),
              subtitle: const Text('Alerts for exchanges, messages, verifications'),
              value: settings.notificationsEnabled,
              activeColor: CblrepColors.actionOrange,
              onChanged: (v) => settings.setNotifications(v),
            ),
            SwitchListTile(
              title: const Text('Exchange updates'),
              subtitle: const Text('Requests, approvals, completions'),
              value: settings.exchangeAlerts,
              activeColor: CblrepColors.actionOrange,
              onChanged: settings.notificationsEnabled ? (v) => settings.setExchangeAlerts(v) : null,
            ),
            SwitchListTile(
              title: const Text('Message alerts'),
              subtitle: const Text('New chat messages'),
              value: settings.messageAlerts,
              activeColor: CblrepColors.actionOrange,
              onChanged: settings.notificationsEnabled ? (v) => settings.setMessageAlerts(v) : null,
            ),
          ]),
          _section(context, 'Account', [
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text('Verification: ${auth.user?.verificationStatus ?? 'Pending'}'),
              subtitle: Text([auth.user?.barangay ?? '', auth.user?.purokSitio ?? ''].where((p) => p.isNotEmpty).join(' · ')),
            ),
          ]),
          _section(context, 'About CBLREP', [
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Community-Based Local Resources Exchange Portal'),
              subtitle: Text('Trinidad, Bohol · v1.0.0+1\nFree · Barter · Paid — 20 official barangays'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.darkCardGreen : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(title.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: dark ? Colors.white70 : Colors.black54)),
        ),
        ...children,
      ]),
    );
  }
}
