import 'package:shared_preferences/shared_preferences.dart';

/// Persisted sign-in preferences for the login screen's "Remember me" box.
///
/// Only the *preference* itself and the member's e-mail address ever live
/// here — never a password, and never the bearer token. The token is owned by
/// `ApiService`, which writes it to encrypted storage only when the member
/// asked to be remembered, and keeps it in memory otherwise.
class SessionPrefs {
  SessionPrefs._();

  static const _rememberKey = 'cblrep_remember_me';
  static const _emailKey = 'cblrep_remembered_email';

  /// The last "Remember me" state the member signed in with.
  ///
  /// Defaults to true: the portal used to keep members signed in across
  /// restarts unconditionally, so remembering stays the out-of-the-box
  /// behaviour until someone opts out once.
  static Future<bool> rememberPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberKey) ?? true;
  }

  /// E-mail of the last *remembered* sign-in, for pre-filling the form.
  static Future<String?> rememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  /// Records the outcome of a successful sign-in.
  ///
  /// The checkbox state always persists so the form looks the same next time;
  /// the e-mail address is kept only for a remembered sign-in and purged when
  /// the member signs in without "Remember me" — an unremembered session
  /// must leave no credentials behind on the device.
  static Future<void> recordSignIn({
    required bool rememberMe,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(_emailKey, email);
    } else {
      await prefs.remove(_emailKey);
    }
  }

  /// Full purge — sign-out removes every saved login preference.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberKey);
    await prefs.remove(_emailKey);
  }
}
