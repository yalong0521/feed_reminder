import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/models/home_widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 3, 12);
  HomeWidgetSnapshot snapshot(
    List<FeedRecord> records, {
    bool stopped = false,
  }) => HomeWidgetSnapshot.fromRecords(
    records: records,
    now: now,
    nextFeedTime: now.add(const Duration(minutes: 20)),
    reminderAcknowledged: stopped,
  );

  test('empty histories have no active reminder', () {
    final value = snapshot([], stopped: true);
    expect(value.latestTimeMs, isNull);
    expect(value.nextFeedTimeMs, isNull);
    expect(value.dayCount, 0);
    expect(value.dayTotalMl, 0);
    expect(value.reminderAcknowledged, isFalse);
  });

  test('clock rollback retains the saved current meal and its reminder', () {
    final future = FeedRecord(
      time: now.add(const Duration(hours: 1)),
      milkAmountMl: 120,
    );
    final value = snapshot([future], stopped: true);
    expect(value.latestTimeMs, future.time.millisecondsSinceEpoch);
    expect(value.latestMilkAmountMl, 120);
    expect(
      value.nextFeedTimeMs,
      now.add(const Duration(minutes: 20)).millisecondsSinceEpoch,
    );
    expect(value.dayCount, 0);
    expect(value.dayTotalMl, 0);
    expect(value.reminderAcknowledged, isTrue);
  });

  test(
    'uses local calendar day and ignores future records without changing input',
    () {
      final records = [
        FeedRecord(time: DateTime(2026, 10, 2, 23, 59), milkAmountMl: 180),
        FeedRecord(time: now, milkAmountMl: 0),
        FeedRecord(time: DateTime(2026, 10, 3).toUtc(), milkAmountMl: 90),
        FeedRecord(
          time: now.add(const Duration(minutes: 1)),
          milkAmountMl: 200,
        ),
      ];
      final value = snapshot(records);
      expect(value.dateKey, '2026-10-03');
      expect(value.zoneOffsetMinutes, now.timeZoneOffset.inMinutes);
      expect(
        value.latestTimeMs,
        now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
      expect(value.latestMilkAmountMl, 200);
      expect(value.dayCount, 2);
      expect(value.dayTotalMl, 90);
      expect(records.first.milkAmountMl, 180);
      expect(records.length, 4);
    },
  );

  test('latest record may be before today while today remains empty', () {
    final record = FeedRecord(
      time: DateTime(2026, 10, 2, 23),
      milkAmountMl: 120,
    );
    final value = snapshot([record]);
    expect(value.latestTimeMs, record.time.millisecondsSinceEpoch);
    expect(value.latestMilkAmountMl, 120);
    expect(value.dayCount, 0);
    expect(value.dayTotalMl, 0);
  });

  test(
    'forwards effective snooze deadline and independently marks stopped state',
    () {
      final value = snapshot([FeedRecord(time: now)], stopped: true);
      expect(
        value.nextFeedTimeMs,
        now.add(const Duration(minutes: 20)).millisecondsSinceEpoch,
      );
      expect(value.reminderAcknowledged, isTrue);
      expect(
        value.toMap().keys,
        unorderedEquals([
          'schemaVersion',
          'generatedAtMs',
          'dateKey',
          'zoneOffsetMinutes',
          'latestTimeMs',
          'latestTimeZoneOffsetMinutes',
          'latestMilkAmountMl',
          'dayTotalMl',
          'dayCount',
          'nextFeedTimeMs',
          'nextFeedTimeZoneOffsetMinutes',
          'reminderAcknowledged',
        ]),
      );
    },
  );

  test('uses the local timezone offset at each displayed instant', () {
    final meal = DateTime.utc(2026, 3, 8, 6, 30);
    final deadline = DateTime.utc(2026, 3, 8, 8, 30);
    final value = HomeWidgetSnapshot.fromRecords(
      records: [FeedRecord(time: meal)],
      now: DateTime.utc(2026, 3, 8, 7, 30),
      nextFeedTime: deadline,
      reminderAcknowledged: false,
    );
    expect(
      value.toMap()['latestTimeZoneOffsetMinutes'],
      meal.toLocal().timeZoneOffset.inMinutes,
    );
    expect(
      value.toMap()['nextFeedTimeZoneOffsetMinutes'],
      deadline.toLocal().timeZoneOffset.inMinutes,
    );
  });

  test(
    'midnight projection belongs to a new date even without new records',
    () {
      final record = FeedRecord(
        time: DateTime(2026, 10, 3, 23, 59),
        milkAmountMl: 100,
      );
      final value = HomeWidgetSnapshot.fromRecords(
        records: [record],
        now: DateTime(2026, 10, 4),
        nextFeedTime: DateTime(2026, 10, 4, 2),
        reminderAcknowledged: false,
      );
      expect(value.dateKey, '2026-10-04');
      expect(value.dayCount, 0);
      expect(value.latestMilkAmountMl, 100);
    },
  );
}
