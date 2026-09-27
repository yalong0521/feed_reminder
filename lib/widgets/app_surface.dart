import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Opaque paper surfaces. Content never depends on shader initialization.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.tinted = false,
    this.color,
    this.outlined = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool tinted;
  final Color? color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Material(
              color: color ?? (tinted ? p.primary : p.surface),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: outlined ? BorderSide(color: p.border) : BorderSide.none,
              ),
            ),
          ),
        ),
        DefaultTextStyle(
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(decoration: TextDecoration.none),
          child: Padding(padding: padding, child: child),
        ),
      ],
    );
  }
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.dimmed = false});
  final Widget child;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: dimmed
        ? AppPalette.dark.background
        : AppPalette.of(context).background,
    child: child,
  );
}
