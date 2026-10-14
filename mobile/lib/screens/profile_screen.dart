import 'package:flutter/material.dart' hide Feedback;
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../config/community.dart';
import '../core/feedback.dart';
import '../core/input_sanitizer.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/welcome_header.dart';
import 'login_screen.dart';
import 'listing_detail_screen.dart';
import 'settings_screen.dart';
import 'verification_screen.dart';
import '../widgets/empty_state.dart';

/// User profile — member card, edit profile, stats, verification, listings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool saving = false;

  /// Which "My Listings" tab is showing: active | paused | traded | archived |
  /// held (a moderator is reviewing it).
  String _myFilter = 'active';

  @override
  void initState() {
    super.initState();
    // The public feed only carries active listings, so the member's own list
    // (which includes paused/traded/archived rows) must be fetched separately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ListingsProvider>().loadMine(showSpinner: false);
    });
  }

  Future<void> _editProfile() async {
    final user = context.read<AuthProvider>().user;
    final name = TextEditingController(text: user?.name ?? '');
    String barangay = (user?.barangay.isNotEmpty ?? false) ? user!.barangay : trinidadBarangays.first;
    final purok = TextEditingController(text: user?.purokSitio ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: trinidadBarangays.contains(barangay) ? barangay : trinidadBarangays.first,
            // isExpanded bounds the button to the field width. Without it the
            // dropdown sizes to its widest item — "Mabuhay Cabigohan" and
            // "Manuel M. Roxas" overflow a narrow phone's dialog.
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Barangay'),
            items: trinidadBarangays
                .map((b) => DropdownMenuItem(
                      value: b,
                      child: Text(b, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) { if (v != null) barangay = v; },
          ),
          const SizedBox(height: 10),
          TextField(controller: purok, decoration: const InputDecoration(labelText: 'Purok / Sitio')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final newName = InputSanitizer.name(name.text);
    name.dispose();
    purok.dispose();
    if (ok != true || !mounted) return;

    setState(() => saving = true);
    try {
      await context.read<AuthProvider>().updateProfile(name: newName, barangay: barangay, purokSitio: purok.text.trim());
      if (mounted) Feedback.success(context, 'Profile updated successfully.');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message, onRetry: _editProfile);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Open the residency submission screen, then refresh the member's status
  /// so the badge reflects a submission (or a decision made meanwhile).
  Future<void> _openVerification() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VerificationScreen()),
    );
    if (!mounted) return;
    await context.read<AuthProvider>().refreshVerification();
  }

  IconData _verificationIcon(String? status) => switch (status) {
        'Verified' => Icons.verified,
        'Pending' => Icons.hourglass_top,
        'Rejected' => Icons.error_outline,
        _ => Icons.verified_outlined,
      };

  Color _verificationColor(String? status) => switch (status) {
        'Verified' => CblrepColors.successGreen,
        'Pending' => CblrepColors.actionOrange,
        'Rejected' => CblrepColors.dangerRed,
        _ => Colors.blueGrey,
      };

  // ── My Listings lifecycle ────────────────────────────────────────────
  //
  // A listing is never destroyed from the app: the owner pauses it (hide
  // without losing it), marks it traded (a deal went through) or archives it
  // (file it away). Every one is reversible, which is why the words here are
  // deliberately softer than "delete".

  String _actionTitle(String status) => switch (status) {
        'paused' => 'Pause',
        'active' => 'Resume',
        'traded' => 'Mark as traded',
        'archived' => 'Archive',
        _ => 'Update',
      };

  String _actionDone(String status) => switch (status) {
        'paused' => 'paused',
        'active' => 'resumed',
        'traded' => 'marked as traded',
        'archived' => 'archived',
        _ => 'updated',
      };

  Future<void> _applyStatus(ListingModel listing, String status) async {
    final title = _actionTitle(status);
    final confirmed = await Feedback.confirm(
      context,
      title: '$title listing?',
      message: switch (status) {
        'paused' =>
          '"${listing.title}" will be hidden from the feed. You can resume it anytime.',
        'active' => '"${listing.title}" will show in the community feed again.',
        'traded' =>
          'Mark "${listing.title}" as traded? It moves to your Traded list.',
        'archived' =>
          '"${listing.title}" moves to your archive. You can restore it anytime.',
        _ => '"${listing.title}" will be updated.',
      },
      confirmLabel: title,
      danger: status == 'archived',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<ListingsProvider>().setMyListingStatus(listing.id, status);
      if (mounted) Feedback.success(context, 'Listing ${_actionDone(status)}.');
    } on ApiException catch (e) {
      if (mounted) Feedback.error(context, e.message);
    }
  }

  /// Menu entries depend on where the listing currently is, so the same menu
  /// never offers a no-op (e.g. "Archive" on an already-archived listing).
  List<PopupMenuEntry<String>> _menuFor(ListingModel l) => [
        if (l.isActiveStatus)
          const PopupMenuItem(
            value: 'paused',
            child: Text('Pause (unavailable)'),
          )
        else
          const PopupMenuItem(
            value: 'active',
            child: Text('Resume (show in feed)'),
          ),
        if (!l.isTraded)
          const PopupMenuItem(value: 'traded', child: Text('Mark as traded')),
        if (!l.isArchived)
          const PopupMenuItem(value: 'archived', child: Text('Archive')),
      ];

  Widget _statusBadge(ListingModel l, bool dark) {
    final color = switch (l.status) {
      'active' => CblrepColors.successGreen,
      'paused' => CblrepColors.actionOrange,
      'traded' => CblrepColors.brandGreen,
      'archived' => (dark ? Colors.white54 : Colors.blueGrey),
      _ => CblrepColors.dangerRed,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        l.statusLabel,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  /// Open one of the member's own listings. Archiving only makes sense if the
  /// item is still reachable afterwards, so paused/traded/archived rows open
  /// the normal detail screen (whose owner panel is status-aware). Reload on
  /// return so a change made there is reflected in the tabs.
  Future<void> _openListing(ListingModel l) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: l)),
    );
    if (mounted) context.read<ListingsProvider>().loadMine(showSpinner: false);
  }

  Widget _myListingTile(ListingModel l, bool dark) {
    final muted = dark ? Colors.white70 : Colors.black54;
    final strong = dark ? Colors.white : Colors.black;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: dark ? CblrepColors.darkCardGreen : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openListing(l),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: strong)),
                  const SizedBox(height: 2),
                  Text('${l.category} · ${l.condition}', style: TextStyle(fontSize: 10, color: muted)),
                  const SizedBox(height: 6),
                  _statusBadge(l, dark),
                ]),
              ),
              // A moderated listing is read-only: the owner cannot move it out of
              // the moderator's hold, so it shows a lock instead of the manage
              // menu.
              if (l.underReview)
                Tooltip(
                  message: 'A moderator is reviewing this listing.',
                  child: Icon(Icons.lock_outline, size: 18, color: muted),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'Manage listing',
                  icon: Icon(Icons.more_vert, size: 18, color: muted),
                  onSelected: (value) => _applyStatus(l, value),
                  itemBuilder: (_) => _menuFor(l),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// The visible tabs, with "Under review" shown only when a moderator has
  /// actually held something back.
  List<MapEntry<String, String>> _myTabs(Map<String, int> counts) => [
        const MapEntry('active', 'Active'),
        const MapEntry('paused', 'Paused'),
        const MapEntry('traded', 'Traded'),
        const MapEntry('archived', 'Archived'),
        if ((counts['held'] ?? 0) > 0) const MapEntry('held', 'Under review'),
      ];

  String _emptyTitle() => switch (_myFilter) {
        'active' => 'No active listings',
        'paused' => 'Nothing paused',
        'traded' => 'No trades yet',
        'archived' => 'Archive is empty',
        _ => 'Nothing under review',
      };

  String _emptySubtitle() => switch (_myFilter) {
        'active' =>
          'Tap "+ Post a Resource" on the home tab to share your first item.',
        'paused' => 'Paused listings are hidden from the feed but kept here.',
        'traded' => 'Mark a listing as traded once a swap is done.',
        'archived' => 'Archived listings rest here until you restore them.',
        _ => 'A moderator has not held any of your listings back.',
      };

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
    final listingsProvider = context.watch<ListingsProvider>();
    final all = listingsProvider.myListings;
    final counts = listingsProvider.myCounts;
    final mine = _myFilter == 'held'
        ? all.where((l) => l.underReview).toList()
        : all.where((l) => l.status == _myFilter).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(16), children: [
      WelcomeHeader(name: user?.name ?? 'member', subtitle: user?.email ?? ''),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: dark ? CblrepColors.darkCardGreen : Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CblrepLogo(radius: 18),
            title: Text(user?.name ?? 'Member', style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black)),
            subtitle: Text([user?.barangay ?? '', user?.purokSitio ?? ''].where((p) => p.isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: dark ? Colors.white70 : Colors.black54)),
            trailing: IconButton(tooltip: 'Edit profile', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: _editProfile),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_verificationIcon(user?.verificationStatus), color: _verificationColor(user?.verificationStatus)),
            title: Text('Verification', style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.verificationStatus ?? 'Unverified', style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black)),
                if (user?.verificationStatus == 'Rejected' && (user?.verificationNote?.isNotEmpty ?? false))
                  Text(user!.verificationNote!, style: TextStyle(fontSize: 10, color: dark ? Colors.white70 : Colors.black54)),
              ],
            ),
            trailing: user?.verificationStatus == 'Verified'
                ? const Icon(Icons.check_circle, color: CblrepColors.successGreen)
                : TextButton(
                    onPressed: _openVerification,
                    child: Text(user?.verificationStatus == 'Unverified' ? 'Submit' : 'Resubmit', style: const TextStyle(fontSize: 11)),
                  ),
            onTap: _openVerification,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: Text('Settings', style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54)),
            subtitle: Text('Theme, notifications, account', style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text('My listings (${counts['all'] ?? all.length})', style: TextStyle(color: dark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 8),
      // Filter tabs. The counts come from the API so an empty tab is obvious
      // before it is opened.
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tab in _myTabs(counts))
            ChoiceChip(
              label: Text('${tab.value} (${counts[tab.key] ?? 0})'),
              selected: _myFilter == tab.key,
              onSelected: (_) => setState(() => _myFilter = tab.key),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (listingsProvider.myLoading && all.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (mine.isEmpty)
        EmptyState(
          icon: Icons.inventory_2_outlined,
          title: _emptyTitle(),
          subtitle: _emptySubtitle(),
        )
      else
        ...mine.map((l) => _myListingTile(l, dark)),
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
