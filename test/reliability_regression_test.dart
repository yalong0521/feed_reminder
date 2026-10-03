import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  bool playing = false;
  bool failStop = false;
  int stops = 0;
  @override
  Future<void> playReminder({bool loop = true}) async {
    playing = true;
  }

  @override
  Future<void> stopReminder() async {
    stops++;
    if (failStop) throw StateError('transient audio stop failure');
    playing = false;
  }
}

class _Notifications extends NotificationService {
  int schedules = 0;
  int shows = 0;
  bool? lastShownSound;

  @override
  bool get isSupported => false;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {
    shows++;
    lastShownSound = playSound;
  }

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {
    schedules++;
  }
}

class _PendingStorage extends StorageService {
  final gate = Completer<void>();
  int writes = 0;
  @override
  Future<void> setFeedHistory(List<FeedRecord> records) async {
    writes++;
    await gate.future;
    await super.setFeedHistory(records);
  }
}

Future<void> _mountApp(
  WidgetTester tester,
  StorageService storage,
  FeedProvider feed,
  SettingsProvider settings,
  _Audio audio,
  _Notifications notifications,
) async {
  await storage.setAcceptedPrivacyPolicyVersion(PrivacyPolicy.version);
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FeedReminderApp(
      storage: storage,
      feedProvider: feed,
      settingsProvider: settings,
      audioService: audio,
      notificationService: notifications,
      enablePlatformEffects: false,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a button must recover after disabling during a press', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter update;
    const contentKey = ValueKey('press-regression-content');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AppButton(
                  onPressed: enabled ? () {} : null,
                  child: const SizedBox(
                    key: contentKey,
                    width: 120,
                    height: 40,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final originalWidth = tester.getRect(find.byKey(contentKey)).width;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppButton)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    update(() => enabled = false);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    update(() => enabled = true);
    await tester.pumpAndSettle();
    final restoredWidth = tester.getRect(find.byKey(contentKey)).width;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(restoredWidth, closeTo(originalWidth, .01));
  });

  testWidgets('recording retries a transient audio stop failure', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 27, 12);
    SharedPreferences.setMockInitialValues({
      StorageKeys.feedIntervalMinutes: 60,
      StorageKeys.feedHistory: jsonEncode([
        FeedRecord(time: now.subtract(const Duration(hours: 2))).toJson(),
      ]),
    });
    final audio = _Audio();
    final feed = FeedProvider(
      storage: StorageService(),
      audioService: audio,
      notificationService: _Notifications(),
      clock: () => now,
    );
    await feed.ready;
    await tester.pump();
    expect(audio.playing, isTrue);
    audio.failStop = true;
    await feed.recordFeed();
    await tester.pump();
    expect(feed.state, FeedState.normal);
    expect(feed.feedHistory, hasLength(2));
    audio.failStop = false;
    final attempts = audio.stops;
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    final stillPlaying = audio.playing;
    final retried = audio.stops > attempts;
    feed.dispose();
    expect(
      stillPlaying,
      isFalse,
      reason: 'The stop operation is healthy again; retried=$retried',
    );
  });

  testWidgets(
    'recording beyond 100 entries and undo preserves all original records',
    (tester) async {
      final now = DateTime(2026, 9, 27, 12);
      final originals = [
        for (var i = 1; i <= 100; i++)
          FeedRecord(
            id: 'original-$i',
            time: now.subtract(Duration(hours: i)),
          ),
      ];
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedHistory: jsonEncode(
          originals.map((r) => r.toJson()).toList(),
        ),
        StorageKeys.burnInProtectionEnabled: false,
      });
      final storage = StorageService();
      final audio = _Audio();
      final notifications = _Notifications();
      final feed = FeedProvider(
        storage: storage,
        audioService: audio,
        notificationService: notifications,
        clock: () => now,
        startTimer: false,
      );
      final settings = SettingsProvider(storage: storage);
      await Future.wait([feed.ready, settings.ready]);
      await _mountApp(tester, storage, feed, settings, audio, notifications);
      final thumb = tester.getCenter(
        find.byKey(const ValueKey('feed-slide-thumb')),
      );
      final track = tester.getRect(
        find.byKey(const ValueKey('feed-slide-track')),
      );
      await tester.dragFrom(thumb, Offset(track.right - 4 - thumb.dx, 0));
      await tester.pumpAndSettle();
      expect(feed.feedHistory, hasLength(101));
      await tester.tap(find.byKey(const ValueKey('feed-slide-undo')));
      await tester.pumpAndSettle();
      final restoredIds = feed.feedHistory.map((r) => r.id).toList();
      final persistedIds = (await storage.getFeedHistory())
          .map((r) => r.id)
          .toList();
      await tester.pumpWidget(const SizedBox.shrink());
      feed.dispose();
      settings.dispose();
      expect(restoredIds, originals.map((r) => r.id).toList());
      expect(persistedIds, originals.map((r) => r.id).toList());
    },
  );

  testWidgets(
    'a damaged display preference must not overwrite reminder policy',
    (tester) async {
      var now = DateTime(2026, 10, 3, 20, 45);
      SharedPreferences.setMockInitialValues({
        StorageKeys.feedIntervalMinutes: 60,
        StorageKeys.nightModeEnabled: true,
        StorageKeys.nightStartTime: '21:00',
        StorageKeys.nightEndTime: '05:00',
        StorageKeys.soundEnabled: false,
        StorageKeys.soundLoopEnabled: false,
        StorageKeys.burnInProtectionEnabled: 'invalid-bool',
        StorageKeys.feedHistory: jsonEncode([
          FeedRecord(time: now.subtract(const Duration(minutes: 30))).toJson(),
        ]),
      });
      final storage = StorageService();
      final audio = _Audio();
      final notifications = _Notifications();
      final feed = FeedProvider(
        storage: storage,
        audioService: audio,
        notificationService: notifications,
        clock: () => now,
        startTimer: false,
      );
      final settings = SettingsProvider(storage: storage);
      try {
        await Future.wait([feed.ready, settings.ready]);
        expect(settings.error, isNull);
        expect(settings.isAvailable, isTrue);
        expect(settings.feedIntervalMinutes, 60);
        expect(settings.nightModeEnabled, isTrue);
        expect(settings.nightStartTime, '21:00');
        expect(settings.nightEndTime, '05:00');
        expect(settings.soundEnabled, isFalse);
        expect(settings.soundLoopEnabled, isFalse);
        expect(
          settings.burnInProtectionEnabled,
          AppDefaults.burnInProtectionEnabled,
        );

        await _mountApp(tester, storage, feed, settings, audio, notifications);
        expect(feed.error, isNull);
        expect(feed.feedIntervalMinutes, 60);
        expect(feed.timeRemaining, const Duration(minutes: 30));
        // The deadline falls inside the saved quiet window. Synchronizing the
        // recovered settings must not replace it with the default night policy.
        expect(notifications.schedules, 0);
        now = DateTime(2026, 10, 3, 21, 30);
        await feed.refresh();
        await tester.pump();
        expect(feed.state, FeedState.alerting);
        expect(notifications.shows, 0);
        expect(audio.playing, isFalse);

        // The saved end is 05:00, earlier than the default. Its overdue visual
        // notification may now appear, while the saved sound-off policy stays.
        now = DateTime(2026, 10, 4, 5, 30);
        await feed.refresh();
        await tester.pump();
        expect(notifications.shows, 1);
        expect(notifications.lastShownSound, isFalse);
        expect(audio.playing, isFalse);
        expect(await storage.getFeedInterval(), 60);
        expect(await storage.getNightModeEnabled(), isTrue);
        expect(await storage.getNightStartTime(), '21:00');
        expect(await storage.getNightEndTime(), '05:00');
        expect(await storage.getSoundEnabled(), isFalse);
        expect(await storage.getSoundLoopEnabled(), isFalse);
        expect(await storage.getFeedHistory(), hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        feed.dispose();
        settings.dispose();
        await tester.pump();
      }
    },
  );

  testWidgets('a pending backfill cannot dismiss via barrier or back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.burnInProtectionEnabled: false,
    });
    final storage = _PendingStorage();
    final audio = _Audio();
    final notifications = _Notifications();
    final feed = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      startTimer: false,
    );
    final settings = SettingsProvider(storage: storage);
    await Future.wait([feed.ready, settings.ready]);
    await _mountApp(tester, storage, feed, settings, audio, notifications);
    await tester.tap(find.byKey(const ValueKey('backfill-feed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-feed-save')));
    await tester.pump();
    expect(storage.writes, 1);
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(find.byType(AddFeedRecordDialog), findsOneWidget);
    await Navigator.of(
      tester.element(find.byType(AddFeedRecordDialog)),
    ).maybePop();
    await tester.pump();
    expect(find.byType(AddFeedRecordDialog), findsOneWidget);
    storage.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsNothing);
    expect(feed.feedHistory, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    feed.dispose();
    settings.dispose();
  });
}
