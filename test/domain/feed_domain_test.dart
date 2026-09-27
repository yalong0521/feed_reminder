import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/time_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudio extends AudioService {
  int plays = 0;
  int stops = 0;
  bool playing = false;
  bool? lastLoop;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> playReminder({bool loop = true}) async {
    plays++;
    playing = true;
    lastLoop = loop;
  }

  @override
  Future<void> stopReminder() async {
    stops++;
    playing = false;
  }
}

class DeferredAudio extends FakeAudio {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> playReminder({bool loop = true}) async {
    entered.complete();
    await release.future;
    await super.playReminder(loop: loop);
  }
}

class FakeNotifications extends Fake implements NotificationService {
  int shown = 0;
  int cancellations = 0;
  DateTime? scheduled;
  bool? sound;

  @override
  Future<void> cancelAll() async {
    cancellations++;
    scheduled = null;
  }

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {
    scheduled = when;
    sound = playSound;
  }

  @override
  Future<void> showFeedReminder({bool playSound = true}) async {
    shown++;
    sound = playSound;
  }
}

class FailingStorage extends StorageService {
  bool fail = false;

  @override
  Future<void> setFeedHistory(List<FeedRecord> records) async {
    if (fail) throw StateError('disk failure');
    return super.setFeedHistory(records);
  }

  @override
  Future<void> setFeedInterval(int minutes) async {
    if (fail) throw StateError('disk failure');
    return super.setFeedInterval(minutes);
  }
}

class MetadataFailureStorage extends StorageService {
  bool failCache = false;

  @override
  Future<void> setLastFeedTime(DateTime time) async {
    if (failCache) throw StateError('legacy cache write failure');
    await super.setLastFeedTime(time);
  }

  @override
  Future<void> clearLastFeedTime() async {
    if (failCache) throw StateError('legacy cache removal failure');
    await super.clearLastFeedTime();
  }
}

class DeferredStorage extends StorageService {
  final gate = Completer<void>();

  @override
  Future<int> getFeedInterval() async {
    await gate.future;
    return super.getFeedInterval();
  }
}

class PartialFailureStorage extends StorageService {
  @override
  Future<void> setNightModeEnabled(bool enabled) async {
    throw StateError('disk failure');
  }
}

class FailingCancellation extends FakeNotifications {
  bool fail = false;

  @override
  Future<void> cancelAll() async {
    if (fail) throw StateError('notification channel unavailable');
    await super.cancelAll();
  }
}

class FailingPlayback extends FakeAudio {
  bool fail = true;

  @override
  Future<void> playReminder({bool loop = true}) async {
    if (fail) throw StateError('audio device unavailable');
    await super.playReminder(loop: loop);
  }
}

class FailingStopAudio extends FakeAudio {
  bool failStop = false;
  int stopAttempts = 0;

  @override
  Future<void> stopReminder() async {
    stopAttempts++;
    if (failStop) throw StateError('audio stop failed');
    await super.stopReminder();
  }
}

class FailingAcknowledgement extends StorageService {
  bool fail = true;

