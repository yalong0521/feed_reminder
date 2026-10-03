import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/models/milk_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar window includes boundary, zero days and unknown feeds', () {
    final now = DateTime(2026, 10, 3, 12);
    final statistics = MilkStatistics.aggregate(
      [
        FeedRecord(time: DateTime(2026, 9, 26, 23, 59), milkAmountMl: 1000),
        FeedRecord(time: DateTime(2026, 9, 27), milkAmountMl: 100),
        FeedRecord(time: DateTime(2026, 10, 1, 9), milkAmountMl: 120),
        FeedRecord(time: DateTime(2026, 10, 1, 12)),
        FeedRecord(time: now, milkAmountMl: 130),
        FeedRecord(
          time: now.add(const Duration(seconds: 1)),
          milkAmountMl: 900,
        ),
        FeedRecord(time: DateTime(2026, 10, 4), milkAmountMl: 800),
      ],
      now: now,
      dayCount: 7,
    );

    expect(statistics.days, hasLength(7));
    expect(statistics.days.first.date, DateTime(2026, 9, 27));
    expect(statistics.days.last.date, DateTime(2026, 10, 3));
    expect(statistics.days.map((day) => day.totalMl), [
      100,
      0,
      0,
      0,
      120,
      0,
      130,
    ]);
    expect(statistics.totalMl, 350);
    expect(statistics.dailyAverageMl, 50);
    expect(statistics.feedCount, 4);
    expect(statistics.recordedCount, 3);
    expect(statistics.unrecordedCount, 1);
    expect(statistics.days[4].feedCount, 2);
    expect(statistics.days[4].unrecordedCount, 1);
  });

  test(
    '30-day windows cross leap days and year boundaries by calendar date',
    () {
      final leap = MilkStatistics.aggregate(
        [],
        now: DateTime(2024, 3, 1),
        dayCount: 30,
      );
      expect(leap.days.first.date, DateTime(2024, 2, 1));
      expect(leap.days[28].date, DateTime(2024, 2, 29));
      expect(leap.days.last.date, DateTime(2024, 3, 1));
      final newYear = MilkStatistics.aggregate(
        [],
        now: DateTime(2026, 1, 2),
        dayCount: 7,
      );
      expect(newYear.days.first.date, DateTime(2025, 12, 27));
      expect(newYear.days.map((day) => day.date).toSet(), hasLength(7));
      expect(newYear.dailyAverageMl, 0);
      expect(newYear.feedCount, 0);
    },
  );

  test('UTC timestamps are grouped into the equivalent local calendar day', () {
    final localTime = DateTime(2026, 10, 3, 0, 30);
    final statistics = MilkStatistics.aggregate(
      [FeedRecord(time: localTime.toUtc(), milkAmountMl: 80)],
      now: DateTime(2026, 10, 3, 12).toUtc(),
      dayCount: 7,
    );
    expect(statistics.days.last.date, DateTime(2026, 10, 3));
    expect(statistics.days.last.totalMl, 80);
    expect(statistics.days.last.feedCount, 1);
  });

  test(
    'legacy zero records count as unknown without inventing milk volume',
    () {
      final now = DateTime(2026, 10, 3);
      final legacy = FeedRecord.fromJson({'time': now.millisecondsSinceEpoch});
      final statistics = MilkStatistics.aggregate(
        [legacy],
        now: now,
        dayCount: 7,
      );
      expect(statistics.totalMl, 0);
      expect(statistics.recordedCount, 0);
      expect(statistics.feedCount, 1);
      expect(statistics.unrecordedCount, 1);
      expect(statistics.dailyAverageMl, 0);
    },
  );

  test('rejects a window without days', () {
    expect(
      () =>
          MilkStatistics.aggregate([], now: DateTime(2026, 10, 3), dayCount: 0),
      throwsArgumentError,
    );
  });
}
