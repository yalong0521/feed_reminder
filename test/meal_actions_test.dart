import 'dart:convert';
import 'dart:async';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/deferred_reminder.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  int stops = 0;

  @override
  Future<void> playReminder({bool loop = true}) async {}

  @override
  Future<void> stopReminder() async => stops++;
}

class _Notifications extends NotificationService {
  @override
  bool get isSupported => false;

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}

  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}

  @override
  Future<void> cancelAll() async {}
}

class _Storage extends StorageService {
  bool failRecords = false;
  bool failSnooze = false;
  bool failAcknowledgement = false;
  Completer<void>? acknowledgementGate;

  @override
  Future<void> setAcknowledgedFeedRecord(FeedRecord? record) async {
    await acknowledgementGate?.future;
    if (failAcknowledgement) {
      throw StateError('simulated acknowledgement write failure');
    }
    await super.setAcknowledgedFeedRecord(record);
  }

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    if (failRecords) throw StateError('simulated full storage');
    await super.saveFeedState(records);
  }

  @override
  Future<void> setDeferredReminder(DeferredReminder reminder) async {
    if (failSnooze) throw StateError('simulated snooze write failure');
    await super.setDeferredReminder(reminder);
  }
}

class _Scenario {
  const _Scenario(this.storage, this.feed, this.settings, this.audio);
  final _Storage storage;
  final FeedProvider feed;
  final SettingsProvider settings;
  final _Audio audio;
}

final _now = DateTime(2026, 10, 3, 12);

