# Feed Reminder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter app for tracking baby feed times with countdown timer, rainbow ring animation, multi-channel reminders, and night mode.

**Architecture:** Provider-based state management with service layer for storage, audio, and notifications. UI layer separated into reusable widgets and screens.

**Tech Stack:** Flutter, Provider, SharedPreferences, audioplayers, wakelock_plus, flutter_local_notifications

---

## File Structure

```
lib/
├── main.dart                    # Entry point
├── app.dart                     # App widget with providers
├── models/
│   └── feed_record.dart         # Feed record data model
├── providers/
│   ├── feed_provider.dart       # Feed time & countdown state
│   └── settings_provider.dart   # All settings state
├── screens/
│   ├── home_screen.dart         # Main countdown screen
│   ├── history_screen.dart      # Feed history list
│   └── settings_screen.dart     # Settings page
├── widgets/
│   ├── countdown_ring.dart      # Rainbow progress ring widget
│   ├── feed_button.dart         # Main feed button with animation
│   └── time_display.dart        # Time text display widget
├── services/
│   ├── storage_service.dart     # SharedPreferences wrapper
│   ├── audio_service.dart       # Audio playback service
│   └── notification_service.dart # Local notification service
└── utils/
    ├── constants.dart           # Colors, strings, dimensions
    └── time_utils.dart          # Time formatting utilities
```

---

## Task 1: Add Dependencies

**File:** `pubspec.yaml`

- [ ] **Step 1: Add required dependencies**

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  provider: ^6.1.0
  shared_preferences: ^2.2.0
  audioplayers: ^6.0.0
  wakelock_plus: ^1.2.0
  flutter_local_notifications: ^18.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

- [ ] **Step 2: Run flutter pub get**

Run: `flutter pub get`
Expected: Dependencies installed successfully

---

## Task 2: Create Utils - Constants

**File:** `lib/utils/constants.dart`

- [ ] **Step 1: Create constants.dart with colors and dimensions**

```dart
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
    blue,
    green,
    yellow,
    orange,
    pink,
    blue,
  ];
}

class AppDimensions {
  static const double ringSize = 0.6; // 60% of screen width
  static const double ringStrokeWidth = 20.0;
  static const double buttonRadius = 30.0;
  static const double buttonHeight = 60.0;
}

class AppStrings {
  static const String appName = '喂奶提醒';
  static const String recordFeed = '🍼 记录喂奶';
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
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/utils/constants.dart`
Expected: No errors

---

## Task 3: Create Utils - Time Utilities

**File:** `lib/utils/time_utils.dart`

- [ ] **Step 1: Create time_utils.dart with formatting functions**

```dart
class TimeUtils {
  static String formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  static String formatInterval(Duration interval) {
    final hours = interval.inHours;
    final minutes = interval.inMinutes % 60;
    if (hours > 0) {
      return '+${hours}h${minutes.toString().padLeft(2, '0')}m';
    }
    return '+${minutes}m';
  }

  static String getDateGroup(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return '今天';
    } else if (dateOnly == yesterday) {
      return '昨天';
    } else {
      return '更早';
    }
  }

  static bool isInNightMode(String startTime, String endTime) {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final startParts = startTime.split(':');
    final endParts = endTime.split(':');
    final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    if (startMinutes > endMinutes) {
      // Overnight (e.g., 22:00 to 06:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    } else {
      // Same day (e.g., 02:00 to 06:00)
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
  }

  static Duration timeSince(DateTime from) {
    return DateTime.now().difference(from);
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/utils/time_utils.dart`
Expected: No errors

---

## Task 4: Create Model - Feed Record

**File:** `lib/models/feed_record.dart`

- [ ] **Step 1: Create feed_record.dart model**

