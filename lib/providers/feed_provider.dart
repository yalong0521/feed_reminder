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

  List<FeedRecord> _feedHistory = [];
  List<FeedRecord> get feedHistory => _feedHistory;

  FeedProvider({
    required StorageService storage,
    required AudioService audioService,
    required NotificationService notificationService,
  }) : _storage = storage,
       _audioService = audioService,
       _notificationService = notificationService {
    _initialize();
  }

  Future<void> _initialize() async {
    _lastFeedTime = await _storage.getLastFeedTime();
    _feedIntervalMinutes = await _storage.getFeedInterval();
    _nightModeEnabled = await _storage.getNightModeEnabled();
    _nightStartTime = await _storage.getNightStartTime();
    _nightEndTime = await _storage.getNightEndTime();
    _soundEnabled = await _storage.getSoundEnabled();
    _soundLoopEnabled = await _storage.getSoundLoopEnabled();
    _feedHistory = await _storage.getFeedHistory();

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
      final nextFeedTime = _lastFeedTime!.add(
        Duration(minutes: _feedIntervalMinutes),
      );
      final now = DateTime.now();

      if (now.isAfter(nextFeedTime)) {
        _timeRemaining = Duration.zero;
        _timeElapsed = now.difference(nextFeedTime);
      } else {
        _timeRemaining = nextFeedTime.difference(now);
        _timeElapsed = now.difference(_lastFeedTime!);
      }

      // Clamp to prevent negative values if device time is wrong
      if (_timeElapsed.isNegative) {
        _timeElapsed = Duration.zero;
        _timeRemaining = Duration(minutes: _feedIntervalMinutes);
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
    await _addFeedRecordWithTime(now);
  }

  Future<void> addFeedRecordWithTime(DateTime time) async {
    await _addFeedRecordWithTime(time);
  }

  Future<void> _addFeedRecordWithTime(DateTime time) async {
    // Calculate interval from previous feed
    Duration? interval;
    if (_lastFeedTime != null) {
      interval = time.difference(_lastFeedTime!);
    }

    // Save record
    final record = FeedRecord(time: time, intervalFromPrevious: interval);
    await _storage.addFeedRecord(record);
    await _storage.setLastFeedTime(time);

    // Insert in correct position (sorted by time descending, newest first)
    int insertIndex = _feedHistory.length;
    for (int i = 0; i < _feedHistory.length; i++) {
      if (time.isAfter(_feedHistory[i].time)) {
        insertIndex = i;
        break;
      }
    }
    _feedHistory.insert(insertIndex, record);
    if (_feedHistory.length > 100) {
      _feedHistory.removeRange(100, _feedHistory.length);
    }

    // Stop any playing audio
    await _audioService.stopReminder();

    // Update state
    _lastFeedTime = time;
    _hasTriggeredAlert = false;
    _timeRemaining = Duration(minutes: _feedIntervalMinutes);
    _timeElapsed = Duration.zero;
    _state = FeedState.normal;

    notifyListeners();
  }

  Future<void> deleteFeedRecord(int index) async {
    if (index < 0 || index >= _feedHistory.length) return;

    // If deleting the most recent record, update lastFeedTime
    if (index == 0 && _feedHistory.length > 1) {
      _lastFeedTime = _feedHistory[1].time;
      await _storage.setLastFeedTime(_lastFeedTime!);
    } else if (index == 0 && _feedHistory.length <= 1) {
      _lastFeedTime = null;
    }

    _feedHistory.removeAt(index);
    await _storage.setFeedHistory(_feedHistory);
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
