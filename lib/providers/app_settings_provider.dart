import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_service.dart';

/// App-level settings: theme mode and notification preferences.
///
/// The notification toggles are shown instantly from the local cache (so the
/// Settings screen never waits on the network), and — when an [ApiService] is
/// supplied — mirrored to the server. The mirror matters: only the server can
/// send an FCM push, so a device-local toggle alone could never silence one.
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider([this._api]);

  final ApiService? _api;

  static const _themeKey = 'cblrep_theme_mode';
  static const _notifKey = 'cblrep_notif_enabled';
  static const _exchangeAlertKey = 'cblrep_exchange_alerts';
  static const _messageAlertKey = 'cblrep_message_alerts';
  static const _announcementAlertKey = 'cblrep_announcement_alerts';
  static const _updateAlertKey = 'cblrep_update_alerts';

  bool darkMode = true;
  bool notificationsEnabled = true;
  bool exchangeAlerts = true;
  bool messageAlerts = true;
  bool announcementAlerts = true;

  /// "A new version of the app is available" alerts. Their own category, so a
  /// member can silence release pings without muting announcements.
  bool updateAlerts = true;

  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode = prefs.getBool(_themeKey) ?? true;
    notificationsEnabled = prefs.getBool(_notifKey) ?? true;
    exchangeAlerts = prefs.getBool(_exchangeAlertKey) ?? true;
    messageAlerts = prefs.getBool(_messageAlertKey) ?? true;
    announcementAlerts = prefs.getBool(_announcementAlertKey) ?? true;
    updateAlerts = prefs.getBool(_updateAlertKey) ?? true;
    loaded = true;
    notifyListeners();
  }

  /// Adopts the server's stored preferences, or seeds the server from the
  /// device on the very first run after the member signs in.
  ///
  /// Best-effort: an older backend (404) or an offline device just keeps the
  /// local values.
  Future<void> syncWithServer() async {
    final api = _api;
    if (api == null) return;

    // Never seed the server from half-loaded defaults: wait for the cached
    // values first, otherwise a member who had muted a category on a previous
    // run could be silently re-subscribed.
    if (!loaded) await load();

    try {
      final response = await api.notificationPreferences();
      final configured = response['configured'] == true;
      final data = Map<String, dynamic>.from(
          (response['notification_preferences'] as Map?) ?? const {});

      if (!configured) {
        // Nothing stored server-side yet: push what the member already chose.
        await _syncToServer();
        return;
      }

      notificationsEnabled = data['enabled'] as bool? ?? notificationsEnabled;
      messageAlerts = data['messages'] as bool? ?? messageAlerts;
      exchangeAlerts = data['exchanges'] as bool? ?? exchangeAlerts;
      announcementAlerts =
          data['announcements'] as bool? ?? announcementAlerts;
      updateAlerts = data['updates'] as bool? ?? updateAlerts;
      await _persistLocal();
    } catch (_) {
      // Leave the cached values in place.
    }
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_themeKey, value);
  }

  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    notifyListeners();
    await _persistLocal();
    await _syncToServer();
  }

  Future<void> setExchangeAlerts(bool value) async {
    exchangeAlerts = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_exchangeAlertKey, value);
    await _syncToServer();
  }

  Future<void> setMessageAlerts(bool value) async {
    messageAlerts = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_messageAlertKey, value);
    await _syncToServer();
  }

  Future<void> setAnnouncementAlerts(bool value) async {
    announcementAlerts = value;
    notifyListeners();
    (await SharedPreferences.getInstance())
        .setBool(_announcementAlertKey, value);
    await _syncToServer();
  }

  Future<void> setUpdateAlerts(bool value) async {
    updateAlerts = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_updateAlertKey, value);
    await _syncToServer();
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifKey, notificationsEnabled);
    await prefs.setBool(_exchangeAlertKey, exchangeAlerts);
    await prefs.setBool(_messageAlertKey, messageAlerts);
    await prefs.setBool(_announcementAlertKey, announcementAlerts);
    await prefs.setBool(_updateAlertKey, updateAlerts);
  }

  /// Mirrors the current toggles to the server. Fire-and-forget in spirit: a
  /// failure must never block the UI toggle the member just flipped.
  Future<void> _syncToServer() async {
    final api = _api;
    if (api == null) return;
    try {
      await api.updateNotificationPreferences({
        'enabled': notificationsEnabled,
        'messages': messageAlerts,
        'exchanges': exchangeAlerts,
        'announcements': announcementAlerts,
        'updates': updateAlerts,
      });
    } catch (_) {
      // Local cache still reflects the choice; the next sync will retry.
    }
  }
}
