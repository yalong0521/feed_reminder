import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:feed_reminder/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const settingsChannel = MethodChannel('feed_reminder/notifications');
  late List<MethodCall> calls;
  late List<MethodCall> settingsCalls;
  bool exact = false;
  bool permissionRevoked = false;
  bool initializationFails = false;
  bool? notificationsEnabled = true;
  bool provisional = false;
  setUp(() {
    calls = [];
    settingsCalls = [];
    exact = false;
    permissionRevoked = false;
    initializationFails = false;
    notificationsEnabled = true;
    provisional = false;
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
            'areNotificationsEnabled' => notificationsEnabled,
            'checkPermissions' =>
              notificationsEnabled == null
                  ? null
                  : {
                      'isEnabled': notificationsEnabled,
                      'isProvisionalEnabled': provisional,
                    },
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, (call) async {
          settingsCalls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, null);
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test(
      '${platform.name} opens settings without requesting permission',
      () async {
        debugDefaultTargetPlatformOverride = platform;

        await NotificationService().openNotificationSettings();

        expect(settingsCalls.map((call) => call.method), [
          'openNotificationSettings',
        ]);
        expect(calls, isEmpty);
      },
    );

    test(
      '${platform.name} distinguishes denied, unknown, and restored access',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        switch (platform) {
          case TargetPlatform.android:
            AndroidFlutterLocalNotificationsPlugin.registerWith();
          case TargetPlatform.iOS:
            IOSFlutterLocalNotificationsPlugin.registerWith();
          case TargetPlatform.macOS:
            MacOSFlutterLocalNotificationsPlugin.registerWith();
          default:
            break;
        }
        final service = NotificationService();
        final deadline = DateTime.now().add(const Duration(hours: 1));
        notificationsEnabled = false;
        for (final operation in <Future<void> Function()>[
          () => service.showFeedReminder(),
          () => service.scheduleFeedReminder(deadline),
        ]) {
          await expectLater(
            operation(),
            throwsA(
              isA<PlatformException>().having(
                (error) => error.code,
                'code',
                'notification_permission_denied',
              ),
            ),
          );
        }
        expect(
          calls.where(
            (call) => call.method == 'show' || call.method == 'zonedSchedule',
          ),
          isEmpty,
        );
        await service.cancelAll();
        expect(calls.last.method, 'cancelAll');

        notificationsEnabled = null;
        await expectLater(
          service.scheduleFeedReminder(deadline),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'notification_status_unavailable',
            ),
          ),
        );
        notificationsEnabled = true;
        await service.scheduleFeedReminder(deadline);
        await service.showFeedReminder();
        expect(
          calls.where((call) => call.method == 'zonedSchedule'),
          hasLength(1),
        );
        expect(calls.where((call) => call.method == 'show'), hasLength(1));
        expect(
          calls.where(
            (call) =>
                call.method == 'requestPermissions' ||
                call.method == 'requestNotificationsPermission',
          ),
          isEmpty,
        );
      },
    );

    if (platform != TargetPlatform.android) {
      test(
        '${platform.name} accepts provisional notification authorization',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          if (platform == TargetPlatform.iOS) {
            IOSFlutterLocalNotificationsPlugin.registerWith();
          } else {
            MacOSFlutterLocalNotificationsPlugin.registerWith();
          }
          notificationsEnabled = false;
          provisional = true;
          await NotificationService().showFeedReminder(playSound: false);
          expect(calls.where((call) => call.method == 'show'), hasLength(1));
        },
      );
    }
  }

  test('unsupported platforms do not open notification settings', () async {
    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      await NotificationService().openNotificationSettings();
    }

    expect(settingsCalls, isEmpty);
    expect(calls, isEmpty);
  });

  test('notification settings errors reach the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(settingsChannel, (call) async {
          throw PlatformException(code: 'settings_unavailable');
        });

    await expectLater(
      NotificationService().openNotificationSettings(),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, isEmpty);
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
