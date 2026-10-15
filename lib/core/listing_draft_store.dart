import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A locally-persisted draft of an unfinished listing.
///
/// Posting a listing is a multi-field task that a member often starts with one
/// bar of signal, gets interrupted, and returns to later — losing the whole form
/// to a back-swipe is the kind of small cruelty that stops people posting at all.
/// This keeps the in-progress form on the device so the Post screen can offer it
/// back.
///
/// It is deliberately device-local and never sent anywhere: a draft is not a
/// listing, and a half-finished post must not leak to the server or to another
/// member. Drafts are scoped per member (keyed by user id) so two people sharing
/// a phone do not inherit each other's unfinished posts.
class ListingDraftStore {
  ListingDraftStore._();

  static const _prefix = 'cblrep_listing_draft_';

  static String _key(int userId) => '$_prefix$userId';

  /// The stored draft for a member, or null when there is none (or it is
  /// unreadable — a corrupt draft, or an unavailable store, is simply ignored
  /// rather than crashing the form).
  static Future<Map<String, dynamic>?> load(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(int userId, Map<String, dynamic> draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), jsonEncode(draft));
    } catch (_) {
      // Best-effort: a draft is a convenience, never a hard dependency.
    }
  }

  static Future<void> clear(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {
      // Ignore — see save().
    }
  }
}