```dart
class FeedRecord {
  final DateTime time;
  final Duration? intervalFromPrevious;

  FeedRecord({
    required this.time,
    this.intervalFromPrevious,
  });

  Map<String, dynamic> toJson() {
    return {
      'time': time.millisecondsSinceEpoch,
      'intervalFromPrevious': intervalFromPrevious?.inMinutes,
    };
  }

  factory FeedRecord.fromJson(Map<String, dynamic> json) {
    return FeedRecord(
      time: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
      intervalFromPrevious: json['intervalFromPrevious'] != null
          ? Duration(minutes: json['intervalFromPrevious'] as int)
          : null,
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/models/feed_record.dart`
Expected: No errors

---

## Task 5: Create Service - Storage

**File:** `lib/services/storage_service.dart`

- [ ] **Step 1: Create storage_service.dart**

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feed_record.dart';
import '../utils/constants.dart';

class StorageService {
  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Feed interval
  int getFeedInterval() {
    return _prefs.getInt(StorageKeys.feedIntervalMinutes) ??
        AppDefaults.feedIntervalMinutes;
  }

  Future<void> setFeedInterval(int minutes) async {
    await _prefs.setInt(StorageKeys.feedIntervalMinutes, minutes);
  }

  // Last feed time
  DateTime? getLastFeedTime() {
    final timestamp = _prefs.getInt(StorageKeys.lastFeedTime);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  Future<void> setLastFeedTime(DateTime time) async {
    await _prefs.setInt(StorageKeys.lastFeedTime, time.millisecondsSinceEpoch);
  }

  // Night mode
  bool getNightModeEnabled() {
    return _prefs.getBool(StorageKeys.nightModeEnabled) ??
        AppDefaults.nightModeEnabled;
  }

  Future<void> setNightModeEnabled(bool enabled) async {
    await _prefs.setBool(StorageKeys.nightModeEnabled, enabled);
  }

  String getNightStartTime() {
    return _prefs.getString(StorageKeys.nightStartTime) ??
        AppDefaults.nightStartTime;
  }

  Future<void> setNightStartTime(String time) async {
    await _prefs.setString(StorageKeys.nightStartTime, time);
  }

  String getNightEndTime() {
    return _prefs.getString(StorageKeys.nightEndTime) ??
        AppDefaults.nightEndTime;
  }

  Future<void> setNightEndTime(String time) async {
    await _prefs.setString(StorageKeys.nightEndTime, time);
  }

  // Sound settings
  bool getSoundEnabled() {
    return _prefs.getBool(StorageKeys.soundEnabled) ??
        AppDefaults.soundEnabled;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs.setBool(StorageKeys.soundEnabled, enabled);
  }

  bool getSoundLoopEnabled() {
    return _prefs.getBool(StorageKeys.soundLoopEnabled) ??
        AppDefaults.soundLoopEnabled;
  }

  Future<void> setSoundLoopEnabled(bool enabled) async {
    await _prefs.setBool(StorageKeys.soundLoopEnabled, enabled);
  }

  // Wakelock
  bool getWakelockEnabled() {
    return _prefs.getBool(StorageKeys.wakelockEnabled) ??
        AppDefaults.wakelockEnabled;
  }

  Future<void> setWakelockEnabled(bool enabled) async {
    await _prefs.setBool(StorageKeys.wakelockEnabled, enabled);
  }

  // Feed history
  List<FeedRecord> getFeedHistory() {
    final jsonString = _prefs.getString(StorageKeys.feedHistory);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList
        .map((e) => FeedRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setFeedHistory(List<FeedRecord> records) async {
    final jsonList = records.map((e) => e.toJson()).toList();
    await _prefs.setString(StorageKeys.feedHistory, json.encode(jsonList));
  }

  Future<void> addFeedRecord(FeedRecord record) async {
    final history = getFeedHistory();
    history.insert(0, record);
    // Keep only last 100 records
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
    await setFeedHistory(history);
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/services/storage_service.dart`
Expected: No errors

---

## Task 6: Create Service - Audio

**File:** `lib/services/audio_service.dart`

- [ ] **Step 1: Create audio_service.dart**

```dart
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  Future<void> playReminder({bool loop = true}) async {
    if (_isPlaying) return;

    await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    await _player.play(AssetSource('sounds/reminder.mp3'));
    _isPlaying = true;
  }

  Future<void> stopReminder() async {
    if (!_isPlaying) return;

    await _player.stop();
    _isPlaying = false;
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/services/audio_service.dart`
Expected: No errors

---

## Task 7: Create Service - Notification

**File:** `lib/services/notification_service.dart`

- [ ] **Step 1: Create notification_service.dart**

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  Future<void> showFeedReminder() async {
    const androidDetails = AndroidNotificationDetails(
      'feed_reminder',
      '喂奶提醒',
      channelDescription: '喂奶时间提醒',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      0,
      '喂奶时间到了！',
      '宝宝该喂奶了 🍼',
      details,
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/services/notification_service.dart`
Expected: No errors

---

## Task 8: Create Provider - Feed Provider

**File:** `lib/providers/feed_provider.dart`

- [ ] **Step 1: Create feed_provider.dart**

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/feed_record.dart';
import '../services/storage_service.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../utils/time_utils.dart';

enum FeedState { normal, warning, alerting }

class FeedProvider extends ChangeNotifier {
  final StorageService _storage;
  final AudioService _audioService;
  final NotificationService _notificationService;

  DateTime? _lastFeedTime;
  Duration _timeRemaining = Duration.zero;
  Duration _timeElapsed = Duration.zero;
  Timer? _timer;
  FeedState _state = FeedState.normal;
  bool _hasTriggeredAlert = false;
  int _feedIntervalMinutes = 180;

  // Settings
  bool _nightModeEnabled = false;
  String _nightStartTime = '22:00';
  String _nightEndTime = '06:00';
  bool _soundEnabled = true;
  bool _soundLoopEnabled = true;

  DateTime? get lastFeedTime => _lastFeedTime;
  Duration get timeRemaining => _timeRemaining;
  Duration get timeElapsed => _timeElapsed;
  FeedState get state => _state;
  int get feedIntervalMinutes => _feedIntervalMinutes;

  FeedProvider({
    required StorageService storage,
    required AudioService audioService,
    required NotificationService notificationService,
  })  : _storage = storage,
        _audioService = audioService,
        _notificationService = notificationService;

  Future<void> init() async {
    _lastFeedTime = _storage.getLastFeedTime();
    _feedIntervalMinutes = _storage.getFeedInterval();
    _nightModeEnabled = _storage.getNightModeEnabled();
    _nightStartTime = _storage.getNightStartTime();
    _nightEndTime = _storage.getNightEndTime();
    _soundEnabled = _storage.getSoundEnabled();
    _soundLoopEnabled = _storage.getSoundLoopEnabled();

    if (_lastFeedTime != null) {
      _updateCountdown();
    } else {
      _timeRemaining = Duration(minutes: _feedIntervalMinutes);
    }

    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (_lastFeedTime == null) {
      _timeRemaining = Duration(minutes: _feedIntervalMinutes);
      _timeElapsed = Duration.zero;
    } else {
      final nextFeedTime =
          _lastFeedTime!.add(Duration(minutes: _feedIntervalMinutes));
      final now = DateTime.now();

      if (now.isAfter(nextFeedTime)) {
        _timeRemaining = Duration.zero;
        _timeElapsed = now.difference(nextFeedTime);
      } else {
        _timeRemaining = nextFeedTime.difference(now);
        _timeElapsed = now.difference(_lastFeedTime!);
      }
    }

    _updateState();
    _checkAlert();
    notifyListeners();
  }

  void _updateState() {
    final totalSeconds = _feedIntervalMinutes * 60;
    final remainingSeconds = _timeRemaining.inSeconds;

    if (remainingSeconds <= 0) {
      _state = FeedState.alerting;
    } else if (remainingSeconds < totalSeconds * 0.2) {
      // Last 20% of time - warning state
      _state = FeedState.warning;
    } else {
      _state = FeedState.normal;
    }
  }

  void _checkAlert() {
    if (_timeRemaining.inSeconds <= 0 && !_hasTriggeredAlert) {
      _hasTriggeredAlert = true;
      _triggerAlert();
    } else if (_timeRemaining.inSeconds > 0) {
      _hasTriggeredAlert = false;
    }
  }

  Future<void> _triggerAlert() async {
    final isNight = TimeUtils.isInNightMode(_nightStartTime, _nightEndTime);

    if (!isNight || !_nightModeEnabled) {
      // Full alert
      if (_soundEnabled) {
        await _audioService.playReminder(loop: _soundLoopEnabled);
      }
      await _notificationService.showFeedReminder();
    }
    // Night mode: only visual alert, no sound
  }

  Future<void> recordFeed() async {
    final now = DateTime.now();

    // Calculate interval from previous feed
    Duration? interval;
    if (_lastFeedTime != null) {
      interval = now.difference(_lastFeedTime!);
    }

    // Save record
    final record = FeedRecord(time: now, intervalFromPrevious: interval);
    await _storage.addFeedRecord(record);
    await _storage.setLastFeedTime(now);

    // Stop any playing audio
    await _audioService.stopReminder();

    // Update state
    _lastFeedTime = now;
    _hasTriggeredAlert = false;
    _timeRemaining = Duration(minutes: _feedIntervalMinutes);
    _timeElapsed = Duration.zero;
    _state = FeedState.normal;

    notifyListeners();
  }

  void updateSettings({
    int? feedIntervalMinutes,
    bool? nightModeEnabled,
    String? nightStartTime,
    String? nightEndTime,
    bool? soundEnabled,
    bool? soundLoopEnabled,
  }) {
    if (feedIntervalMinutes != null) {
      _feedIntervalMinutes = feedIntervalMinutes;
    }
    if (nightModeEnabled != null) {
      _nightModeEnabled = nightModeEnabled;
    }
    if (nightStartTime != null) {
      _nightStartTime = nightStartTime;
    }
    if (nightEndTime != null) {
      _nightEndTime = nightEndTime;
    }
    if (soundEnabled != null) {
      _soundEnabled = soundEnabled;
    }
    if (soundLoopEnabled != null) {
      _soundLoopEnabled = soundLoopEnabled;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioService.stopReminder();
    super.dispose();
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/providers/feed_provider.dart`
Expected: No errors

---

## Task 9: Create Provider - Settings Provider

**File:** `lib/providers/settings_provider.dart`

- [ ] **Step 1: Create settings_provider.dart**

```dart
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;

  int _feedIntervalMinutes = AppDefaults.feedIntervalMinutes;
  bool _nightModeEnabled = AppDefaults.nightModeEnabled;
  String _nightStartTime = AppDefaults.nightStartTime;
  String _nightEndTime = AppDefaults.nightEndTime;
  bool _soundEnabled = AppDefaults.soundEnabled;
  bool _soundLoopEnabled = AppDefaults.soundLoopEnabled;
  bool _wakelockEnabled = AppDefaults.wakelockEnabled;

  int get feedIntervalMinutes => _feedIntervalMinutes;
  bool get nightModeEnabled => _nightModeEnabled;
  String get nightStartTime => _nightStartTime;
  String get nightEndTime => _nightEndTime;
  bool get soundEnabled => _soundEnabled;
  bool get soundLoopEnabled => _soundLoopEnabled;
  bool get wakelockEnabled => _wakelockEnabled;

  SettingsProvider({required StorageService storage}) : _storage = storage;

  Future<void> init() async {
    _feedIntervalMinutes = _storage.getFeedInterval();
    _nightModeEnabled = _storage.getNightModeEnabled();
    _nightStartTime = _storage.getNightStartTime();
    _nightEndTime = _storage.getNightEndTime();
    _soundEnabled = _storage.getSoundEnabled();
    _soundLoopEnabled = _storage.getSoundLoopEnabled();
    _wakelockEnabled = _storage.getWakelockEnabled();
    notifyListeners();
  }

  Future<void> setFeedInterval(int minutes) async {
    _feedIntervalMinutes = minutes;
    await _storage.setFeedInterval(minutes);
    notifyListeners();
  }

  Future<void> setNightModeEnabled(bool enabled) async {
    _nightModeEnabled = enabled;
    await _storage.setNightModeEnabled(enabled);
    notifyListeners();
  }

  Future<void> setNightStartTime(String time) async {
    _nightStartTime = time;
    await _storage.setNightStartTime(time);
    notifyListeners();
  }

  Future<void> setNightEndTime(String time) async {
    _nightEndTime = time;
    await _storage.setNightEndTime(time);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    await _storage.setSoundEnabled(enabled);
    notifyListeners();
  }

  Future<void> setSoundLoopEnabled(bool enabled) async {
    _soundLoopEnabled = enabled;
    await _storage.setSoundLoopEnabled(enabled);
    notifyListeners();
  }

  Future<void> setWakelockEnabled(bool enabled) async {
    _wakelockEnabled = enabled;
    await _storage.setWakelockEnabled(enabled);
    notifyListeners();
  }

  String get feedIntervalDisplay {
    final hours = _feedIntervalMinutes ~/ 60;
    final minutes = _feedIntervalMinutes % 60;
    if (minutes == 0) {
      return '${hours}小时';
    }
    return '${hours}小时${minutes}分钟';
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/providers/settings_provider.dart`
Expected: No errors

---

## Task 10: Create Widget - Countdown Ring

**File:** `lib/widgets/countdown_ring.dart`

- [ ] **Step 1: Create countdown_ring.dart**

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../providers/feed_provider.dart';

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
          scale: widget.state != FeedState.normal
              ? _pulseAnimation.value
              : 1.0,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RainbowRingPainter(
                progress: _calculateProgress(),
                colorAnimation: _colorController.value,
                state: widget.state,
              ),
              child: Center(
                child: _buildTimeDisplay(),
              ),
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
          const Text(
            '🔔',
            style: TextStyle(fontSize: 32),
          ),
        Text(
          _formatTime(widget.timeRemaining),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: textColor,
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

    // Rainbow arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: _getColors(),
      tileMode: TileMode.clamp,
    );

    final arcPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppDimensions.ringStrokeWidth
      ..strokeCap = StrokeCap.round;

    // Apply opacity for night mode / alerting
    if (state == FeedState.alerting) {
      arcPaint.color = AppColors.accent;
    }

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  List<Color> _getColors() {
    if (state == FeedState.alerting) {
      return [
        AppColors.accent,
        AppColors.accent,
      ];
    }
    if (state == FeedState.warning) {
      return [
        AppColors.orange,
        AppColors.yellow,
      ];
    }
    return AppColors.rainbowGradient;
  }

  @override
  bool shouldRepaint(_RainbowRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.colorAnimation != colorAnimation ||
        oldDelegate.state != state;
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/widgets/countdown_ring.dart`
Expected: No errors

---

## Task 11: Create Widget - Feed Button

**File:** `lib/widgets/feed_button.dart`

- [ ] **Step 1: Create feed_button.dart**

```dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class FeedButton extends StatefulWidget {
  final VoidCallback onPressed;

  const FeedButton({super.key, required this.onPressed});

  @override
  State<FeedButton> createState() => _FeedButtonState();
}

class _FeedButtonState extends State<FeedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onPressed();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              height: AppDimensions.buttonHeight,
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.pink, AppColors.orange],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius:
                    BorderRadius.circular(AppDimensions.buttonRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pink.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  AppStrings.recordFeed,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/widgets/feed_button.dart`
Expected: No errors

---

## Task 12: Create Widget - Time Display

**File:** `lib/widgets/time_display.dart`

- [ ] **Step 1: Create time_display.dart**

```dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

class TimeDisplay extends StatelessWidget {
  final Duration timeElapsed;
  final DateTime? lastFeedTime;

  const TimeDisplay({
    super.key,
    required this.timeElapsed,
    this.lastFeedTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${AppStrings.timeElapsed}: ${TimeUtils.formatDuration(timeElapsed)}',
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.textLight,
          ),
        ),
        const SizedBox(height: 8),
        if (lastFeedTime != null)
          Text(
            '${AppStrings.lastFeed}: ${TimeUtils.formatTime(lastFeedTime!)}',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textLight,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/widgets/time_display.dart`
Expected: No errors

---

## Task 13: Create Screen - Home Screen

**File:** `lib/screens/home_screen.dart`

- [ ] **Step 1: Create home_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/feed_button.dart';
import '../widgets/time_display.dart';
import '../utils/constants.dart';
import '../services/audio_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<FeedProvider, SettingsProvider>(
      builder: (context, feedProvider, settingsProvider, child) {
        final isAlerting = feedProvider.state == FeedState.alerting;

        return Scaffold(
          backgroundColor: isAlerting
              ? AppColors.accent.withOpacity(0.1)
              : AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Title
                const Text(
                  AppStrings.appName,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                // Countdown Ring
                CountdownRing(
                  timeRemaining: feedProvider.timeRemaining,
                  timeElapsed: feedProvider.timeElapsed,
                  feedIntervalMinutes: feedProvider.feedIntervalMinutes,
                  state: feedProvider.state,
                ),
                const SizedBox(height: 24),
                // Time Display
                TimeDisplay(
                  timeElapsed: feedProvider.timeElapsed,
                  lastFeedTime: feedProvider.lastFeedTime,
                ),
                const Spacer(),
                // Stop sound button (when alerting)
                if (isAlerting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextButton(
                      onPressed: () {
                        context.read<AudioService>().stopReminder();
                      },
                      child: const Text(
                        '🔇 停止提醒',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                // Feed Button
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: FeedButton(
                    onPressed: () async {
                      await feedProvider.recordFeed();
                      settingsProvider.updateSettings(
                        feedIntervalMinutes: settingsProvider.feedIntervalMinutes,
                        nightModeEnabled: settingsProvider.nightModeEnabled,
                        nightStartTime: settingsProvider.nightStartTime,
                        nightEndTime: settingsProvider.nightEndTime,
                        soundEnabled: settingsProvider.soundEnabled,
                        soundLoopEnabled: settingsProvider.soundLoopEnabled,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/screens/home_screen.dart`
Expected: No errors

---

## Task 14: Create Screen - History Screen

**File:** `lib/screens/history_screen.dart`

- [ ] **Step 1: Create history_screen.dart**

```dart
import 'package:flutter/material.dart';
import '../models/feed_record.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FeedRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final storage = StorageService();
    await storage.init();
    final records = storage.getFeedHistory();
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.history,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(
                  child: Text(
                    '还没有喂奶记录',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textLight,
                    ),
                  ),
                )
              : _buildGroupedList(),
    );
  }

  Widget _buildGroupedList() {
    final grouped = <String, List<FeedRecord>>{};

    for (final record in _records) {
      final group = TimeUtils.getDateGroup(record.time);
      grouped.putIfAbsent(group, () => []).add(record);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped.entries.elementAt(index);
        return _buildDateGroup(entry.key, entry.value);
      },
    );
  }

  Widget _buildDateGroup(String dateLabel, List<FeedRecord> records) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            dateLabel,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        ...records.map((record) => _buildRecordItem(record)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRecordItem(FeedRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            TimeUtils.formatTime(record.time),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          if (record.intervalFromPrevious != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                TimeUtils.formatInterval(record.intervalFromPrevious!),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/screens/history_screen.dart`
Expected: No errors

---

## Task 15: Create Screen - Settings Screen

**File:** `lib/screens/settings_screen.dart`

- [ ] **Step 1: Create settings_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, FeedProvider>(
      builder: (context, settings, feedProvider, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text(
              AppStrings.settings,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Feed Interval
              _buildSectionTitle(AppStrings.feedInterval),
              _buildDropdown(
                context,
                value: settings.feedIntervalMinutes,
                items: const [120, 150, 180, 210, 240],
                labels: const ['2小时', '2.5小时', '3小时', '3.5小时', '4小时'],
                onChanged: (value) {
                  settings.setFeedInterval(value);
                  feedProvider.updateSettings(feedIntervalMinutes: value);
                },
              ),
              const SizedBox(height: 24),

              // Night Mode Section
              _buildSectionTitle(AppStrings.nightMode),
              _buildSwitchTile(
                title: AppStrings.nightMode,
                value: settings.nightModeEnabled,
                onChanged: (value) {
                  settings.setNightModeEnabled(value);
                  feedProvider.updateSettings(nightModeEnabled: value);
                },
              ),
              if (settings.nightModeEnabled) ...[
                _buildTimePicker(
                  context,
                  title: AppStrings.nightStart,
                  value: settings.nightStartTime,
                  onChanged: (time) {
                    settings.setNightStartTime(time);
                    feedProvider.updateSettings(nightStartTime: time);
                  },
                ),
                _buildTimePicker(
                  context,
                  title: AppStrings.nightEnd,
                  value: settings.nightEndTime,
                  onChanged: (time) {
                    settings.setNightEndTime(time);
                    feedProvider.updateSettings(nightEndTime: time);
                  },
                ),
              ],
              const SizedBox(height: 24),

              // Reminder Section
              _buildSectionTitle('提醒设置'),
              _buildSwitchTile(
                title: AppStrings.soundReminder,
                value: settings.soundEnabled,
                onChanged: (value) {
                  settings.setSoundEnabled(value);
                  feedProvider.updateSettings(soundEnabled: value);
                },
              ),
              if (settings.soundEnabled)
                _buildSwitchTile(
                  title: AppStrings.loopSound,
                  value: settings.soundLoopEnabled,
                  onChanged: (value) {
                    settings.setSoundLoopEnabled(value);
                    feedProvider.updateSettings(soundLoopEnabled: value);
                  },
                ),
              const SizedBox(height: 24),

              // Other Section
              _buildSectionTitle('其他'),
              _buildSwitchTile(
                title: AppStrings.keepScreenOn,
                value: settings.wakelockEnabled,
                onChanged: (value) {
                  settings.setWakelockEnabled(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required int value,
    required List<int> items,
    required List<String> labels,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        items: List.generate(items.length, (index) {
          return DropdownMenuItem<int>(
            value: items[index],
            child: Text(labels[index]),
          );
        }),
        onChanged: (v) => onChanged(v!),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.pink,
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(
    BuildContext context, {
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          TextButton(
            onPressed: () async {
              final parts = value.split(':');
              final initialTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
              final picked = await showTimePicker(
                context: context,
                initialTime: initialTime,
              );
              if (picked != null) {
                final newTime =
                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                onChanged(newTime);
              }
            },
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.pink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: No errors

---

## Task 16: Create App Widget

**File:** `lib/app.dart`

- [ ] **Step 1: Create app.dart**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage_service.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'utils/constants.dart';

class FeedReminderApp extends StatefulWidget {
  const FeedReminderApp({super.key});

  @override
  State<FeedReminderApp> createState() => _FeedReminderAppState();
}

class _FeedReminderAppState extends State<FeedReminderApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>(
          create: (_) => StorageService(),
        ),
        Provider<AudioService>(
          create: (_) => AudioService(),
        ),
        Provider<NotificationService>(
          create: (_) => NotificationService(),
        ),
        ChangeNotifierProxyProvider<StorageService, SettingsProvider>(
          create: (context) =>
              SettingsProvider(storage: context.read<StorageService>()),
          update: (context, storage, previous) =>
              previous ?? SettingsProvider(storage: storage),
        ),
        ChangeNotifierProxyProvider3<StorageService, AudioService,
            NotificationService, FeedProvider>(
          create: (context) => FeedProvider(
            storage: context.read<StorageService>(),
            audioService: context.read<AudioService>(),
            notificationService: context.read<NotificationService>(),
          ),
          update: (context, storage, audio, notification, previous) =>
              previous ??
              FeedProvider(
                storage: storage,
                audioService: audio,
                notificationService: notification,
              ),
        ),
      ],
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.pink,
            surface: AppColors.background,
          ),
          useMaterial3: true,
          fontFamily: 'SF Pro Display',
        ),
        home: _buildMainScreen(),
      ),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            selectedItemColor: AppColors.pink,
            unselectedItemColor: AppColors.textLight,
            backgroundColor: Colors.transparent,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded),
                label: '历史',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/app.dart`
Expected: No errors

---

## Task 17: Update Main Entry Point

**File:** `lib/main.dart`

- [ ] **Step 1: Update main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'app.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations (landscape for tablet)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize services
  final storageService = StorageService();
  await storageService.init();

  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.requestPermissions();

  // Enable wakelock if enabled
  if (storageService.getWakelockEnabled()) {
    await WakelockPlus.enable();
  }

  runApp(const FeedReminderApp());
}
```

- [ ] **Step 2: Verify file compiles**

Run: `flutter analyze lib/main.dart`
Expected: No errors

---

## Task 18: Add Audio Asset

- [ ] **Step 1: Create assets folder structure**

Run: `mkdir -p /Users/weiyalong/Projects/flutter_clients/feed_reminder/assets/sounds`

- [ ] **Step 2: Add reminder sound to pubspec.yaml**

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/sounds/
```

- [ ] **Step 3: Note about audio file**

> **Note:** You need to add an audio file named `reminder.mp3` to `assets/sounds/`. For a placeholder, you can download a free notification sound or use a simple beep tone.

---

## Task 19: Final Build Verification

- [ ] **Step 1: Run flutter pub get**

Run: `flutter pub get`
Expected: Dependencies resolved

- [ ] **Step 2: Analyze entire project**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 3: Build for iOS simulator**

Run: `flutter build ios --simulator --no-codesign`
Expected: Build succeeded

---

## Task 20: Post-Implementation Verification

Verify all acceptance criteria from design spec:

- [ ] **AC1:** Countdown updates every second accurately
- [ ] **AC2:** Rainbow ring gradient animates smoothly
- [ ] **AC3:** Tapping "记录喂奶" resets countdown
- [ ] **AC4:** Alert sound loops until manually stopped (daytime)
- [ ] **AC5:** Night mode shows visual only, no sound
- [ ] **AC6:** Settings persist across app restarts
- [ ] **AC7:** History shows records grouped by date
- [ ] **AC8:** Screen stays on when wakelock enabled
- [ ] **AC9:** Local notification fires when app is backgrounded

---

## Plan Summary

| Task | File | Status |
|------|------|--------|
| 1 | pubspec.yaml | Pending |
| 2 | utils/constants.dart | Pending |
| 3 | utils/time_utils.dart | Pending |
| 4 | models/feed_record.dart | Pending |
| 5 | services/storage_service.dart | Pending |
| 6 | services/audio_service.dart | Pending |
| 7 | services/notification_service.dart | Pending |
| 8 | providers/feed_provider.dart | Pending |
| 9 | providers/settings_provider.dart | Pending |
| 10 | widgets/countdown_ring.dart | Pending |
| 11 | widgets/feed_button.dart | Pending |
| 12 | widgets/time_display.dart | Pending |
| 13 | screens/home_screen.dart | Pending |
| 14 | screens/history_screen.dart | Pending |
| 15 | screens/settings_screen.dart | Pending |
| 16 | app.dart | Pending |
| 17 | main.dart | Pending |
| 18 | assets/sounds/ | Pending |
| 19 | Build verification | Pending |
| 20 | Acceptance criteria | Pending |
