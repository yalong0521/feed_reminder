import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/feed_provider.dart';
import '../utils/constants.dart';

class CountdownRing extends StatefulWidget {
  final Duration timeRemaining;
  final Duration timeElapsed;
  final int feedIntervalMinutes;
  final FeedState state;

  const CountdownRing({
    super.key,
    required this.timeRemaining,
    required this.timeElapsed,
    required this.feedIntervalMinutes,
    required this.state,
  });

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing>
    with TickerProviderStateMixin {
  late AnimationController _colorController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(CountdownRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == FeedState.alerting) {
      _pulseController.repeat(reverse: true);
    } else if (widget.state == FeedState.warning) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _colorController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * AppDimensions.ringSize;

    return AnimatedBuilder(
      animation: Listenable.merge([_colorController, _pulseController]),
      builder: (context, child) {
        return Transform.scale(
          scale: widget.state != FeedState.normal ? _pulseAnimation.value : 1.0,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RainbowRingPainter(
                progress: _calculateProgress(),
                colorAnimation: _colorController.value,
                state: widget.state,
              ),
              child: Center(child: _buildTimeDisplay()),
            ),
          ),
        );
      },
    );
  }

  double _calculateProgress() {
    final totalSeconds = widget.feedIntervalMinutes * 60;
    final elapsedSeconds = widget.timeElapsed.inSeconds;
    if (elapsedSeconds >= totalSeconds) return 1.0;
    return elapsedSeconds / totalSeconds;
  }

  Widget _buildTimeDisplay() {
    final isWarning = widget.state == FeedState.warning;
    final isAlerting = widget.state == FeedState.alerting;

    Color textColor = AppColors.textPrimary;
    if (isAlerting) {
      textColor = AppColors.accent;
    } else if (isWarning) {
      textColor = AppColors.orange;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.state == FeedState.alerting)
          const Text('🔔', style: TextStyle(fontSize: 32)),
        Text(
          _formatTime(widget.timeRemaining),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: textColor,
            fontFamily: 'Menlo',
          ),
        ),
      ],
    );
  }

  String _formatTime(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _RainbowRingPainter extends CustomPainter {
  final double progress;
  final double colorAnimation;
  final FeedState state;

  _RainbowRingPainter({
    required this.progress,
    required this.colorAnimation,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - AppDimensions.ringStrokeWidth) / 2;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppDimensions.ringStrokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // White inner circle with shadow for depth effect
    final innerCirclePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius - AppDimensions.ringStrokeWidth / 2, innerCirclePaint);

    // Rainbow arc - full 360 degree gradient
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: math.pi  *2,
      colors: AppColors.rainbowGradient,
    );

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppDimensions.ringStrokeWidth
      ..strokeCap = StrokeCap.round;

    // In alerting state, show solid color and stop animation (progress frozen at 100%)
    if (state == FeedState.alerting) {
      arcPaint.color = AppColors.accent;
    } else {
      arcPaint.shader = gradient.createShader(rect);
    }

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      rect,
      -math.pi / 2, // Start at top
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RainbowRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.colorAnimation != colorAnimation ||
        oldDelegate.state != state;
  }
}
