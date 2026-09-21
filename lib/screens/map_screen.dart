import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../config/community.dart';
import '../models/models.dart';
import '../providers/app_settings_provider.dart';
import '../providers/listings_provider.dart';
import '../theme/cblrep_theme.dart';
import 'listing_detail_screen.dart';

/// Community map — interactive Google Map of live offers & needs.
///
/// Every listing is pinned at its barangay's anchor coordinate and filtered
/// by the proximity radius chosen in Settings (live haversine distance from
/// the municipal centre). Markers update instantly with ListingsProvider
/// polling, so new postings appear without any manual reload.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _controller;
  String segment = 'all'; // all | offer | request

  static LatLng _center =
      LatLng(trinidadCenter.lat, trinidadCenter.lng);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  LatLng _pointFor(ListingModel listing) {
    final (lat, lng) = coordinatesForBarangay(listing.location);
    return LatLng(lat, lng);
  }

  void _openDetail(ListingModel listing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing)),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ListingsProvider>();
    final radiusKm = context.watch<AppSettingsProvider>().radiusKm;
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Live proximity filter: keep listings whose barangay anchor sits within
    // the configured radius of the municipal centre.
    final visible = provider.listings.where((listing) {
      if (segment == 'offer' && listing.type == 'request') return false;
      if (segment == 'request' && listing.type != 'request') return false;
      final (lat, lng) = coordinatesForBarangay(listing.location);
      return distanceKm(trinidadCenter.lat, trinidadCenter.lng, lat, lng) <=
          radiusKm;
    }).toList();

    final markers = <Marker>{
      for (final listing in visible)
        Marker(
          markerId: MarkerId('listing-${listing.id}'),
          position: _pointFor(listing),
          anchor: const Offset(0.5, 1.0),
          icon: listing.type == 'request'
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen)
              : BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: listing.title,
            snippet:
                '${listing.type == 'request' ? 'NEED' : 'OFFER'} · ${listing.location}',
            onTap: () => _openDetail(listing),
          ),
          onTap: () => _openDetail(listing),
        ),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: dark ? CblrepColors.fieldGreen : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: dark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.radar,
                          size: 18, color: CblrepColors.actionOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${visible.length} listing(s) within ${radiusKm.toStringAsFixed(0)} km',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: dark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
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
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: _center, zoom: 12.5),
              markers: markers,
              circles: {
                Circle(
                  circleId: const CircleId('proximity-radius'),
                  center: _center,
                  radius: radiusKm * 1000,
                  fillColor: CblrepColors.actionOrange.withValues(alpha: 0.12),
                  strokeColor: CblrepColors.actionOrange,
                  strokeWidth: 2,
                ),
              },
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              onMapCreated: (controller) => _controller = controller,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              _legendDot(CblrepColors.actionOrange, 'Offers'),
              const SizedBox(width: 12),
              _legendDot(CblrepColors.brandGreen, 'Needs'),
              const Spacer(),
              Text(
                'Radius adjustable in Settings',
                style: TextStyle(
                  fontSize: 10,
                  color: dark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

