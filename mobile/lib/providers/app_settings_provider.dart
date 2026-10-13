import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level settings: theme mode and notification preferences.
class AppSettingsProvider extends ChangeNotifier {
  static const _themeKey = 'cblrep_theme_mode';
  static const _notifKey = 'cblrep_notif_enabled';
  static const _exchangeAlertKey = 'cblrep_exchange_alerts';
  static const _messageAlertKey = 'cblrep_message_alerts';

  bool darkMode = true;
  bool notificationsEnabled = true;
  bool exchangeAlerts = true;
  bool messageAlerts = true;
  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode = prefs.getBool(_themeKey) ?? true;
    notificationsEnabled = prefs.getBool(_notifKey) ?? true;
    exchangeAlerts = prefs.getBool(_exchangeAlertKey) ?? true;
    messageAlerts = prefs.getBool(_messageAlertKey) ?? true;
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
}
