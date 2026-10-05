import 'feed_record.dart';

/// A one-cycle reminder override. It never changes feeding history or settings.
class DeferredReminder {
  const DeferredReminder({
    required this.recordId,
    required this.recordTime,
    required this.intervalMinutes,
    required this.remindAt,
  });

  final String recordId;
  final DateTime recordTime;
  final int intervalMinutes;
  final DateTime remindAt;

  bool matches(FeedRecord? record, int interval) =>
      record?.id == recordId &&
      record?.time.millisecondsSinceEpoch ==
          recordTime.millisecondsSinceEpoch &&
      interval == intervalMinutes;

  Map<String, Object> toJson() => {
    'recordId': recordId,
    'recordTime': recordTime.millisecondsSinceEpoch,
    'intervalMinutes': intervalMinutes,
    'remindAt': remindAt.millisecondsSinceEpoch,
  };

  factory DeferredReminder.fromJson(Map<String, dynamic> json) {
    final id = json['recordId'];
    final time = json['recordTime'];
    final interval = json['intervalMinutes'];
    final deadline = json['remindAt'];
    if (id is! String ||
        id.isEmpty ||
        time is! int ||
        interval is! int ||
        interval <= 0 ||
        deadline is! int) {
      throw const FormatException('延后提醒格式无法读取');
    }
    final original = DateTime.fromMillisecondsSinceEpoch(time);
    final remindAt = DateTime.fromMillisecondsSinceEpoch(deadline);
    if (!remindAt.isAfter(original.add(Duration(minutes: interval)))) {
      throw const FormatException('延后提醒时间无效');
    }
    return DeferredReminder(
      recordId: id,
      recordTime: original,
      intervalMinutes: interval,
      remindAt: remindAt,
    );
  }
}
