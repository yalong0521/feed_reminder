import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

class TimeDisplay extends StatelessWidget {
  final Duration timeElapsed;
  final DateTime? lastFeedTime;

  const TimeDisplay({
    super.key,
    required this.timeElapsed,
    this.lastFeedTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${AppStrings.timeElapsed}: ${TimeUtils.formatDuration(timeElapsed)}',
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.textLight,
            fontFamily: 'Menlo',
          ),
        ),
        const SizedBox(height: 8),
        if (lastFeedTime != null)
          Text(
            '${AppStrings.lastFeed}: ${_formatLastFeedTime(lastFeedTime!)}',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textLight,
              fontFamily: 'Menlo',
            ),
          ),
      ],
    );
  }

  String _formatLastFeedTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(time.year, time.month, time.day);

    if (dateOnly == today) {
      return TimeUtils.formatTime(time);
    } else {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${TimeUtils.formatTime(time)}';
    }
  }
}
