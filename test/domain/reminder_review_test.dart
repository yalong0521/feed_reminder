import 'dart:async';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  bool playing = false;
  @override
  Future<void> playReminder({bool loop = true}) async => playing = true;
  @override
  Future<void> stopReminder() async => playing = false;
}

class _Notifications extends Fake implements NotificationService {
  int cancellations = 0;
  Completer<void>? nextCancelGate;
  Completer<void>? cancelStarted;
  @override
  Future<void> cancelAll() async {
    cancellations++;
    final gate = nextCancelGate;
    nextCancelGate = null;
    if (gate != null) {
      cancelStarted?.complete();
      await gate.future;
    }
  }

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
}

class _Storage extends StorageService {
  bool failAcknowledgement = false;
  bool failHistoryRead = false;
  int historyReads = 0;
  int acknowledgementWrites = 0;
  Completer<void>? historyReadGate;
  Completer<void>? historyReadStarted;
  Completer<void>? acknowledgementGate;
  Completer<void>? acknowledgementStarted;
  @override
  Future<List<FeedRecord>> getFeedHistory() async {
    historyReads++;
    if (historyReadStarted?.isCompleted == false) {
      historyReadStarted!.complete();
    }
    await historyReadGate?.future;
    if (failHistoryRead) throw StateError('History read failure');
    return super.getFeedHistory();
  }

  @override
  Future<void> setAcknowledgedFeedRecord(FeedRecord? record) async {
    acknowledgementWrites++;
    if (acknowledgementStarted?.isCompleted == false) {
      acknowledgementStarted!.complete();
    }
    await acknowledgementGate?.future;
    if (failAcknowledgement) throw StateError('Acknowledgement disk failure');
    await super.setAcknowledgedFeedRecord(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Storage storage;
  late _Audio audio;
  late _Notifications notifications;
  late DateTime now;

  Future<FeedProvider> create({bool seed = true}) async {
    if (seed) {
      await storage.setFeedHistory([
        FeedRecord(
          id: 'first-cycle',
          time: DateTime(2026, 10, 3, 9),
          milkAmountMl: 120,
        ),
      ]);
    }
    final provider = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      clock: () => now,
      startTimer: false,
    );
    addTearDown(provider.dispose);
    await provider.ready;
    if (provider.isAvailable) await provider.refresh();
    return provider;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = _Storage();
    audio = _Audio();
    notifications = _Notifications();
    now = DateTime(2026, 10, 3, 14);
  });

  test(
    'failed load does not cancel existing native reminders on refresh or settings',
    () async {
      storage.failHistoryRead = true;
      final feed = await create();
      expect(feed.isAvailable, isFalse);
      expect(notifications.cancellations, 0);
      await feed.refresh();
      feed.updateSettings(soundEnabled: false);
      feed.setForeground(false);
      await feed.refresh();
      expect(notifications.cancellations, 0);
    },
  );

  test(
    'failed load cannot replace the saved acknowledgement with an empty cycle',
    () async {
      final record = FeedRecord(
        id: 'first-cycle',
        time: DateTime(2026, 10, 3, 9),
      );
      await storage.setAcknowledgedFeedRecord(record);
      storage.failHistoryRead = true;
      final feed = await create();
      await expectLater(feed.stopAlert(), throwsStateError);
      expect((await storage.getFeedAcknowledgement())?.recordId, 'first-cycle');
      expect(storage.acknowledgementWrites, 1);
    },
  );

  test(
    'loading retries coalesce, preserve newer settings and recover the saved records',
    () async {
      storage.failHistoryRead = true;
      final feed = await create();
      expect(feed.isInitialized, isTrue);
      expect(feed.isAvailable, isFalse);
      expect(feed.error, contains('记录读取失败'));
      final gate = storage.historyReadGate = Completer<void>();
      storage.historyReadStarted = Completer<void>();
      final first = feed.retryLoading();
      final second = feed.retryLoading();
      expect(first, same(second));
      expect(feed.isRetryingLoading, isTrue);
      await storage.historyReadStarted!.future;
      expect(storage.historyReads, 2);
      expect(feed.isInitialized, isTrue);
      expect(feed.isAvailable, isFalse);
      feed.updateSettings(feedIntervalMinutes: 240);
      storage.failHistoryRead = false;
      gate.complete();
      await Future.wait([first, second]);
      expect(feed.isRetryingLoading, isFalse);
      expect(feed.isAvailable, isTrue);
      expect(feed.error, isNull);
      expect(feed.feedHistory.single.id, 'first-cycle');
      expect(feed.feedIntervalMinutes, 240);
    },
  );

  test(
    'another failed retry stays unavailable and a later retry can recover',
    () async {
      storage.failHistoryRead = true;
      final feed = await create();
      await feed.retryLoading();
      expect(feed.isRetryingLoading, isFalse);
      expect(feed.isAvailable, isFalse);
      expect(feed.error, contains('记录读取失败'));
      await expectLater(feed.recordFeed(milkAmountMl: 90), throwsStateError);
      storage.failHistoryRead = false;
      await feed.retryLoading();
      expect(feed.isAvailable, isTrue);
      expect(feed.feedHistory.single.milkAmountMl, 120);
    },
  );

  test(
    'retry on an already available provider never reloads or replaces history',
    () async {
      final feed = await create();
      await feed.recordFeed(milkAmountMl: 90);
      final snapshot = feed.feedHistory;
      final readCount = storage.historyReads;
      storage.failHistoryRead = true;
      await feed.retryLoading();
      expect(feed.feedHistory, same(snapshot));
      expect(storage.historyReads, readCount);
      expect(feed.isAvailable, isTrue);
    },
  );

