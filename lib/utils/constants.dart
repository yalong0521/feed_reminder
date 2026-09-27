import 'package:flutter/material.dart';

/// Daylight journal: warm paper, terracotta accents and readable ink.
class AppColors {
  // Foundation
  static const Color background = Color(0xFFFAF6EE);
  static const Color surface = Color(0xFFFFFCF6);
  static const Color white = Color(0xFFFFFFFF);

  // Brand
  static const Color primary = Color(0xFFAD593C);
  static const Color accent = primary;
  static const Color accentLight = Color(0xFFD69A7D);
  static const Color border = Color(0xFFE3D9CB);
  static const Color softGreen = Color(0xFFF1E8DB);
  static const Color softPeach = Color(0xFFF4E5D9);

  // Semantic
  static const Color success = Color(0xFF327A69);
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
    required this.accent,
    required this.accentLight,
    required this.border,
    required this.softGreen,
    required this.softPeach,
    required this.success,
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
    accent: AppColors.accent,
    accentLight: AppColors.accentLight,
    border: AppColors.border,
    softGreen: AppColors.softGreen,
    softPeach: AppColors.softPeach,
    success: AppColors.success,
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
    accent: Color(0xFFEDA987),
    accentLight: Color(0xFFAB7156),
    border: Color(0xFF4A3E34),
    softGreen: Color(0xFF3C3028),
    softPeach: Color(0xFF443027),
    success: Color(0xFF94C7B8),
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
  final Color accent;
  final Color accentLight;
  final Color border;
  final Color softGreen;
  final Color softPeach;
  final Color success;
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
    Color? accent,
    Color? accentLight,
    Color? border,
    Color? softGreen,
    Color? softPeach,
    Color? success,
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
    accent: accent ?? this.accent,
    accentLight: accentLight ?? this.accentLight,
    border: border ?? this.border,
    softGreen: softGreen ?? this.softGreen,
    softPeach: softPeach ?? this.softPeach,
    success: success ?? this.success,
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
      accent: Color.lerp(accent, other.accent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      border: Color.lerp(border, other.border, t)!,
      softGreen: Color.lerp(softGreen, other.softGreen, t)!,
      softPeach: Color.lerp(softPeach, other.softPeach, t)!,
      success: Color.lerp(success, other.success, t)!,
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
  static const String appName = '喂奶提醒';
  static const String recordFeed = '滑动记录喂奶';
  static const String recordComplete = '✓ 已记录';
  static const String lastFeed = '上次喂奶';
  static const String timeElapsed = '距上次喂奶';
  static const String history = '喂奶记录';
  static const String settings = '设置';
  static const String feedInterval = '喂奶间隔';
  static const String nightMode = '夜间模式';
  static const String nightStart = '开始时间';
  static const String nightEnd = '结束时间';
  static const String soundReminder = '声音提醒';
  static const String loopSound = '循环播放';
  static const String reminderSound = '提醒音';
  static const String keepScreenOn = '屏幕常亮';
  static const String displaySettings = '显示设置';
  static const String reminderSettings = '提醒设置';
  static const String burnInProtection = '防烧屏保护';
  static const String today = '今天';
  static const String yesterday = '昨天';
  static const String earlier = '更早';
  static const String stopAlert = '停止提醒';
  static const String noRecords = '还没有喂奶记录\n点击下方按钮添加';
  static const String addRecord = '添加记录';
  static const String deleteConfirm = '确定要删除这条喂奶记录吗？';
  static const String deleteTitle = '确认删除';
  static const String cancel = '取消';
  static const String delete = '删除';
  static const String deleted = '记录已删除';
  static const String confirm = '确定';
  static const String futureTimeError = '不能选择未来的时间';
  static const String addFeedTitle = '添加喂奶记录';
  static const String dateTab = '日期';
  static const String timeTab = '时间';
}

class AppDefaults {
  static const ThemeMode themeMode = ThemeMode.system;
  static const int feedIntervalMinutes = 180;
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
  static const String nightModeEnabled = 'nightModeEnabled';
  static const String nightStartTime = 'nightStartTime';
  static const String nightEndTime = 'nightEndTime';
  static const String soundEnabled = 'soundEnabled';
  static const String soundLoopEnabled = 'soundLoopEnabled';
  static const String feedHistory = 'feedHistory';
  static const String burnInProtectionEnabled = 'burnInProtectionEnabled';
}
