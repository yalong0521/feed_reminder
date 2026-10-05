import 'dart:async';

import 'package:feed_reminder/models/home_widget_snapshot.dart';
import 'package:feed_reminder/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/home_widget');
  late List<MethodCall> calls;

  HomeWidgetSnapshot snapshot({
    int generatedAt = 1000,
    String date = '2026-10-03',
    int offset = 480,
    int total = 120,
  }) => HomeWidgetSnapshot(
    generatedAtMs: generatedAt,
    dateKey: date,
    zoneOffsetMinutes: offset,
    latestTimeMs: 500,
    latestMilkAmountMl: total,
    dayTotalMl: total,
    dayCount: 1,
    nextFeedTimeMs: 2000,
    reminderAcknowledged: false,
  );

  setUp(() {
    calls = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test(
    'unsupported platforms never access native data or pending actions',
    () async {
      final service = HomeWidgetService(channel: channel, supported: false);
      await service.update(snapshot());
      expect(await service.consumePendingAction(), isNull);
      service.dispose();
      expect(calls, isEmpty);
    },
  );

  test(
    'ignores ticking timestamps but republishes new date and time zone',
    () async {
      final service = HomeWidgetService(channel: channel, supported: true);
      addTearDown(service.dispose);
      await service.update(snapshot());
      await service.update(snapshot(generatedAt: 2000));
      await service.update(snapshot(date: '2026-10-04'));
      await service.update(snapshot(date: '2026-10-04', offset: 420));
      expect(calls, hasLength(3));
      expect((calls.last.arguments as Map)['zoneOffsetMinutes'], 420);
    },
  );

  test('failed writes are isolated and identical data can retry', () async {
    var fail = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'widget_update_failed');
      return null;
    });
    final service = HomeWidgetService(channel: channel, supported: true);
    addTearDown(service.dispose);
    await service.update(snapshot());
    expect(service.lastError, isNotNull);
    fail = false;
    await service.update(snapshot(generatedAt: 2000));
    expect(calls, hasLength(2));
    expect(service.lastError, isNull);
  });

  test(
    'a partial native failure invalidates the cache before undoing to old data',
    () async {
      var visibleTotal = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        visibleTotal = (call.arguments as Map)['dayTotalMl'] as int;
        if (visibleTotal == 180) {
          // Native persisted B, then one card update failed.
          throw PlatformException(code: 'widget_update_failed');
        }
        return null;
      });
      final service = HomeWidgetService(channel: channel, supported: true);
      addTearDown(service.dispose);
      await service.update(snapshot(total: 120));
      await service.update(snapshot(total: 180));
      expect(visibleTotal, 180);
      expect(service.lastError, isNotNull);
      await service.update(snapshot(total: 120, generatedAt: 3000));
      expect(calls, hasLength(3));
      expect(visibleTotal, 120);
      expect(service.lastError, isNull);
    },
  );

  test(
    'overlapping updates are serialized and newest committed snapshot wins',
    () async {
      final firstWrite = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (calls.length == 1) await firstWrite.future;
        return null;
      });
      final service = HomeWidgetService(channel: channel, supported: true);
      addTearDown(service.dispose);
      final first = service.update(snapshot(total: 90));
      final second = service.update(snapshot(total: 120));
      final duplicate = service.update(snapshot(total: 120, generatedAt: 2000));
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      firstWrite.complete();
      await Future.wait([first, second, duplicate]);
      expect(calls, hasLength(2));
      expect((calls.last.arguments as Map)['dayTotalMl'], 120);
    },
  );

  test(
    'only consumes known actions and tolerates a missing native channel',
    () async {
      var action = 'record_feed';
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => action,
      );
      final service = HomeWidgetService(channel: channel, supported: true);
      addTearDown(service.dispose);
      expect(await service.consumePendingAction(), 'record_feed');
      action = 'open_timer';
      expect(await service.consumePendingAction(), 'open_timer');
      action = 'write_record';
      expect(await service.consumePendingAction(), isNull);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      expect(await service.consumePendingAction(), isNull);
      await service.update(snapshot());
      expect(service.lastError, isNotNull);
    },
  );

  test(
    'disposing prevents queued and later updates without disturbing an in-flight write',
    () async {
      final write = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        await write.future;
        return null;
      });
      final service = HomeWidgetService(channel: channel, supported: true);
      final first = service.update(snapshot(total: 90));
      final queued = service.update(snapshot(total: 120));
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      write.complete();
      await Future.wait([first, queued]);
      await service.update(snapshot(total: 180));
      expect(calls, hasLength(1));
      expect(await service.consumePendingAction(), isNull);
    },
  );

  test(
    'native wake-up and startup polling consume a request only once',
    () async {
      String? pending = 'record_feed';
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method != 'getPendingAction') return null;
        final value = pending;
        pending = null;
        return value;
      });
      final received = <String>[];
      final service = HomeWidgetService(channel: channel, supported: true);
      addTearDown(service.dispose);
      Future<void> wake() async {
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('widgetAction'),
          ),
          null,
        );
      }

      // Before the consented shell installs a handler, preserve the launch action.
      await wake();
      expect(pending, 'record_feed');
      service.setActionHandler(received.add);
      final startup = service.consumePendingAction();
      final signal = wake();
      final launch = await startup;
      if (launch != null) received.add(launch);
      await signal;
      expect(received, ['record_feed']);

      pending = 'open_timer';
      await wake();
      await wake();
      expect(received, ['record_feed', 'open_timer']);
    },
  );
}
