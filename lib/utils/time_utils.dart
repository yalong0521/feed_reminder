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

  static String formatInterval(Duration interval) {
    final hours = interval.inHours;
    final minutes = interval.inMinutes % 60;
    if (hours > 0) {
      return '+${hours}h${minutes.toString().padLeft(2, '0')}m';
    }
    return '+${minutes}m';
  }

  static String getDateGroup(DateTime date, {DateTime? now}) {
    now ??= DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return '今天';
    } else if (dateOnly == yesterday) {
      return '昨天';
    } else {
      return '更早';
    }
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

  static Duration timeSince(DateTime from) {
    return DateTime.now().difference(from);
  }
}
