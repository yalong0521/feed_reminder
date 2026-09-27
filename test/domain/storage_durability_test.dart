import 'dart:async';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/repositories/feed_repository.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors SharedPreferences 2.5.5: its setters mutate the process cache before
/// awaiting a platform write, even when the platform rejects that write.
class _FalliblePreferences extends Fake implements SharedPreferences {
  _FalliblePreferences(Map<String, Object> values)
    : disk = Map.of(values),
      cache = Map.of(values);

  final Map<String, Object> disk;
  final Map<String, Object> cache;
  final Set<String> rejectedKeys = {};
  bool throwOnWrite = false;
  bool failReload = false;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  int reloads = 0;

  @override
  Object? get(String key) => cache[key];
  @override
  bool containsKey(String key) => cache.containsKey(key);
  @override
  int? getInt(String key) => cache[key] as int?;
  @override
  String? getString(String key) => cache[key] as String?;
  @override
  bool? getBool(String key) => cache[key] as bool?;

  Future<bool> _write(String key, Object? value) async {
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    if (writeStarted?.isCompleted == false) writeStarted!.complete();
    await writeGate?.future;
    if (rejectedKeys.contains(key)) {
      if (throwOnWrite) throw StateError('platform write failed');
      return false;
    }
    if (value == null) {
      disk.remove(key);
    } else {
      disk[key] = value;
    }
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) => _write(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);
  @override
  Future<bool> setString(String key, String value) => _write(key, value);
  @override
  Future<bool> remove(String key) => _write(key, null);

  @override
  Future<void> reload() async {
    reloads++;
    if (failReload) throw StateError('platform read failed');
    cache
      ..clear()
      ..addAll(disk);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a rejected settings write cannot survive provider recreation',
    () async {
      final prefs = _FalliblePreferences({StorageKeys.themeMode: 'light'});
      final storage = StorageService(preferencesLoader: () async => prefs);
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      await settings.ready;
      prefs.rejectedKeys.add(StorageKeys.themeMode);
      prefs.throwOnWrite = true;
      await expectLater(
        settings.setThemeMode(ThemeMode.dark),
        throwsStateError,
      );
      expect(settings.themeMode, ThemeMode.light);
      expect(await storage.getThemeMode(), ThemeMode.light);
      expect(prefs.cache, prefs.disk);

      final restored = SettingsProvider(storage: storage);
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.themeMode, ThemeMode.light);
      prefs.rejectedKeys.clear();
      await restored.setThemeMode(ThemeMode.dark);
      expect(await storage.getThemeMode(), ThemeMode.dark);
      expect(prefs.disk[StorageKeys.themeMode], 'dark');
    },
  );

  test(
    'a false history write cannot introduce an unsaved meal on reload',
    () async {
      final prefs = _FalliblePreferences({});
      final storage = StorageService(preferencesLoader: () async => prefs);
      final repository = FeedRepository(storage);
      await repository.load();
      final first = DateTime(2026, 9, 25, 9);
      final second = first.add(const Duration(hours: 3));
      await repository.add(first);
      prefs.rejectedKeys.add(StorageKeys.feedHistory);
      await expectLater(repository.add(second), throwsStateError);
      expect(repository.records.map((record) => record.time), [first]);
      final restored = FeedRepository(storage);
      await restored.load();
      expect(restored.records.map((record) => record.time), [first]);
      prefs.rejectedKeys.clear();
      await restored.add(second);
      expect(restored.records.map((record) => record.time), [second, first]);
      expect(await storage.getFeedHistory(), hasLength(2));
    },
  );

  test(
    'cache recovery completes before queued settings writes and reads',
    () async {
      final prefs = _FalliblePreferences({
        StorageKeys.feedIntervalMinutes: 180,
      });
      final storage = StorageService(preferencesLoader: () async => prefs);
      prefs.rejectedKeys.add(StorageKeys.feedIntervalMinutes);
      prefs.writeStarted = Completer<void>();
      prefs.writeGate = Completer<void>();
      final failed = expectLater(storage.setFeedInterval(60), throwsStateError);
      await prefs.writeStarted!.future;
      final soundSaved = storage.setSoundEnabled(false);
      final intervalRead = storage.getFeedInterval();
      expect(prefs.cache.containsKey(StorageKeys.soundEnabled), isFalse);
      prefs.writeGate!.complete();
      await Future.wait([failed, soundSaved]);
      expect(await intervalRead, 180);
      expect(prefs.disk[StorageKeys.soundEnabled], isFalse);
      expect(prefs.cache, prefs.disk);
    },
  );

  test(
    'failed cache recovery blocks dirty reads until reload can succeed',
    () async {
      final prefs = _FalliblePreferences({
        StorageKeys.feedIntervalMinutes: 180,
      });
      final storage = StorageService(preferencesLoader: () async => prefs);
      prefs.rejectedKeys.add(StorageKeys.feedIntervalMinutes);
      prefs.failReload = true;
      await expectLater(storage.setFeedInterval(60), throwsStateError);
      expect(prefs.cache[StorageKeys.feedIntervalMinutes], 60);
      await expectLater(storage.getFeedInterval(), throwsStateError);
      prefs.failReload = false;
      expect(await storage.getFeedInterval(), 180);
      prefs.rejectedKeys.clear();
      await storage.setFeedInterval(90);
      expect(await storage.getFeedInterval(), 90);
    },
  );

  test(
    'failed legacy cache removal preserves the authoritative empty history',
    () async {
      final prefs = _FalliblePreferences({});
      final storage = StorageService(preferencesLoader: () async => prefs);
      await storage.saveFeedState([
        FeedRecord(time: DateTime(2026, 9, 25, 12)),
      ]);
      prefs.rejectedKeys.add(StorageKeys.lastFeedTime);
      await storage.saveFeedState([]);
      expect(await storage.getFeedHistory(), isEmpty);
      expect(await storage.getLastFeedTime(), isNotNull);
      final restored = FeedRepository(storage);
      await restored.load();
      expect(restored.records, isEmpty);
      expect(restored.lastFeedTime, isNull);
    },
  );
}
