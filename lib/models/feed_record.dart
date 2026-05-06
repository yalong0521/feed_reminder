class FeedRecord {
  final DateTime time;
  final Duration? intervalFromPrevious;

  FeedRecord({
    required this.time,
    this.intervalFromPrevious,
  });

  Map<String, dynamic> toJson() {
    return {
      'time': time.millisecondsSinceEpoch,
      'intervalFromPrevious': intervalFromPrevious?.inMinutes,
    };
  }

  factory FeedRecord.fromJson(Map<String, dynamic> json) {
    return FeedRecord(
      time: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
      intervalFromPrevious: json['intervalFromPrevious'] != null
          ? Duration(minutes: json['intervalFromPrevious'] as int)
          : null,
    );
  }
}
