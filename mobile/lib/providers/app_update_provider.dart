import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_service.dart';

/// In-app update channel for the sideloaded APK.
///
/// CBLREP ships as an APK from GitHub Releases, not the Play Store, so the
/// Android Play Core "in-app updates" API is unavailable. Instead the app:
///
///   1. reads the *installed* build with `package_info_plus`, and
///   2. compares it against GET /api/app-version (see AppVersionController),
///   3. and, when a newer build exists, offers the release APK download.
///
/// Everything fails soft: a launch with no network, or a backend that has the
/// channel switched off (empty `apk_url`), simply produces no prompt.
class AppUpdateProvider extends ChangeNotifier {
  AppUpdateProvider(this._api);

  final ApiService _api;

  /// build number (versionCode) the member tapped "Later" for, so an optional
  /// prompt does not reappear on every launch. A force update ignores it.
  static const _dismissedKey = 'cblrep_dismissed_update_build';

  String installedVersionName = '';
  int installedBuild = 0;

  String latestVersionName = '';
  int latestBuild = 0;
  int minSupportedBuild = 1;
  String apkUrl = '';
  String notes = '';

  bool checking = false;
  bool checked = false;
  String? error;

  int _dismissedBuild = 0;

  /// True when the backend advertises a newer build the member can install.
  bool get updateAvailable =>
      checked && apkUrl.isNotEmpty && latestBuild > installedBuild;

  /// Builds at or below the published floor must update; the prompt cannot be
  /// dismissed. Guarded by [updateAvailable] so an unconfigured backend can
  /// never lock a member out of the app.
  bool get forceUpdate => updateAvailable && installedBuild < minSupportedBuild;

  /// Whether the launch prompt should appear right now.
  bool get shouldPrompt => updateAvailable && (forceUpdate || latestBuild > _dismissedBuild);

  /// A display string for the installed build, e.g. "1.2.0+2".
  String get installedLabel =>
      installedVersionName.isEmpty ? 'unknown' : '$installedVersionName+$installedBuild';

  /// Reads the installed build, restores the dismissed marker, then checks the
  /// backend. Safe to call once at startup.
  Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      installedVersionName = info.version;
      installedBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (error) {
      debugPrint('[CBLREP] could not read app version: $error');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedBuild = prefs.getInt(_dismissedKey) ?? 0;
    } catch (_) {
      // A preferences failure must not block the update check.
    }

    notifyListeners();
    await check();
  }

  /// Queries the release channel. Never throws — [error] carries the failure.
  Future<void> check() async {
    checking = true;
    error = null;
    notifyListeners();

    try {
      final data = await _api.appVersion();
      latestVersionName = (data['version_name'] ?? '').toString();
      latestBuild = _asInt(data['version_code']);
      minSupportedBuild = _asInt(data['min_supported_code']);
      apkUrl = (data['apk_url'] ?? '').toString();
      notes = (data['notes'] ?? '').toString();
      checked = true;
    } catch (error) {
      this.error = 'Could not check for updates. Please try again later.';
      debugPrint('[CBLREP] update check failed: $error');
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// Remembers that the member declined this build.
  Future<void> dismiss() async {
    _dismissedBuild = latestBuild;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedKey, _dismissedBuild);
    } catch (_) {
      // Non-fatal: the prompt just reappears next launch.
    }
  }

  /// Opens the release APK in the browser, where Android's installer takes over.
  Future<bool> openDownload() async {
    if (apkUrl.isEmpty) return false;
    try {
      return await launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[CBLREP] could not open update URL: $error');
      return false;
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
