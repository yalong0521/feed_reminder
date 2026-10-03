import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}
  @override
  Future<void> stopReminder() async {}
}

class _Notifications extends NotificationService {
  @override
  bool get isSupported => false;
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
  @override
  Future<void> cancelAll() async {}
}

void main() {
  testWidgets(
    'home records displayed default and later changes only affect new meals',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'acceptedPrivacyPolicyVersion': PrivacyPolicy.version,
      });
      final storage = StorageService();
      final settings = SettingsProvider(storage: storage);
      final audio = _Audio();
      final notifications = _Notifications();
      final feed = FeedProvider(
        storage: storage,
        audioService: audio,
        notificationService: notifications,
        startTimer: false,
        clock: () => DateTime(2026, 10, 3, 12),
      );
      await Future.wait([settings.ready, feed.ready]);
      await settings.setDefaultMilkAmountMl(120);
      await tester.pumpWidget(
        FeedReminderApp(
          storage: storage,
          settingsProvider: settings,
          feedProvider: feed,
          audioService: audio,
          notificationService: notifications,
          enablePlatformEffects: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本次 120 mL'), findsOneWidget);
      Future<void> slide() async {
        final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
        final start = tester.getCenter(thumb);
        final track = tester.getRect(
          find.byKey(const ValueKey('feed-slide-track')),
        );
        await tester.dragFrom(start, Offset(track.right - 4 - start.dx, 0));
        await tester.pumpAndSettle();
      }

      await slide();
      expect(feed.feedHistory.single.milkAmountMl, 120);
      await settings.setDefaultMilkAmountMl(180);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('本次 180 mL'), findsOneWidget);
      await slide();
      expect(
        feed.feedHistory.map((record) => record.milkAmountMl),
        containsAll([120, 180]),
      );
      expect(
        (await storage.getFeedHistory()).map((record) => record.milkAmountMl),
        containsAll([120, 180]),
      );
      await tester.tap(find.byKey(const ValueKey('feed-slide-undo')));
      await tester.pumpAndSettle();
      expect(feed.feedHistory.single.milkAmountMl, 120);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      feed.dispose();
      settings.dispose();
    },
  );
}
