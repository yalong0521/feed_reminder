import 'dart:async';

import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DeferredFinalReadStorage extends StorageService {
  _DeferredFinalReadStorage({required this.failRead});

  final bool failRead;
  final gate = Completer<void>();

  @override
  Future<bool> getBurnInProtectionEnabled() async {
    await gate.future;
    if (failRead) throw StateError('Final preference could not be read');
    return super.getBurnInProtectionEnabled();
  }
}

class _PartialWriteFailureStorage extends StorageService {
  @override
  Future<void> setNightModeEnabled(bool enabled) async {
    throw StateError('Night preference could not be saved');
  }
}

class _RecoveringReadStorage extends StorageService {
  bool failRead = true;
  int reads = 0;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  @override
  Future<bool> getBurnInProtectionEnabled() async {
    reads++;
    readStarted?.complete();
    await readGate?.future;
    if (failRead) throw StateError('Settings temporarily unavailable');
    return super.getBurnInProtectionEnabled();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      StorageKeys.feedIntervalMinutes: 120,
      StorageKeys.soundEnabled: false,
      StorageKeys.nightModeEnabled: false,
    });
  });

  test(
    'failed settings reads retry once and recover the complete stored snapshot',
    () async {
      final storage = _RecoveringReadStorage();
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      await settings.ready;
      expect(settings.isAvailable, isFalse);
      expect(settings.feedIntervalMinutes, AppDefaults.feedIntervalMinutes);

      await settings.retryLoading();
      expect(settings.isAvailable, isFalse);
      expect(settings.isLoading, isFalse);
      expect(storage.reads, 2);

      storage.failRead = false;
      storage.readGate = Completer<void>();
      storage.readStarted = Completer<void>();
      final first = settings.retryLoading();
      final second = settings.retryLoading();
      expect(identical(first, second), isTrue);
      await storage.readStarted!.future;
      expect(settings.isLoading, isTrue);
      expect(settings.isAvailable, isFalse);
      expect(settings.feedIntervalMinutes, AppDefaults.feedIntervalMinutes);
      storage.readGate!.complete();
      await first;
      expect(storage.reads, 3);
      expect(settings.isLoading, isFalse);
      expect(settings.isAvailable, isTrue);
      expect(settings.error, isNull);
      expect(settings.feedIntervalMinutes, 120);
      expect(settings.soundEnabled, isFalse);
      expect(settings.nightModeEnabled, isFalse);
      expect(await storage.getFeedInterval(), 120);

      await settings.setFeedInterval(90);
      await settings.retryLoading();
      expect(storage.reads, 3);
      expect(settings.feedIntervalMinutes, 90);
      expect(await storage.getFeedInterval(), 90);
    },
  );

  for (final failRead in [false, true]) {
    test(
      'initialization completion exposes availability only after a complete read '
      '(failure: $failRead)',
      () async {
        final storage = _DeferredFinalReadStorage(failRead: failRead);
        final settings = SettingsProvider(storage: storage);
        addTearDown(settings.dispose);
        expect(settings.isInitialized, isFalse);
        expect(settings.isAvailable, isFalse);

        storage.gate.complete();
        await settings.ready;

        expect(settings.isInitialized, isTrue);
        expect(settings.isAvailable, !failRead);
        if (failRead) {
          expect(settings.error, isNotNull);
          await expectLater(settings.setSoundEnabled(true), throwsStateError);
          expect(settings.isAvailable, isFalse);
          expect(await storage.getSoundEnabled(), isFalse);
          expect(await storage.getFeedInterval(), 120);
        } else {
          expect(settings.error, isNull);
          expect(settings.feedIntervalMinutes, 120);
          expect(settings.soundEnabled, isFalse);
        }
      },
    );
  }

  test(
    'partially saved settings remain available to synchronization',
    () async {
      final storage = _PartialWriteFailureStorage();
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      await settings.ready;
      final snapshots = <({int interval, bool nightMode})>[];
      settings.addListener(() {
        if (settings.isAvailable) {
          snapshots.add((
            interval: settings.feedIntervalMinutes,
            nightMode: settings.nightModeEnabled,
          ));
        }
      });

      await expectLater(
        settings.updateSettings(
          feedIntervalMinutes: 60,
          nightModeEnabled: true,
        ),
        throwsStateError,
      );

      expect(settings.error, isNotNull);
      expect(settings.isAvailable, isTrue);
      expect(snapshots.last, (interval: 60, nightMode: false));
      expect(await storage.getFeedInterval(), 60);
      expect(await storage.getNightModeEnabled(), isFalse);
    },
  );
}
