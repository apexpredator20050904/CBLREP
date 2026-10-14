import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';
import '../widgets/listing_card.dart';
import 'listing_detail_screen.dart';

/// Community map — OpenStreetMap tiles (flutter_map) showing live offers &
/// needs, each pinned at its stored GPS coordinates (barangay anchor
/// fallback from the backend). Markers refresh with ListingsProvider
/// polling, so new postings appear without a manual reload.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _controller = MapController();
  String segment = 'all'; // all | offer | request
  LatLng? _userPosition;

  static const LatLng _trinidadCenter = LatLng(10.0797, 124.3431);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _userPosition = LatLng(pos.latitude, pos.longitude));
      _controller.move(_userPosition!, 14);
    } catch (_) {
      // Location unavailable — map stays centred on Trinidad, Bohol.
    }
  }

  LatLng _pointFor(ListingModel l) => (l.latitude != null && l.longitude != null)
      ? LatLng(l.latitude!, l.longitude!)
      : _trinidadCenter;

  void _showSheet(ListingModel listing) {
    final need = listing.type == 'request';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (listing.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(listing.imageUrl!, height: 160, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(height: 4)),
            ),
          const SizedBox(height: 10),
          Text(listing.title, style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ListingCard.compensationColor(listing.compensationType),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(listing.compensationLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Text(need ? 'NEED' : 'OFFER', style: Theme.of(ctx).textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          Text(
            '${listing.category} · ${listing.condition}',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 13),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                [listing.barangay, listing.purokSitio].where((p) => p.trim().isNotEmpty).join(' · ').isEmpty
                    ? listing.location
                    : [listing.barangay, listing.purokSitio].where((p) => p.trim().isNotEmpty).join(' · '),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing)));
            },
            child: const Text('View details'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingsProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    final visible = provider.listings.where((l) {
      if (segment == 'offer' && l.type == 'request') return false;
      if (segment == 'request' && l.type != 'request') return false;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: dark ? CblrepColors.fieldGreen : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dark ? Colors.white12 : Colors.black12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.place_outlined, size: 18, color: CblrepColors.actionOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${visible.length} listing(s) across Trinidad barangays',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'offer', label: Text('Offers')),
                  ButtonSegment(value: 'request', label: Text('Needs')),
                ],
                selected: {segment},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onSelectionChanged: (v) => setState(() => segment = v.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: dark ? Colors.white12 : Colors.black12),
            ),
            child: FlutterMap(
              mapController: _controller,
              options: const MapOptions(initialCenter: _trinidadCenter, initialZoom: 13),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ph.cblrep.app',
                  // Dark mode: invert the light OSM tiles so the map stays legible.
                  tileBuilder: dark ? _darkTile : null,
                ),
                if (_userPosition != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _userPosition!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                        ),
                      ),
                    ),
                  ]),
                MarkerLayer(
                  markers: [
                    for (final l in visible)
                      Marker(
                        point: _pointFor(l),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => _showSheet(l),
                          child: Icon(
                            Icons.location_on,
                            size: 34,
                            color: l.type == 'request' ? CblrepColors.brandGreen : CblrepColors.actionOrange,
                            shadows: const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            _legendDot(CblrepColors.actionOrange, 'Offers'),
            const SizedBox(width: 12),
            _legendDot(CblrepColors.brandGreen, 'Needs'),
            const Spacer(),
            IconButton(
              tooltip: 'My location',
              icon: const Icon(Icons.my_location, size: 20),
              onPressed: _locate,
            ),
          ]),
        ),
      ],
    );
  }

  static Widget _darkTile(BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -0.7, 0, 0, 0, 220,
        0, -0.85, 0, 0, 220,
        0, 0, -0.8, 0, 200,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }

  Widget _legendDot(Color color, String label) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}
