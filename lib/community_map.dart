import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'app_drawer.dart';
import 'post_resource_dialog.dart';
import 'resource_provider.dart';

class CommunityMapPage extends StatefulWidget {
  const CommunityMapPage({super.key});

  @override
  State<CommunityMapPage> createState() => _CommunityMapPageState();
}

class _CommunityMapPageState extends State<CommunityMapPage> {
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
          'Community Map',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16.0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(14.5995, 120.9842), // Default map center
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}{r}.png',
                      userAgentPackageName: 'com.cblrep.app',
                      retinaMode: RetinaMode.isHighDensity(context),
                    ),
                  ],
                ),
              ),
            ),
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
                    '+ POST A RESOURCE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
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