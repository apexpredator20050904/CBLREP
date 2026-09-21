import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../config/community.dart';
import '../core/feedback.dart';
import '../core/input_sanitizer.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/welcome_header.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'timebank_screen.dart';
import 'verification_screen.dart';

/// User profile — member card, edit profile, stats, verification, listings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool saving = false;

  Future<void> _editProfile() async {
    final user = context.read<AuthProvider>().user;
    final name = TextEditingController(text: user?.name ?? '');
    String barangay = (user?.barangay.isNotEmpty ?? false) ? user!.barangay : trinidadBarangays.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: trinidadBarangays.contains(barangay) ? barangay : trinidadBarangays.first,
            decoration: const InputDecoration(labelText: 'Barangay'),
            items: trinidadBarangays.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (v) { if (v != null) barangay = v; },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final newName = InputSanitizer.name(name.text);
    name.dispose();
    if (ok != true || !mounted) return;

    setState(() => saving = true);
    try {
      await context.read<AuthProvider>().updateProfile(name: newName, barangay: barangay);
      if (mounted) Feedback.success(context, 'Profile updated successfully.');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: _editProfile);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _closeListing(int id, String title) async {
    final confirmed = await Feedback.confirm(
      context,
      title: 'Close listing?',
      message: '"$title" will stop appearing in the community feed.',
      confirmLabel: 'Close listing',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<ListingsProvider>().close(id);
      if (mounted) Feedback.success(context, 'Listing closed.');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await Feedback.confirm(
      context,
      title: 'Sign out?',
      message: 'You will need your password to sign back in.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !mounted) return;
    await Feedback.alert(
      context,
      title: 'Signed out',
      message: 'Your session token has been revoked on the server.',
      icon: Icons.logout,
      color: CblrepColors.brandGreen,
    );
    if (!mounted) return;
    final hub = context.read<LiveHubProvider>();
    await context.read<AuthProvider>().logout();
    hub.stopLive();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final mine = context.watch<ListingsProvider>().listings.where((l) => l.owner == (user?.name ?? '')).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(16), children: [
      WelcomeHeader(name: user?.name ?? 'member', subtitle: user?.email ?? ''),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CblrepLogo(radius: 18),
            title: Text(user?.name ?? 'Member', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            subtitle: Text(user?.barangay ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            trailing: IconButton(tooltip: 'Edit profile', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: _editProfile),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Verification', style: TextStyle(fontSize: 12, color: Colors.black54)),
            subtitle: Text(user?.verificationStatus ?? 'Pending', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            trailing: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen())), child: const Text('Verify', style: TextStyle(fontSize: 11))),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timelapse),
            title: const Text('Time-bank credits', style: TextStyle(fontSize: 12, color: Colors.black54)),
            subtitle: Text('${user?.credits ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            trailing: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TimeBankScreen())), child: const Text('View', style: TextStyle(fontSize: 11))),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings', style: TextStyle(fontSize: 12, color: Colors.black54)),
            subtitle: const Text('Theme, notifications, account', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text('My listings (${mine.length})', style: TextStyle(color: dark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 6),
      if (mine.isEmpty)
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)), child: const Text('You have no active listings yet.', style: TextStyle(fontSize: 12, color: Colors.black54)))
      else
        ...mine.map((l) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: dark ? CblrepColors.cardGrey : Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                  Text('${l.category} · ${l.exchangeType}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ])),
                TextButton(onPressed: () => _closeListing(l.id, l.title), child: const Text('Close')),
              ]),
            )),
      const SizedBox(height: 12),
      SizedBox(
        height: 42, width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ),
    ]);
  }
}
