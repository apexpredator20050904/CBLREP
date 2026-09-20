import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../core/api_service.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/listings_provider.dart';
import 'create_listing_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final search = TextEditingController();
  String? barangay;
  bool maintenance = false;
  String maintenanceMessage = '';

  @override
  void initState() {
    super.initState();
    final listingsProvider = context.read<ListingsProvider>();
    Future.microtask(() async {
      await listingsProvider.load();
      if (!mounted) return;
      try {
        final status = await ApiService.instance.platformStatus();
        if (mounted) setState(() { maintenance = status['maintenance'] == true; maintenanceMessage = status['message'] as String? ?? ''; });
      } catch (_) {}
    });
  }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> refresh() => context.read<ListingsProvider>().load(query: search.text, barangay: barangay);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ListingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('CBLRE'),
        actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())), icon: const Icon(Icons.person_outline))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen())); if (mounted) refresh(); }, icon: const Icon(Icons.add), label: const Text('Post resource')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (maintenance) Card(color: Colors.amber.shade50, child: ListTile(leading: const Icon(Icons.info_outline), title: const Text('Scheduled updates'), subtitle: Text(maintenanceMessage))),
            Text('Welcome, ${auth.user?.name ?? 'member'}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(communityName, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(controller: search, onSubmitted: (_) => refresh(), decoration: InputDecoration(hintText: 'Search offers and needs', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: refresh, icon: const Icon(Icons.arrow_forward)), border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: barangay,
              decoration: const InputDecoration(labelText: 'Filter by barangay', border: OutlineInputBorder()),
              items: [const DropdownMenuItem<String>(value: null, child: Text('All Trinidad barangays')), ...trinidadBarangays.map((item) => DropdownMenuItem(value: item, child: Text(item)))],
              onChanged: (value) { setState(() => barangay = value); refresh(); },
            ),
            const SizedBox(height: 16),
            if (provider.loading) const Center(child: CircularProgressIndicator()),
            if (provider.error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('Could not load listings'), subtitle: Text(provider.error!))),
            if (!provider.loading && provider.error == null && provider.listings.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No active resources match your filters.'))),
            ...provider.listings.map((listing) => ListingCard(listing: listing)),
          ],
        ),
      ),
    );
  }
}

class ListingCard extends StatelessWidget {
  final ListingModel listing;
  const ListingCard({super.key, required this.listing});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: const Color(0xFF1B3B22), child: Icon(listing.type == 'request' ? Icons.help_outline : Icons.volunteer_activism, color: Colors.white)),
          title: Text(listing.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${listing.type == 'request' ? 'Need' : 'Offer'} · ${listing.category}\n${listing.location} · ${listing.owner}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