Future<_Scenario> _launch(
  WidgetTester tester, {
  bool overdue = false,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({
    'acceptedPrivacyPolicyVersion': PrivacyPolicy.version,
    StorageKeys.defaultMilkAmountMl: 120,
    StorageKeys.burnInProtectionEnabled: false,
    StorageKeys.feedIntervalMinutes: 180,
    if (overdue)
      StorageKeys.feedHistory: jsonEncode([
        FeedRecord(
          id: 'previous-meal',
          time: _now.subtract(const Duration(hours: 4)),
          milkAmountMl: 110,
        ).toJson(),
      ]),
  });
  final storage = _Storage();
  final settings = SettingsProvider(storage: storage);
  final audio = _Audio();
  final notifications = _Notifications();
  final feed = FeedProvider(
    storage: storage,
    audioService: audio,
    notificationService: notifications,
    startTimer: false,
    clock: clock ?? () => _now,
  );
  await Future.wait([settings.ready, feed.ready]);
  await tester.pumpWidget(
    FeedReminderApp(
      storage: storage,
      settingsProvider: settings,
      feedProvider: feed,
      audioService: audio,
      notificationService: notifications,
      enablePlatformEffects: false,
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    feed.dispose();
    settings.dispose();
  });
  return _Scenario(storage, feed, settings, audio);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final control = find.byKey(ValueKey(key));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _adjust(WidgetTester tester, int amount) async {
  await _tap(tester, 'adjust-meal-amount');
  await tester.enterText(
    find.byKey(const ValueKey('milk-amount-input')),
    '$amount',
  );
  await _tap(tester, 'meal-amount-apply');
}

Future<void> _slide(WidgetTester tester) async {
  final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
  await tester.ensureVisible(thumb);
  await tester.pumpAndSettle();
  final start = tester.getCenter(thumb);
  final track = tester.getRect(find.byKey(const ValueKey('feed-slide-track')));
  await tester.dragFrom(start, Offset(track.right - 4 - start.dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed stop confirmation has an explicit retry action', (
    tester,
  ) async {
    final scenario = await _launch(tester, overdue: true);
    scenario.storage.failAcknowledgement = true;
    scenario.storage.acknowledgementGate = Completer<void>();
    await tester.tap(find.text('停止本次提醒'));
    await tester.pump();
    expect(find.text('正在停止提醒…'), findsOneWidget);
    scenario.storage.acknowledgementGate!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('重试保存停止状态').hitTestable(), findsOneWidget);
    expect(scenario.feed.isAlertAcknowledgementPersisted, isFalse);
    scenario.storage.failAcknowledgement = false;
    scenario.storage.acknowledgementGate = null;
    await tester.tap(find.text('重试保存停止状态'));
    await tester.pumpAndSettle();
    expect(find.text('本次提醒已停止'), findsOneWidget);
    expect(scenario.feed.isAlertAcknowledgementPersisted, isTrue);
    expect(scenario.feed.error, isNull);
  });

  testWidgets(
    'temporary 90 mL records one meal then next meal uses unchanged 120 mL default',
    (tester) async {
      final scenario = await _launch(tester);
      expect(find.text('本次 120 mL'), findsOneWidget);
      await _adjust(tester, 90);
      expect(find.text('本次 90 mL'), findsOneWidget);
      expect(scenario.settings.defaultMilkAmountMl, 120);
      await _slide(tester);
      expect(scenario.feed.feedHistory.single.milkAmountMl, 90);
      expect((await scenario.storage.getFeedHistory()).single.milkAmountMl, 90);
      expect(scenario.settings.defaultMilkAmountMl, 120);
      expect(await scenario.storage.getDefaultMilkAmountMl(), 120);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('本次 120 mL'), findsOneWidget);
      expect(find.text('本次奶量 · 120 mL · 调整'), findsOneWidget);
      await _slide(tester);
      expect(
        scenario.feed.feedHistory.map((r) => r.milkAmountMl),
        containsAll([90, 120]),
      );
      expect(scenario.feed.feedHistory.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel retains an earlier adjustment and reset restores the current default',
    (tester) async {
      final scenario = await _launch(tester);
      await _adjust(tester, 90);
      await _tap(tester, 'adjust-meal-amount');
      final ruler = find.byKey(const ValueKey('milk-amount-ruler-scroll'));
      await tester.ensureVisible(ruler);
      await tester.pumpAndSettle();
      await tester.drag(ruler, const Offset(-90, 0));
      await tester.pumpAndSettle();
      final draft = tester
          .widget<CupertinoTextField>(
            find.byKey(const ValueKey('milk-amount-input')),
          )
          .controller!
          .text;
      expect(int.parse(draft), greaterThan(90));
      await _tap(tester, 'meal-amount-cancel');
      expect(find.text('本次 90 mL'), findsOneWidget);
      expect(find.text('本次奶量 · 90 mL · 已调整'), findsOneWidget);
      expect(scenario.feed.feedHistory, isEmpty);
      expect(scenario.settings.defaultMilkAmountMl, 120);
      await _tap(tester, 'adjust-meal-amount');
      await _tap(tester, 'meal-amount-reset');
      expect(find.text('本次 120 mL'), findsOneWidget);
      expect(find.text('本次奶量 · 120 mL · 调整'), findsOneWidget);
      expect(scenario.feed.feedHistory, isEmpty);
      expect(await scenario.storage.getDefaultMilkAmountMl(), 120);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed recording retains temporary amount for an actual slider retry',
    (tester) async {
      final scenario = await _launch(tester);
      await _adjust(tester, 90);
      scenario.storage.failRecords = true;
      await _slide(tester);
      expect(scenario.feed.feedHistory, isEmpty);
      expect(await scenario.storage.getFeedHistory(), isEmpty);
      expect(find.text('本次奶量 · 90 mL · 已调整'), findsOneWidget);
      expect(find.text('未保存，右滑重试'), findsOneWidget);
      expect(scenario.settings.defaultMilkAmountMl, 120);
      scenario.storage.failRecords = false;
      await _slide(tester);
      expect(scenario.feed.feedHistory.single.milkAmountMl, 90);
      expect((await scenario.storage.getFeedHistory()).single.milkAmountMl, 90);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('本次 120 mL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'meal editor rejects an invalid amount and can choose unrecorded without changing default',
    (tester) async {
      final scenario = await _launch(tester);
      await _tap(tester, 'adjust-meal-amount');
      final input = find.byKey(const ValueKey('milk-amount-input'));
      await tester.enterText(input, '2001');
      await _tap(tester, 'meal-amount-apply');
      expect(find.text('调整本次奶量'), findsOneWidget);
      expect(scenario.feed.feedHistory, isEmpty);
      await tester.enterText(input, '0');
      await _tap(tester, 'meal-amount-apply');
      expect(find.text('调整本次奶量'), findsNothing);
      await _slide(tester);
      expect(scenario.feed.feedHistory.single.milkAmountMl, 0);
      expect(scenario.settings.defaultMilkAmountMl, 120);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'snooze ten minutes changes only the reminder and persists no extra meal',
    (tester) async {
      final scenario = await _launch(tester, overdue: true);
      final before = scenario.feed.feedHistory.single.toJson();
      final lastFeedTime = scenario.feed.lastFeedTime;
      final stopsBefore = scenario.audio.stops;
      expect(scenario.feed.state, FeedState.alerting);
      await _tap(tester, 'snooze-reminder');
      expect(find.text('10 分钟后'), findsOneWidget);
      await _tap(tester, 'snooze-10');
      expect(scenario.feed.isReminderDeferred, isTrue);
      expect(scenario.feed.nextFeedTime, _now.add(const Duration(minutes: 10)));
      expect(scenario.feed.lastFeedTime, lastFeedTime);
      expect(scenario.feed.feedHistory.single.toJson(), before);
      expect((await scenario.storage.getFeedHistory()).single.toJson(), before);
      expect(
        (await scenario.storage.getDeferredReminder())!.remindAt,
        _now.add(const Duration(minutes: 10)),
      );
      expect(scenario.settings.feedIntervalMinutes, 180);
      expect(scenario.audio.stops, greaterThan(stopsBefore));
      expect(find.text('已延后提醒'), findsOneWidget);
      expect(find.text('下次提醒 12:10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'snooze opened five minutes earlier starts ten minutes from confirmation',
    (tester) async {
      var now = _now;
      final scenario = await _launch(tester, overdue: true, clock: () => now);
      final before = scenario.feed.feedHistory.single.toJson();
      await _tap(tester, 'snooze-reminder');
      expect(find.text('10 分钟后'), findsOneWidget);
      expect(find.textContaining('从确认时起延后本次提醒'), findsOneWidget);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await _tap(tester, 'snooze-10');
      final deadline = _now.add(const Duration(minutes: 15));
      expect(scenario.feed.nextFeedTime, deadline);
      expect(
        (await scenario.storage.getDeferredReminder())!.remindAt,
        deadline,
      );
      expect(scenario.feed.feedHistory.single.toJson(), before);
      expect(find.text('下次提醒 12:15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed snooze stays due, retains history and offers an error without fake success',
    (tester) async {
      final scenario = await _launch(tester, overdue: true);
      final before = scenario.feed.feedHistory.single.toJson();
      final originalDeadline = scenario.feed.nextFeedTime;
      scenario.storage.failSnooze = true;
      await _tap(tester, 'snooze-reminder');
      await _tap(tester, 'snooze-10');
      expect(scenario.feed.isReminderDeferred, isFalse);
      expect(scenario.feed.state, FeedState.alerting);
      expect(scenario.feed.nextFeedTime, originalDeadline);
      expect(scenario.feed.feedHistory.single.toJson(), before);
      expect(await scenario.storage.getDeferredReminder(), isNull);
      expect(find.text('已延后提醒'), findsNothing);
      expect(find.text('未能延后提醒，请确认当前提醒状态后重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
