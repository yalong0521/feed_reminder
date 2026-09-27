import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:feed_reminder/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;
  bool exact = false;
  bool permissionRevoked = false;
  bool initializationFails = false;
  setUp(() {
    calls = [];
    exact = false;
    permissionRevoked = false;
    initializationFails = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize' && initializationFails) {
            initializationFails = false;
            throw PlatformException(code: 'temporarily_unavailable');
          }
          if (call.method == 'zonedSchedule' && permissionRevoked) {
            permissionRevoked = false;
            throw PlatformException(code: 'exact_alarms_not_permitted');
          }
          return switch (call.method) {
            'initialize' => true,
            'canScheduleExactNotifications' => exact,
            _ => null,
          };
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a failed initialization can recover for the next reminder', () async {
    final service = NotificationService();
    initializationFails = true;
    await expectLater(service.init(), throwsA(isA<PlatformException>()));

    await service.showFeedReminder();

    expect(calls.where((call) => call.method == 'initialize'), hasLength(2));
    expect(calls.where((call) => call.method == 'show'), hasLength(1));
  });

  test('concurrent notification operations share initialization', () async {
    final service = NotificationService();
    await Future.wait([service.init(), service.init()]);
    await service.showFeedReminder();

    expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
  });

  test('revoked exact permission retries as an inexact alarm', () async {
    exact = true;
    permissionRevoked = true;
    await NotificationService().scheduleFeedReminder(
      DateTime.now().add(const Duration(hours: 2)),
    );
    final schedules = calls
        .where((call) => call.method == 'zonedSchedule')
        .toList();
    expect(schedules, hasLength(2));
    final arguments = schedules.last.arguments as Map;
    expect(
      (arguments['platformSpecifics'] as Map)['scheduleMode'],
      'inexactAllowWhileIdle',
    );
  });

  test('muted native reminder uses a separate silent channel', () async {
    await NotificationService().showFeedReminder(playSound: false);
    final arguments =
        calls.singleWhere((call) => call.method == 'show').arguments as Map;
    final details = arguments['platformSpecifics'] as Map;
    expect(details['playSound'], isFalse);
    expect(details['enableVibration'], isFalse);
    expect(details['channelId'], 'feeding_reminders_silent_v2');
  });

  test(
    'native deadline falls back to an inexact alarm without permission',
    () async {
      await NotificationService().scheduleFeedReminder(
        DateTime.now().add(const Duration(hours: 2)),
      );
      final arguments =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      expect(arguments['timeZoneName'], 'UTC');
      expect(
        (arguments['platformSpecifics'] as Map)['scheduleMode'],
        'inexactAllowWhileIdle',
      );
    },
  );

  test(
    'native deadline uses exact alarm when permission is available',
    () async {
      exact = true;
      await NotificationService().scheduleFeedReminder(
        DateTime.now().add(const Duration(hours: 2)),
      );
      final arguments =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      expect(
        (arguments['platformSpecifics'] as Map)['scheduleMode'],
        'exactAllowWhileIdle',
      );
    },
  );
}
