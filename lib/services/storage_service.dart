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
  static const _acknowledgedFeedRecordKey = 'acknowledgedFeedRecord';
  static const _acceptedPrivacyPolicyVersionKey =
      'acceptedPrivacyPolicyVersion';
  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<SharedPreferences>? _preferences;
  Future<void> _writes = Future.value();
  bool _needsReload = false;

  Future<void> init() async {
    await _prefsSafe;
  }

  Future<String?> getAcceptedPrivacyPolicyVersion() async =>
      (await _prefsSafe).getString(_acceptedPrivacyPolicyVersionKey);

  Future<void> setAcceptedPrivacyPolicyVersion(String version) async => _write(
    (prefs) => prefs.setString(_acceptedPrivacyPolicyVersionKey, version),
  );

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
    final value = (await _prefsSafe).get(StorageKeys.feedIntervalMinutes);
    return value is int && value > 0 ? value : AppDefaults.feedIntervalMinutes;
  }

  Future<void> setFeedInterval(int minutes) async {
    if (minutes <= 0) throw ArgumentError.value(minutes, 'minutes');
    await _write(
      (prefs) => prefs.setInt(StorageKeys.feedIntervalMinutes, minutes),
    );
  }

  Future<int> getDefaultMilkAmountMl() async {
    final value = (await _prefsSafe).get(StorageKeys.defaultMilkAmountMl);
    return value is int && FeedRecord.isValidMilkAmount(value)
        ? value
        : AppDefaults.defaultMilkAmountMl;
  }

  Future<void> setDefaultMilkAmountMl(int amount) async {
    FeedRecord.validateMilkAmount(amount);
    await _write(
      (prefs) => prefs.setInt(StorageKeys.defaultMilkAmountMl, amount),
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

  /// A new snapshot takes precedence even when cleared or damaged. Falling
  /// back to an older timestamp in those cases could silence the wrong cycle.
  Future<({String? recordId, DateTime time})?> getFeedAcknowledgement() async {
    final prefs = await _prefsSafe;
    if (prefs.containsKey(_acknowledgedFeedRecordKey)) {
      final encoded = prefs.getString(_acknowledgedFeedRecordKey);
      if (encoded == null) throw const FormatException('提醒确认状态无法读取');
      final decoded = jsonDecode(encoded);
      if (decoded == null) return null;
      if (decoded is! Map<String, dynamic> ||
          decoded['id'] is! String ||
          (decoded['id'] as String).isEmpty ||
          decoded['time'] is! int) {
        throw const FormatException('提醒确认状态无法读取');
      }
      return (
        recordId: decoded['id'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(decoded['time'] as int),
      );
    }
    final timestamp = prefs.getInt(_acknowledgedFeedKey);
    return timestamp == null
        ? null
        : (
            recordId: null,
            time: DateTime.fromMillisecondsSinceEpoch(timestamp),
          );
  }

  /// Compatibility view for consumers that only need the confirmation time.
  Future<DateTime?> getAcknowledgedFeedTime() async =>
      (await getFeedAcknowledgement())?.time;

  Future<void> setAcknowledgedFeedRecord(FeedRecord? record) => _write(
    (prefs) => prefs.setString(
      _acknowledgedFeedRecordKey,
      jsonEncode(
        record == null
            ? null
            : {'id': record.id, 'time': record.time.millisecondsSinceEpoch},
      ),
    ),
  );

  /// Imports legacy timestamp-only state. Once a record snapshot exists it
  /// remains authoritative; new acknowledgements use setAcknowledgedFeedRecord.
  Future<void> setAcknowledgedFeedTime(DateTime? time) async {
    await _write(
      (prefs) => time == null
          ? prefs.remove(_acknowledgedFeedKey)
          : prefs.setInt(_acknowledgedFeedKey, time.millisecondsSinceEpoch),
    );
  }

  Future<bool> _getBool(String key, bool fallback) async {
    final value = (await _prefsSafe).get(key);
    return value is bool ? value : fallback;
  }

  Future<bool> getNightModeEnabled() =>
      _getBool(StorageKeys.nightModeEnabled, AppDefaults.nightModeEnabled);

  Future<void> setNightModeEnabled(bool enabled) async =>
      _write((prefs) => prefs.setBool(StorageKeys.nightModeEnabled, enabled));

  Future<String> _getTime(String key, String fallback) async {
    final value = (await _prefsSafe).get(key);
    return value is String && TimeUtils.isValidTime(value) ? value : fallback;
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

  Future<bool> getSoundEnabled() =>
      _getBool(StorageKeys.soundEnabled, AppDefaults.soundEnabled);

  Future<void> setSoundEnabled(bool enabled) async =>
      _write((prefs) => prefs.setBool(StorageKeys.soundEnabled, enabled));

  Future<bool> getSoundLoopEnabled() =>
      _getBool(StorageKeys.soundLoopEnabled, AppDefaults.soundLoopEnabled);

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
    final entries = decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('喂奶记录格式无法读取');
      }
      return entry;
    }).toList();
    final identities = {
      for (final entry in entries)
        if (entry['id'] is String) entry['id'] as String,
    };
    return [
      for (var index = 0; index < entries.length; index++)
        _readRecord(entries[index], index, identities),
    ];
  }

  FeedRecord _readRecord(
    Map<String, dynamic> entry,
    int index,
    Set<String> identities,
  ) {
    if (entry['id'] is String) return FeedRecord.fromJson(entry);
    // Legacy entries lack IDs. A stable identity must survive a read-only
    // restart; equal timestamps still represent distinct records. Reserve all
    // explicit IDs before generating any, so migrations cannot introduce a
    // collision with a later entry. Normal saves persist the generated IDs.
    final base = 'legacy-${entry['time']}-$index';
    var identity = base;
    var suffix = 1;
    while (!identities.add(identity)) {
      identity = '$base-${suffix++}';
    }
    return FeedRecord.fromJson({...entry, 'id': identity});
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

  Future<bool> getBurnInProtectionEnabled() => _getBool(
    StorageKeys.burnInProtectionEnabled,
    AppDefaults.burnInProtectionEnabled,
  );

  Future<void> setBurnInProtectionEnabled(bool enabled) async => _write(
    (prefs) => prefs.setBool(StorageKeys.burnInProtectionEnabled, enabled),
  );
}