  @override
  Future<void> setAcknowledgedFeedTime(DateTime? time) async {
    if (fail) throw StateError('acknowledgement write failed');
    await super.setAcknowledgedFeedTime(time);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late StorageService storage;
  late FakeAudio audio;
  late FakeNotifications notifications;
  FeedProvider createProvider({StorageService? source}) => FeedProvider(
    storage: source ?? storage,
    audioService: audio,
    notificationService: notifications,
    clock: () => now,
    startTimer: false,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 25, 12);
    storage = StorageService();
    audio = FakeAudio();
    notifications = FakeNotifications();
  });

  testWidgets(
    'a timer tick handles clock rollback without an explicit refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Construct its async queues inside the widget test's fake-time zone.
      // The shared setUp storage was created in the outer real-time zone.
      final provider = FeedProvider(
        storage: StorageService(),
        audioService: audio,
        notificationService: notifications,
        clock: () => now,
      );
      try {
        await tester.pump();
        await provider.ready;
        final recording = provider.addFeedRecordWithTime(
          now.subtract(const Duration(hours: 4)),
        );
        await tester.pump();
        await recording;
        expect(audio.playing, isTrue);
        now = now.subtract(const Duration(hours: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(provider.state, isNot(FeedState.alerting));
        expect(audio.playing, isFalse);
        expect(notifications.scheduled, provider.nextFeedTime);
        final stops = audio.stops;
        final cancellations = notifications.cancellations;
        await tester.pump(const Duration(seconds: 1));
        expect(audio.stops, stops);
        expect(notifications.cancellations, cancellations);
        now = provider.nextFeedTime!;
        await tester.pump(const Duration(seconds: 1));
        expect(audio.playing, isTrue);
        expect(audio.plays, 2);
      } finally {
        // Cancel the real periodic timer before testWidgets checks invariants.
        provider.dispose();
        await tester.pump();
      }
    },
  );

  test(
    'backdated insertion keeps latest and recomputes adjacent intervals on disk',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      final first = now.subtract(const Duration(hours: 4));
      final latest = now.subtract(const Duration(hours: 1));
      final middle = now.subtract(const Duration(hours: 2));
      await provider.addFeedRecordWithTime(first);
      await provider.addFeedRecordWithTime(latest);
      await provider.addFeedRecordWithTime(middle);

      expect(provider.lastFeedTime, latest);
      expect(provider.feedHistory.map((item) => item.time), [
        latest,
        middle,
        first,
      ]);
      expect(provider.feedHistory.map((item) => item.intervalFromPrevious), [
        const Duration(hours: 1),
        const Duration(hours: 2),
        null,
      ]);
      expect(provider.timeElapsed, const Duration(hours: 1));
      expect(provider.timeRemaining, const Duration(hours: 2));
      expect(() => provider.feedHistory.clear(), throwsUnsupportedError);
      expect(await storage.getLastFeedTime(), latest);
      final saved = await storage.getFeedHistory();
      expect(saved.map((item) => item.time), [latest, middle, first]);
      expect(saved[0].id, provider.feedHistory[0].id);

      await provider.deleteFeedRecord(1);
      expect(
        provider.feedHistory.first.intervalFromPrevious,
        const Duration(hours: 3),
      );
      expect(
        (await storage.getFeedHistory()).first.intervalFromPrevious,
        const Duration(hours: 3),
      );
    },
  );

  test(
    'deleting final record clears persisted timer and survives restart',
    () async {
      final provider = createProvider();
      await provider.ready;
      await provider.recordFeed();
      await provider.deleteFeedRecord(0);
      expect(provider.lastFeedTime, isNull);
      expect(provider.nextFeedTime, isNull);
      expect(provider.state, FeedState.normal);
      expect(await storage.getLastFeedTime(), isNull);
      provider.dispose();

      final restored = createProvider();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.feedHistory, isEmpty);
      expect(restored.lastFeedTime, isNull);
    },
  );

  test(
    'legacy unsorted history is authoritative over an outdated last-feed cache',
    () async {
      final older = now.subtract(const Duration(hours: 5));
      final latest = now.subtract(const Duration(hours: 1));
      SharedPreferences.setMockInitialValues({
        StorageKeys.lastFeedTime: older.millisecondsSinceEpoch,
        StorageKeys.feedHistory: jsonEncode([
          {'time': older.millisecondsSinceEpoch, 'intervalFromPrevious': -10},
          {'time': latest.millisecondsSinceEpoch, 'intervalFromPrevious': null},
        ]),
      });
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      expect(provider.lastFeedTime, latest);
      expect(
        provider.feedHistory.first.intervalFromPrevious,
        const Duration(hours: 4),
      );
      await provider.recordFeed();
      expect(await storage.getLastFeedTime(), now);
    },
  );

  test(
    'a failed legacy cache write cannot roll back committed history',
    () async {
      final metadataStorage = MetadataFailureStorage();
      final provider = createProvider(source: metadataStorage);
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.recordFeed();
      final initialTime = now;
      metadataStorage.failCache = true;
      now = now.add(const Duration(minutes: 10));
      await provider.recordFeed();
      expect(provider.error, isNull);
      expect(provider.feedHistory, hasLength(2));
      expect(provider.lastFeedTime, now);
      expect(await metadataStorage.getLastFeedTime(), initialTime);
      now = now.add(const Duration(minutes: 10));
      await provider.recordFeed();
      expect(provider.feedHistory, hasLength(3));
      expect(await metadataStorage.getFeedHistory(), hasLength(3));
      final restored = createProvider(source: metadataStorage);
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.feedHistory, hasLength(3));
      expect(restored.lastFeedTime, now);
      metadataStorage.failCache = false;
      now = now.add(const Duration(minutes: 10));
      await provider.recordFeed();
      expect(await metadataStorage.getLastFeedTime(), now);
      expect(provider.feedHistory, hasLength(4));
    },
  );

  test(
    'a failed legacy cache removal cannot resurrect deleted history',
    () async {
      final metadataStorage = MetadataFailureStorage();
      final provider = createProvider(source: metadataStorage);
      await provider.ready;
      await provider.recordFeed();
      metadataStorage.failCache = true;
      await provider.deleteFeedRecord(0);
      expect(provider.error, isNull);
      expect(provider.feedHistory, isEmpty);
      expect(provider.lastFeedTime, isNull);
      expect(await metadataStorage.getLastFeedTime(), now);
      expect(await metadataStorage.getFeedHistory(), isEmpty);
      provider.dispose();
      final restored = createProvider(source: metadataStorage);
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.feedHistory, isEmpty);
      expect(restored.lastFeedTime, isNull);
      expect(restored.nextFeedTime, isNull);
    },
  );

  test(
    'legacy last-feed-only installation migrates without losing its countdown',
    () async {
      await storage.setLastFeedTime(now.subtract(const Duration(hours: 1)));
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      expect(provider.feedHistory, hasLength(1));
      expect(provider.timeRemaining, const Duration(hours: 2));
    },
  );

  test(
    'subsecond boundary, elapsed and overdue retain separate meanings',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.recordFeed();
      now = now.add(
        const Duration(hours: 3) - const Duration(milliseconds: 500),
      );
      await provider.refresh();
      expect(provider.state, FeedState.warning);
      expect(audio.plays, 0);
      now = now.add(const Duration(milliseconds: 500));
      await provider.refresh();
      expect(provider.state, FeedState.alerting);
      expect(provider.timeElapsed, const Duration(hours: 3));
      expect(provider.overdue, Duration.zero);
      expect(audio.plays, 1);
      now = now.add(const Duration(minutes: 15));
      await provider.refresh();
      expect(provider.timeElapsed, const Duration(hours: 3, minutes: 15));
      expect(provider.overdue, const Duration(minutes: 15));
      expect(audio.plays, 1);
    },
  );

  test(
    'acknowledgement stops repeated alerts until a new feeding cycle',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 4)),
      );
      expect(audio.plays, 1);
      await provider.stopAlert();
      await provider.refresh();
      expect(provider.isAlertAcknowledged, isTrue);
      expect(audio.playing, isFalse);
      expect(audio.plays, 1);
      expect(notifications.scheduled, isNull);
      await provider.recordFeed();
      expect(provider.isAlertAcknowledged, isFalse);
      now = now.add(const Duration(hours: 3));
      await provider.refresh();
      expect(audio.plays, 2);
    },
  );

  test(
    'clock rollback keeps remaining time aligned with the deadline',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.recordFeed();
      final deadline = provider.nextFeedTime!;
      now = now.subtract(const Duration(hours: 1));
      await provider.refresh();
      expect(provider.timeElapsed, Duration.zero);
      expect(provider.timeRemaining, const Duration(hours: 4));
      expect(provider.timeRemaining, deadline.difference(now));
      expect(notifications.scheduled, deadline);
    },
  );

  test(
    'an alert re-arms after the clock moves back before its deadline',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.recordFeed();
      now = now.add(const Duration(hours: 3));
      await provider.refresh();
      expect(audio.plays, 1);
      now = now.subtract(const Duration(minutes: 10));
      await provider.refresh();
      expect(provider.state, FeedState.warning);
      expect(audio.playing, isFalse);
      now = now.add(const Duration(minutes: 10));
      await provider.refresh();
      expect(provider.state, FeedState.alerting);
      expect(audio.plays, 2);
      expect(audio.playing, isTrue);
    },
  );

  test(
    'notification failure cannot prevent stopping a looping sound',
    () async {
      final failing = FailingCancellation();
      notifications = failing;
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 4)),
      );
      expect(audio.playing, isTrue);
      failing.fail = true;
      await provider.stopAlert();
      expect(audio.playing, isFalse);
      expect(provider.isAlertAcknowledged, isTrue);
      expect(provider.error, contains('提醒服务'));
      expect(await storage.getAcknowledgedFeedTime(), provider.lastFeedTime);
      failing.fail = false;
      await provider.refresh();
      expect(provider.error, isNull);
    },
  );

  test('failed audio still shows a visual reminder and can retry', () async {
    final failing = FailingPlayback();
    audio = failing;
    final provider = createProvider();
    addTearDown(provider.dispose);
    await provider.ready;
    await provider.addFeedRecordWithTime(
      now.subtract(const Duration(hours: 4)),
    );
    expect(notifications.shown, 1);
    expect(provider.error, contains('提醒服务'));
    failing.fail = false;
    await provider.refresh();
    expect(audio.playing, isTrue);
    expect(audio.plays, 1);
    expect(provider.error, isNull);
  });

  test('successful acknowledgement retry clears its saved error', () async {
    final failing = FailingAcknowledgement();
    final provider = createProvider(source: failing);
    addTearDown(provider.dispose);
    await provider.ready;
    await provider.addFeedRecordWithTime(
      now.subtract(const Duration(hours: 4)),
    );
    await expectLater(provider.stopAlert(), throwsStateError);
    expect(provider.error, contains('状态保存失败'));
    expect(audio.playing, isFalse);
    failing.fail = false;
    await provider.stopAlert();
    expect(provider.error, isNull);
    expect(await failing.getAcknowledgedFeedTime(), provider.lastFeedTime);
  });

  test(
    'failed audio stop does not acknowledge and an explicit retry succeeds',
    () async {
      final failing = FailingStopAudio();
      audio = failing;
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 4)),
      );
      expect(audio.playing, isTrue);
      failing.failStop = true;
      final stopping = provider.stopAlert();
      expect(provider.stopAlert(), same(stopping));
      await expectLater(stopping, throwsStateError);
      expect(provider.isAlertAcknowledged, isFalse);
      expect(await storage.getAcknowledgedFeedTime(), isNull);
      expect(audio.playing, isTrue);
      expect(provider.error, contains('声音停止失败'));

      final stopAttempts = failing.stopAttempts;
      await provider.refresh();
      expect(failing.stopAttempts, stopAttempts);
      expect(audio.plays, 1);

      failing.failStop = false;
      await provider.stopAlert();
      expect(audio.playing, isFalse);
      expect(provider.isAlertAcknowledged, isTrue);
      expect(await storage.getAcknowledgedFeedTime(), provider.lastFeedTime);
      expect(provider.error, isNull);
      expect(audio.plays, 1);
    },
  );

  test(
    'interval updates recalculate immediately and reschedule native reminder',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 1)),
      );
      provider.updateSettings(feedIntervalMinutes: 120);
      expect(provider.timeRemaining, const Duration(hours: 1));
      await provider.refresh();
      expect(notifications.scheduled, now.add(const Duration(hours: 1)));
      expect(notifications.sound, isFalse);
      provider.setForeground(false);
      await provider.refresh();
      expect(notifications.sound, isTrue);
      now = now.add(const Duration(hours: 1));
      await provider.refresh();
      expect(audio.plays, 0);
      provider.setForeground(true);
      await provider.refresh();
      expect(audio.plays, 1);
    },
  );

  test(
    'acknowledged feeding cycle stays quiet after an application restart',
    () async {
      final provider = createProvider();
      await provider.ready;
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 4)),
      );
      await provider.stopAlert();
      provider.dispose();
      audio = FakeAudio();
      final restored = createProvider();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.isAlertAcknowledged, isTrue);
      expect(restored.state, FeedState.alerting);
      expect(audio.plays, 0);
      await restored.recordFeed();
      expect(restored.isAlertAcknowledged, isFalse);
    },
  );

  test('sound disabled still allows a silent visual notification', () async {
    final provider = createProvider();
    addTearDown(provider.dispose);
    await provider.ready;
    provider.updateSettings(soundEnabled: false);
    await provider.addFeedRecordWithTime(
      now.subtract(const Duration(hours: 4)),
    );
    expect(audio.plays, 0);
    expect(notifications.shown, 1);
    expect(notifications.sound, isFalse);
  });

  test(
    'lifecycle refresh preserves an overdue native alarm until acknowledged',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.recordFeed();
      final scheduled = notifications.scheduled;
      final cancellations = notifications.cancellations;
      // Simulate an inexact OS alarm that is still waiting after its deadline.
      now = now.add(const Duration(hours: 3, minutes: 1));
      provider.setForeground(false);
      await provider.refresh();
      expect(notifications.scheduled, scheduled);
      expect(notifications.cancellations, cancellations);
      provider.setForeground(true);
      await provider.refresh();
      expect(notifications.cancellations, cancellations);
      await provider.stopAlert();
      expect(notifications.scheduled, isNull);
      expect(notifications.cancellations, greaterThan(cancellations));
    },
  );

  test(
    'an unacknowledged looping reminder resumes audio after backgrounding',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 4)),
      );
      expect(audio.plays, 1);
      provider.setForeground(false);
      await provider.refresh();
      expect(audio.playing, isFalse);
      provider.setForeground(true);
      await provider.refresh();
      expect(audio.plays, 2);
      expect(audio.playing, isTrue);
      await provider.stopAlert();
      provider.setForeground(false);
      provider.setForeground(true);
      await provider.refresh();
      expect(audio.plays, 2);
      expect(audio.playing, isFalse);
    },
  );

  test(
    'completed one-shot audio does not replay on lifecycle resume',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      provider.updateSettings(soundLoopEnabled: false);
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(hours: 4)),
      );
      provider.setForeground(false);
      await provider.refresh();
      provider.setForeground(true);
      await provider.refresh();
      expect(audio.plays, 1);
    },
  );

  test('acknowledgement wins over an in-flight audio start', () async {
    final delayedAudio = DeferredAudio();
    audio = delayedAudio;
    final provider = createProvider();
    addTearDown(provider.dispose);
    await provider.ready;
    final recording = provider.addFeedRecordWithTime(
      now.subtract(const Duration(hours: 4)),
    );
    await delayedAudio.entered.future;
    final stopping = provider.stopAlert();
    await Future<void>.delayed(Duration.zero);
    delayedAudio.release.complete();
    await Future.wait([recording, stopping]);
    expect(audio.playing, isFalse);
    expect(provider.isAlertAcknowledged, isTrue);
    expect(notifications.shown, 0);
  });

  test(
    'partial settings failure preserves fields already committed to storage',
    () async {
      final partialStorage = PartialFailureStorage();
      final settings = SettingsProvider(storage: partialStorage);
      addTearDown(settings.dispose);
      await settings.ready;
      await expectLater(
        settings.updateSettings(
          feedIntervalMinutes: 60,
          nightModeEnabled: true,
        ),
        throwsStateError,
      );
      expect(settings.feedIntervalMinutes, 60);
      expect(await partialStorage.getFeedInterval(), 60);
      expect(settings.nightModeEnabled, isFalse);
      expect(settings.error, isNotNull);
    },
  );

  test(
    'quiet hours suppress sound and native scheduling, then allow an overdue alert',
    () async {
      now = DateTime(2026, 9, 25, 21);
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      provider.updateSettings(nightModeEnabled: true);
      await provider.recordFeed();
      expect(notifications.scheduled, isNull);
      now = DateTime(2026, 9, 26, 1);
      await provider.refresh();
      expect(provider.state, FeedState.alerting);
      expect(audio.plays, 0);
      expect(notifications.shown, 0);
      now = DateTime(2026, 9, 26, 6);
      await provider.refresh();
      expect(audio.plays, 1);
    },
  );

  test(
    'record and settings writes survive calls made during initialization',
    () async {
      final deferred = DeferredStorage();
      final provider = createProvider(source: deferred);
      addTearDown(provider.dispose);
      final write = provider.recordFeed();
      provider.updateSettings(feedIntervalMinutes: 60);
      deferred.gate.complete();
      await write;
      expect(provider.feedHistory, hasLength(1));
      expect(provider.feedIntervalMinutes, 60);
      expect(provider.timeRemaining, const Duration(hours: 1));
    },
  );

  test(
    'disposing during initialization never starts effects or notifies listeners',
    () async {
      final deferred = DeferredStorage();
      final provider = createProvider(source: deferred);
      var changes = 0;
      provider.addListener(() => changes++);
      provider.dispose();
      deferred.gate.complete();
      await provider.ready;
      expect(changes, 0);
      expect(notifications.cancellations, 0);
      expect(audio.plays, 0);
    },
  );

  test(
    'failed persistence preserves history and the next mutation can succeed',
    () async {
      final failing = FailingStorage();
      final provider = createProvider(source: failing);
      addTearDown(provider.dispose);
      await provider.ready;
      await provider.recordFeed();
      failing.fail = true;
      now = now.add(const Duration(minutes: 10));
      await expectLater(provider.recordFeed(), throwsStateError);
      expect(provider.feedHistory, hasLength(1));
      expect(provider.error, isNotNull);
      expect(provider.isSaving, isFalse);
      failing.fail = false;
      await provider.recordFeed();
      expect(provider.feedHistory, hasLength(2));
      expect(provider.error, isNull);
    },
  );

  test(
    'corrupt history is reported and preserved instead of being overwritten',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedHistory: 'damaged',
      });
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      expect(provider.error, isNotNull);
      await expectLater(provider.recordFeed(), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getString(
          StorageKeys.feedHistory,
        ),
        'damaged',
      );
    },
  );

  test(
    'duplicate persisted identities cannot delete multiple records',
    () async {
      final history = jsonEncode([
        {'id': 'same-id', 'time': now.millisecondsSinceEpoch},
        {
          'id': 'same-id',
          'time': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        },
      ]);
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedHistory: history,
      });
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      expect(provider.error, contains('标识重复'));
      await expectLater(provider.recordFeed(), throwsStateError);
      expect(
        (await SharedPreferences.getInstance()).getString(
          StorageKeys.feedHistory,
        ),
        history,
      );
    },
  );

  test(
    'concurrent additions are serialized without discarding older records',
    () async {
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      await Future.wait([
        for (var index = 104; index >= 0; index--)
          provider.addFeedRecordWithTime(
            now.subtract(Duration(minutes: index)),
          ),
      ]);
      expect(provider.feedHistory, hasLength(105));
      expect(provider.feedHistory.first.time, now);
      expect(
        provider.feedHistory.last.time,
        now.subtract(const Duration(minutes: 104)),
      );
      expect(provider.feedHistory.last.intervalFromPrevious, isNull);
      expect((await storage.getFeedHistory()), hasLength(105));
    },
  );

  test(
    'large persisted history survives loading, old backfill and deletion',
    () async {
      final seed = [
        for (var index = 0; index < 250; index++)
          FeedRecord(
            id: 'retained-$index',
            time: now.subtract(Duration(hours: index + 1)),
          ),
      ];
      // Existing JSON remains readable even when it was not saved in order.
      await storage.setFeedHistory(seed.reversed.toList());
      final provider = createProvider();
      addTearDown(provider.dispose);
      await provider.ready;
      expect(
        provider.feedHistory.map((record) => record.id),
        seed.map((record) => record.id),
      );
      expect(provider.feedHistory, hasLength(250));
      expect(
        provider.feedHistory.first.intervalFromPrevious,
        const Duration(hours: 1),
      );
      final deadline = provider.nextFeedTime;

      final oldestTime = seed.last.time.subtract(const Duration(days: 7));
      await provider.addFeedRecordWithTime(oldestTime);
      expect(provider.feedHistory, hasLength(251));
      expect(provider.feedHistory.last.time, oldestTime);
      expect(
        provider.feedHistory[249].intervalFromPrevious,
        const Duration(days: 7),
      );
      expect(provider.feedHistory.last.intervalFromPrevious, isNull);
      expect(provider.nextFeedTime, deadline);

      await provider.deleteFeedRecord(120);
      expect(provider.feedHistory, hasLength(250));
      expect(
        provider.feedHistory.any((record) => record.id == 'retained-120'),
        isFalse,
      );
      expect(
        provider.feedHistory[119].intervalFromPrevious,
        const Duration(hours: 2),
      );
      final persisted = await storage.getFeedHistory();
      expect(
        persisted.map((record) => record.toJson()),
        provider.feedHistory.map((record) => record.toJson()),
      );

      final restored = createProvider();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(
        restored.feedHistory.map((record) => record.toJson()),
        provider.feedHistory.map((record) => record.toJson()),
      );
      expect(restored.feedHistory.last.time, oldestTime);
      expect(restored.nextFeedTime, deadline);
    },
  );

  test(
    'legacy storage additions also preserve all records and intervals',
    () async {
      final seed = [
        for (var index = 0; index < 120; index++)
          FeedRecord(
            id: 'storage-$index',
            time: now.subtract(Duration(hours: index + 1)),
          ),
      ];
      await storage.setFeedHistory(seed);
      final old = FeedRecord(
        id: 'old-backfill',
        time: seed.last.time.subtract(const Duration(days: 2)),
      );
      await storage.addFeedRecord(old);
      final saved = await storage.getFeedHistory();
      expect(saved, hasLength(121));
      expect(saved.map((record) => record.id), [
        ...seed.map((record) => record.id),
        old.id,
      ]);
      expect(saved[119].intervalFromPrevious, const Duration(days: 2));
      expect(saved.last.intervalFromPrevious, isNull);
      expect(await storage.getLastFeedTime(), seed.first.time);
    },
  );

  test(
    'settings changes synchronize listeners and persist across restart',
    () async {
      final settings = SettingsProvider(storage: storage);
      final provider = createProvider();
      addTearDown(settings.dispose);
      addTearDown(provider.dispose);
      await Future.wait([settings.ready, provider.ready]);
      settings.addListener(
        () => provider.updateSettings(
          feedIntervalMinutes: settings.feedIntervalMinutes,
          soundEnabled: settings.soundEnabled,
        ),
      );
      await provider.recordFeed();
      await settings.setFeedInterval(90);
      expect(provider.timeRemaining, const Duration(minutes: 90));
      await Future.wait([
        settings.setFeedInterval(120),
        settings.setFeedInterval(30),
      ]);
      expect(settings.feedIntervalMinutes, 30);
      expect(settings.feedIntervalDisplay, '30分钟');
      expect(settings.isSaving, isFalse);
      final restored = SettingsProvider(storage: storage);
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.feedIntervalMinutes, 30);
      await expectLater(settings.setFeedInterval(0), throwsArgumentError);
      await expectLater(
        settings.setNightStartTime('24:00'),
        throwsArgumentError,
      );
    },
  );

  test(
    'failed settings update rolls back and restores the countdown through listeners',
    () async {
      final failing = FailingStorage();
      final settings = SettingsProvider(storage: failing);
      addTearDown(settings.dispose);
      await settings.ready;
      failing.fail = true;
      await expectLater(settings.setFeedInterval(60), throwsStateError);
      expect(settings.feedIntervalMinutes, 180);
      expect(settings.error, isNotNull);
      expect(settings.isSaving, isFalse);
    },
  );

  test(
    'night windows have inclusive starts, exclusive ends, and safe invalid input',
    () {
      bool night(String start, String end, int hour, int minute) =>
          TimeUtils.isInNightMode(
            start,
            end,
            now: DateTime(2026, 9, 25, hour, minute),
          );
      expect(night('22:00', '06:00', 21, 59), isFalse);
      expect(night('22:00', '06:00', 22, 0), isTrue);
      expect(night('22:00', '06:00', 5, 59), isTrue);
      expect(night('22:00', '06:00', 6, 0), isFalse);
      expect(night('02:00', '06:00', 3, 0), isTrue);
      expect(night('06:00', '06:00', 6, 0), isFalse);
      expect(night('bad', '06:00', 5, 0), isFalse);
      expect(TimeUtils.formatDuration(const Duration(seconds: -1)), '00:00:00');
    },
  );
}
