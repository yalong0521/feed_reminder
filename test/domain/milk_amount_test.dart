import 'dart:convert';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/repositories/feed_repository.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  bool playing = false;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> playReminder({bool loop = true}) async => playing = true;

  @override
  Future<void> stopReminder() async => playing = false;
}

class _Notifications extends Fake implements NotificationService {
  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}

  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
}

class _FallibleStorage extends StorageService {
  bool fail = false;

  @override
  Future<void> setDefaultMilkAmountMl(int amount) async {
    if (fail) throw StateError('disk failure');
    await super.setDefaultMilkAmountMl(amount);
  }

  @override
  Future<void> setFeedHistory(List<FeedRecord> records) async {
    if (fail) throw StateError('disk failure');
    await super.setFeedHistory(records);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 3, 18);

  FeedProvider providerFor(StorageService storage) {
    final provider = FeedProvider(
      storage: storage,
      audioService: _Audio(),
      notificationService: _Notifications(),
      clock: () => now,
      startTimer: false,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'missing legacy milk amount migrates to zero without rewriting history',
    () async {
      final history = jsonEncode([
        {'time': now.millisecondsSinceEpoch},
        {'time': now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch},
      ]);
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedHistory: history,
      });
      final storage = StorageService();
      final repository = FeedRepository(storage);
      await repository.load();
      expect(repository.records.map((record) => record.milkAmountMl), [0, 0]);
      expect(
        (await SharedPreferences.getInstance()).getString(
          StorageKeys.feedHistory,
        ),
        history,
      );
      await storage.setDefaultMilkAmountMl(120);
      expect(
        (await storage.getFeedHistory()).map((record) => record.milkAmountMl),
        [0, 0],
      );
      await repository.add(now, milkAmountMl: 120);
      final restored = FeedRepository(StorageService());
      await restored.load();
      expect(restored.records.map((record) => record.milkAmountMl), [
        0,
        120,
        0,
      ]);
      expect(
        restored.records.map((record) => record.id),
        repository.records.map((record) => record.id),
      );
    },
  );

  test('last-time-only legacy migration has zero milk amount', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.lastFeedTime: now.millisecondsSinceEpoch,
    });
    final repository = FeedRepository(StorageService());
    await repository.load();
    expect(repository.records.single.milkAmountMl, 0);
  });

  test(
    'record serialization preserves valid boundaries and rejects damaged amounts',
    () {
      for (final amount in [0, 1, 120, 2000]) {
        final record = FeedRecord(time: now, milkAmountMl: amount);
        final restored = FeedRecord.fromJson(record.toJson());
        expect(restored.milkAmountMl, amount);
        expect(restored.id, record.id);
      }
      for (final amount in <Object?>[-1, 2001, 120.5, '120', null]) {
        expect(
          () => FeedRecord.fromJson({
            'time': now.millisecondsSinceEpoch,
            'milkAmountMl': amount,
          }),
          throwsFormatException,
        );
      }
      for (final amount in [-1, 2001]) {
        expect(
          () => FeedRecord(time: now, milkAmountMl: amount),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'default amount persists and changes affect only subsequent records',
    () async {
      final storage = StorageService();
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      final provider = providerFor(storage);
      await Future.wait([settings.ready, provider.ready]);
      expect(settings.defaultMilkAmountMl, 0);
      await provider.recordFeed();
      await settings.setDefaultMilkAmountMl(120);
      await provider.recordFeed(milkAmountMl: settings.defaultMilkAmountMl);
      await settings.setDefaultMilkAmountMl(150);
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 3)),
        milkAmountMl: settings.defaultMilkAmountMl,
      );
      expect(provider.feedHistory.map((record) => record.milkAmountMl), [
        0,
        120,
        150,
      ]);
      final restoredSettings = SettingsProvider(storage: StorageService());
      addTearDown(restoredSettings.dispose);
      await restoredSettings.ready;
      expect(restoredSettings.defaultMilkAmountMl, 150);
      final restored = providerFor(StorageService());
      await restored.ready;
      expect(restored.feedHistory.map((record) => record.milkAmountMl), [
        0,
        120,
        150,
      ]);
    },
  );

  test(
    'invalid and failed default writes retain the previous committed value',
    () async {
      final storage = _FallibleStorage();
      final settings = SettingsProvider(storage: storage);
      addTearDown(settings.dispose);
      await settings.ready;
      await settings.setDefaultMilkAmountMl(120);
      for (final amount in [-1, 2001]) {
        await expectLater(
          settings.setDefaultMilkAmountMl(amount),
          throwsArgumentError,
        );
        await expectLater(
          storage.setDefaultMilkAmountMl(amount),
          throwsArgumentError,
        );
      }
      expect(settings.defaultMilkAmountMl, 120);
      storage.fail = true;
      await expectLater(settings.setDefaultMilkAmountMl(150), throwsStateError);
      expect(settings.defaultMilkAmountMl, 120);
      expect(await storage.getDefaultMilkAmountMl(), 120);
      expect(settings.isSaving, isFalse);
      storage.fail = false;
      await settings.setDefaultMilkAmountMl(0);
      expect(settings.defaultMilkAmountMl, 0);
      expect(settings.error, isNull);
    },
  );

  test(
    'editing time and amount preserves identity, sorts history and moves reminder anchor',
    () async {
      final storage = StorageService();
      final provider = providerFor(storage);
      await provider.ready;
      final oldest = now.subtract(const Duration(hours: 6));
      final latest = now.subtract(const Duration(hours: 1));
      await provider.addFeedRecordWithTime(oldest, milkAmountMl: 80);
      await provider.addFeedRecordWithTime(latest, milkAmountMl: 120);
      final editedId = provider.feedHistory.last.id;
      final editedTime = now.subtract(const Duration(minutes: 30));
      await provider.updateFeedRecord(
        editedId,
        time: editedTime,
        milkAmountMl: 150,
      );
      expect(provider.feedHistory.first.id, editedId);
      expect(provider.feedHistory.first.milkAmountMl, 150);
      expect(
        provider.feedHistory.first.intervalFromPrevious,
        const Duration(minutes: 30),
      );
      expect(provider.feedHistory.last.intervalFromPrevious, isNull);
      expect(provider.lastFeedTime, editedTime);
      expect(provider.nextFeedTime, editedTime.add(const Duration(hours: 3)));
      final restored = providerFor(StorageService());
      await restored.ready;
      expect(
        restored.feedHistory.map((record) => record.toJson()),
        provider.feedHistory.map((record) => record.toJson()),
      );
      await provider.updateFeedRecord(editedId, time: oldest, milkAmountMl: 90);
      expect(provider.lastFeedTime, latest);
      expect(
        provider.feedHistory.first.intervalFromPrevious,
        const Duration(hours: 5),
      );
      expect(provider.feedHistory.last.id, editedId);
    },
  );

  test(
    'amount-only edit preserves acknowledged cycle across restart; time edit starts a new cycle',
    () async {
      final storage = StorageService();
      final provider = providerFor(storage);
      await provider.ready;
      final time = now.subtract(const Duration(hours: 4));
      await provider.addFeedRecordWithTime(time, milkAmountMl: 120);
      await provider.stopAlert();
      final id = provider.feedHistory.single.id;
      await provider.updateFeedRecord(id, time: time, milkAmountMl: 150);
      expect(provider.isAlertAcknowledged, isTrue);
      expect(provider.nextFeedTime, time.add(const Duration(hours: 3)));
      final restored = providerFor(StorageService());
      await restored.ready;
      expect(restored.isAlertAcknowledged, isTrue);
      expect(restored.feedHistory.single.milkAmountMl, 150);
      await restored.updateFeedRecord(
        id,
        time: time.add(const Duration(minutes: 10)),
        milkAmountMl: 150,
      );
      expect(restored.isAlertAcknowledged, isFalse);
    },
  );

  test(
    'amount-only edits retain existing dates even before initialization completes',
    () async {
      for (final time in [
        DateTime(2019, 12, 31, 23, 59),
        now.add(const Duration(hours: 1)),
      ]) {
        final storage = StorageService();
        await storage.setFeedHistory([FeedRecord(id: 'existing', time: time)]);
        final provider = providerFor(storage);
        await provider.updateFeedRecord(
          'existing',
          time: time,
          milkAmountMl: 120,
        );
        expect(provider.feedHistory.single.id, 'existing');
        expect(provider.feedHistory.single.time, time);
        expect(provider.feedHistory.single.milkAmountMl, 120);
        expect(provider.nextFeedTime, time.add(const Duration(hours: 3)));
        expect((await storage.getFeedHistory()).single.milkAmountMl, 120);
      }
    },
  );

  test(
    'queued edits cannot restore a future timestamp after it has been corrected',
    () async {
      final storage = StorageService();
      final originalTime = now.add(const Duration(hours: 1));
      await storage.setFeedHistory([
        FeedRecord(id: 'corrected', time: originalTime),
      ]);
      final provider = providerFor(storage);
      await provider.ready;
      final correctedTime = now.subtract(const Duration(hours: 1));
      final correction = provider.updateFeedRecord(
        'corrected',
        time: correctedTime,
        milkAmountMl: 90,
      );
      final staleEdit = provider.updateFeedRecord(
        'corrected',
        time: originalTime,
        milkAmountMl: 120,
      );
      final rejection = expectLater(staleEdit, throwsArgumentError);
      await correction;
      await rejection;
      expect(provider.feedHistory.single.time, correctedTime);
      expect(provider.feedHistory.single.milkAmountMl, 90);
      await expectLater(
        provider.addFeedRecordWithTime(originalTime, milkAmountMl: 120),
        throwsArgumentError,
      );
    },
  );

  test(
    'failed edit keeps saved amount, history order and reminder anchor, then retries',
    () async {
      final storage = _FallibleStorage();
      final provider = providerFor(storage);
      await provider.ready;
      final time = now.subtract(const Duration(hours: 2));
      await provider.addFeedRecordWithTime(time, milkAmountMl: 120);
      final original = provider.feedHistory.single;
      storage.fail = true;
      await expectLater(
        provider.updateFeedRecord(original.id, time: now, milkAmountMl: 180),
        throwsStateError,
      );
      expect(provider.feedHistory.single.toJson(), original.toJson());
      expect(provider.lastFeedTime, time);
      expect(
        (await storage.getFeedHistory()).single.toJson(),
        original.toJson(),
      );
      expect(provider.isSaving, isFalse);
      storage.fail = false;
      await provider.updateFeedRecord(
        original.id,
        time: now,
        milkAmountMl: 180,
      );
      expect(provider.feedHistory.single.id, original.id);
      expect(provider.feedHistory.single.milkAmountMl, 180);
      expect(provider.error, isNull);
    },
  );

  test(
    'invalid edits and stale deleted identities cannot insert or corrupt records',
    () async {
      final storage = StorageService();
      final provider = providerFor(storage);
      await provider.ready;
      await provider.recordFeed(milkAmountMl: 120);
      final original = provider.feedHistory.single;
      for (final amount in [-1, 2001]) {
        await expectLater(
          provider.recordFeed(milkAmountMl: amount),
          throwsArgumentError,
        );
        await expectLater(
          provider.updateFeedRecord(
            original.id,
            time: now,
            milkAmountMl: amount,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        provider.updateFeedRecord(
          original.id,
          time: now.add(const Duration(minutes: 1)),
          milkAmountMl: 150,
        ),
        throwsArgumentError,
      );
      expect(provider.feedHistory.single.toJson(), original.toJson());
      await provider.deleteFeedRecord(0);
      await expectLater(
        provider.updateFeedRecord(original.id, time: now, milkAmountMl: 150),
        throwsStateError,
      );
      expect(provider.feedHistory, isEmpty);
      expect(await storage.getFeedHistory(), isEmpty);
    },
  );
}
