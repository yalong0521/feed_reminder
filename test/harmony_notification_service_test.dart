import 'package:feed_reminder/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final harmony = TargetPlatform.values
      .where((platform) => platform.name == 'ohos')
      .firstOrNull;
  const channel = MethodChannel('feed_reminder/notifications');

  group(
    'HarmonyOS notification bridge',
    () {
      late List<MethodCall> calls;
      var initializationFails = false;

      setUp(() {
        calls = [];
        initializationFails = false;
        debugDefaultTargetPlatformOverride = harmony;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'initialize' && initializationFails) {
                initializationFails = false;
                throw PlatformException(code: 'temporarily_unavailable');
              }
              return null;
            });
      });

      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      test(
        'restoring reminders does not request notification permission',
        () async {
          final service = NotificationService();
          expect(service.isSupported, isTrue);
          await Future.wait([service.init(), service.init()]);
          await service.cancelAll();
          expect(calls.map((call) => call.method), ['initialize', 'cancelAll']);
          await service.requestPermissions();
          expect(calls.last.method, 'requestPermissions');
        },
      );

      test(
        'schedule preserves the instant rather than a local date string',
        () async {
          final when = DateTime.now().toUtc().add(const Duration(hours: 2));
          final service = NotificationService();
          await service.scheduleFeedReminder(when, playSound: false);
          await service.scheduleFeedReminder(when.toLocal(), playSound: true);
          final scheduled = calls
              .where((call) => call.method == 'schedule')
              .toList();
          expect(scheduled, hasLength(2));
          for (final call in scheduled) {
            expect(
              (call.arguments as Map)['epochMilliseconds'],
              when.millisecondsSinceEpoch,
            );
          }
          expect((scheduled.first.arguments as Map)['playSound'], isFalse);
          expect((scheduled.last.arguments as Map)['playSound'], isTrue);
        },
      );

      test('a deadline in the past is not scheduled', () async {
        final service = NotificationService();
        await service.scheduleFeedReminder(
          DateTime.now().subtract(const Duration(seconds: 1)),
        );
        expect(calls.where((call) => call.method == 'schedule'), isEmpty);
      });

      test(
        'failed initialization can recover before showing a quiet reminder',
        () async {
          initializationFails = true;
          final service = NotificationService();
          await expectLater(service.init(), throwsA(isA<PlatformException>()));
          await service.showFeedReminder(playSound: false);
          expect(
            calls.where((call) => call.method == 'initialize'),
            hasLength(2),
          );
          final arguments = calls.last.arguments as Map;
          expect(calls.last.method, 'show');
          expect(arguments['playSound'], isFalse);
          expect(arguments['title'], '到设定的喂奶时间了');
        },
      );

      test('native scheduling errors reach the reminder coordinator', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'schedule') {
                throw PlatformException(code: 'reminder_unavailable');
              }
              return null;
            });
        await expectLater(
          NotificationService().scheduleFeedReminder(
            DateTime.now().add(const Duration(minutes: 2)),
          ),
          throwsA(isA<PlatformException>()),
        );
      });
    },
    skip: harmony == null ? 'Run with tool/ohos.sh test on Flutter-OH.' : false,
  );
}
