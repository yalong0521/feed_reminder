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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      StorageKeys.feedIntervalMinutes: 120,
      StorageKeys.soundEnabled: false,
      StorageKeys.nightModeEnabled: false,
    });
  });

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
