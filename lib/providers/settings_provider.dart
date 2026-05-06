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

  SettingsProvider({required StorageService storage}) : _storage = storage {
    _initialize();
  }

  Future<void> _initialize() async {
    _feedIntervalMinutes = await _storage.getFeedInterval();
    _nightModeEnabled = await _storage.getNightModeEnabled();
    _nightStartTime = await _storage.getNightStartTime();
    _nightEndTime = await _storage.getNightEndTime();
    _soundEnabled = await _storage.getSoundEnabled();
    _soundLoopEnabled = await _storage.getSoundLoopEnabled();
    _wakelockEnabled = await _storage.getWakelockEnabled();
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

  Future<void> updateSettings({
    int? feedIntervalMinutes,
    bool? nightModeEnabled,
    String? nightStartTime,
    String? nightEndTime,
    bool? soundEnabled,
    bool? soundLoopEnabled,
  }) async {
    if (feedIntervalMinutes != null) {
      await setFeedInterval(feedIntervalMinutes);
    }
    if (nightModeEnabled != null) {
      await setNightModeEnabled(nightModeEnabled);
    }
    if (nightStartTime != null) {
      await setNightStartTime(nightStartTime);
    }
    if (nightEndTime != null) {
      await setNightEndTime(nightEndTime);
    }
    if (soundEnabled != null) {
      await setSoundEnabled(soundEnabled);
    }
    if (soundLoopEnabled != null) {
      await setSoundLoopEnabled(soundLoopEnabled);
    }
  }

  String get feedIntervalDisplay {
    final hours = _feedIntervalMinutes ~/ 60;
    final minutes = _feedIntervalMinutes % 60;
    if (minutes == 0) {
      return '$hours小时';
    }
    return '$hours小时$minutes分钟';
  }
}
