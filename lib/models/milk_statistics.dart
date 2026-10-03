import 'feed_record.dart';

/// One local calendar day, including days without any feeding records.
class MilkDayStatistics {
  const MilkDayStatistics({
    required this.date,
    required this.totalMl,
    required this.feedCount,
    required this.unrecordedCount,
  });

  final DateTime date;
  final int totalMl;
  final int feedCount;
  final int unrecordedCount;

  int get recordedCount => feedCount - unrecordedCount;
}

/// Descriptive totals for an inclusive local-calendar window ending today.
/// A zero amount means unknown, and never contributes a guessed milk volume.
class MilkStatistics {
  MilkStatistics._(this.days);

  final List<MilkDayStatistics> days;

  int get totalMl => days.fold(0, (total, day) => total + day.totalMl);
  int get feedCount => days.fold(0, (total, day) => total + day.feedCount);
  int get unrecordedCount =>
      days.fold(0, (total, day) => total + day.unrecordedCount);
  int get recordedCount => feedCount - unrecordedCount;
  double get dailyAverageMl => totalMl / days.length;

  factory MilkStatistics.aggregate(
    Iterable<FeedRecord> records, {
    required DateTime now,
    required int dayCount,
  }) {
    if (dayCount < 1) throw ArgumentError.value(dayCount, 'dayCount');
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    // Construct calendar dates instead of subtracting 24-hour durations, so
    // daylight-saving transitions still produce one bucket per local day.
    final dates = List.generate(
      dayCount,
      (index) =>
          DateTime(today.year, today.month, today.day - dayCount + 1 + index),
    );
    final amounts = <DateTime, int>{};
    final counts = <DateTime, int>{};
    final unrecorded = <DateTime, int>{};
    for (final record in records) {
      final time = record.time.toLocal();
      if (time.isAfter(localNow) || time.isBefore(dates.first)) continue;
      final date = DateTime(time.year, time.month, time.day);
      counts.update(date, (value) => value + 1, ifAbsent: () => 1);
      amounts.update(
        date,
        (value) => value + record.milkAmountMl,
        ifAbsent: () => record.milkAmountMl,
      );
      if (record.milkAmountMl == 0) {
        unrecorded.update(date, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return MilkStatistics._(
      List.unmodifiable([
        for (final date in dates)
          MilkDayStatistics(
            date: date,
            totalMl: amounts[date] ?? 0,
            feedCount: counts[date] ?? 0,
            unrecordedCount: unrecorded[date] ?? 0,
          ),
      ]),
    );
  }
}
