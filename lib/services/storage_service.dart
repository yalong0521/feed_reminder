import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_record.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

/// SharedPreferences adapter. Existing keys and minute-based JSON remain valid.
class StorageService {
  StorageService({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _acknowledgedFeedKey = 'acknowledgedFeedTime';
  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<SharedPreferences>? _preferences;
  Future<void> _writes = Future.value();
  bool _needsReload = false;

  Future<void> init() async {
    await _prefsSafe;
  }

  Future<SharedPreferences> get _prefsSafe async {
    await _writes;
    return _prefsRaw;
  }

  Future<SharedPreferences> get _prefsRaw async {
    final loading = _preferences ??= _preferencesLoader();
    try {
      final prefs = await loading;
      if (_needsReload) {
        await prefs.reload();
        _needsReload = false;
      }
      return prefs;
    } catch (_) {
      if (identical(_preferences, loading)) _preferences = null;
      rethrow;
    }
  }

  Future<void> _write(Future<bool> Function(SharedPreferences) write) {
    final operation = _writes.then((_) async {
      final prefs = await _prefsRaw;
      try {
        if (!await write(prefs)) throw StateError('本地保存失败，请重试');
      } catch (_) {
        // The legacy plugin mutates its cache BEFORE the platform confirms a
        // write. Repair that cache before reads or another queued write can use
        // a value that was never saved. A failed reload blocks dirty reads.
        _needsReload = true;
        try {
          await prefs.reload();
          _needsReload = false;
        } catch (_) {
          // The next read/write retries recovery; preserve the original error.
        }
        rethrow;
      }
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<ThemeMode> getThemeMode() async {
    final value = (await _prefsSafe).get(StorageKeys.themeMode);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => AppDefaults.themeMode,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };
    await _write((prefs) => prefs.setString(StorageKeys.themeMode, value));
  }

  Future<int> getFeedInterval() async {
    final value = (await _prefsSafe).getInt(StorageKeys.feedIntervalMinutes);
    return value != null && value > 0 ? value : AppDefaults.feedIntervalMinutes;
  }

  Future<void> setFeedInterval(int minutes) async {
    if (minutes <= 0) throw ArgumentError.value(minutes, 'minutes');
    await _write(
      (prefs) => prefs.setInt(StorageKeys.feedIntervalMinutes, minutes),
    );
  }

  Future<DateTime?> getLastFeedTime() async {
    final timestamp = (await _prefsSafe).getInt(StorageKeys.lastFeedTime);
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> setLastFeedTime(DateTime time) async => _write(
    (prefs) =>
        prefs.setInt(StorageKeys.lastFeedTime, time.millisecondsSinceEpoch),
  );

  Future<void> clearLastFeedTime() async =>
      _write((prefs) => prefs.remove(StorageKeys.lastFeedTime));

  Future<DateTime?> getAcknowledgedFeedTime() async {
    final timestamp = (await _prefsSafe).getInt(_acknowledgedFeedKey);
    return timestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> setAcknowledgedFeedTime(DateTime? time) async {
    await _write(
      (prefs) => time == null
          ? prefs.remove(_acknowledgedFeedKey)
          : prefs.setInt(_acknowledgedFeedKey, time.millisecondsSinceEpoch),
    );
  }

  Future<bool> getNightModeEnabled() async =>
      (await _prefsSafe).getBool(StorageKeys.nightModeEnabled) ??
      AppDefaults.nightModeEnabled;

  Future<void> setNightModeEnabled(bool enabled) async =>
      _write((prefs) => prefs.setBool(StorageKeys.nightModeEnabled, enabled));

  Future<String> _getTime(String key, String fallback) async {
    final value = (await _prefsSafe).getString(key);
    return value != null && TimeUtils.isValidTime(value) ? value : fallback;
  }

  Future<void> _setTime(String key, String value) async {
    if (!TimeUtils.isValidTime(value)) throw ArgumentError.value(value, 'time');
    await _write((prefs) => prefs.setString(key, value));
  }

  Future<String> getNightStartTime() =>
      _getTime(StorageKeys.nightStartTime, AppDefaults.nightStartTime);

  Future<void> setNightStartTime(String time) =>
      _setTime(StorageKeys.nightStartTime, time);

  Future<String> getNightEndTime() =>
      _getTime(StorageKeys.nightEndTime, AppDefaults.nightEndTime);

  Future<void> setNightEndTime(String time) =>
      _setTime(StorageKeys.nightEndTime, time);

  Future<bool> getSoundEnabled() async =>
      (await _prefsSafe).getBool(StorageKeys.soundEnabled) ??
      AppDefaults.soundEnabled;

  Future<void> setSoundEnabled(bool enabled) async =>
      _write((prefs) => prefs.setBool(StorageKeys.soundEnabled, enabled));

  Future<bool> getSoundLoopEnabled() async =>
      (await _prefsSafe).getBool(StorageKeys.soundLoopEnabled) ??
      AppDefaults.soundLoopEnabled;

  Future<void> setSoundLoopEnabled(bool enabled) async =>
      _write((prefs) => prefs.setBool(StorageKeys.soundLoopEnabled, enabled));

  Future<bool> hasFeedHistory() async =>
      (await _prefsSafe).containsKey(StorageKeys.feedHistory);

  Future<List<FeedRecord>> getFeedHistory() async {
    final encoded = (await _prefsSafe).getString(StorageKeys.feedHistory);
    if (encoded == null) return [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) throw const FormatException('喂奶记录格式无法读取');
    // Reject a damaged payload instead of silently erasing the original data.
    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('喂奶记录格式无法读取');
      }
      return FeedRecord.fromJson(entry);
    }).toList();
  }

  Future<void> setFeedHistory(List<FeedRecord> records) async => _write(
    (prefs) => prefs.setString(
      StorageKeys.feedHistory,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    ),
  );

  /// A successful history write is the commit point. The legacy last-time key
  /// is only a derived compatibility cache and must not turn a committed save
  /// into an apparent failure (which could cause duplicate retries or data loss).
  Future<void> saveFeedState(List<FeedRecord> records) async {
    await setFeedHistory(records);
    try {
      if (records.isEmpty) {
        await clearLastFeedTime();
      } else {
        await setLastFeedTime(records.first.time);
      }
    } catch (_) {
      // Readers prefer persisted history even when it is empty. A subsequent
      // mutation retries this cache update, so the committed history stays safe.
    }
  }

  Future<void> addFeedRecord(FeedRecord record) async {
    final history = await getFeedHistory();
    history.add(record);
    history.sort((a, b) => b.time.compareTo(a.time));
    await saveFeedState([
      for (var i = 0; i < history.length; i++)
        FeedRecord(
          id: history[i].id,
          time: history[i].time,
          intervalFromPrevious: i + 1 < history.length
              ? history[i].time.difference(history[i + 1].time)
              : null,
        ),
    ]);
  }

  Future<bool> getBurnInProtectionEnabled() async =>
      (await _prefsSafe).getBool(StorageKeys.burnInProtectionEnabled) ??
      AppDefaults.burnInProtectionEnabled;

  Future<void> setBurnInProtectionEnabled(bool enabled) async => _write(
    (prefs) => prefs.setBool(StorageKeys.burnInProtectionEnabled, enabled),
  );
}
