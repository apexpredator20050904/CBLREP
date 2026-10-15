import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/community.dart';
import '../theme/cblrep_theme.dart';

/// Pick an exact point for a listing.
///
/// A member's barangay + purok is enough to place a listing near them, but a
/// neighbour actually going to collect something benefits from the exact spot:
/// the gate, the sari-sari store, the corner. This screen lets the poster drop
/// a pin — either by using their current GPS position or by panning the map —
/// and returns the chosen coordinates to the Post form.
///
/// The pin is held at the centre of the map (a fixed crosshair) rather than
/// being a draggable marker: panning a map to a point is far easier on a phone
/// than dragging a small marker under a finger, and it keeps the pin visible
/// while the underlying tiles move.
class LocationPickerScreen extends StatefulWidget {
  /// Where the map opens before the member moves it. Defaults to the Trinidad
  /// municipal centre when nothing better is known.
  final LatLng? initial;

  const LocationPickerScreen({super.key, this.initial});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _controller = MapController();

  /// The point under the crosshair. A notifier (not plain state) so panning the
  /// map updates the coordinate readout without rebuilding the whole tile layer.
  late final ValueNotifier<LatLng> _center = ValueNotifier(
    widget.initial ?? LatLng(trinidadCenter.lat, trinidadCenter.lng),
  );

  bool _locating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // If the caller gave no starting point, try to open on the member's own
    // position so the first thing they see is usually already right.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrentLocation());
    }
  }

  @override
  void dispose() {
    _center.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locating = false;
            _message = 'Location permission denied. You can still pan the map.';
          });
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      _center.value = point;
      setState(() => _locating = false);
      _controller.move(point, 16);
    } catch (_) {
      if (mounted) {
        setState(() {
          _locating = false;
          _message = 'Could not get your location. Pan the map instead.';
        });
      }
    }
  }

  void _confirm() => Navigator.pop(context, _center.value);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin exact location', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: _confirm, child: const Text('Use this point')),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center.value,
              initialZoom: 16,
              onPositionChanged: (position, _) => _center.value = position.center,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ph.cblrep.app',
              ),
            ],
          ),
          // Fixed crosshair: whatever sits under it is the chosen point.
          const IgnorePointer(
            child: Center(
              child: Icon(
                Icons.location_on,
                size: 44,
                color: CblrepColors.actionOrange,
                shadows: [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))],
              ),
            ),
          ),
          if (_message != null)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Material(
                color: dark ? CblrepColors.deepForest : Colors.white,
                borderRadius: BorderRadius.circular(10),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_message!, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _locating ? null : _useCurrentLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: Text(_locating ? 'Locating…' : 'My location'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Use this point'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ValueListenableBuilder<LatLng>(
                  valueListenable: _center,
                  builder: (_, point, _) => Text(
                    'Coordinates: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: dark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
