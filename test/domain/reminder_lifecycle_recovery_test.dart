import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends Fake implements AudioPlayer {
  final completions = StreamController<void>.broadcast(sync: true);
  int plays = 0;
  int stops = 0;
  int releases = 0;
  bool failStop = false;
  Completer<void>? nextPlayGate;
  Completer<void>? playingGate;

  @override
  Stream<void> get onPlayerComplete => completions.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
    final gate = nextPlayGate;
    nextPlayGate = null;
    playingGate = gate;
    try {
      await gate?.future;
    } finally {
      playingGate = null;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw PlatformException(code: 'stop_failed');
  }

  @override
  Future<void> release() async {
    releases++;
  }

  @override
  Future<void> dispose() async {
    unawaited(completions.close());
  }
}

class _Notifications extends Fake implements NotificationService {
  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
}

class _Storage extends StorageService {
  bool failAcknowledgement = false;

  @override
  Future<void> setAcknowledgedFeedRecord(FeedRecord? record) async {
    if (failAcknowledgement) throw StateError('Acknowledgement write failed');
    await super.setAcknowledgedFeedRecord(record);
  }
}

void main() {
  late DateTime now;
  late _Storage storage;
  late _Player player;
  late AudioService audio;
  late FeedProvider feed;
  FeedProvider? activeFeed;
  AudioService? activeAudio;

  Future<void> start(WidgetTester tester, {bool loop = true}) async {
    now = DateTime(2026, 9, 27, 12);
    SharedPreferences.setMockInitialValues({
      StorageKeys.feedIntervalMinutes: 60,
      StorageKeys.nightModeEnabled: false,
      StorageKeys.soundEnabled: true,
      StorageKeys.soundLoopEnabled: loop,
      StorageKeys.feedHistory: jsonEncode([
        FeedRecord(
          id: 'previous-feeding',
          time: now.subtract(const Duration(hours: 2)),
        ).toJson(),
      ]),
    });
    storage = _Storage();
    player = _Player();
    audio = activeAudio = AudioService(playerFactory: () => player);
    feed = activeFeed = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: _Notifications(),
      clock: () => now,
    );
    await feed.ready;
    // Local readiness no longer waits for the serialized reminder effects.
    await tester.pump();
    expect(audio.isPlaying, isTrue);
  }

  void recoveryTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        final gate = player.playingGate;
        if (gate != null && !gate.isCompleted) gate.complete();
        activeFeed?.dispose();
        activeFeed = null;
        await tester.pump();
        final disposingAudio = activeAudio;
        activeAudio = null;
        if (disposingAudio != null) {
          // StreamSubscription.cancel may complete outside fakeAsync. Drain
          // playback first, then release the actual service in the real zone.
          await tester.runAsync(disposingAudio.dispose);
        }
        await tester.pump();
      }
    });
  }

  recoveryTest(
    'undo restores the persisted acknowledgement before and after restart',
    (tester) async {
      await start(tester);
      final previousTime = feed.lastFeedTime;
      await feed.stopAlert();
      expect(await storage.getAcknowledgedFeedTime(), previousTime);
      await feed.recordFeed();
      await tester.pump();
      expect(feed.isAlertAcknowledged, isFalse);
      await feed.deleteFeedRecord(0);
      await tester.pump();
      expect(feed.lastFeedTime, previousTime);
      expect(feed.isAlertAcknowledged, isTrue);
      expect(audio.isPlaying, isFalse);
      expect(player.plays, 1);

      feed.dispose();
      feed = activeFeed = FeedProvider(
        storage: storage,
        audioService: audio,
        notificationService: _Notifications(),
        clock: () => now,
      );
      await feed.ready;
      await tester.pump();
      expect(feed.isAlertAcknowledged, isTrue);
      await feed.recordFeed();
      await tester.pump();
      await feed.deleteFeedRecord(0);
      await tester.pump();
      expect(feed.isAlertAcknowledged, isTrue);
      expect(audio.isPlaying, isFalse);
      expect(player.plays, 1);
    },
  );

  recoveryTest(
    'a failed acknowledgement is not restored as committed after undo',
    (tester) async {
      await start(tester);
      storage.failAcknowledgement = true;
      await expectLater(feed.stopAlert(), throwsStateError);
      expect(feed.isAlertAcknowledged, isTrue);
      expect(await storage.getAcknowledgedFeedTime(), isNull);
      await feed.recordFeed();
      await tester.pump();
      await feed.deleteFeedRecord(0);
      await tester.pump();
      expect(feed.isAlertAcknowledged, isFalse);
      expect(audio.isPlaying, isTrue);
      expect(player.plays, 2);
    },
  );

  recoveryTest(
    'a looping reminder recovers after an asynchronous native error',
    (tester) async {
      await start(tester);
      player.completions.addError(PlatformException(code: 'playback_failed'));
      expect(audio.isPlaying, isFalse);
      final gate = player.nextPlayGate = Completer<void>();
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(player.plays, 2);
      expect(player.releases, 1);
      expect(feed.error, '提醒声音播放失败，请重试');
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(player.plays, 2);
      gate.complete();
      await tester.pump();
      expect(audio.isPlaying, isTrue);
      expect(feed.error, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(player.plays, 2);
    },
  );

  recoveryTest('normal one-shot completion never becomes automatic replay', (
    tester,
  ) async {
    await start(tester, loop: false);
    player.completions.add(null);
    await tester.pump(const Duration(seconds: 10));
    expect(audio.isPlaying, isFalse);
    expect(player.plays, 1);
    expect(feed.error, isNull);
  });

  recoveryTest('one-shot stream failures are visible without replaying audio', (
    tester,
  ) async {
    await start(tester, loop: false);
    player.completions.addError(PlatformException(code: 'playback_failed'));
    await tester.pump(const Duration(seconds: 1));
    expect(feed.error, '提醒声音播放失败，请重试');
    expect(audio.isPlaying, isFalse);
    expect(player.plays, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(player.plays, 1);
    expect(feed.error, '提醒声音播放失败，请重试');

    feed.updateSettings(soundEnabled: false);
    await tester.pump();
    expect(feed.error, isNull);
  });

  recoveryTest('acknowledging an errored reminder prevents automatic replay', (
    tester,
  ) async {
    await start(tester);
    player.completions.addError(PlatformException(code: 'playback_failed'));
    await feed.stopAlert();
    await tester.pump(const Duration(seconds: 10));
    expect(feed.isAlertAcknowledged, isTrue);
    expect(audio.isPlaying, isFalse);
    expect(player.plays, 1);
  });

  recoveryTest(
    'failed explicit stop cannot restart an already errored reminder',
    (tester) async {
      await start(tester);
      player.completions.addError(PlatformException(code: 'playback_failed'));
      player.failStop = true;
      await expectLater(feed.stopAlert(), throwsStateError);
      expect(feed.isAlertAcknowledged, isFalse);
      await feed.refresh();
      await tester.pump(const Duration(seconds: 10));
      expect(player.plays, 1);
      expect(audio.isPlaying, isFalse);
      player.failStop = false;
      feed.setForeground(false);
      await tester.pump();
      feed.setForeground(true);
      await tester.pump(const Duration(seconds: 10));
      expect(feed.isAlertAcknowledged, isFalse);
      expect(player.plays, 1);
      expect(audio.isPlaying, isFalse);
      await feed.stopAlert();
      expect(feed.isAlertAcknowledged, isTrue);
      expect(feed.error, isNull);
    },
  );

  recoveryTest(
    'an errored reminder stays stopped in background and resumes once',
    (tester) async {
      await start(tester);
      player.completions.addError(PlatformException(code: 'playback_failed'));
      feed.setForeground(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(audio.isPlaying, isFalse);
      expect(player.plays, 1);
      feed.setForeground(true);
      await tester.pump();
      expect(audio.isPlaying, isTrue);
      expect(player.plays, 2);
    },
  );
}
