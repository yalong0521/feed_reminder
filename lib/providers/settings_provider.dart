import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../models/feed_record.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({required StorageService storage}) : _storage = storage {
    ready = _initialize();
  }

  final StorageService _storage;
  late final Future<void> ready;
  Future<void> _writeQueue = Future.value();
  _Settings _values = const _Settings();
  bool _disposed = false;
  bool _isInitialized = false;
  bool _loadFailed = false;
  int _pendingWrites = 0;
  String? _error;

  bool get isInitialized => _isInitialized;

  /// Only a complete initial snapshot may replace the running reminder policy.
  /// Save errors do not invalidate the fields that were already committed.
  bool get isAvailable => _isInitialized && !_loadFailed;
  bool get isSaving => _pendingWrites > 0;
  String? get error => _error;
  ThemeMode get themeMode => _values.themeMode;
  int get feedIntervalMinutes => _values.feedIntervalMinutes;
  int get defaultMilkAmountMl => _values.defaultMilkAmountMl;
  bool get nightModeEnabled => _values.nightModeEnabled;
  String get nightStartTime => _values.nightStartTime;
  String get nightEndTime => _values.nightEndTime;
  bool get soundEnabled => _values.soundEnabled;
  bool get soundLoopEnabled => _values.soundLoopEnabled;
  bool get burnInProtectionEnabled => _values.burnInProtectionEnabled;

  Future<void> _initialize() async {
    try {
      final values = _Settings(
        themeMode: await _storage.getThemeMode(),
        feedIntervalMinutes: await _storage.getFeedInterval(),
        defaultMilkAmountMl: await _storage.getDefaultMilkAmountMl(),
        nightModeEnabled: await _storage.getNightModeEnabled(),
        nightStartTime: await _storage.getNightStartTime(),
        nightEndTime: await _storage.getNightEndTime(),
        soundEnabled: await _storage.getSoundEnabled(),
        soundLoopEnabled: await _storage.getSoundLoopEnabled(),
        burnInProtectionEnabled: await _storage.getBurnInProtectionEnabled(),
      );
      if (!_disposed) _values = values;
    } catch (error) {
      _loadFailed = true;
      _error = '设置读取失败：$error';
    } finally {
      _isInitialized = true;
      _notify();
    }
  }

  Future<void> setFeedInterval(int minutes) =>
      updateSettings(feedIntervalMinutes: minutes);
  Future<void> setDefaultMilkAmountMl(int amount) =>
      updateSettings(defaultMilkAmountMl: amount);
  Future<void> setThemeMode(ThemeMode mode) => updateSettings(themeMode: mode);
  Future<void> setNightModeEnabled(bool enabled) =>
      updateSettings(nightModeEnabled: enabled);
  Future<void> setNightStartTime(String time) =>
      updateSettings(nightStartTime: time);
  Future<void> setNightEndTime(String time) =>
      updateSettings(nightEndTime: time);
  Future<void> setSoundEnabled(bool enabled) =>
      updateSettings(soundEnabled: enabled);
  Future<void> setSoundLoopEnabled(bool enabled) =>
      updateSettings(soundLoopEnabled: enabled);
  Future<void> setBurnInProtectionEnabled(bool enabled) =>
      updateSettings(burnInProtectionEnabled: enabled);

  Future<void> updateSettings({
    ThemeMode? themeMode,
    int? feedIntervalMinutes,
    int? defaultMilkAmountMl,
    bool? nightModeEnabled,
    String? nightStartTime,
    String? nightEndTime,
    bool? soundEnabled,
    bool? soundLoopEnabled,
    bool? burnInProtectionEnabled,
  }) {
    if (_disposed) return Future.value();
    if (defaultMilkAmountMl != null &&
        !FeedRecord.isValidMilkAmount(defaultMilkAmountMl)) {
      return Future.error(
        ArgumentError.value(
          defaultMilkAmountMl,
          'defaultMilkAmountMl',
          '奶量应为 0–2000 mL',
        ),
      );
    }
    if (feedIntervalMinutes != null && feedIntervalMinutes <= 0) {
      return Future.error(
        ArgumentError.value(feedIntervalMinutes, 'feedIntervalMinutes'),
      );
    }
    if ((nightStartTime != null && !TimeUtils.isValidTime(nightStartTime)) ||
        (nightEndTime != null && !TimeUtils.isValidTime(nightEndTime))) {
      return Future.error(ArgumentError('时间格式应为 HH:mm'));
    }
    _pendingWrites++;
    _notify();
    final operation = _writeQueue
        .then((_) async {
          await ready;
          if (_disposed) return;
          if (_loadFailed) throw StateError('设置尚未成功读取，请重新打开应用');
          final before = _values;
          var committed = before;
          final after = _Settings(
            themeMode: themeMode ?? before.themeMode,
            feedIntervalMinutes:
                feedIntervalMinutes ?? before.feedIntervalMinutes,
            defaultMilkAmountMl:
                defaultMilkAmountMl ?? before.defaultMilkAmountMl,
            nightModeEnabled: nightModeEnabled ?? before.nightModeEnabled,
            nightStartTime: nightStartTime ?? before.nightStartTime,
            nightEndTime: nightEndTime ?? before.nightEndTime,
            soundEnabled: soundEnabled ?? before.soundEnabled,
            soundLoopEnabled: soundLoopEnabled ?? before.soundLoopEnabled,
            burnInProtectionEnabled:
                burnInProtectionEnabled ?? before.burnInProtectionEnabled,
          );
          _values = after;
          _error = null;
          // Listeners immediately synchronize the countdown and reminder policy.
          _notify();
          try {
            if (defaultMilkAmountMl != null) {
              await _storage.setDefaultMilkAmountMl(defaultMilkAmountMl);
              committed = committed.copyWith(
                defaultMilkAmountMl: defaultMilkAmountMl,
              );
            }
            if (feedIntervalMinutes != null) {
              await _storage.setFeedInterval(feedIntervalMinutes);
              committed = committed.copyWith(
                feedIntervalMinutes: feedIntervalMinutes,
              );
            }
            if (nightModeEnabled != null) {
              await _storage.setNightModeEnabled(nightModeEnabled);
              committed = committed.copyWith(
                nightModeEnabled: nightModeEnabled,
              );
            }
            if (nightStartTime != null) {
              await _storage.setNightStartTime(nightStartTime);
              committed = committed.copyWith(nightStartTime: nightStartTime);
            }
            if (nightEndTime != null) {
              await _storage.setNightEndTime(nightEndTime);
              committed = committed.copyWith(nightEndTime: nightEndTime);
            }
            if (soundEnabled != null) {
              await _storage.setSoundEnabled(soundEnabled);
              committed = committed.copyWith(soundEnabled: soundEnabled);
            }
            if (soundLoopEnabled != null) {
              await _storage.setSoundLoopEnabled(soundLoopEnabled);
              committed = committed.copyWith(
                soundLoopEnabled: soundLoopEnabled,
              );
            }
            if (burnInProtectionEnabled != null) {
              await _storage.setBurnInProtectionEnabled(
                burnInProtectionEnabled,
              );
              committed = committed.copyWith(
                burnInProtectionEnabled: burnInProtectionEnabled,
              );
            }
            if (themeMode != null) {
              await _storage.setThemeMode(themeMode);
              committed = committed.copyWith(themeMode: themeMode);
            }
          } catch (error) {
            _values = committed;
            _error = '设置保存失败，请重试';
            rethrow;
          }
        })
        .whenComplete(() {
          _pendingWrites--;
          _notify();
        });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _Settings {
  const _Settings({
    this.themeMode = AppDefaults.themeMode,
    this.feedIntervalMinutes = AppDefaults.feedIntervalMinutes,
    this.defaultMilkAmountMl = AppDefaults.defaultMilkAmountMl,
    this.nightModeEnabled = AppDefaults.nightModeEnabled,
    this.nightStartTime = AppDefaults.nightStartTime,
    this.nightEndTime = AppDefaults.nightEndTime,
    this.soundEnabled = AppDefaults.soundEnabled,
    this.soundLoopEnabled = AppDefaults.soundLoopEnabled,
    this.burnInProtectionEnabled = AppDefaults.burnInProtectionEnabled,
  });

  final ThemeMode themeMode;
  final int feedIntervalMinutes;
  final int defaultMilkAmountMl;
  final bool nightModeEnabled;
  final String nightStartTime;
  final String nightEndTime;
  final bool soundEnabled;
  final bool soundLoopEnabled;
  final bool burnInProtectionEnabled;

  _Settings copyWith({
    ThemeMode? themeMode,
    int? feedIntervalMinutes,
    int? defaultMilkAmountMl,
    bool? nightModeEnabled,
    String? nightStartTime,
    String? nightEndTime,
    bool? soundEnabled,
    bool? soundLoopEnabled,
    bool? burnInProtectionEnabled,
  }) => _Settings(
    themeMode: themeMode ?? this.themeMode,
    feedIntervalMinutes: feedIntervalMinutes ?? this.feedIntervalMinutes,
    defaultMilkAmountMl: defaultMilkAmountMl ?? this.defaultMilkAmountMl,
    nightModeEnabled: nightModeEnabled ?? this.nightModeEnabled,
    nightStartTime: nightStartTime ?? this.nightStartTime,
    nightEndTime: nightEndTime ?? this.nightEndTime,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    soundLoopEnabled: soundLoopEnabled ?? this.soundLoopEnabled,
    burnInProtectionEnabled:
        burnInProtectionEnabled ?? this.burnInProtectionEnabled,
  );
}
