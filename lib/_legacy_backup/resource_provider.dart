import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class ResourceItem {
  final String id;
  final String title;
  final String postedBy;
  final String brgy;
  String status; // 'available', 'pending', or 'exchanged'
  final LatLng location;

  ResourceItem({
    required this.id,
    required this.title,
    required this.postedBy,
    required this.brgy,
    required this.location,
    this.status = 'available',
  });
}

class ResourceProvider extends ChangeNotifier {
  final List<ResourceItem> _items = [
    ResourceItem(
      id: '1',
      title: 'HEAVY DUTY POWER DRILL',
      postedBy: 'Zaki S.',
      brgy: 'Brgy 2',
      status: 'available',
      location: const LatLng(10.0818, 124.3369),
    ),
    ResourceItem(
      id: '2',
      title: 'FRESH VEGGIE BASKET',
      postedBy: 'Judas R.',
      brgy: 'Brgy 2',
      status: 'pending',
      location: const LatLng(10.0850, 124.3400),
    ),
    ResourceItem(
      id: '3',
      title: 'EXTENSION LADDER',
      postedBy: 'Peter P.',
      brgy: 'Brgy 2',
      status: 'available',
      location: const LatLng(10.0790, 124.3320),
    ),
    ResourceItem(
      id: '4',
      title: 'COMMUTER BIKE',
      postedBy: 'Jesus G.',
      brgy: 'Brgy 2',
      status: 'pending',
      location: const LatLng(10.0830, 124.3390),
    ),
    ResourceItem(
      id: '5',
      title: 'PORTABLE POWER TOOL',
      postedBy: 'Mary S.',
      brgy: 'Brgy 2',
      status: 'pending',
      location: const LatLng(10.0805, 124.3350),
    ),
    ResourceItem(
      id: '6',
      title: 'CLOTHES RACK',
      postedBy: 'Moises R.',
      brgy: 'Brgy 2',
      status: 'available',
      location: const LatLng(10.0840, 124.3310),
    ),
    ResourceItem(
      id: '7',
      title: 'BACKPACK',
      postedBy: 'Angelou R.',
      brgy: 'Brgy 2',
      status: 'available',
      location: const LatLng(10.0810, 124.3380),
    ),
  ];

  List<ResourceItem> get items => List.unmodifiable(_items);

  int get totalListings => _items.length;
  int get totalPending => _items.where((item) => item.status == 'pending').length;
  int get totalExchanged => _items.where((item) => item.status == 'exchanged').length;

  List<ResourceItem> get pendingItems => _items.where((item) => item.status == 'pending').toList();

  void addResource(String title, String postedBy, String brgy) {
    _items.insert(
      0,
      ResourceItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        postedBy: postedBy,
        brgy: brgy,
        status: 'available',
        location: const LatLng(10.0818, 124.3369),
      ),
    );
    notifyListeners();
  }

  void updateStatus(String id, String newStatus) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      _items[index].status = newStatus;
      notifyListeners();
    }
  }
}

final globalResourceProvider = ResourceProvider();