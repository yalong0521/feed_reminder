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

/// Descriptive totals for an inclusive local-calendar window.
/// A zero amount means unknown, and never contributes a guessed milk volume.
class MilkStatistics {
  MilkStatistics._(this.days, this.averageInterval);

  static const maxCustomDays = 366;

  final List<MilkDayStatistics> days;

  /// Only adjacent records inside this window count, including unknown milk
  /// amounts and simultaneous feeds. The first feed has no incoming interval.
  final Duration? averageInterval;

  int get totalMl => days.fold(0, (total, day) => total + day.totalMl);
  int get feedCount => days.fold(0, (total, day) => total + day.feedCount);
  int get unrecordedCount =>
      days.fold(0, (total, day) => total + day.unrecordedCount);
  int get recordedCount => feedCount - unrecordedCount;
  double get dailyAverageMl => totalMl / days.length;
  double? get averageMealMl =>
      recordedCount == 0 ? null : totalMl / recordedCount;

  factory MilkStatistics.aggregate(
    Iterable<FeedRecord> records, {
    required DateTime now,
    int? dayCount,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final DateTime start;
    final DateTime end;
    if (dayCount != null) {
      if (dayCount < 1 || startDate != null || endDate != null) {
        throw ArgumentError('Use a positive dayCount or a start and end date.');
      }
      start = DateTime(today.year, today.month, today.day - dayCount + 1);
      end = today;
    } else {
      if (startDate == null || endDate == null) {
        throw ArgumentError('Both startDate and endDate are required.');
      }
      start = _localDate(startDate);
      end = _localDate(endDate);
      final count = _calendarDays(start, end);
      if (count < 1 || count > maxCustomDays || end.isAfter(today)) {
        throw ArgumentError('Choose 1–366 calendar days ending by today.');
      }
    }
    // Construct calendar dates instead of subtracting 24-hour durations, so
    // daylight-saving transitions still produce one bucket per local day.
    final dates = List.generate(
      _calendarDays(start, end),
      (index) => DateTime(start.year, start.month, start.day + index),
    );
    final amounts = <DateTime, int>{};
    final counts = <DateTime, int>{};
    final unrecorded = <DateTime, int>{};
    DateTime? firstTime;
    DateTime? lastTime;
    var timeCount = 0;
    final afterEnd = DateTime(end.year, end.month, end.day + 1);
    for (final record in records) {
      final time = record.time.toLocal();
      if (time.isAfter(localNow) ||
          time.isBefore(start) ||
          !time.isBefore(afterEnd)) {
        continue;
      }
      timeCount++;
      if (firstTime == null || time.isBefore(firstTime)) firstTime = time;
      if (lastTime == null || time.isAfter(lastTime)) lastTime = time;
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
    // Adjacent differences telescope to last - first. A single pass finds the
    // bounds without copying/sorting a potentially large imported history.
    final averageInterval = timeCount < 2
        ? null
        : Duration(
            microseconds:
                (lastTime!.difference(firstTime!).inMicroseconds /
                        (timeCount - 1))
                    .round(),
          );
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
      averageInterval,
    );
  }
}

DateTime _localDate(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

int _calendarDays(DateTime start, DateTime end) =>
    DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
    1;
