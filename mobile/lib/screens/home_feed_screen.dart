import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart' as feedback;
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/listing_card.dart';
import '../widgets/welcome_header.dart';
import 'listing_detail_screen.dart';

/// Home feed — live offer/need grid with search, barangay + proximity
/// filters, welcome header and maintenance banner. Auto-refreshes via
/// ListingsProvider polling so no manual reload is needed.
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final search = TextEditingController();
  String? barangay;
  String segment = 'all'; // all | offer | request
  bool maintenance = false;
  String maintenanceMessage = '';

  @override
  void initState() {
    super.initState();
    final provider = context.read<ListingsProvider>();
    Future.microtask(() async {
      await provider.load();
      provider.startAutoRefresh(interval: const Duration(seconds: 20));
      if (!mounted) return;
      try {
        final status = await ApiService.instance.platformStatus();
        if (mounted) {
          setState(() {
            maintenance = status['maintenance'] == true;
            maintenanceMessage = status['message'] as String? ?? '';
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() => context
      .read<ListingsProvider>()
      .load(query: search.text.trim(), barangay: barangay);

  @override
  Widget build(BuildContext context) {
    // Granular selects: this screen rebuilds only when a rendered value
    // actually changes — plain watches re-fired on every 20s live poll.
    final memberName = context.select<AuthProvider, String>((p) => p.user?.name ?? 'member');
    final memberAvatar = context.select<AuthProvider, String?>((p) => p.user?.avatarUrl);
    final loading = context.select<ListingsProvider, bool>((p) => p.loading);
    final loadError = context.select<ListingsProvider, String?>((p) => p.error);
    final listings = context.select<ListingsProvider, List<ListingModel>>((p) => p.listings);
    final lastUpdated = context.select<LiveHubProvider, DateTime?>((p) => p.lastUpdated);
    final dark = Theme.of(context).brightness == Brightness.dark;
    var visible = listings.where((item) {
      if (segment == 'offer' && item.type == 'request') return false;
      if (segment == 'request' && item.type != 'request') return false;
      return true;
    }).toList();
    final liveHub = context.read<LiveHubProvider>();
    return RefreshIndicator(
      onRefresh: () async {
        await refresh();
        await liveHub.refreshAll();
      },
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 700;
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            sliver: SliverList.list(children: [
            if (lastUpdated != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Live · updated ${_ago(lastUpdated)}',
                    style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black45)),
              ),
            if (maintenance)
              Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Scheduled updates', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(maintenanceMessage),
                ),
              ),
            WelcomeHeader(name: memberName, subtitle: '$communityName · by barangay & purok', avatarUrl: memberAvatar),
            const SizedBox(height: 12),
            TextField(
              controller: search,
              onSubmitted: (_) => refresh(),
              decoration: InputDecoration(
                hintText: 'Search offers and needs',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: refresh, icon: const Icon(Icons.arrow_forward)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: barangay,
                  isExpanded: true,
                  iconEnabledColor: Theme.of(context).colorScheme.onSurface,
                  decoration: const InputDecoration(labelText: 'Barangay'),
                  items: [
                    const DropdownMenuItem<String>(child: Text('All barangays')),
                    ...trinidadBarangays.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) { setState(() => barangay = v); refresh(); },
                ),
              ),
              const SizedBox(width: 8),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'offer', label: Text('Offers')),
                ButtonSegment(value: 'request', label: Text('Needs')),
              ],
              selected: {segment},
              onSelectionChanged: (v) => setState(() => segment = v.first),
            ),
            const SizedBox(height: 12),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (loadError != null)
              _ConnectionErrorCard(message: loadError, onRetry: refresh),
            if (!loading && loadError == null && visible.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: 'No resources found',
                subtitle: 'No active resources match your filters. Try broadening your search.',
              ),
            ]),
          ),
          // Lazy grid: only the on-screen cards are built/painted. The old
            // shrinkWrap GridView built and laid out EVERY card up-front on
            // the first frame — the main cause of feed lag on this device.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: wide ? 3 : 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Taller cells for the 2-up phone grid. The card body now
                  // carries title (2 lines) + meta + location chip + author,
                  // so a fixed 0.74 clipped the author line on short screens
                  // (small Galaxy A-series: ~320dp wide → ~145dp cells). The
                  // card's image is Flexible, so a generous ratio simply
                  // yields a taller photo rather than dead space.
                  childAspectRatio: wide ? 0.72 : 0.66,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: visible.length,
                  (context, i) {
                    final listing = visible[i];
                    return RepaintBoundary(
                      child: ListingCard(
                        listing: listing,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing))).then((_) => refresh()),
                      ),
                    );
                  },
                ),
              ),
            ),
          ], // slivers
        );
      }),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 30) return 'just now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

/// Explicit failure state for the listings feed.
///
/// The message from [ApiService] already names the host the app tried, so the
/// card shows that plus a retry — a network failure must never look like an
/// empty dashboard.
class _ConnectionErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ConnectionErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? CblrepColors.darkCardGreen : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CblrepColors.dangerRed.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.wifi_off, color: CblrepColors.dangerRed, size: 20),
            const SizedBox(width: 8),
            Text(
              'Could not load listings',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.dns_outlined, size: 12, color: dark ? Colors.white54 : Colors.black45),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Trying ${ApiService.instance.baseUrlHost}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: CblrepColors.actionOrange,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => feedback.Feedback.info(
                context,
                'Showing the last loaded results. Pull down to refresh.',
              ),
              child: const Text('Dismiss'),
            ),
          ]),
        ],
      ),
    );
  }
}
