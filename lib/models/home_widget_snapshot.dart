import 'feed_record.dart';

/// A small, committed-data projection for the HarmonyOS service widget.
///
/// The date and UTC offset travel with totals so a suspended widget never has
/// to label an old aggregate as today's data. The latest saved record stays
/// consistent with the timer after a clock rollback; future records do not
/// contribute to the day's aggregate until their recorded instant has passed.
class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.generatedAtMs,
    required this.dateKey,
    required this.zoneOffsetMinutes,
    required this.latestTimeMs,
    required this.latestMilkAmountMl,
    required this.dayTotalMl,
    required this.dayCount,
    required this.nextFeedTimeMs,
    required this.reminderAcknowledged,
    this.latestTimeZoneOffsetMinutes,
    this.nextFeedTimeZoneOffsetMinutes,
  });

  factory HomeWidgetSnapshot.fromRecords({
    required List<FeedRecord> records,
    required DateTime now,
    required DateTime? nextFeedTime,
    required bool reminderAcknowledged,
  }) {
    final localNow = now.toLocal();
    FeedRecord? latest;
    var total = 0;
    var count = 0;
    for (final record in records) {
      if (latest == null || record.time.isAfter(latest.time)) latest = record;
      if (record.time.isAfter(now)) continue;
      final local = record.time.toLocal();
      if (local.year == localNow.year &&
          local.month == localNow.month &&
          local.day == localNow.day) {
        total += record.milkAmountMl;
        count++;
      }
    }
    return HomeWidgetSnapshot(
      generatedAtMs: now.millisecondsSinceEpoch,
      dateKey:
          '${localNow.year.toString().padLeft(4, '0')}-'
          '${localNow.month.toString().padLeft(2, '0')}-'
          '${localNow.day.toString().padLeft(2, '0')}',
      zoneOffsetMinutes: localNow.timeZoneOffset.inMinutes,
      latestTimeMs: latest?.time.millisecondsSinceEpoch,
      latestTimeZoneOffsetMinutes: latest?.time
          .toLocal()
          .timeZoneOffset
          .inMinutes,
      latestMilkAmountMl: latest?.milkAmountMl ?? 0,
      dayTotalMl: total,
      dayCount: count,
      nextFeedTimeMs: latest == null
          ? null
          : nextFeedTime?.millisecondsSinceEpoch,
      nextFeedTimeZoneOffsetMinutes: latest == null
          ? null
          : nextFeedTime?.toLocal().timeZoneOffset.inMinutes,
      reminderAcknowledged: latest != null && reminderAcknowledged,
    );
  }

  final int generatedAtMs;
  final String dateKey;
  final int zoneOffsetMinutes;
  final int? latestTimeMs;
  // The offset can change between a recorded meal, now, and the next reminder
  // across daylight-saving transitions. Each instant keeps its own local time.
  final int? latestTimeZoneOffsetMinutes;
  final int latestMilkAmountMl;
  final int dayTotalMl;
  final int dayCount;
  final int? nextFeedTimeMs;
  final int? nextFeedTimeZoneOffsetMinutes;
  final bool reminderAcknowledged;

  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'generatedAtMs': generatedAtMs,
    'dateKey': dateKey,
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'latestTimeMs': latestTimeMs,
    'latestTimeZoneOffsetMinutes': latestTimeZoneOffsetMinutes,
    'latestMilkAmountMl': latestMilkAmountMl,
    'dayTotalMl': dayTotalMl,
    'dayCount': dayCount,
    'nextFeedTimeMs': nextFeedTimeMs,
    'nextFeedTimeZoneOffsetMinutes': nextFeedTimeZoneOffsetMinutes,
    'reminderAcknowledged': reminderAcknowledged,
  };
}
