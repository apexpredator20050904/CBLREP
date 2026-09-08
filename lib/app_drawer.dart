import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'browse_listings.dart';
import 'my_exchanges.dart';
import 'community_map.dart';
import 'post_resource_dialog.dart';
import 'resource_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.pop(context); // Closes drawer modal overlay
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  Future<void> _openPostResourceModal(BuildContext context) async {
    Navigator.pop(context);

    final newResource = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const PostResourceDialog(),
    );

    if (newResource != null) {
      globalResourceProvider.addResource(
        newResource['title']!,
        newResource['postedBy']!,
        newResource['brgy']!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF2D4D36),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header Header
            Container(
              color: const Color(0xFFCCCCCC),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.black, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 14,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'COMMUNITY-BASED\nLOCAL RESOURCES\nEXCHANGE PORTAL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Profile Container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(0xFFD97706),
                      radius: 16,
                      child: Text(
                        'ZS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Zaki\nSantos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Navigation Links
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                children: [
                  _DrawerItemButton(
                    label: 'Dashboard',
                    onTap: () => _navigateTo(context, const DashboardPage()),
                  ),
                  _DrawerItemButton(
                    label: 'Browse Listings',
                    onTap: () => _navigateTo(context, const BrowseListingsPage()),
                  ),
                  _DrawerItemButton(
                    label: 'My Exchanges',
                    onTap: () => _navigateTo(context, const MyExchangesPage()),
                  ),
                  _DrawerItemButton(
                    label: 'Community Map',
                    onTap: () => _navigateTo(context, const CommunityMapPage()),
                  ),
                  _DrawerItemButton(
                    label: 'Messages',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Messages feature coming soon!')),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom Action Buttons
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  _DrawerItemButton(
                    label: 'Post a Resource',
                    onTap: () => _openPostResourceModal(context),
                  ),
                  const SizedBox(height: 8),
                  _DrawerItemButton(
                    label: 'My Profile',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile page coming soon!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Optimized Stateless Widget for performance
class _DrawerItemButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DrawerItemButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: SizedBox(
        width: double.infinity,
        height: 38,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFCCCCCC),
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: onTap,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}