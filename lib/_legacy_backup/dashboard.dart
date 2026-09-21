import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'browse_listings.dart';
import 'post_resource_dialog.dart';
import 'resource_provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    globalResourceProvider.addListener(_refreshState);
  }

  @override
  void dispose() {
    globalResourceProvider.removeListener(_refreshState);
    super.dispose();
  }

  void _refreshState() {
    if (mounted) setState(() {});
  }

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

  @override
  Widget build(BuildContext context) {
    final provider = globalResourceProvider;
    final recentItems = provider.items.take(2).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF2D4D36),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D4D36),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'Dashboard - CBLREP - barangay2',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 45,
                          height: 45,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Welcome Back',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Good day, Zaki!',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 30,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC86400),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: _openPostResourceModal,
                                child: const Text(
                                  '+Post Resource',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 30,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F4022),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const BrowseListingsPage()),
                                  );
                                },
                                child: const Text(
                                  'Browse Listing',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _buildStatBox('Items Available', provider.totalListings.toString(), 'Active on database'),
                  _buildStatBox('Active Exchanges', provider.totalPending.toString(), 'Pending/Ongoing'),
                  _buildStatBox('Members Nearby', '0', 'In barangay2'),
                  _buildStatBox('Time-Bank Credit', '0', 'Your ledger balance'),
                ],
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('View all - ', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('Activity Logs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text(
                    'No recent activity logged',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recent Database Listings',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: recentItems.isEmpty
                    ? const Column(
                  children: [
                    Text(
                      'No resource listed yet',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Be the first member in barangay 2 to post a resource',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: recentItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black),
                          ),
                          Text(
                            'By: ${item.postedBy}',
                            style: const TextStyle(fontSize: 10, color: Colors.black54),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBox(String title, String count, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFCCCCCC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black),
          ),
          const SizedBox(height: 2),
          Text(
            count,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}