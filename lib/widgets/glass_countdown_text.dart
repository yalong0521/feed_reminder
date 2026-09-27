import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'countdown_glyphs.dart';

/// Font outlines mask real backdrop blur; directional highlights suggest glass
/// thickness without the premium refraction pipeline or a continuous ticker.
class GlassCountdownText extends StatefulWidget {
  const GlassCountdownText(
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
  State<GlassCountdownText> createState() => _GlassCountdownTextState();
}

class _GlassCountdownTextState extends State<GlassCountdownText> {
  _CountdownGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    _updateGeometry();
  }

  @override
  void didUpdateWidget(GlassCountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _updateGeometry();
  }

  void _updateGeometry() {
    // A future formatter/localization change must never hide the time.
    _geometry = RegExp(r'^[0-9:\-]+$').hasMatch(widget.text)
        ? _CountdownGeometry(widget.text)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    if (geometry == null) {
      return Text(
        widget.text,
        semanticsLabel: widget.semanticLabel,
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1,
          fontWeight: FontWeight.w600,
          color: widget.color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = MediaQuery.highContrastOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(widget.fontSize) / 100;
    final material = CustomPaint(
      painter: _GlassNumeralPainter(
        geometry: geometry,
        color: widget.color,
        dark: dark,
        solid: solid,
      ),
      size: geometry.size,
    );
    return Semantics(
      label: widget.semanticLabel ?? widget.text,
      // Readable on demand; a live region would announce every second.
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: geometry.size.width * scale,
          height: geometry.size.height * scale,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
              size: geometry.size,
              child: Stack(
                children: [
                  if (!solid)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _NumeralShadowPainter(
                          geometry: geometry,
                          color: widget.color,
                          dark: dark,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: solid
                        ? material
                        : ClipPath(
                            clipper: _NumeralClipper(geometry),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                              child: material,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownGeometry {
  _CountdownGeometry(this.text) {
    const spacing = -2.8;
    var x = padding;
    for (final character in text.split('')) {
      path.addPath(CountdownGlyphs.pathFor(character), Offset(x, padding));
      x += CountdownGlyphs.advanceFor(character) + spacing;
    }
    size = Size(x - spacing + padding, CountdownGlyphs.height + padding * 2);
    topEdge = Path.combine(
      PathOperation.difference,
      path,
      path.shift(const Offset(2.1, 2.5)),
    );
    bottomEdge = Path.combine(
      PathOperation.difference,
      path,
      path.shift(const Offset(-1.8, -2.2)),
    );
  }

  static const padding = 5.0;
  final String text;
  final Path path = Path();
  late final Size size;
  late final Path topEdge;
  late final Path bottomEdge;
}

class _NumeralClipper extends CustomClipper<Path> {
  const _NumeralClipper(this.geometry);
  final _CountdownGeometry geometry;

  @override
  Path getClip(Size size) => geometry.path;

  @override
  bool shouldReclip(_NumeralClipper oldClipper) =>
      oldClipper.geometry.text != geometry.text;
}

class _GlassNumeralPainter extends CustomPainter {
  const _GlassNumeralPainter({
    required this.geometry,
    required this.color,
    required this.dark,
    required this.solid,
  });

  final _CountdownGeometry geometry;
  final Color color;
  final bool dark;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    if (solid) {
      canvas.drawPath(geometry.path, Paint()..color = color);
      return;
    }
    final rect = Rect.fromLTWH(
      0,
      _CountdownGeometry.padding,
      size.width,
      CountdownGlyphs.height,
    );
    final light = Color.lerp(color, Colors.white, dark ? .60 : .24)!;
    final depth = Color.lerp(color, Colors.black, dark ? .30 : .18)!;
    canvas.drawPath(
      geometry.path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            light.withValues(alpha: .90),
            color.withValues(alpha: .78),
            light.withValues(alpha: .88),
            color.withValues(alpha: .91),
            depth.withValues(alpha: .98),
            light.withValues(alpha: .84),
          ],
          stops: const [0, .29, .42, .47, .82, 1],
        ).createShader(rect),
    );
    // A thin bright rim and the opposing shaded rim give each glyph a rounded
    // edge. The interior remains tinted so the time stays legible at a distance.
    canvas.drawPath(
      geometry.topEdge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: dark ? .9 : .95),
            light.withValues(alpha: .16),
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      geometry.bottomEdge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            depth.withValues(alpha: .06),
            depth.withValues(alpha: dark ? .62 : .7),
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      geometry.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .8),
            light.withValues(alpha: .22),
            depth.withValues(alpha: .7),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassNumeralPainter oldDelegate) =>
      oldDelegate.geometry.text != geometry.text ||
      oldDelegate.color != color ||
      oldDelegate.dark != dark ||
      oldDelegate.solid != solid;
}

class _NumeralShadowPainter extends CustomPainter {
  const _NumeralShadowPainter({
    required this.geometry,
    required this.color,
    required this.dark,
  });

  final _CountdownGeometry geometry;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      geometry.path.shift(const Offset(0, 2.4)),
      Paint()
        ..color = (dark ? color : Colors.black).withValues(
          alpha: dark ? .12 : .11,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_NumeralShadowPainter oldDelegate) =>
      oldDelegate.geometry.text != geometry.text ||
      oldDelegate.color != color ||
      oldDelegate.dark != dark;
}
