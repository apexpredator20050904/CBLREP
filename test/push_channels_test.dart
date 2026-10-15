import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/push_service.dart';
import 'package:untitled1/providers/app_settings_provider.dart';

/// Part B — the mobile side of notifications beyond messaging.
///
/// The backend now sends a `channel` with every push so Android can route it to
/// a per-category channel (letting a member mute barter alerts without muting
/// chat). [resolveChannelId] is the guard that keeps an unknown channel from
/// ever dropping a notification.
void main() {
  group('push channel routing', () {
    test('known channels are passed through untouched', () {
      expect(resolveChannelId('cblrep_messages'), kCblrepChannelMessages);
      expect(resolveChannelId('cblrep_exchanges'), kCblrepChannelExchanges);
      expect(resolveChannelId('cblrep_announcements'),
          kCblrepChannelAnnouncements);
      expect(resolveChannelId('cblrep_account'), kCblrepChannelAccount);
    });

    test('an unknown or missing channel falls back to messages', () {
      expect(resolveChannelId(null), kCblrepChannelMessages);
      expect(resolveChannelId(''), kCblrepChannelMessages);
      expect(resolveChannelId('made_up'), kCblrepChannelMessages);
    });

    test('every channel has a human-readable name', () {
      expect(channelNameFor(kCblrepChannelExchanges), 'Barter activity');
      expect(channelNameFor(kCblrepChannelAnnouncements), 'Announcements');
      // An unknown id must still yield a usable label.
      expect(channelNameFor('nope'), isNotEmpty);
    });
  });

  group('AppSettingsProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults every notification toggle on', () async {
      final settings = AppSettingsProvider()..load();
      await Future<void>.delayed(Duration.zero);

      expect(settings.notificationsEnabled, isTrue);
      expect(settings.exchangeAlerts, isTrue);
      expect(settings.messageAlerts, isTrue);
      expect(settings.announcementAlerts, isTrue);
    });

    test('a flipped toggle is persisted locally with no server configured',
        () async {
      final settings = AppSettingsProvider();
      await settings.load();

      await settings.setAnnouncementAlerts(false);
      expect(settings.announcementAlerts, isFalse);

      // Reload from the same (mocked) store to prove it was written.
      final reloaded = AppSettingsProvider();
      await reloaded.load();
      expect(reloaded.announcementAlerts, isFalse);
    });

    test('the master switch and a category are stored independently', () async {
      final settings = AppSettingsProvider();
      await settings.load();

      await settings.setNotifications(false);
      await settings.setMessageAlerts(false);

      final reloaded = AppSettingsProvider();
      await reloaded.load();
      expect(reloaded.notificationsEnabled, isFalse);
      expect(reloaded.messageAlerts, isFalse);
      expect(reloaded.exchangeAlerts, isTrue);
    });
  });
}
