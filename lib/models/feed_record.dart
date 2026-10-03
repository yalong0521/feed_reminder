class FeedRecord {
  static int _sequence = 0;
  static const int maxMilkAmountMl = 2000;

  final String id;
  final DateTime time;
  final Duration? intervalFromPrevious;

  /// Zero represents a feeding whose milk amount was not recorded.
  final int milkAmountMl;

  FeedRecord({
    String? id,
    required this.time,
    this.intervalFromPrevious,
    this.milkAmountMl = 0,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}' {
    validateMilkAmount(milkAmountMl);
  }

  static bool isValidMilkAmount(int amount) =>
      amount >= 0 && amount <= maxMilkAmountMl;

  static void validateMilkAmount(int amount) {
    if (!isValidMilkAmount(amount)) {
      throw ArgumentError.value(amount, 'milkAmountMl', '奶量应为 0–2000 mL');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time.millisecondsSinceEpoch,
      'intervalFromPrevious': intervalFromPrevious?.inMinutes,
      'milkAmountMl': milkAmountMl,
    };
  }

  factory FeedRecord.fromJson(Map<String, dynamic> json) {
    final timestamp = json['time'];
    final interval = json['intervalFromPrevious'];
    final milkAmount = json.containsKey('milkAmountMl')
        ? json['milkAmountMl']
        : 0;
    if (timestamp is! int ||
        (interval != null && interval is! int) ||
        milkAmount is! int ||
        !isValidMilkAmount(milkAmount)) {
      throw const FormatException('Invalid feeding record');
    }
    return FeedRecord(
      id: json['id'] is String ? json['id'] as String : null,
      time: DateTime.fromMillisecondsSinceEpoch(timestamp),
      milkAmountMl: milkAmount,
      intervalFromPrevious: interval != null
          ? Duration(minutes: interval as int)
          : null,
    );
  }
}
