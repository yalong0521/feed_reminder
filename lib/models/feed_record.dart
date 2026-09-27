class FeedRecord {
  static int _sequence = 0;

  final String id;
  final DateTime time;
  final Duration? intervalFromPrevious;

  FeedRecord({String? id, required this.time, this.intervalFromPrevious})
    : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time.millisecondsSinceEpoch,
      'intervalFromPrevious': intervalFromPrevious?.inMinutes,
    };
  }

  factory FeedRecord.fromJson(Map<String, dynamic> json) {
    final timestamp = json['time'];
    final interval = json['intervalFromPrevious'];
    if (timestamp is! int || (interval != null && interval is! int)) {
      throw const FormatException('Invalid feeding record');
    }
    return FeedRecord(
      id: json['id'] is String ? json['id'] as String : null,
      time: DateTime.fromMillisecondsSinceEpoch(timestamp),
      intervalFromPrevious: interval != null
          ? Duration(minutes: interval as int)
          : null,
    );
  }
}
