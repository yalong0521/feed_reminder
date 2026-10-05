import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/time_utils.dart';
import 'countdown_text.dart';

/// Elapsed minutes read differently from a clock counting down to a deadline.
class OverdueDuration extends StatefulWidget {
  const OverdueDuration({
    super.key,
    required this.duration,
    required this.color,
    this.fontSize = 128,
    this.unitFontSize = 30,
    this.pulse = false,
  });

  final Duration duration;
  final Color color;
  final double fontSize;
  final double unitFontSize;
  final bool pulse;

  static TextStyle _labelStyle(Color color, double fontSize) => TextStyle(
    color: color,
    fontSize: fontSize,
    height: 1,
    fontWeight: FontWeight.w600,
  );

  /// Measures the unscaled baseline row using the same styles as its texts.
  static Size measure(
    BuildContext context, {
    required Duration duration,
    required double fontSize,
    required double unitFontSize,
  }) => _measureLayout(
    context,
    duration: duration,
    fontSize: fontSize,
    unitFontSize: unitFontSize,
  ).size;

  static ({Size size, double sideWidth}) _measureLayout(
    BuildContext context, {
    required Duration duration,
    required double fontSize,
    required double unitFontSize,
  }) {
    final inherited = DefaultTextStyle.of(context);
    ({double width, double ascent, double descent}) text(
      String value,
      TextStyle style,
    ) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: inherited.style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textHeightBehavior: inherited.textHeightBehavior,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final ascent = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final result = (
        width: painter.width,
        ascent: ascent,
        descent: painter.height - ascent,
      );
      painter.dispose();
      return result;
    }

    final labelStyle = _labelStyle(Colors.transparent, unitFontSize);
    final parts = [
      text('超时', labelStyle),
      text(
        '${duration.isNegative ? 0 : duration.inMinutes}',
        CountdownText.textStyle(
          context,
          fontSize: fontSize,
          color: Colors.transparent,
        ),
      ),
      text('分钟', labelStyle),
    ];
    final sideWidth = math.max(parts.first.width, parts.last.width);
    return (
      size: Size(
        sideWidth * 2 + 24 + parts[1].width,
        parts.map((part) => part.ascent).reduce(math.max) +
            parts.map((part) => part.descent).reduce(math.max),
      ),
      sideWidth: sideWidth,
    );
  }

  @override
  State<OverdueDuration> createState() => _OverdueDurationState();
}

class _OverdueDurationState extends State<OverdueDuration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _opacity = _pulse.drive(
    Tween(begin: 1.0, end: .72).chain(CurveTween(curve: Curves.easeInOut)),
  );
  late final Animation<double> _scale = _pulse.drive(
    Tween(begin: 1.0, end: .96).chain(CurveTween(curve: Curves.easeInOut)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePulse();
  }

  @override
  void didUpdateWidget(OverdueDuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulse();
  }

  void _updatePulse() {
    final enabled =
        widget.pulse &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (enabled) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = OverdueDuration._labelStyle(
      widget.color,
      widget.unitFontSize,
    );
    Widget label(String value, String peer, Alignment alignment) {
      final inherited = DefaultTextStyle.of(context);
      var measuringStyle = inherited.style.merge(labelStyle);
      if (MediaQuery.boldTextOf(context)) {
        measuringStyle = measuringStyle.merge(
          const TextStyle(fontWeight: FontWeight.bold),
        );
      }
      // Both slots lay out both words, so their widths remain equal even when
      // a browser loads its CJK fallback font after the first frame. A fixed
      // width from a one-off TextPainter would retain the old font's width and
      // clip one character. These paragraphs relayout with the rendered font.
      return Stack(
        alignment: alignment,
        children: [
          ExcludeSemantics(
            child: Opacity(
              opacity: 0,
              child: RichText(
                text: TextSpan(text: peer, style: measuringStyle),
                textScaler: MediaQuery.textScalerOf(context),
                textHeightBehavior: inherited.textHeightBehavior,
                locale: Localizations.maybeLocaleOf(context),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          Text(value, maxLines: 1, softWrap: false, style: labelStyle),
        ],
      );
    }

    return Semantics(
      label: '超时 ${TimeUtils.formatDuration(widget.duration)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Equal label slots keep the numeral centered.
          label('超时', '分钟', Alignment.centerRight),
          const SizedBox(width: 12),
          // Paint-only motion leaves the baseline and neighboring controls fixed.
          FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: CountdownText(
                '${widget.duration.isNegative ? 0 : widget.duration.inMinutes}',
                color: widget.color,
                fontSize: widget.fontSize,
              ),
            ),
          ),
          const SizedBox(width: 12),
          label('分钟', '超时', Alignment.centerLeft),
        ],
      ),
    );
  }
}
