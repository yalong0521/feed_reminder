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
            '${AppStrings.lastFeed}: ${TimeUtils.formatTime(lastFeedTime!)}',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textLight,
              fontFamily: 'Menlo',
            ),
          ),
      ],
    );
  }
}
