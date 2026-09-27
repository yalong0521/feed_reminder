import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceTint: Colors.transparent,
      error: p.alert,
      onError: p.white,
      outline: p.textTertiary,
      outlineVariant: p.border,
    );
    final base = ThemeData(colorScheme: scheme, fontFamily: 'Inter');
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      disabledColor: p.textTertiary.withValues(alpha: .5),
      // Defensive fallback: even a framework-provided Material control may
      // never reintroduce radial ink or Android overscroll feedback.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      iconTheme: IconThemeData(color: p.textSecondary),
      dividerColor: p.border,
      dividerTheme: DividerThemeData(
        color: p.border.withValues(alpha: .6),
        thickness: .5,
        space: 1,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: p.primary,
        primaryContrastingColor: p.onPrimary,
        scaffoldBackgroundColor: p.background,
        barBackgroundColor: p.surface.withValues(alpha: .7),
        textTheme: CupertinoTextThemeData(
          primaryColor: p.primary,
          textStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            color: p.textPrimary,
          ),
          pickerTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 21,
            color: p.textPrimary,
          ),
          dateTimePickerTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            color: p.textPrimary,
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: .25),
        selectionHandleColor: p.primary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: TextStyle(color: p.textPrimary, fontSize: 13),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
