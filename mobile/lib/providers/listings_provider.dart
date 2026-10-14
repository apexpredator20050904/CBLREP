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

  /// The signed-in member's own listings, including the paused/traded/archived
  /// rows the public feed hides. Populated by [loadMine].
  List<ListingModel> myListings = const [];
  Map<String, int> myCounts = const <String, int>{};
  bool myLoading = false;

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
    } catch (unexpected) {
      // Anything that is not an ApiException (a parsing error on a malformed
      // payload, a storage plugin failure) used to escape load() as an
      // unhandled async error, leaving the feed frozen on whatever it last
      // rendered with no way to recover.
      debugPrint('[CBLREP] listings load failed: $unexpected');
      const message = 'Unexpected problem loading listings. Please retry.';
      if (error != message) {
        error = message;
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
  void startAutoRefresh({Duration interval = const Duration(seconds: 12)}) {
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
    required String condition,
    required String location,
    required String barangay,
    required String purokSitio,
    String compensationType = 'barter',
    double? price,
    String? wantedItem,
    File? image,
  }) async {
    final created = await api.createListing(
      // Strip control characters and any HTML/script before it reaches MySQL.
      title: InputSanitizer.text(title, max: 120),
      type: type,
      description: InputSanitizer.text(description, max: 2000),
      category: category,
      condition: condition,
      location: InputSanitizer.name(location),
      barangay: barangay,
      purokSitio: InputSanitizer.name(purokSitio),
      compensationType: compensationType,
      price: price,
      // Barter-only: the return side. Free/paid listings have none, and the
      // backend nulls it for them regardless.
      wantedItem: compensationType == 'barter' && (wantedItem?.isNotEmpty ?? false)
          ? InputSanitizer.text(wantedItem!, max: 160)
          : null,
      image: image,
    );
    await load();
    return created;
  }

  /// Load the member's own listings (every lifecycle state) plus per-status
  /// counts. This is what powers the "My Listings" tabs — the public feed only
  /// ever returns active listings, so it cannot.
  Future<void> loadMine({bool showSpinner = true}) async {
    if (showSpinner) {
      myLoading = true;
      notifyListeners();
    }
    try {
      final data = await api.myListings();
      final raw = List<dynamic>.from(data['listings'] ?? data['data'] ?? const []);
      myListings = raw
          .map((item) => ListingModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      final counts = data['counts'];
      myCounts = counts is Map
          ? counts.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0))
          : const <String, int>{};
      error = null;
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (unexpected) {
      debugPrint('[CBLREP] my-listings load failed: $unexpected');
    } finally {
      myLoading = false;
      notifyListeners();
    }
  }

  /// Move one of the member's own listings to a new lifecycle state
  /// (active | paused | traded | archived), then refresh both the public feed
  /// and the member's own list.
  ///
  /// A listing a moderator has flagged/hidden/removed is refused by the API
  /// (403) and surfaces as an [ApiException] instead of a silent no-op.
  Future<void> setMyListingStatus(int id, String status) async {
    await api.updateListing(id, {'status': status});
    await Future.wait([
      load(showSpinner: false),
      loadMine(showSpinner: false),
    ]);
  }

  /// Temporarily hide a listing ("unavailable") without losing it.
  Future<void> pause(int id) => setMyListingStatus(id, 'paused');

  /// Put a paused/traded/archived listing back in the feed.
  Future<void> resume(int id) => setMyListingStatus(id, 'active');

  /// Record that a barter/sale went through.
  Future<void> markTraded(int id) => setMyListingStatus(id, 'traded');

  /// File a listing away in the archive (reversible).
  Future<void> archive(int id) => setMyListingStatus(id, 'archived');

  /// Backwards-compatible alias: the old "close" is now an archive.
  Future<void> close(int id) => archive(id);

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

