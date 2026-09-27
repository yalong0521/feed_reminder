import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_glass.dart';
import 'package:feed_reminder/widgets/feed_button.dart';

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

  setUpAll(() async {
    // Match production startup so this smoke test renders the real glass
    // engine instead of silently exercising only solid fallback surfaces.
    await AppGlass.initialize();
    expect(AppGlass.isReady, isTrue);
  });

  testWidgets('Android feeding, navigation and settings smoke test', (
    tester,
  ) async {
    // Exercise the real engine/plugins without touching the device's stored records.
    SharedPreferences.setMockInitialValues({'burnInProtectionEnabled': false});
    await tester.pumpWidget(
      const FeedReminderApp(enablePlatformEffects: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('等待第一条记录'), findsOneWidget);
    _expectNoMaterialInteractions();
    final dock = find.byKey(const ValueKey('feed-control-dock'));
    expect(
      find.descendant(of: dock, matching: find.byType(GlassContainer)),
      findsWidgets,
    );

    // An initialized shader must still yield to system accessibility. Retain
    // this check here because unit tests intentionally omit shader startup.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNothing);
    final solidDock = tester.widget<Material>(
      find.descendant(of: dock, matching: find.byType(Material)).first,
    );
    expect(solidDock.color, AppPalette.of(tester.element(dock)).surface);
    expect(solidDock.color!.a, 1);
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
      find.descendant(of: dock, matching: find.byType(GlassContainer)),
      findsWidgets,
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
}
