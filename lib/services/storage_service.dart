import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feed_record.dart';
import '../utils/constants.dart';

class StorageService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> get _prefsSafe async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // Feed interval
  Future<int> getFeedInterval() async {
    final prefs = await _prefsSafe;
    return prefs.getInt(StorageKeys.feedIntervalMinutes) ??
        AppDefaults.feedIntervalMinutes;
  }

  Future<void> setFeedInterval(int minutes) async {
    final prefs = await _prefsSafe;
    await prefs.setInt(StorageKeys.feedIntervalMinutes, minutes);
  }

  // Last feed time
  Future<DateTime?> getLastFeedTime() async {
    final prefs = await _prefsSafe;
    final timestamp = prefs.getInt(StorageKeys.lastFeedTime);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  Future<void> setLastFeedTime(DateTime time) async {
    final prefs = await _prefsSafe;
    await prefs.setInt(StorageKeys.lastFeedTime, time.millisecondsSinceEpoch);
  }

  // Night mode
  Future<bool> getNightModeEnabled() async {
    final prefs = await _prefsSafe;
    return prefs.getBool(StorageKeys.nightModeEnabled) ??
        AppDefaults.nightModeEnabled;
  }

  Future<void> setNightModeEnabled(bool enabled) async {
    final prefs = await _prefsSafe;
    await prefs.setBool(StorageKeys.nightModeEnabled, enabled);
  }

  Future<String> getNightStartTime() async {
    final prefs = await _prefsSafe;
    return prefs.getString(StorageKeys.nightStartTime) ??
        AppDefaults.nightStartTime;
  }

  Future<void> setNightStartTime(String time) async {
    final prefs = await _prefsSafe;
    await prefs.setString(StorageKeys.nightStartTime, time);
  }

  Future<String> getNightEndTime() async {
    final prefs = await _prefsSafe;
    return prefs.getString(StorageKeys.nightEndTime) ??
        AppDefaults.nightEndTime;
  }

  Future<void> setNightEndTime(String time) async {
    final prefs = await _prefsSafe;
    await prefs.setString(StorageKeys.nightEndTime, time);
  }

  // Sound settings
  Future<bool> getSoundEnabled() async {
    final prefs = await _prefsSafe;
    return prefs.getBool(StorageKeys.soundEnabled) ?? AppDefaults.soundEnabled;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await _prefsSafe;
    await prefs.setBool(StorageKeys.soundEnabled, enabled);
  }

  Future<bool> getSoundLoopEnabled() async {
    final prefs = await _prefsSafe;
    return prefs.getBool(StorageKeys.soundLoopEnabled) ??
        AppDefaults.soundLoopEnabled;
  }

  Future<void> setSoundLoopEnabled(bool enabled) async {
    final prefs = await _prefsSafe;
    await prefs.setBool(StorageKeys.soundLoopEnabled, enabled);
  }

  // Wakelock
  Future<bool> getWakelockEnabled() async {
    final prefs = await _prefsSafe;
    return prefs.getBool(StorageKeys.wakelockEnabled) ??
        AppDefaults.wakelockEnabled;
  }

  Future<void> setWakelockEnabled(bool enabled) async {
    final prefs = await _prefsSafe;
    await prefs.setBool(StorageKeys.wakelockEnabled, enabled);
  }

  // Feed history
  Future<List<FeedRecord>> getFeedHistory() async {
    final prefs = await _prefsSafe;
    final jsonString = prefs.getString(StorageKeys.feedHistory);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList
        .map((e) => FeedRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setFeedHistory(List<FeedRecord> records) async {
    final prefs = await _prefsSafe;
    final jsonList = records.map((e) => e.toJson()).toList();
    await prefs.setString(StorageKeys.feedHistory, json.encode(jsonList));
  }

  Future<void> addFeedRecord(FeedRecord record) async {
    final history = await getFeedHistory();
    history.insert(0, record);
    // Keep only last 100 records
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
    await setFeedHistory(history);
  }
}
