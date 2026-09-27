import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../utils/constants.dart';

/// Startup failure affects decoration only, never access to feeding records.
abstract final class AppGlass {
  static bool _ready = false;
  static bool get isReady => _ready;

  static Future<void> initialize() async {
    if (_ready) return;
    try {
      // The package catches some preload failures internally. Validate the
      // required shader ourselves before marking optical surfaces available.
      await ui.FragmentProgram.fromAsset(
        'packages/liquid_glass_widgets/shaders/lightweight_glass.frag',
      );
      await LiquidGlassWidgets.initialize(
        enablePerformanceMonitor: false,
        warmUpMode: GlassWarmUpMode.never,
      );
      _ready = true;
    } catch (error) {
      debugPrint('Glass shaders unavailable; using solid surfaces: $error');
    }
  }

  static Widget wrap(Widget child) => LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    respectSystemAccessibility: true,
    child: child,
  );
}

/// The only optical surface used by the app. Text stays outside the shader.
/// Standard shaders avoid the premium pipeline's Android cold-start failures.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.tinted = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = MediaQuery.highContrastOf(context) || !AppGlass.isReady;
    final tint = tinted ? colors.primary : colors.surface;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final surface = solid
        ? Material(
            color: tint,
            shape: shape.copyWith(side: BorderSide(color: colors.border)),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              // A stable tint under the optical layer keeps white button labels
              // readable even when the shader samples a very pale backdrop.
              color: tinted ? colors.primary : null,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .14 : .055),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: GlassContainer(
              useOwnLayer: true,
              quality: GlassQuality.standard,
              shape: LiquidRoundedSuperellipse(borderRadius: radius),
              settings: LiquidGlassSettings(
                glassColor: tint.withValues(
                  alpha: tinted
                      ? .84
                      : dark
                      ? .48
                      : .42,
                ),
                blur: 8,
                thickness: tinted ? 16 : 22,
                lightIntensity: dark ? .35 : .55,
                ambientStrength: .12,
                refractiveIndex: 1.16,
                chromaticAberration: .005,
                saturation: 1.05,
                shadow: const [],
              ),
              child: const SizedBox.expand(),
            ),
          );
    // Keep content beside, rather than beneath, GlassContainer. Its inherited
    // avoidsRefraction flag would otherwise turn nested buttons into flat fills.
    // The stable foreground path also preserves in-flight button state when
    // accessibility changes replace the decorative background.
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: RepaintBoundary(child: surface)),
        ),
        DefaultTextStyle(
          // Popup routes do not have a Scaffold's text-style ancestor. Give
          // every glass surface an explicit base, including Cupertino sheets.
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(decoration: TextDecoration.none),
          child: Padding(padding: padding, child: child),
        ),
      ],
    );
  }
}

/// A generated, still backdrop gives the glass an understated surface to sample.
class AppGlassBackdrop extends StatelessWidget {
  const AppGlassBackdrop({super.key, required this.child, this.dimmed = false});
  final Widget child;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!dimmed && !MediaQuery.highContrastOf(context))
          Positioned.fill(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: Image.asset(
                  'assets/img/glass_ambient.png',
                  fit: BoxFit.cover,
                  color: dark ? colors.background : null,
                  colorBlendMode: dark ? BlendMode.modulate : null,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}
