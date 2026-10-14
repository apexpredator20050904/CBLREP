import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/providers/app_update_provider.dart';

/// The sideloaded updater must never nag a tester on a backend whose release
/// channel is switched off, and must never trap a member in a non-dismissible
/// prompt that has no APK to install. These pin those two safety rules plus the
/// plain version comparison.
void main() {
  group('AppUpdateProvider decision logic', () {
    AppUpdateProvider provider() => AppUpdateProvider(ApiService.instance);

    test('no prompt when the release channel is switched off', () {
      final p = provider();
      p.checked = true;
      p.installedBuild = 1;
      p.latestBuild = 5;
      p.minSupportedBuild = 1;
      p.apkUrl = ''; // dev/ngrok backend stays silent
      expect(p.updateAvailable, isFalse);
      expect(p.forceUpdate, isFalse);
      expect(p.shouldPrompt, isFalse);
    });

    test('no prompt when the installed build is current or newer', () {
      final p = provider();
      p.checked = true;
      p.apkUrl = 'https://example.test/app-release.apk';
      p.minSupportedBuild = 1;

      p.installedBuild = 2;
      p.latestBuild = 2;
      expect(p.updateAvailable, isFalse);

      p.latestBuild = 1;
      expect(p.updateAvailable, isFalse);
    });

    test('a newer build is offered as an optional update', () {
      final p = provider();
      p.checked = true;
      p.apkUrl = 'https://example.test/app-release.apk';
      p.installedBuild = 1;
      p.latestBuild = 2;
      p.minSupportedBuild = 1;
      expect(p.updateAvailable, isTrue);
      expect(p.forceUpdate, isFalse);
      expect(p.shouldPrompt, isTrue);
    });

    test('a build below the supported floor is forced', () {
      final p = provider();
      p.checked = true;
      p.apkUrl = 'https://example.test/app-release.apk';
      p.installedBuild = 1;
      p.latestBuild = 3;
      p.minSupportedBuild = 2;
      expect(p.forceUpdate, isTrue);
      expect(p.shouldPrompt, isTrue);
    });

    test('a raised floor with no published APK does not lock the member out', () {
      final p = provider();
      p.checked = true;
      p.apkUrl = '';
      p.installedBuild = 1;
      p.latestBuild = 3;
      p.minSupportedBuild = 2;
      expect(p.forceUpdate, isFalse);
      expect(p.shouldPrompt, isFalse);
    });
  });
}
