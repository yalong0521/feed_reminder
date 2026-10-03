import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../theme/app_typography.dart';
import '../utils/time_utils.dart';

/// The overdue summary compares the original deadline with the current time.
class OverdueTimeline extends StatelessWidget {
  const OverdueTimeline({
    super.key,
    required this.deadline,
    required this.now,
    required this.color,
    this.compact = false,
  });

  final DateTime deadline;
  final DateTime now;
  final Color color;
  final bool compact;

  static ({String deadline, String now}) _labels(
    DateTime deadline,
    DateTime now,
  ) {
    final showDate = !DateUtils.isSameDay(deadline, now);
    String format(DateTime value) => showDate
        ? '${value.month}/${value.day} ${TimeUtils.formatTime(value)}'
        : TimeUtils.formatTime(value);
    return (deadline: '原定 ${format(deadline)}', now: '现在 ${format(now)}');
  }

  static TextStyle _labelStyle(BuildContext context) =>
      AppTypography.supporting(context).copyWith(
        color: MediaQuery.highContrastOf(context)
            ? AppPalette.of(context).textPrimary
            : AppPalette.of(context).textSecondary,
      );

  /// Includes the track, label gap and any wrapping caused by width or text size.
  static double requiredHeight(
    BuildContext context, {
    required DateTime deadline,
    required DateTime now,
    required double width,
  }) {
    final labels = _labels(deadline, now);
    final inherited = DefaultTextStyle.of(context);
    double height(String label) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: inherited.style.merge(_labelStyle(context)),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textHeightBehavior: inherited.textHeightBehavior,
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: math.max(0, (width - 16) / 2));
      final result = painter.height;
      painter.dispose();
      return result;
    }

    return 12 + 8 + math.max(height(labels.deadline), height(labels.now));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final labels = _labels(deadline, now);
    final deadlineLabel = labels.deadline;
    final nowLabel = labels.now;
    final style = _labelStyle(context);

    return Semantics(
      label: '$deadlineLabel，$nowLabel',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            SizedBox(
              height: 12,
              child: CustomPaint(
                painter: _OverdueTimelinePainter(
                  color: color,
                  border: highContrast ? p.textSecondary : p.border,
                  highContrast: highContrast,
                ),
              ),
            ),
          if (!compact) const SizedBox(height: 8),
          if (compact)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 4,
              children: [
                Text(deadlineLabel, style: style, textAlign: TextAlign.center),
                Text(nowLabel, style: style, textAlign: TextAlign.center),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(deadlineLabel, style: style)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    nowLabel,
                    style: style,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OverdueTimelinePainter extends CustomPainter {
  const _OverdueTimelinePainter({
    required this.color,
    required this.border,
    required this.highContrast,
  });

  final Color color;
  final Color border;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = (size.height / 2).clamp(0.0, size.width / 2);
    final start = Offset(radius, size.height / 2);
    final end = Offset(size.width - radius, size.height / 2);
    final paint = Paint()
      ..color = border
      ..strokeWidth = highContrast ? 2.5 : 1.5
      ..strokeCap = StrokeCap.round;
    // The neutral lead-in separates the reference point from elapsed overtime.
    final boundary = Offset.lerp(start, end, .28)!;
    canvas.drawLine(start, boundary, paint);
    paint.color = color;
    canvas.drawLine(boundary, end, paint);
    canvas.drawCircle(end, highContrast ? 4.5 : 4, paint);
    paint.color = border;
    canvas.drawCircle(start, highContrast ? 3.5 : 3, paint);
  }

  @override
  bool shouldRepaint(_OverdueTimelinePainter oldDelegate) =>
      color != oldDelegate.color ||
      border != oldDelegate.border ||
      highContrast != oldDelegate.highContrast;
}
