import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/time_utils.dart';

/// Places the current time between the last feeding and its next reminder.
class CountdownTimeline extends StatelessWidget {
  const CountdownTimeline({
    super.key,
    required this.lastFeedTime,
    required this.nextFeedTime,
    required this.now,
    required this.color,
  });

  final DateTime? lastFeedTime;
  final DateTime? nextFeedTime;
  final DateTime now;
  final Color color;

  double get _progress {
    final last = lastFeedTime;
    final next = nextFeedTime;
    if (last == null || next == null || !next.isAfter(last)) return 0;
    return (next.difference(now).inMicroseconds /
            next.difference(last).inMicroseconds)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final last = lastFeedTime;
    final next = nextFeedTime;
    if (last == null || next == null || !next.isAfter(last)) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final showDate =
        !DateUtils.isSameDay(last, now) || !DateUtils.isSameDay(next, now);
    String format(DateTime time) => showDate
        ? '${time.month}/${time.day} ${TimeUtils.formatTime(time)}'
        : TimeUtils.formatTime(time);
    final lastLabel = '上次 ${format(last)}';
    final nowLabel = '现在 ${format(now)}';
    final nextLabel = '${now.isBefore(next) ? '下一次' : '原定'} ${format(next)}';
    final nowStyle = DefaultTextStyle.of(context).style.copyWith(
      color: color,
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w500,
    );
    final endpointStyle = nowStyle.copyWith(
      color: highContrast ? palette.textPrimary : palette.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w400,
    );
    final position = 1 - _progress;
    const trackHeight = 16.0;

    return Semantics(
      label: '$lastLabel，$nowLabel，$nextLabel',
      // Read the timeline on demand without announcing every clock update.
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textPainter = TextPainter(
            text: TextSpan(text: nowLabel, style: nowStyle),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          final labelWidth = textPainter.width;
          textPainter.dispose();
          final inset = (trackHeight / 2).clamp(0.0, constraints.maxWidth / 2);
          final markerX = inset + (constraints.maxWidth - inset * 2) * position;
          // Center the label on the point until an endpoint needs the space.
          final labelLeft = (markerX - labelWidth / 2).clamp(
            0.0,
            constraints.maxWidth - labelWidth,
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(left: labelLeft),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    nowLabel,
                    style: nowStyle,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: trackHeight,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    position: position,
                    active: color,
                    elapsed: highContrast
                        ? palette.textSecondary
                        : palette.border,
                    background: palette.background,
                    highContrast: highContrast,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      lastLabel,
                      style: endpointStyle,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      nextLabel,
                      style: endpointStyle,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.position,
    required this.active,
    required this.elapsed,
    required this.background,
    required this.highContrast,
  });

  final double position;
  final Color active;
  final Color elapsed;
  final Color background;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final inset = (size.height / 2).clamp(0.0, size.width / 2);
    final start = Offset(inset, size.height / 2);
    final end = Offset(size.width - inset, size.height / 2);
    final current = Offset.lerp(start, end, position)!;
    final paint = Paint()
      ..color = elapsed
      ..strokeWidth = highContrast ? 2 : 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);
    paint.color = active;
    if (position < 1) canvas.drawLine(current, end, paint);

    final endpointRadius = highContrast ? 3.5 : 3.0;
    paint.color = elapsed;
    canvas.drawCircle(start, endpointRadius, paint);
    paint.color = active;
    canvas.drawCircle(end, endpointRadius, paint);
    paint.color = background;
    canvas.drawCircle(current, highContrast ? 7 : 6, paint);
    paint.color = active;
    canvas.drawCircle(current, highContrast ? 5 : 4, paint);
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.active != active ||
      oldDelegate.elapsed != elapsed ||
      oldDelegate.background != background ||
      oldDelegate.highContrast != highContrast;
}
