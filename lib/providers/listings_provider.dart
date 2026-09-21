import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../core/input_sanitizer.dart';
import '../models/models.dart';

/// Single source of truth for resource listings.
///
/// Wraps [ApiService] (Laravel `/api/listings`) and notifies listeners so
/// every screen (Home feed, Browse grid, Community map, Dashboard stats)
/// updates in real time after create / delete / refresh.
class ListingsProvider extends ChangeNotifier {
  final ApiService api;
  List<ListingModel> listings = const [];
  bool loading = false;
  String? error;
  Timer? _pollTimer;

  ListingsProvider(this.api);

  List<ListingModel> get offers =>
      listings.where((item) => item.type != 'request').toList();
  List<ListingModel> get needs =>
      listings.where((item) => item.type == 'request').toList();

  Future<void> load({String? query, String? barangay, bool showSpinner = true}) async {
    if (showSpinner && !loading) {
      loading = true;
      notifyListeners();
    }
    var changed = false;
    try {
      final fresh = (await api.listings(query: query, barangay: barangay))
          .map((item) => ListingModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      // Keep the previous list object when the poll returns identical data —
      // the feed then skips the rebuild entirely (see _sameListings).
      if (!_sameListings(listings, fresh)) {
        listings = fresh;
        changed = true;
      }
      if (error != null) {
        error = null;
        changed = true;
      }
    } on ApiException catch (exception) {
      if (error != exception.message) {
        error = exception.message;
        changed = true;
      }
    } finally {
      if (loading) {
        loading = false;
        changed = true;
      }
      // Background polls (showSpinner: false) only notify on real changes.
      if (changed || showSpinner) notifyListeners();
    }
  }

  /// Cheap content check so no-op background polls never touch the UI.
  bool _sameListings(List<ListingModel> a, List<ListingModel> b) {
    if (identical(a, b) || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].title != b[i].title || a[i].active != b[i].active) {
        return false;
      }
    }
    return true;
  }

  /// Poll the backend so listings stay fresh in real time. Background polls
  /// skip the loading spinner so the grid is never torn down mid-scroll.
  void startAutoRefresh({Duration interval = const Duration(seconds: 30)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) {
      if (!loading) load(showSpinner: false);
    });
  }

  void stopAutoRefresh() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Create a listing on the backend, then refresh so the feed updates
  /// immediately. Returns the created listing payload.
  Future<Map<String, dynamic>> create({
    required String title,
    required String type,
    required String description,
    required String category,
    required String exchangeType,
    required String condition,
    required String location,
    File? image,
  }) async {
    final created = await api.createListing(
      // Strip control characters and any HTML/script before it reaches MySQL.
      title: InputSanitizer.text(title, max: 120),
      type: type,
      description: InputSanitizer.text(description, max: 2000),
      category: category,
      exchangeType: exchangeType,
      condition: condition,
      location: InputSanitizer.name(location),
      image: image,
    );
    await load();
    return created;
  }

  /// Close (soft-delete) a listing owned by the member, then refresh.
  Future<void> close(int id) async {
    try {
      await api.updateListing(id, {'status': 'closed'});
    } on ApiException {
      // Fall back to the hard-delete path used by older backends.
      await api.deleteListing(id);
    }
    await load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

