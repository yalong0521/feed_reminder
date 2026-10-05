import 'dart:async';

import 'package:feed_reminder/models/deferred_reminder.dart';
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
  DateTime? scheduled;
  @override
  Future<void> cancelAll() async => scheduled = null;
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async => scheduled = when;
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
}

class _Storage extends StorageService {
  bool failDeferred = false;
  Future<void>? deferredGate;
  @override
  Future<void> setDeferredReminder(DeferredReminder reminder) async {
    await deferredGate;
    if (failDeferred) throw StateError('disk failure');
    await super.setDeferredReminder(reminder);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late _Storage storage;
  late _Audio audio;
  late _Notifications notifications;

  Future<FeedProvider> create({bool seed = true}) async {
    if (seed) {
      await storage.setFeedHistory([
        FeedRecord(
          id: 'meal',
          time: DateTime(2026, 10, 3, 9),
          milkAmountMl: 120,
        ),
      ]);
    }
    final feed = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      clock: () => now,
      startTimer: false,
    );
    addTearDown(feed.dispose);
    await feed.ready;
    await feed.refresh();
    return feed;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 3, 12);
    storage = _Storage();
    audio = _Audio();
    notifications = _Notifications();
  });

  test('snooze changes only reminder and alerts at the new time', () async {
    final feed = await create();
    expect(audio.playing, isTrue);
    final original = feed.feedHistory.single;
    await feed.snoozeAlert(10);
    await feed.refresh();
    expect(feed.feedHistory.single, same(original));
    expect(feed.feedIntervalMinutes, 180);
    expect(feed.lastFeedTime, DateTime(2026, 10, 3, 9));
    expect(feed.scheduledFeedTime, now);
    expect(feed.nextFeedTime, DateTime(2026, 10, 3, 12, 10));
    expect(feed.isReminderDeferred, isTrue);
    expect(audio.playing, isFalse);
    expect(notifications.scheduled, feed.nextFeedTime);
    now = DateTime(2026, 10, 3, 12, 9);
    await feed.refresh();
    expect(feed.timeRemaining, const Duration(minutes: 1));
    now = DateTime(2026, 10, 3, 12, 10);
    await feed.refresh();
    expect(feed.state, FeedState.alerting);
    expect(feed.isReminderDeferred, isFalse);
    expect(audio.playing, isTrue);
    await feed.snoozeAlert(20);
    expect(feed.nextFeedTime, DateTime(2026, 10, 3, 12, 30));
  });

  test(
    'snooze survives restart and changes to milk or older records',
    () async {
      final feed = await create();
      await feed.snoozeAlert(20);
      await feed.updateFeedRecord(
        'meal',
        time: DateTime(2026, 10, 3, 9),
        milkAmountMl: 90,
      );
      await feed.addFeedRecordWithTime(
        DateTime(2026, 10, 3, 6),
        milkAmountMl: 60,
      );
      final restored = await create(seed: false);
      expect(restored.nextFeedTime, DateTime(2026, 10, 3, 12, 20));
      expect(restored.isReminderDeferred, isTrue);
      expect(restored.feedHistory.first.milkAmountMl, 90);
    },
  );

  test(
    'new meal uses regular interval and undo restores deferred cycle',
    () async {
      final feed = await create();
      await feed.snoozeAlert(30);
      await feed.recordFeed(milkAmountMl: 150);
      expect(feed.isReminderDeferred, isFalse);
      expect(feed.nextFeedTime, now.add(const Duration(hours: 3)));
      await feed.deleteFeedRecord(0);
      expect(feed.isReminderDeferred, isTrue);
      expect(feed.nextFeedTime, now.add(const Duration(minutes: 30)));
    },
  );

  test('changed record time or interval excludes the old override', () async {
    final feed = await create();
    await feed.snoozeAlert(30);
    feed.updateSettings(feedIntervalMinutes: 240);
    expect(feed.nextFeedTime, DateTime(2026, 10, 3, 13));
    expect(feed.isReminderDeferred, isFalse);
    await feed.updateFeedRecord(
      'meal',
      time: DateTime(2026, 10, 3, 10),
      milkAmountMl: 120,
    );
    expect(feed.nextFeedTime, DateTime(2026, 10, 3, 14));
  });

  test(
    'failed snooze leaves original overdue cycle and supports retry',
    () async {
      final feed = await create();
      storage.failDeferred = true;
      await expectLater(feed.snoozeAlert(10), throwsStateError);
      expect(feed.state, FeedState.alerting);
      expect(feed.nextFeedTime, now);
      expect(feed.isReminderDeferred, isFalse);
      expect(await storage.getDeferredReminder(), isNull);
      storage.failDeferred = false;
      await feed.snoozeAlert(10);
      expect(feed.isReminderDeferred, isTrue);
    },
  );

  test(
    'stopped cycle and duplicate requests cannot rearm a reminder',
    () async {
      final feed = await create();
      final first = feed.snoozeAlert(10);
      final second = feed.snoozeAlert(20);
      await expectLater(second, throwsStateError);
      await first;
      expect(feed.nextFeedTime, now.add(const Duration(minutes: 10)));
      now = now.add(const Duration(minutes: 10));
      await feed.refresh();
      await feed.stopAlert();
      await expectLater(feed.snoozeAlert(10), throwsStateError);
      final restored = await create(seed: false);
      expect(restored.isAlertAcknowledged, isTrue);
      expect(audio.playing, isFalse);
    },
  );

  test('a stop during a pending snooze remains authoritative', () async {
    final feed = await create();
    final gate = Completer<void>();
    storage.deferredGate = gate.future;
    final snooze = feed.snoozeAlert(10);
    await Future<void>.delayed(Duration.zero);
    await feed.stopAlert();
    gate.complete();
    await snooze;
    await feed.refresh();
    expect(feed.isAlertAcknowledged, isTrue);
    expect(audio.playing, isFalse);
    expect(notifications.scheduled, isNull);
  });

  test('quiet hours suppress deferred sound and native scheduling', () async {
    final feed = await create();
    feed.updateSettings(
      nightModeEnabled: true,
      nightStartTime: '12:05',
      nightEndTime: '13:00',
    );
    await feed.snoozeAlert(10);
    await feed.refresh();
    expect(notifications.scheduled, isNull);
    now = DateTime(2026, 10, 3, 12, 10);
    await feed.refresh();
    expect(audio.playing, isFalse);
    now = DateTime(2026, 10, 3, 13);
    await feed.refresh();
    expect(audio.playing, isTrue);
  });

  test('invalid optional override does not block reading history', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('deferredFeedReminder', '{broken');
    final feed = await create();
    expect(feed.isAvailable, isTrue);
    expect(feed.feedHistory, hasLength(1));
    expect(feed.nextFeedTime, now);
    await expectLater(feed.snoozeAlert(0), throwsArgumentError);
    await expectLater(feed.snoozeAlert(121), throwsArgumentError);
  });
}
