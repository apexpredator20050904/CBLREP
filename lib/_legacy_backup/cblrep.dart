import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'browse_listings.dart';
import 'my_exchanges.dart';
import 'community_map.dart';
import 'post_resource_dialog.dart';
import 'resource_provider.dart';

class CblrepPortalPage extends StatefulWidget {
  const CblrepPortalPage({super.key});

  @override
  State<CblrepPortalPage> createState() => _CblrepPortalPageState();
}

class _CblrepPortalPageState extends State<CblrepPortalPage> {
  Future<void> _openPostResourceModal() async {
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

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF142B1D),
        title: const Text(
          'COMMUNITY-BASED LOCAL RESOURCES EXCHANGE PORTAL',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            children: [
              // User Card Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD3D3D3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFE88A34),
                      child: const Text('ZS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Zaki', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13)),
                        Text('Santos', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Navigation Options
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildNavButton('Dashboard', () => _navigateTo(const DashboardPage())),
                    _buildNavButton('Browse Listings', () => _navigateTo(const BrowseListingsPage())),
                    _buildNavButton('My Exchanges', () => _navigateTo(const MyExchangesPage())),
                    _buildNavButton('Community Map', () => _navigateTo(const CommunityMapPage())),
                    _buildNavButton('Messages', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Messages screen feature coming soon!')),
                      );
                    }),
                    const SizedBox(height: 12),
                    _buildActionButton('+ Post a Resource', _openPostResourceModal, const Color(0xFFD9822B)),
                    const SizedBox(height: 8),
                    _buildNavButton('My Profile', () {}),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 42,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD3D3D3),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: onTap,
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildActionButton(String title, VoidCallback onTap, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 42,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: onTap,
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
}