import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/live_hub_provider.dart';
import '../screens/create_listing_screen.dart';
import '../screens/exchanges_screen.dart';
import '../screens/home_feed_screen.dart';
import '../screens/map_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/timebank_screen.dart';
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
    Future.microtask(() => context.read<LiveHubProvider>().startLive());
  }

  void _openDrawerPage(Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
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
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: const Icon(Icons.logout, size: 20),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF2E5339), Color(0xFF1B382B)]),
              ),
              child: Row(children: [
                const CblrepLogo(radius: 26),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('CBLREP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.5)),
                    Text('Trinidad, Bohol', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            ListTile(leading: const Icon(Icons.home_outlined), title: const Text('Home feed'), onTap: () { Navigator.pop(context); setState(() => index = 0); }),
            ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('Exchanges'), onTap: () { Navigator.pop(context); setState(() => index = 1); }),
            ListTile(leading: const Icon(Icons.map_outlined), title: const Text('Community map'), onTap: () { Navigator.pop(context); setState(() => index = 2); }),
            ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Messages'), onTap: () { Navigator.pop(context); setState(() => index = 3); }),
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Profile'), onTap: () { Navigator.pop(context); setState(() => index = 4); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.timelapse), title: const Text('Time Bank'), onTap: () => _openDrawerPage(const TimeBankScreen())),
            ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Notifications'), onTap: () => _openDrawerPage(const NotificationsScreen())),
          ],
        ),
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
