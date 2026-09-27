import 'dart:async';

import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingThemeStorage extends StorageService {
  bool failThemeWrite = false;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    if (failThemeWrite) throw StateError('Theme preference write failed');
    await super.setThemeMode(mode);
  }
}

class _DeferredThemeRead extends StorageService {
  final readGate = Completer<void>();

  @override
  Future<ThemeMode> getThemeMode() async {
    await readGate.future;
    return super.getThemeMode();
  }
}

class _DeferredThemeWrite extends StorageService {
  final started = Completer<void>();
  final writeGate = Completer<void>();

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    started.complete();
    await writeGate.future;
    await super.setThemeMode(mode);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy preferences default to system without changing saved records',
    () async {
      const history = '[{"time":1790332800000,"intervalFromPrevious":null}]';
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedHistory: history,
        StorageKeys.feedIntervalMinutes: 120,
        StorageKeys.soundEnabled: false,
      });
      final settings = SettingsProvider(storage: StorageService());
      addTearDown(settings.dispose);
      expect(settings.themeMode, ThemeMode.system);
      await settings.ready;
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.feedIntervalMinutes, 120);
      expect(settings.soundEnabled, isFalse);
      expect(settings.error, isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(StorageKeys.feedHistory), history);
      expect(preferences.containsKey(StorageKeys.themeMode), isFalse);
    },
  );

  for (final unsupported in <Object>['sepia', '', 1, true]) {
    test(
      'unsupported theme value $unsupported safely falls back to system',
      () async {
        SharedPreferences.setMockInitialValues({
          StorageKeys.themeMode: unsupported,
        });
        final storage = StorageService();
        expect(await storage.getThemeMode(), ThemeMode.system);
        final settings = SettingsProvider(storage: storage);
        addTearDown(settings.dispose);
        await settings.ready;
        expect(settings.themeMode, ThemeMode.system);
        expect(settings.error, isNull);
      },
    );
  }

  for (final entry in const {
    ThemeMode.system: 'system',
    ThemeMode.light: 'light',
    ThemeMode.dark: 'dark',
  }.entries) {
    test(
      '${entry.value} persists as a stable string and survives provider recreation',
      () async {
        final settings = SettingsProvider(storage: StorageService());
        await settings.ready;
        await settings.setThemeMode(entry.key);
        expect(settings.themeMode, entry.key);
        expect(settings.isSaving, isFalse);
        expect(
          (await SharedPreferences.getInstance()).getString(
            StorageKeys.themeMode,
          ),
          entry.value,
        );
        settings.dispose();
        final restored = SettingsProvider(storage: StorageService());
        addTearDown(restored.dispose);
        await restored.ready;
        expect(restored.themeMode, entry.key);
      },
    );
  }

  test('theme updates notify before persistence finishes', () async {
    final storage = _DeferredThemeWrite();
    final settings = SettingsProvider(storage: storage);
    addTearDown(settings.dispose);
    await settings.ready;
    final observed = <ThemeMode>[];
    settings.addListener(() => observed.add(settings.themeMode));
    final saving = settings.setThemeMode(ThemeMode.dark);
    await storage.started.future;
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.isSaving, isTrue);
    expect(observed, contains(ThemeMode.dark));
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        StorageKeys.themeMode,
      ),
      isFalse,
    );
    storage.writeGate.complete();
    await saving;
    expect(settings.isSaving, isFalse);
    expect(await storage.getThemeMode(), ThemeMode.dark);
  });

  test(
    'failed theme persistence restores the prior choice and permits retry',
    () async {
      final storage = _FailingThemeStorage();
      await storage.setThemeMode(ThemeMode.light);
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      await settings.ready;
      storage.failThemeWrite = true;
      await expectLater(
        settings.setThemeMode(ThemeMode.dark),
        throwsStateError,
      );
      expect(settings.themeMode, ThemeMode.light);
      expect(await storage.getThemeMode(), ThemeMode.light);
      expect(settings.isSaving, isFalse);
      expect(settings.error, isNotNull);
      storage.failThemeWrite = false;
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
      expect(await storage.getThemeMode(), ThemeMode.dark);
      expect(settings.error, isNull);
    },
  );

  test(
    'pre-initialization choice is applied after the stored settings load',
    () async {
      SharedPreferences.setMockInitialValues({StorageKeys.themeMode: 'light'});
      final storage = _DeferredThemeRead();
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      final saving = settings.setThemeMode(ThemeMode.dark);
      expect(settings.isInitialized, isFalse);
      storage.readGate.complete();
      await saving;
      expect(settings.isInitialized, isTrue);
      expect(settings.themeMode, ThemeMode.dark);
      expect(await storage.getThemeMode(), ThemeMode.dark);
    },
  );

  test(
    'queued theme changes persist the last choice without changing other settings',
    () async {
      final storage = StorageService();
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      await settings.ready;
      await Future.wait([
        settings.updateSettings(
          themeMode: ThemeMode.dark,
          feedIntervalMinutes: 90,
        ),
        settings.setThemeMode(ThemeMode.light),
        settings.setThemeMode(ThemeMode.system),
      ]);
      expect(settings.themeMode, ThemeMode.system);
      expect(await storage.getThemeMode(), ThemeMode.system);
      expect(settings.feedIntervalMinutes, 90);
      expect(await storage.getFeedInterval(), 90);
      expect(settings.isSaving, isFalse);
    },
  );
}
