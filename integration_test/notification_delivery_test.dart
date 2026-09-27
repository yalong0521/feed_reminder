import 'dart:io';

import 'package:feed_reminder/services/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<List<ActiveNotification>> _waitForActiveCount(
  FlutterLocalNotificationsPlugin plugin,
  int count,
  Stopwatch elapsed,
) async {
  var active = await plugin.getActiveNotifications();
  while (active.length != count &&
      elapsed.elapsed < const Duration(seconds: 15)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    active = await plugin.getActiveNotifications();
  }
  expect(
    active,
    hasLength(count),
    reason:
        'Android must report $count active notifications within 15 seconds.',
  );
  return active;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android scheduled reminder is delivered, replaced and cancelled', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    // NotificationService uses the app's real reminder ID and cancelAll. Refuse
    // physical devices before touching notifications or persisted alarm data.
    // Android's Build.IS_EMULATOR uses the same read-only system property.
    final emulator = await Process.run('/system/bin/getprop', ['ro.boot.qemu']);
    expect(emulator.exitCode, 0);
    expect(
      emulator.stdout.toString().trim(),
      '1',
      reason: 'Run this test only on the disposable emulator-5554 instance.',
    );

    final plugin = FlutterLocalNotificationsPlugin();
    final notifications = NotificationService(notifications: plugin);
    await notifications.init();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    expect(
      await android.areNotificationsEnabled(),
      isTrue,
      reason: 'Grant POST_NOTIFICATIONS on emulator-5554 before this test.',
    );
    expect(
      await android.canScheduleExactNotifications(),
      isTrue,
      reason:
          'Allow SCHEDULE_EXACT_ALARM on emulator-5554 before this test; '
          'the inexact fallback cannot validate a seconds-long deadline.',
    );

    // This checks delivery by AlarmManager and ScheduledNotificationReceiver
    // into NotificationManager. The test activity stays foreground, so it does
    // not claim coverage of background execution, Doze or reboot recovery.
    final elapsed = Stopwatch()..start();
    try {
      await notifications.cancelAll();
      expect(await plugin.pendingNotificationRequests(), isEmpty);
      await _waitForActiveCount(plugin, 0, elapsed);

      await notifications.scheduleFeedReminder(
        DateTime.now().add(const Duration(minutes: 1)),
        playSound: false,
      );
      expect(await plugin.pendingNotificationRequests(), hasLength(1));
      expect(await plugin.getActiveNotifications(), isEmpty);

      // Moving the same reminder from one minute away to three seconds must
      // replace the native alarm, not merely update its persisted request list.
      await notifications.scheduleFeedReminder(
        DateTime.now().add(const Duration(seconds: 3)),
        playSound: false,
      );
      final pending = await plugin.pendingNotificationRequests();
      expect(pending, hasLength(1));
      expect(pending.single.id, 0);

      final delivered = await _waitForActiveCount(plugin, 1, elapsed);
      expect(delivered.single.id, 0);
      expect(delivered.single.title, '到设定的喂奶时间了');
      expect(delivered.single.body, '留意宝宝的状态，准备好后记下这一餐。');
      expect(delivered.single.channelId, 'feeding_reminders_silent_v2');
      expect(await plugin.pendingNotificationRequests(), isEmpty);

      // A visible reminder and a newly scheduled reminder must both disappear.
      await notifications.scheduleFeedReminder(
        DateTime.now().add(const Duration(minutes: 1)),
        playSound: false,
      );
      expect(await plugin.pendingNotificationRequests(), hasLength(1));
      await notifications.cancelAll();
      expect(await plugin.pendingNotificationRequests(), isEmpty);
      await _waitForActiveCount(plugin, 0, elapsed);
      expect(tester.takeException(), isNull);
    } finally {
      await notifications.cancelAll();
      elapsed.stop();
    }
  });
}
