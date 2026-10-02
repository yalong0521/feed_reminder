import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:feed_reminder/widgets/app_message_dialog.dart';

void _expectNoMaterialInteractions() {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is InkResponse ||
          widget is ButtonStyleButton ||
          widget is MaterialButton ||
          widget is IconButton ||
          widget is ChoiceChip ||
          widget is Switch ||
          widget is TextField ||
          widget is SnackBar,
      description: 'Material controls, ripple interactions, or Snackbar',
    ),
    findsNothing,
  );
}

Future<void> _slideToRecord(WidgetTester tester) async {
  final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
  await tester.ensureVisible(thumb);
  final start = tester.getCenter(thumb);
  final track = tester.getRect(find.byKey(const ValueKey('feed-slide-track')));
  await tester.dragFrom(start, Offset(track.right - 4 - start.dx, 0));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android feeding, navigation and settings smoke test', (
    tester,
  ) async {
    // Exercise the real engine/plugins without touching the device's stored records.
    SharedPreferences.setMockInitialValues({'burnInProtectionEnabled': false});
    await StorageService().setAcceptedPrivacyPolicyVersion(
      PrivacyPolicy.version,
    );
    await tester.pumpWidget(
      const FeedReminderApp(enablePlatformEffects: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('等待第一条记录'), findsOneWidget);
    _expectNoMaterialInteractions();
    final slider = find.byType(FeedButton);
    expect(slider.hitTestable(), findsOneWidget);

    // Check opaque control contrast in the real engine and system high contrast.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    final palette = AppPalette.of(tester.element(slider));
    final solidSlider = tester.widget<Material>(
      find.descendant(of: slider, matching: find.byType(Material)).first,
    );
    expect(solidSlider.color, palette.softGreen);
    expect(solidSlider.color!.a, 1);
    final label = tester.widget<Text>(
      find.descendant(of: slider, matching: find.byType(Text)).first,
    );
    expect(label.style?.color, palette.textSecondary);
    final feed = tester.element(find.byType(FeedButton)).read<FeedProvider>();
    await tester.tap(find.byType(FeedButton));
    await tester.pumpAndSettle();
    expect(feed.feedHistory, isEmpty);
    await _slideToRecord(tester);
    await tester.pumpAndSettle();
    expect(feed.feedHistory, hasLength(1));
    expect(find.byKey(const ValueKey('feed-slide-undo')), findsOneWidget);
    expect(find.text('等待第一条记录'), findsNothing);
    _expectNoMaterialInteractions();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feed-slide-undo')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    _expectNoMaterialInteractions();
    await tester.ensureVisible(
      find.byKey(const ValueKey('interval-preset-120')),
    );
    await tester.tap(find.byKey(const ValueKey('interval-preset-120')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpAndSettle();
    expect(feed.feedIntervalMinutes, 120);
    expect(feed.nextFeedTime, feed.lastFeedTime!.add(const Duration(hours: 2)));
    await tester.tap(find.byKey(const ValueKey('nav-history')));
    await tester.pumpAndSettle();
    expect(find.text('喂奶记录'), findsOneWidget);
    _expectNoMaterialInteractions();
    final delete = find.byKey(
      ValueKey('delete-record-${feed.feedHistory.single.id}'),
    );
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.byType(AppMessageDialog), findsOneWidget);
    _expectNoMaterialInteractions();
    await tester.tap(find.byKey(const ValueKey('cancel-delete-record')));
    await tester.pumpAndSettle();
    expect(feed.feedHistory, hasLength(1));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-record')));
    await tester.pumpAndSettle();
    expect(feed.feedHistory, isEmpty);
    expect(feed.nextFeedTime, isNull);
    expect(find.byType(AppMessageDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await NotificationService().cancelAll();
  });

  testWidgets('Android native scheduling and audio start/stop', (tester) async {
    final notifications = NotificationService();
    addTearDown(notifications.cancelAll);
    await notifications.init();
    await notifications.scheduleFeedReminder(
      DateTime.now().add(const Duration(minutes: 3)),
      playSound: false,
    );
    final plugin = FlutterLocalNotificationsPlugin();
    expect(
      (await plugin.pendingNotificationRequests()).map((request) => request.id),
      contains(0),
    );
    // Replacing an existing alarm reads the persisted Gson cache in release.
    await notifications.scheduleFeedReminder(
      DateTime.now().add(const Duration(minutes: 6)),
      playSound: false,
    );
    final replaced = await plugin.pendingNotificationRequests();
    expect(replaced, hasLength(1));
    expect(replaced.single.id, 0);
    await notifications.cancelAll();
    expect(await plugin.pendingNotificationRequests(), isEmpty);
    await notifications.scheduleFeedReminder(
      DateTime.now().add(const Duration(minutes: 3)),
      playSound: false,
    );
    expect(await plugin.pendingNotificationRequests(), hasLength(1));
    await notifications.cancelAll();
    expect(await plugin.pendingNotificationRequests(), isEmpty);
    final audio = AudioService();
    addTearDown(audio.dispose);
    await audio.playReminder(loop: true);
    expect(audio.isPlaying, isTrue);
    await audio.stopReminder();
    expect(audio.isPlaying, isFalse);
    await audio.dispose();
  });

  testWidgets(
    'sliding a feeding stops native looping audio and replaces its reminder',
    (tester) async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedIntervalMinutes: 60,
        StorageKeys.soundEnabled: true,
        StorageKeys.soundLoopEnabled: true,
        StorageKeys.nightModeEnabled: false,
        StorageKeys.burnInProtectionEnabled: false,
        StorageKeys.feedHistory: jsonEncode([
          FeedRecord(time: now.subtract(const Duration(hours: 2))).toJson(),
        ]),
      });
      final storage = StorageService();
      await storage.setAcceptedPrivacyPolicyVersion(PrivacyPolicy.version);
      final audio = AudioService();
      final notifications = NotificationService();
      addTearDown(audio.dispose);
      addTearDown(notifications.cancelAll);
      await notifications.init();
      final feed = FeedProvider(
        storage: storage,
        audioService: audio,
        notificationService: notifications,
        clock: () => now,
        startTimer: false,
      );
      final settings = SettingsProvider(storage: storage);
      addTearDown(feed.dispose);
      addTearDown(settings.dispose);
      await Future.wait([feed.ready, settings.ready]);
      expect(feed.state, FeedState.alerting);
      expect(audio.isPlaying, isTrue);

      await tester.pumpWidget(
        FeedReminderApp(
          storage: storage,
          audioService: audio,
          notificationService: notifications,
          feedProvider: feed,
          settingsProvider: settings,
          enablePlatformEffects: false,
        ),
      );
      // Native looping playback can keep the live test binding scheduling
      // frames. Wait for the actual save result instead of global frame idle.
      await tester.pump(const Duration(milliseconds: 400));
      await _slideToRecord(tester);
      for (var attempt = 0; attempt < 50; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (!feed.isSaving &&
            feed.feedHistory.length == 2 &&
            find
                .byKey(const ValueKey('feed-slide-undo'))
                .evaluate()
                .isNotEmpty) {
          break;
        }
      }
      expect(feed.feedHistory, hasLength(2));
      expect(feed.state, FeedState.normal);
      expect(audio.isPlaying, isFalse);
      expect(find.byKey(const ValueKey('feed-slide-undo')), findsOneWidget);
      expect(
        await FlutterLocalNotificationsPlugin().pendingNotificationRequests(),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
