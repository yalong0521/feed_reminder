import 'package:flutter/material.dart';

/// Daylight journal: warm paper, terracotta accents and readable ink.
class AppColors {
  // Foundation
  static const Color background = Color(0xFFFAF6EE);
  static const Color surface = Color(0xFFFFFCF6);
  static const Color white = Color(0xFFFFFFFF);

  // Brand
  static const Color primary = Color(0xFFAD593C);
  static const Color border = Color(0xFFE3D9CB);
  static const Color softGreen = Color(0xFFF1E8DB);

  // Semantic
  static const Color warning = Color(0xFF996526);
  static const Color alert = Color(0xFFB64648);

  // Text
  static const Color textPrimary = Color(0xFF3A322D);
  static const Color textSecondary = Color(0xFF706257);
  static const Color textTertiary = Color(0xFF796D61);
}

/// Semantic colors for pages and shared widgets. Read through [of] so widgets
/// rebuild when the system brightness or an ancestor theme changes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.border,
    required this.softGreen,
    required this.warning,
    required this.alert,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.white,
  });

  static const light = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    primary: AppColors.primary,
    onPrimary: AppColors.white,
    border: AppColors.border,
    softGreen: AppColors.softGreen,
    warning: AppColors.warning,
    alert: AppColors.alert,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    white: AppColors.white,
  );

  static const dark = AppPalette(
    background: Color(0xFF221E1B),
    surface: Color(0xFF2C2622),
    primary: Color(0xFFEDA987),
    onPrimary: Color(0xFF382219),
    border: Color(0xFF4A3E34),
    softGreen: Color(0xFF3C3028),
    warning: Color(0xFFE0BD8B),
    alert: Color(0xFFFFA5AA),
    textPrimary: Color(0xFFF4EADC),
    textSecondary: Color(0xFFC5B3A2),
    textTertiary: Color(0xFFB9A694),
    white: Colors.white,
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  final Color background;
  final Color surface;
  final Color primary;
  final Color onPrimary;
  final Color border;
  final Color softGreen;
  final Color warning;
  final Color alert;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color white;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? primary,
    Color? onPrimary,
    Color? border,
    Color? softGreen,
    Color? warning,
    Color? alert,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? white,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    border: border ?? this.border,
    softGreen: softGreen ?? this.softGreen,
    warning: warning ?? this.warning,
    alert: alert ?? this.alert,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    white: white ?? this.white,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      border: Color.lerp(border, other.border, t)!,
      softGreen: Color.lerp(softGreen, other.softGreen, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      white: Color.lerp(white, other.white, t)!,
    );
  }
}

class AppStrings {
  static const String appName = '奶点记';
  static const String history = '喂奶记录';
  static const String cancel = '取消';
  static const String futureTimeError = '不能选择未来的时间';
  static const String addFeedTitle = '添加喂奶记录';
}

class AppDefaults {
  static const ThemeMode themeMode = ThemeMode.system;
  static const int feedIntervalMinutes = 180;
  static const int defaultMilkAmountMl = 0;
  static const bool nightModeEnabled = false;
  static const String nightStartTime = '22:00';
  static const String nightEndTime = '06:00';
  static const bool soundEnabled = true;
  static const bool soundLoopEnabled = true;
  static const bool burnInProtectionEnabled = true;
}

class StorageKeys {
  static const String themeMode = 'themeMode';
  static const String lastFeedTime = 'lastFeedTime';
  static const String feedIntervalMinutes = 'feedIntervalMinutes';
  static const String defaultMilkAmountMl = 'defaultMilkAmountMl';
  static const String nightModeEnabled = 'nightModeEnabled';
  static const String nightStartTime = 'nightStartTime';
  static const String nightEndTime = 'nightEndTime';
  static const String soundEnabled = 'soundEnabled';
  static const String soundLoopEnabled = 'soundLoopEnabled';
  static const String feedHistory = 'feedHistory';
  static const String burnInProtectionEnabled = 'burnInProtectionEnabled';
}
