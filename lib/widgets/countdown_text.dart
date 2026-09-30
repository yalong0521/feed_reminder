import 'package:flutter/material.dart';

/// The serif face is reserved for countdown and standby time displays.
/// Tabular figures keep each tick in place.
class CountdownText extends StatelessWidget {
  const CountdownText(
    this.text, {
    super.key,
    required this.color,
    this.fontSize = 160,
    this.semanticLabel,
  });

  final String text;
  final Color color;
  final double fontSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel ?? text,
    // The time is available on demand without announcing every second.
    excludeSemantics: true,
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontFamily: 'JournalSerif',
        fontSize: fontSize,
        height: 1,
        fontWeight: MediaQuery.highContrastOf(context)
            ? FontWeight.w700
            : FontWeight.w400,
        color: color,
        letterSpacing: -fontSize * .018,
        fontFeatures: const [
          FontFeature.tabularFigures(),
          FontFeature.liningFigures(),
          // Tinos kerns repeated 1s even though its digit advances are equal.
          // The clock must not shift horizontally when seconds change.
          FontFeature('kern', 0),
        ],
      ),
    ),
  );
}
