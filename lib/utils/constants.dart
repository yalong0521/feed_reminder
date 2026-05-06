import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFFFF8F0);
  static const Color pink = Color(0xFFFFB5C2);
  static const Color blue = Color(0xFFA8D8EA);
  static const Color yellow = Color(0xFFFFE5A0);
  static const Color green = Color(0xFFB5EAD7);
  static const Color orange = Color(0xFFFFCBA4);
  static const Color accent = Color(0xFFFF6B9D);
  static const Color textPrimary = Color(0xFF5D5D5D);
  static const Color textLight = Color(0xFF8D8D8D);
  static const Color white = Color(0xFFFFFFFF);

  static const List<Color> rainbowGradient = [
    pink,
    Color(0xFFFFB5C2), // pink
    orange,
    Color(0xFFFFCBA4), // orange
    yellow,
    Color(0xFFFFE5A0), // yellow
    green,
    Color(0xFFB5EAD7), // green
    blue,
    Color(0xFFA8D8EA), // blue
    pink,
  ];
}

class AppDimensions {
  static const double ringSize = 0.75; // 75% of screen width
  static const double ringStrokeWidth = 24.0;
  static const double buttonRadius = 30.0;
  static const double buttonHeight = 60.0;
}

class AppStrings {
  static const String appName = '喂奶提醒';
  static const String recordFeed = '🍼 滑动记录喂奶';
  static const String lastFeed = '上次喂奶';
  static const String timeElapsed = '已过去';
  static const String history = '📋 喂奶记录';
  static const String settings = '⚙️ 设置';
  static const String feedInterval = '喂奶间隔';
  static const String nightMode = '夜间模式';
  static const String nightStart = '开始时间';
  static const String nightEnd = '结束时间';
  static const String soundReminder = '声音提醒';
  static const String loopSound = '循环播放';
  static const String reminderSound = '提醒音';
  static const String keepScreenOn = '平板常亮';
  static const String today = '今天';
  static const String yesterday = '昨天';
  static const String earlier = '更早';
}

class AppDefaults {
  static const int feedIntervalMinutes = 180; // 3 hours
  static const bool nightModeEnabled = false;
  static const String nightStartTime = '22:00';
  static const String nightEndTime = '06:00';
  static const bool soundEnabled = true;
  static const bool soundLoopEnabled = true;
  static const bool wakelockEnabled = true;
}

class StorageKeys {
  static const String lastFeedTime = 'lastFeedTime';
  static const String feedIntervalMinutes = 'feedIntervalMinutes';
  static const String nightModeEnabled = 'nightModeEnabled';
  static const String nightStartTime = 'nightStartTime';
  static const String nightEndTime = 'nightEndTime';
  static const String soundEnabled = 'soundEnabled';
  static const String soundLoopEnabled = 'soundLoopEnabled';
  static const String wakelockEnabled = 'wakelockEnabled';
  static const String feedHistory = 'feedHistory';
}
