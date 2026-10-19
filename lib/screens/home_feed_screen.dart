import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../core/feedback.dart' as feedback;
import '../core/sign_in_gate.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import '../providers/live_hub_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_banner.dart';
import '../widgets/listing_card.dart';
import '../widgets/listing_skeleton.dart';
import '../widgets/member_profile_sheet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/trade_offer_sheet.dart';
import 'content_page_screen.dart';
import 'listing_detail_screen.dart';

/// Home feed — the community's live offer/need board.
///
/// The screen is built as one scroll view with three parts:
///
///   1. a warm, localized hero (the greeting and the barangay quick-filter),
///   2. a STICKY search-and-filter bar that stays reachable while the
///      member scrolls, and
///   3. the listings themselves.
///
/// The feed auto-refreshes through [ListingsProvider] polling, so no manual
/// reload is needed — and the poll re-applies whatever filters the member
/// has set, so a search never evaporates on its own.
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final search = TextEditingController();

  /// Mirrors the search box's text so the parts of the screen that depend on
  /// it (the clear button, the result caption) can react to a keystroke
  /// without rebuilding the whole feed.
  final searchText = ValueNotifier<String>('');

  /// Debounces the live search so a fast typist does not fire a request per
  /// keystroke.
  Timer? _debounce;

  /// The barangay the feed is filtered by ('' = all of Trinidad).
  String barangay = '';

  /// all | offer | request — the NEED/OFFER split.
  String segment = 'all';

  /// The category the feed is filtered by ('' = all categories).
  String category = '';

  /// recent | nearby — how the results are ordered.
  String sort = 'recent';

  bool maintenance = false;
  String maintenanceMessage = '';

  /// The category chips offered above the feed.
  static const List<String> _categories = [
    'Tools',
    'Agriculture',
    'Electronics',
    'Services',
  ];

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
    _debounce?.cancel();
    search.dispose();
    searchText.dispose();
    super.dispose();
  }

  /// Re-runs the feed with the current filters.
  Future<void> refresh() => context
      .read<ListingsProvider>()
      .load(query: search.text.trim(), barangay: barangay, category: category);

  /// Live search: the request waits for a pause in typing.
  void _onSearchChanged(String value) {
    searchText.value = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) refresh();
    });
  }

  /// Picks a barangay from the hero's quick-filter bar.
  void _selectBarangay(String value) {
    setState(() => barangay = value);
    refresh();
  }

  /// Picks a filter chip. The NEED/OFFER chips and the category chips are
  /// independent, so a member can narrow the feed to "Electronics offers".
  void _selectSegment(String value) {
    setState(() => segment = value);
    refresh();
  }

  void _selectCategory(String value) {
    setState(() => category = category == value ? '' : value);
    refresh();
  }

  /// Clears every filter and brings the whole board back.
  Future<void> _clearFilters() async {
    _debounce?.cancel();
    search.clear();
    searchText.value = '';
    setState(() {
      barangay = '';
      segment = 'all';
      category = '';
    });
    await context.read<ListingsProvider>().clearFilters();
  }

  /// Open a listing's details.
  Future<void> _openListing(ListingModel listing) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing)),
    );
    if (mounted) refresh();
  }

  /// The card's "Propose Barter" fast action: the same two-sided proposal
  /// the details screen offers, opened straight from the feed.
  Future<void> _proposeBarter(ListingModel listing) async {
    if (listing.ownerId <= 0) {
      if (mounted) {
        feedback.Feedback.info(context, 'Trade offers are unavailable for this listing.');
      }
      return;
    }
    if (!await ensureSignedIn(context, 'send a trade offer for this listing')) return;
    if (!mounted) return;
    final sent = await showTradeOfferSheet(context, listing);
    if (sent && mounted) {
      feedback.Feedback.success(context, 'Trade offer sent. Track it in Exchanges.');
    }
  }

  /// The card's three-dot menu: report the posting.
  Future<void> _reportListing(ListingModel listing) async {
    final sent = await showReportSheet(
      context,
      reportableType: ReportTarget.listing,
      reportableId: listing.id,
      subjectName: listing.title,
    );
    if (sent && mounted) {
      feedback.Feedback.success(
        context,
        'Thank you for helping keep our community safe. '
        'Our team will review this listing.',
      );
    }
  }

  /// The card's owner row: open the member's profile, where a member can be
  /// reported if their behaviour is unacceptable.
  Future<void> _openMember(ListingModel listing) async {
    final myId = context.read<AuthProvider>().user?.id;
    await showMemberProfileSheet(
      context,
      name: listing.owner,
      avatarUrl: listing.ownerAvatarUrl,
      verified: listing.ownerVerified,
      userId: listing.ownerId,
      // You cannot report yourself, and the sheet does not offer the action
      // for the member's own listings.
      canReport: myId == null || myId != listing.ownerId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Granular selects: this screen rebuilds only when a rendered value
    // actually changes — plain watches re-fired on every 20s live poll.
    final memberName = context.select<AuthProvider, String>((p) => p.user?.name ?? 'member');
    final memberAvatar = context.select<AuthProvider, String?>((p) => p.user?.avatarUrl);
    final memberBarangay = context.select<AuthProvider, String?>((p) => p.user?.barangay);
    final loading = context.select<ListingsProvider, bool>((p) => p.loading);
    final loadError = context.select<ListingsProvider, String?>((p) => p.error);
    final listings = context.select<ListingsProvider, List<ListingModel>>((p) => p.listings);
    final lastUpdated = context.select<LiveHubProvider, DateTime?>((p) => p.lastUpdated);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // The NEED/OFFER split is applied here rather than on the server: it is
    // a view over the same page of results, and doing it locally keeps the
    // switch instant.
    var visible = listings.where((item) {
      if (segment == 'offer' && item.type == 'request') return false;
      if (segment == 'request' && item.type != 'request') return false;
      return true;
    }).toList();

    // Where the "nearby" distances are measured from: the member's own
    // barangay when they have one, the municipal centre otherwise.
    final origin = memberBarangay != null && memberBarangay.isNotEmpty
        ? coordinatesForBarangay(memberBarangay)
        : (trinidadCenter.lat, trinidadCenter.lng);

    if (sort == 'nearby') {
      visible.sort((a, b) => _distanceTo(a, origin).compareTo(_distanceTo(b, origin)));
    }

    final hasFilters = search.text.trim().isNotEmpty ||
        barangay.isNotEmpty ||
        category.isNotEmpty ||
        segment != 'all';

    final liveHub = context.read<LiveHubProvider>();

    return RefreshIndicator(
      onRefresh: () async {
        await refresh();
        await liveHub.refreshAll();
      },
      child: LayoutBuilder(builder: (context, c) {
        // A single, comfortable column. The rich card carries a photo, a
        // title, a location, the owner's wish and two actions — that is far
        // too much to read in a 145dp two-up cell, so the feed is one
        // column and the column is capped and centred on a tablet.
        final maxWidth = 640.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverList.list(children: [
                    if (lastUpdated != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Live · updated ${_ago(lastUpdated)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: dark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ),
                    if (maintenance)
                      Card(
                        color: Colors.amber.shade50,
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: const Text(
                            'Scheduled updates',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(maintenanceMessage),
                        ),
                      ),
                    // ── Hero: greeting + barangay quick filter ──
                    HeroBanner(
                      name: memberName,
                      avatarUrl: memberAvatar,
                      selectedBarangay: barangay,
                      onBarangaySelected: _selectBarangay,
                    ),
                    const SizedBox(height: 12),
                    // Published municipal page — the mobile counterpart of the
                    // admin console's public /page/:slug route. Drafts and
                    // unknown slugs 404 on the backend, so only published
                    // content is reachable here.
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              CblrepColors.actionOrange.withValues(alpha: 0.15),
                          foregroundColor: CblrepColors.actionOrange,
                          child: const Icon(Icons.menu_book_outlined, size: 22),
                        ),
                        title: const Text(
                          'Waste Segregation Guide',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Published public page',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ContentPageScreen(
                              slug: 'waste-segregation-guide',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),

                // ── Sticky search & filter bar ──
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FilterBarDelegate(
                    height: 96,
                    background: dark ? CblrepColors.deepForest : const Color(0xFFF5EFE2),
                    search: search,
                    searchText: searchText,
                    onSearchChanged: _onSearchChanged,
                    onSearchSubmitted: (_) => refresh(),
                    sort: sort,
                    onSortChanged: (value) => setState(() => sort = value),
                    segment: segment,
                    onSegmentChanged: _selectSegment,
                    category: category,
                    categories: _categories,
                    onCategoryChanged: _selectCategory,
                  ),
                ),

                // ── Result count ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  sliver: SliverToBoxAdapter(
                    child: ValueListenableBuilder<String>(
                      valueListenable: searchText,
                      builder: (context, text, _) {
                        final filtered = text.trim().isNotEmpty ||
                            barangay.isNotEmpty ||
                            category.isNotEmpty ||
                            segment != 'all';
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                _resultCaption(visible.length, sort),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: dark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ),
                            if (filtered)
                              TextButton.icon(
                                onPressed: _clearFilters,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                                label: const Text('Clear', style: TextStyle(fontSize: 11)),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // ── The listings themselves ──
                if (loadError != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    sliver: SliverToBoxAdapter(
                      child: _ConnectionErrorCard(message: loadError, onRetry: refresh),
                    ),
                  )
                else if (loading && listings.isEmpty)
                  // Skeletons, not a spinner: the member sees the shape of
                  // what is coming, and the layout does not jump when the
                  // real cards replace them.
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    sliver: SliverList.separated(
                      itemCount: 4,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, _) => const ListingSkeletonCard(),
                    ),
                  )
                else if (visible.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    sliver: SliverToBoxAdapter(
                      child: hasFilters
                          ? EmptyState(
                              icon: Icons.search_off,
                              title: 'Nothing matches yet',
                              subtitle:
                                  'No listings in $communityName match your filters. '
                                  'Try a different barangay, a different category, or '
                                  'clear the filters to see everything.',
                              actionLabel: 'Clear filters',
                              onAction: _clearFilters,
                            )
                          : EmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: 'No listings yet',
                              subtitle:
                                  'Nothing has been shared in $communityName so far. '
                                  'Be the first — post a resource and let your '
                                  'neighbours know what you have.',
                            ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final listing = visible[i];
                        return RepaintBoundary(
                          child: ListingCard(
                            listing: listing,
                            onTap: () => _openListing(listing),
                            onViewDetails: () => _openListing(listing),
                            onPropose: () => _proposeBarter(listing),
                            onReport: () => _reportListing(listing),
                            onOwnerTap: () => _openMember(listing),
                            // The distance only earns its place when the
                            // member asked for proximity.
                            distanceLabel: sort == 'nearby'
                                ? _formatDistance(_distanceTo(listing, origin))
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// The distance from the origin to a listing, in kilometres.
  double _distanceTo(ListingModel listing, (double, double) origin) {
    // The payload carries a pin for every listing — the exact one when the
    // poster dropped it, the barangay anchor otherwise — so the distance is
    // always computable.
    final lat = listing.latitude;
    final lng = listing.longitude;
    final double targetLat;
    final double targetLng;
    if (lat != null && lng != null) {
      targetLat = lat;
      targetLng = lng;
    } else {
      final anchor = coordinatesForBarangay(listing.barangay);
      targetLat = anchor.$1;
      targetLng = anchor.$2;
    }
    return distanceKm(origin.$1, origin.$2, targetLat, targetLng);
  }

  /// "850 m away" / "2.4 km away".
  static String _formatDistance(double km) {
    if (km < 1) return '≈${(km * 1000).round()} m away';
    return '≈${km.toStringAsFixed(1)} km away';
  }

  /// The line under the sticky bar that says what is on screen.
  String _resultCaption(int count, String currentSort) {
    final noun = count == 1 ? 'listing' : 'listings';
    if (currentSort == 'nearby') return '$count $noun near you';
    return '$count $noun in $communityName';
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 30) return 'just now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

/// The sticky search-and-filter bar.
///
/// Pinned to the top of the scroll view so the search box and the chips stay
/// reachable however far the member has scrolled through the board.
class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color background;
  final TextEditingController search;
  final ValueNotifier<String> searchText;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final String sort;
  final ValueChanged<String> onSortChanged;
  final String segment;
  final ValueChanged<String> onSegmentChanged;
  final String category;
  final List<String> categories;
  final ValueChanged<String> onCategoryChanged;

  _FilterBarDelegate({
    required this.height,
    required this.background,
    required this.search,
    required this.searchText,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.sort,
    required this.onSortChanged,
    required this.segment,
    required this.onSegmentChanged,
    required this.category,
    required this.categories,
    required this.onCategoryChanged,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // A Material (not a ColoredBox): the search field inside needs a
    // Material ancestor to draw its selection and its ink.
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Search + sort ──
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      controller: search,
                      onChanged: onSearchChanged,
                      onSubmitted: onSearchSubmitted,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search offers and needs',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        // The clear button appears as soon as there is
                        // something to clear — driven by the notifier, so it
                        // does not need the whole feed to rebuild.
                        suffixIcon: ValueListenableBuilder<String>(
                          valueListenable: searchText,
                          builder: (context, text, _) => text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    search.clear();
                                    onSearchChanged('');
                                  },
                                ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SortButton(sort: sort, onChanged: onSortChanged),
              ],
            ),
            const SizedBox(height: 8),
            // ── Filter chips ──
            SizedBox(
              height: 30,
              child: ListView(
                key: const Key('home-filter-chips'),
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: segment == 'all' && category.isEmpty,
                    onTap: () {
                      onSegmentChanged('all');
                      if (category.isNotEmpty) onCategoryChanged(category);
                    },
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: 'Offers',
                    selected: segment == 'offer',
                    onTap: () => onSegmentChanged('offer'),
                  ),
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: 'Needs',
                    selected: segment == 'request',
                    onTap: () => onSegmentChanged('request'),
                  ),
                  for (final name in categories) ...[
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: name,
                      selected: category == name,
                      onTap: () => onCategoryChanged(name),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterBarDelegate oldDelegate) =>
      oldDelegate.sort != sort ||
      oldDelegate.segment != segment ||
      oldDelegate.category != category ||
      oldDelegate.background != background;
}

/// The sort control: a compact button that opens the order menu.
class _SortButton extends StatelessWidget {
  final String sort;
  final ValueChanged<String> onChanged;

  const _SortButton({required this.sort, required this.onChanged});

  String get _label => sort == 'nearby' ? 'Nearby' : 'Recent';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;

    return PopupMenuButton<String>(
      tooltip: 'Sort listings',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'recent',
          child: Row(
            children: [
              Icon(Icons.new_releases_outlined, size: 18),
              SizedBox(width: 10),
              Text('Recent', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'nearby',
          child: Row(
            children: [
              Icon(Icons.near_me_outlined, size: 18),
              SizedBox(width: 10),
              Text('Nearby', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: dark ? CblrepColors.fieldGreen : const Color(0xFFF4F1E8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: dark ? Colors.white24 : Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sort == 'nearby' ? Icons.near_me_outlined : Icons.new_releases_outlined,
              size: 16,
              color: CblrepColors.actionOrange,
            ),
            const SizedBox(width: 5),
            Text(
              _label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: CblrepColors.actionOrange),
          ],
        ),
      ),
    );
  }
}

/// One filter chip in the sticky bar.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    return Material(
      color: selected
          ? CblrepColors.actionOrange
          : (dark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? CblrepColors.actionOrange : Colors.black12,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Colors.white : foreground,
            ),
          ),
        ),
      ),
    );
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
