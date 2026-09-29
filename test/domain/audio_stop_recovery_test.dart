import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  bool playing = false;
  bool failStop = false;
  int stops = 0;
  int plays = 0;
  Completer<void>? nextStopGate;
  void Function()? onPlay;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> playReminder({bool loop = true}) async {
    if (playing) return;
    plays++;
    playing = true;
    onPlay?.call();
  }

  @override
  Future<void> stopReminder() async {
    stops++;
    final gate = nextStopGate;
    nextStopGate = null;
    await gate?.future;
    if (failStop) throw StateError('Temporary audio stop failure');
    playing = false;
  }
}

class _Notifications extends Fake implements NotificationService {
  int cancellations = 0;
  int schedules = 0;
  bool failCancellation = false;

  @override
  Future<void> cancelAll() async {
    cancellations++;
    if (failCancellation) throw StateError('Temporary notification failure');
  }

  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {
    schedules++;
  }
}

void main() {
  late DateTime now;
  late StorageService storage;
  late _Audio audio;
  late _Notifications notifications;
  late FeedProvider feed;
  FeedProvider? activeFeed;

  Future<void> start(WidgetTester tester) async {
    now = DateTime(2026, 9, 27, 12);
    SharedPreferences.setMockInitialValues({
      StorageKeys.feedIntervalMinutes: 60,
      StorageKeys.nightModeEnabled: false,
      StorageKeys.soundEnabled: true,
      StorageKeys.soundLoopEnabled: true,
      StorageKeys.feedHistory: jsonEncode([
        FeedRecord(
          id: 'previous-feeding',
          time: now.subtract(const Duration(hours: 2)),
        ).toJson(),
      ]),
    });
    storage = StorageService();
    audio = _Audio();
    notifications = _Notifications();
    feed = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      clock: () => now,
    );
    activeFeed = feed;
    await feed.ready;
    // Local readiness no longer waits for the serialized reminder effects.
    await tester.pump();
    expect(feed.state, FeedState.alerting);
    expect(audio.playing, isTrue);
  }

  void recoveryTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        activeFeed?.dispose();
        activeFeed = null;
        await tester.pump();
      }
    });
  }

  recoveryTest(
    'a committed feeding retries failed audio stop without repeating native scheduling',
    (tester) async {
      await start(tester);
      audio.failStop = true;
      await feed.recordFeed();
      await tester.pump();
      expect(feed.state, FeedState.normal);
      expect(feed.isSaving, isFalse);
      expect(feed.feedHistory, hasLength(2));
      expect(await storage.getFeedHistory(), hasLength(2));
      expect(feed.error, '声音停止失败，请重试');
      expect(audio.playing, isTrue);
      final stops = audio.stops;
      final schedules = notifications.schedules;
      final cancellations = notifications.cancellations;

      audio.failStop = false;
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(audio.stops, stops + 1);
      expect(audio.playing, isFalse);
      expect(feed.error, isNull);
      expect(notifications.schedules, schedules);
      expect(notifications.cancellations, cancellations);

      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(audio.stops, stops + 1);
      expect(audio.plays, 1);
      expect(feed.feedHistory, hasLength(2));
    },
  );

  recoveryTest('a slow recovery cannot accumulate timer retries', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    await feed.recordFeed();
    await tester.pump();
    final failedStops = audio.stops;
    audio.failStop = false;
    final gate = audio.nextStopGate = Completer<void>();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(audio.stops, failedStops + 1);

    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(audio.stops, failedStops + 1);
    gate.complete();
    await tester.pump();
    expect(audio.playing, isFalse);
    expect(feed.error, isNull);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(audio.stops, failedStops + 1);
  });

  recoveryTest('an obsolete failed stop cannot silence the next due cycle', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    await feed.recordFeed();
    await tester.pump();
    final failedStops = audio.stops;
    audio.failStop = false;
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(feed.state, FeedState.alerting);
    expect(audio.playing, isTrue);
    expect(audio.stops, failedStops);
    await tester.pump(const Duration(seconds: 5));
    expect(audio.stops, failedStops);

    // A later explicit stop still works after discarding the obsolete retry.
    await feed.stopAlert();
    expect(audio.playing, isFalse);
    expect(feed.isAlertAcknowledged, isTrue);
  });

  recoveryTest('a new due cycle can play after an in-flight recovery stops', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    await feed.recordFeed();
    await tester.pump();
    audio.failStop = false;
    final gate = audio.nextStopGate = Completer<void>();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final stops = audio.stops;
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(seconds: 20));
    expect(audio.stops, stops);
    gate.complete();
    await tester.pump();
    expect(feed.state, FeedState.alerting);
    expect(audio.playing, isTrue);
    expect(audio.plays, 2);
    expect(audio.stops, stops);
  });

  recoveryTest('queued loop changes replay after each successful stop', (
    tester,
  ) async {
    await start(tester);
    final gate = audio.nextStopGate = Completer<void>();
    feed.updateSettings(soundLoopEnabled: false);
    await tester.pump();
    expect(audio.stops, 1);
    feed.updateSettings(soundLoopEnabled: true);
    await tester.pump();
    gate.complete();
    await tester.pump();
    expect(audio.stops, 2);
    expect(audio.playing, isTrue);
    expect(audio.plays, 3);
    expect(feed.error, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(audio.stops, 2);
    expect(audio.plays, 3);
  });

  recoveryTest(
    'slow recovery does not queue overdue work before backgrounding',
    (tester) async {
      await start(tester);
      audio.failStop = true;
      await feed.recordFeed();
      await tester.pump();
      audio.failStop = false;
      final gate = audio.nextStopGate = Completer<void>();
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final stops = audio.stops;
      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 20));

      // The user leaves as the next reminder starts. Only its in-flight cleanup
      // and the lifecycle update need a stop; accumulated timer work would add
      // one more unnecessary stop per elapsed tick.
      audio.onPlay = () => feed.setForeground(false);
      gate.complete();
      await tester.pump();
      expect(audio.plays, 2);
      expect(audio.playing, isFalse);
      expect(audio.stops, stops + 2);
    },
  );

  recoveryTest('failed settings restart does not replay over existing sound', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    feed.updateSettings(soundLoopEnabled: false);
    await tester.pump();
    expect(audio.playing, isTrue);
    expect(audio.plays, 1);
    expect(feed.error, isNotNull);
    final stops = audio.stops;
    await tester.pump(const Duration(seconds: 5));
    expect(audio.stops, stops);

    audio.failStop = false;
    feed.updateSettings(soundLoopEnabled: true);
    await tester.pump();
    expect(audio.playing, isTrue);
    expect(audio.plays, 2);
    expect(feed.error, isNull);
  });

  recoveryTest('audio recovery preserves an unresolved notification failure', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    notifications.failCancellation = true;
    await feed.recordFeed();
    await tester.pump();
    expect(feed.feedHistory, hasLength(2));
    expect(feed.error, '声音停止失败，请重试');
    final cancellations = notifications.cancellations;
    audio.failStop = false;
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(audio.playing, isFalse);
    expect(notifications.cancellations, cancellations);
    expect(feed.error, '系统通知暂时失败，请稍后重试');

    notifications.failCancellation = false;
    await feed.refresh();
    expect(notifications.cancellations, cancellations + 1);
    expect(feed.error, isNull);
  });

  recoveryTest('background recovery stops audio without foreground playback', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    feed.setForeground(false);
    await tester.pump();
    expect(audio.playing, isTrue);
    final stops = audio.stops;
    audio.failStop = false;
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(audio.stops, stops + 1);
    expect(audio.playing, isFalse);
    expect(audio.plays, 1);
    feed.setForeground(true);
    await tester.pump();
    expect(audio.playing, isTrue);
    expect(audio.plays, 2);
  });

  recoveryTest('failed explicit acknowledgement still requires user retry', (
    tester,
  ) async {
    await start(tester);
    audio.failStop = true;
    await expectLater(feed.stopAlert(), throwsStateError);
    expect(feed.isAlertAcknowledged, isFalse);
    expect(await storage.getAcknowledgedFeedTime(), isNull);
    final failedStops = audio.stops;
    audio.failStop = false;
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(audio.stops, failedStops);
    expect(audio.playing, isTrue);

    await feed.stopAlert();
    expect(audio.playing, isFalse);
    expect(feed.isAlertAcknowledged, isTrue);
    expect(await storage.getAcknowledgedFeedTime(), feed.lastFeedTime);
    expect(feed.error, isNull);
  });
}
