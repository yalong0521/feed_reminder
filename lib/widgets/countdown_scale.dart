import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// A quiet visual measure of the remaining feeding interval.
class CountdownScale extends StatelessWidget {
  const CountdownScale({
    super.key,
    required this.remaining,
    required this.interval,
    required this.color,
  });

  final Duration remaining;
  final Duration interval;
  final Color color;

  double get progress => interval.inMicroseconds <= 0
      ? 0
      : (remaining.inMicroseconds / interval.inMicroseconds).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      // The adjacent clock already exposes the exact remaining time.
      child: SizedBox(
        height: 24,
        width: double.infinity,
        child: CustomPaint(
          painter: _ScalePainter(
            progress: progress,
            active: color,
            inactive: AppPalette.of(
              context,
            ).textTertiary.withValues(alpha: highContrast ? .65 : .28),
            strokeWidth: highContrast ? 2 : 1.5,
          ),
        ),
      ),
    );
  }
}

class _ScalePainter extends CustomPainter {
  const _ScalePainter({
    required this.progress,
    required this.active,
    required this.inactive,
    required this.strokeWidth,
  });

  final double progress;
  final Color active;
  final Color inactive;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= strokeWidth || size.height <= 0) return;
    const count = 31;
    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final spacing = (size.width - strokeWidth) / (count - 1);
    for (var i = 0; i < count; i++) {
      final height = i == count ~/ 2 ? 24.0 : (i % 5 == 0 ? 12.0 : 8.0);
      final x = strokeWidth / 2 + i * spacing;
      final halfHeight = height.clamp(0.0, size.height - strokeWidth) / 2;
      // Only the boundary tick fades as the lit portion recedes from the right,
      // without a continuously running animation or a separate timer.
      final coverage = (progress * count - i).clamp(0.0, 1.0);
      paint.color = Color.lerp(inactive, active, coverage)!;
      canvas.drawLine(
        Offset(x, size.height / 2 - halfHeight),
        Offset(x, size.height / 2 + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScalePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.inactive != inactive ||
      oldDelegate.strokeWidth != strokeWidth;
}
