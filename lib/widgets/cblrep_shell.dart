import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/live_hub_provider.dart';
import '../screens/create_listing_screen.dart';
import '../screens/exchanges_screen.dart';
import '../screens/home_feed_screen.dart';
import '../screens/login_screen.dart';
import '../screens/map_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/profile_screen.dart';
import '../theme/cblrep_theme.dart';

/// Bottom-tab shell — branded header with official logo, live notification
/// badge, and tabs for Home / Exchanges / Map / Messages / Profile.
class CblrepShell extends StatefulWidget {
  const CblrepShell({super.key});

  @override
  State<CblrepShell> createState() => _CblrepShellState();
}

class _CblrepShellState extends State<CblrepShell> {
  int index = 0;

  /// App-scoped providers captured once, so disposing this shell never has to
  /// reach for a context that is already going away.
  late final LiveHubProvider _hub;
  AuthProvider? _auth;

  static const _pages = [
    HomeFeedScreen(),
    ExchangesScreen(),
    MapScreen(),
    MessagesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _hub = context.read<LiveHubProvider>();
    // The launch gate (AuthGate) is popped the moment the member signs in, so
    // nothing else reacts when a session dies mid-run — the shell simply kept
    // rendering with no token while every authenticated call, Message /
    // Inquire included, came back "Unauthenticated." Watch the auth state from
    // here and put the member back on the sign-in form instead.
    _auth = context.read<AuthProvider>()..addListener(_onAuthChanged);
    Future.microtask(_hub.startLive);
  }

  void _onAuthChanged() {
    // A deliberate sign-out is owned by ProfileScreen (it shows the
    // confirmation and navigates itself); only a session that expired
    // underneath the member needs rescuing from here.
    if (!mounted || _auth?.user != null || _auth?.sessionExpired != true) return;
    Future.microtask(() {
      if (!mounted || _auth?.user != null) return;
      _hub.stopLive();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    // The hub lives at app scope, so its 10-second poll would otherwise keep
    // firing after this shell is gone: token-less requests that can only ever
    // answer 401, and whose late replies may land in the middle of the next
    // sign-in.
    _hub.stopLive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Select only the badge count — a plain watch would rebuild the entire
    // shell (app bar, navigation bar and the open page) on every 20s poll.
    final unread = context.select<LiveHubProvider, int>((hub) => hub.unreadCount);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? CblrepColors.deepForest : Colors.white;
    return Scaffold(
      backgroundColor: dark ? CblrepColors.deepForest : null,
      appBar: AppBar(
        backgroundColor: barColor,
        title: const Row(
          children: [
            CblrepLogo(radius: 15),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CBLREP', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  Text('Community-Based Local Resources Exchange Portal',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                icon: const Icon(Icons.notifications_outlined, size: 22),
              ),
              if (unread > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: CblrepColors.actionOrange, borderRadius: BorderRadius.circular(10)),
                    child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              backgroundColor: CblrepColors.actionOrange,
              foregroundColor: Colors.white,
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen()));
              },
              icon: const Icon(Icons.add),
              label: const Text('+ Post a Resource', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), selectedIcon: Icon(Icons.swap_horiz), label: 'Exchanges'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Messages'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      body: SafeArea(child: _pages[index]),
    );
  }
}
