class TimeUtils {
  static String formatDuration(Duration duration) {
    if (duration.isNegative) duration = Duration.zero;
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String formatInterval(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$remainder 分钟';
    if (remainder == 0) return '$hours 小时';
    return '$hours 小时 $remainder 分钟';
  }

  static bool isValidTime(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    return match != null &&
        int.parse(match[1]!) < 24 &&
        int.parse(match[2]!) < 60;
  }

  /// Start is inclusive, end exclusive. Equal times represent an empty window.
  static bool isInNightMode(String startTime, String endTime, {DateTime? now}) {
    if (!isValidTime(startTime) || !isValidTime(endTime)) return false;
    now ??= DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final startParts = startTime.split(':');
    final endParts = endTime.split(':');
    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    if (startMinutes > endMinutes) {
      // Overnight (e.g., 22:00 to 06:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    } else {
      // Same day (e.g., 02:00 to 06:00)
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
  }
}
