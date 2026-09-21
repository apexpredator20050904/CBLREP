import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level settings: theme mode, notifications, proximity radius.
class AppSettingsProvider extends ChangeNotifier {
  static const _themeKey = 'cblrep_theme_mode';
  static const _notifKey = 'cblrep_notif_enabled';
  static const _exchangeAlertKey = 'cblrep_exchange_alerts';
  static const _messageAlertKey = 'cblrep_message_alerts';
  static const _radiusKey = 'cblrep_radius_km';

  bool darkMode = true;
  bool notificationsEnabled = true;
  bool exchangeAlerts = true;
  bool messageAlerts = true;
  double radiusKm = 5.0;
  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode = prefs.getBool(_themeKey) ?? true;
    notificationsEnabled = prefs.getBool(_notifKey) ?? true;
    exchangeAlerts = prefs.getBool(_exchangeAlertKey) ?? true;
    messageAlerts = prefs.getBool(_messageAlertKey) ?? true;
    radiusKm = prefs.getDouble(_radiusKey) ?? 5.0;
    loaded = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_themeKey, value);
  }

  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_notifKey, value);
  }

  Future<void> setExchangeAlerts(bool value) async {
    exchangeAlerts = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_exchangeAlertKey, value);
  }

  Future<void> setMessageAlerts(bool value) async {
    messageAlerts = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_messageAlertKey, value);
  }

  Future<void> setRadius(double value) async {
    radiusKm = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_radiusKey, value);
  }
}
