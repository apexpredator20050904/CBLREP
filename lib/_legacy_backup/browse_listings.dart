import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'post_resource_dialog.dart';
import 'resource_provider.dart';

class BrowseListingsPage extends StatefulWidget {
  const BrowseListingsPage({super.key});

  @override
  State<BrowseListingsPage> createState() => _BrowseListingsPageState();
}

class _BrowseListingsPageState extends State<BrowseListingsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Listen to global resource updates & local search changes
    globalResourceProvider.addListener(_refreshState);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    globalResourceProvider.removeListener(_refreshState);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _refreshState() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
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
    // Dynamic filtering based on search query
    final allItems = globalResourceProvider.items;
    final filteredItems = allItems.where((item) {
      final matchesTitle = item.title.toLowerCase().contains(_searchQuery);
      final matchesUser = item.postedBy.toLowerCase().contains(_searchQuery);
      final matchesBrgy = item.brgy.toLowerCase().contains(_searchQuery);

      return matchesTitle || matchesUser || matchesBrgy;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1B382B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B382B),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'Browse Listings',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search title, user, or barangay...',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF234735),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Functional Filtered Grid View
            Expanded(
              child: filteredItems.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 48, color: Colors.white38),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isEmpty
                          ? 'No listings available.'
                          : 'No items match "$_searchQuery"',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              )
                  : GridView.builder(
                padding: const EdgeInsets.all(16.0),
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    color: const Color(0xFF234735),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            color: const Color(0xFFCCCCCC),
                            child: const Icon(
                              Icons.image,
                              size: 50,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Posted by: ${item.postedBy}',
                                style: const TextStyle(color: Colors.white70, fontSize: 9),
                              ),
                              Text(
                                item.brgy,
                                style: const TextStyle(color: Colors.white70, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Post Resource Button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE58824),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: _openPostResourceModal,
                  child: const Text(
                    '+ Post a Resource',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}