  test(
    'persisted confirmation changes only after a successful write and notifies listeners',
    () async {
      final feed = await create();
      final notifications = <bool>[];
      final stoppingStates = <bool>[];
      feed.addListener(() {
        notifications.add(feed.isAlertAcknowledgementPersisted);
        stoppingStates.add(feed.isStoppingAlert);
      });
      final gate = storage.acknowledgementGate = Completer<void>();
      storage.acknowledgementStarted = Completer<void>();
      final stopping = feed.stopAlert();
      expect(feed.isStoppingAlert, isTrue);
      await storage.acknowledgementStarted!.future;
      expect(feed.isAlertAcknowledged, isTrue);
      expect(feed.isAlertAcknowledgementPersisted, isFalse);
      expect(notifications, isNot(contains(true)));
      gate.complete();
      await stopping;
      expect(feed.isStoppingAlert, isFalse);
      expect(stoppingStates.first, isTrue);
      expect(stoppingStates.last, isFalse);
      expect(feed.isAlertAcknowledgementPersisted, isTrue);
      expect(notifications.last, isTrue);
      await feed.updateFeedRecord(
        'first-cycle',
        time: DateTime(2026, 10, 3, 9),
        milkAmountMl: 90,
      );
      expect(feed.isAlertAcknowledgementPersisted, isTrue);
      await feed.updateFeedRecord(
        'first-cycle',
        time: DateTime(2026, 10, 3, 9, 30),
        milkAmountMl: 90,
      );
      expect(feed.isAlertAcknowledgementPersisted, isFalse);
      await feed.updateFeedRecord(
        'first-cycle',
        time: DateTime(2026, 10, 3, 9),
        milkAmountMl: 90,
      );
      expect(feed.isAlertAcknowledgementPersisted, isTrue);
      await feed.importFeedRecords([
        FeedRecord(id: 'same-time', time: DateTime(2026, 10, 3, 9)),
      ]);
      await feed.deleteFeedRecord(0);
      expect(feed.isAlertAcknowledgementPersisted, isFalse);
      final restored = await create(seed: false);
      expect(restored.isAlertAcknowledgementPersisted, isFalse);
    },
  );

  for (final importEarlier in [false, true]) {
    test(
      'unrelated ${importEarlier ? 'import' : 'amount edit'} cannot hide an unsaved stopped reminder',
      () async {
        final feed = await create();
        final stoppingStates = <bool>[];
        feed.addListener(() => stoppingStates.add(feed.isStoppingAlert));
        storage.failAcknowledgement = true;
        await expectLater(feed.stopAlert(), throwsStateError);
        expect(feed.isStoppingAlert, isFalse);
        expect(stoppingStates, contains(true));
        expect(stoppingStates.last, isFalse);
        expect(feed.isAlertAcknowledged, isTrue);
        expect(feed.isAlertAcknowledgementPersisted, isFalse);
        expect(feed.error, '提醒已停止，但状态保存失败，请重试');
        if (importEarlier) {
          await feed.importFeedRecords([
            FeedRecord(id: 'earlier', time: DateTime(2026, 10, 3, 6)),
          ]);
        } else {
          await feed.updateFeedRecord(
            'first-cycle',
            time: DateTime(2026, 10, 3, 9),
            milkAmountMl: 90,
          );
        }
        expect(await storage.getFeedAcknowledgement(), isNull);
        expect(feed.isAlertAcknowledged, isTrue);
        expect(feed.error, '提醒已停止，但状态保存失败，请重试');
        storage.failAcknowledgement = false;
        await feed.stopAlert();
        expect(feed.error, isNull);
        final restored = await create(seed: false);
        expect(restored.isAlertAcknowledged, isTrue);
      },
    );
  }

  test(
    'duplicate stop requests share one future and one acknowledgement write',
    () async {
      final feed = await create();
      final gate = Completer<void>();
      notifications.nextCancelGate = gate;
      notifications.cancelStarted = Completer<void>();
      final first = feed.stopAlert();
      final second = feed.stopAlert();
      expect(second, same(first));
      await notifications.cancelStarted!.future;
      gate.complete();
      await Future.wait([first, second]);
      expect(storage.acknowledgementWrites, 1);
      expect(feed.isAlertAcknowledgementPersisted, isTrue);
    },
  );

  test(
    'a stop on a newly imported due cycle does not join the previous cycle stop',
    () async {
      final feed = await create();
      final gate = Completer<void>();
      notifications.nextCancelGate = gate;
      notifications.cancelStarted = Completer<void>();
      final stoppingFirst = feed.stopAlert();
      expect(feed.isStoppingAlert, isTrue);
      await notifications.cancelStarted!.future;
      await feed.importFeedRecords([
        FeedRecord(id: 'second-cycle', time: DateTime(2026, 10, 3, 10)),
      ]);
      expect(feed.state, FeedState.alerting);
      expect(feed.isAlertAcknowledged, isFalse);
      expect(feed.isStoppingAlert, isFalse);
      final stoppingSecond = feed.stopAlert();
      expect(feed.isStoppingAlert, isTrue);
      gate.complete();
      await Future.wait([stoppingFirst, stoppingSecond]);
      expect(feed.isStoppingAlert, isFalse);
      await feed.refresh();
      expect(feed.isAlertAcknowledged, isTrue);
      expect(audio.playing, isFalse);
      expect(
        (await storage.getFeedAcknowledgement())?.recordId,
        'second-cycle',
      );
      final restored = await create(seed: false);
      expect(restored.isAlertAcknowledged, isTrue);
    },
  );
}
