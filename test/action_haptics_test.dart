import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/models/deferred_reminder.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/history_screen.dart';
import 'package:feed_reminder/screens/home_screen.dart';
import 'package:feed_reminder/screens/settings_screen.dart';
import 'package:feed_reminder/services/app_haptics.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}
  @override
  Future<void> stopReminder() async {}
}

class _Notifications extends NotificationService {
  @override
  bool get isSupported => false;
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
  @override
  Future<void> cancelAll() async {}
}

class _Storage extends StorageService {
  Completer<void>? gate;
  bool fail = false;
  int writes = 0;

  Future<void> _write() async {
    writes++;
    await gate?.future;
    if (fail) throw StateError('simulated save failure');
  }

  @override
  Future<void> setFeedInterval(int minutes) async {
    await _write();
    await super.setFeedInterval(minutes);
  }

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    await _write();
    await super.saveFeedState(records);
  }

  @override
  Future<void> setAcknowledgedFeedRecord(FeedRecord? record) async {
    await _write();
    await super.setAcknowledgedFeedRecord(record);
  }

  @override
  Future<void> setDeferredReminder(DeferredReminder reminder) async {
    await _write();
    await super.setDeferredReminder(reminder);
  }
}

typedef _Scenario = ({
  _Storage storage,
  FeedProvider feed,
  SettingsProvider settings,
});
final _now = DateTime(2026, 10, 5, 12);

Future<_Scenario> _launch(
  WidgetTester tester,
  Widget home, {
  bool record = false,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({
    StorageKeys.feedIntervalMinutes: 180,
    StorageKeys.defaultMilkAmountMl: 120,
    StorageKeys.burnInProtectionEnabled: false,
    if (record)
      StorageKeys.feedHistory: jsonEncode([
        FeedRecord(
          id: 'meal',
          time: _now.subtract(const Duration(hours: 4)),
          milkAmountMl: 120,
        ).toJson(),
      ]),
  });
  final storage = _Storage();
  final settings = SettingsProvider(storage: storage);
  final notifications = _Notifications();
  final feed = FeedProvider(
    storage: storage,
    audioService: _Audio(),
    notificationService: notifications,
    startTimer: false,
    clock: () => _now,
  );
  await Future.wait([settings.ready, feed.ready]);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: feed),
        ChangeNotifierProvider.value(value: settings),
        Provider<NotificationService>.value(value: notifications),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
  storage.writes = 0;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    feed.dispose();
    settings.dispose();
  });
  return (storage: storage, feed: feed, settings: settings);
}

Finder _key(String key) => find.byKey(ValueKey(key));

Widget _tabbedPage(ValueNotifier<bool> active, Widget Function(bool) page) =>
    ValueListenableBuilder<bool>(
      valueListenable: active,
      builder: (context, isActive, _) => IndexedStack(
        index: isActive ? 0 : 1,
        children: [page(isActive), const Text('另一个页面')],
      ),
    );

Future<void> _recordWithSlider(WidgetTester tester) async {
  final track = _key('feed-slide-track');
  await tester.ensureVisible(track);
  await tester.pumpAndSettle();
  await tester.drag(
    _key('feed-slide-thumb'),
    Offset(tester.getSize(track).width, 0),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pulses = <String>[];
  void resetFeedback() {
    pulses.clear();
    AppHaptics.resetForTesting();
  }

  setUp(() {
    resetFeedback();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            pulses.add(call.arguments as String);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    resetFeedback();
  });

  for (final undo in [false, true]) {
    for (final fail in [false, true]) {
      testWidgets(
        '${undo ? 'undo' : 'record'} ${fail ? 'failure' : 'success'} stays quiet after changing tabs without cancelling persistence',
        (tester) async {
          final active = ValueNotifier(true);
          addTearDown(active.dispose);
          final scenario = await _launch(
            tester,
            _tabbedPage(active, (isActive) => HomeScreen(isActive: isActive)),
          );
          if (undo) {
            await _recordWithSlider(tester);
            await tester.pumpAndSettle();
            expect(scenario.feed.feedHistory, hasLength(1));
            expect(pulses, ['HapticFeedbackType.lightImpact']);
            resetFeedback();
          }
          scenario.storage.gate = Completer<void>();
          scenario.storage.fail = fail;
          if (undo) {
            await tester.tap(_key('feed-slide-undo'));
            await tester.pump();
          } else {
            await _recordWithSlider(tester);
          }
          expect(scenario.feed.isSaving, isTrue);
          expect(pulses, isEmpty);
          active.value = false;
          await tester.pump();
          scenario.storage.gate!.complete();
          await tester.pumpAndSettle();
          expect(pulses, isEmpty);
          expect(scenario.feed.isSaving, isFalse);
          expect(scenario.feed.feedHistory, hasLength(undo == fail ? 1 : 0));
          // Returning to the page must reveal the saved outcome, not replay it.
          active.value = true;
          await tester.pumpAndSettle();
          expect(pulses, isEmpty);
          expect(
            find.text(
              undo ? (fail ? '撤销失败' : '滑动记录喂奶') : (fail ? '未保存，右滑重试' : '已记录'),
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  for (final fail in [false, true]) {
    testWidgets(
      'history deletion ${fail ? 'failure' : 'success'} stays quiet when its tab is no longer active',
      (tester) async {
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        final scenario = await _launch(
          tester,
          _tabbedPage(active, (isActive) => HistoryScreen(isActive: isActive)),
          record: true,
        );
        scenario.storage.gate = Completer<void>();
        scenario.storage.fail = fail;
        await _tap(tester, _key('delete-record-meal'));
        await tester.tap(_key('confirm-delete-record'));
        await tester.pump();
        expect(scenario.feed.isSaving, isTrue);
        active.value = false;
        await tester.pump();
        scenario.storage.gate!.complete();
        await tester.pumpAndSettle();
        expect(pulses, isEmpty);
        expect(scenario.feed.feedHistory, hasLength(fail ? 1 : 0));
        expect(find.text('删除失败，请重试'), findsNothing);
        active.value = true;
        await tester.pumpAndSettle();
        expect(pulses, isEmpty);
      },
    );
  }

  testWidgets(
    'settings haptics follow changed persistence and reject invalid input',
    (tester) async {
      final scenario = await _launch(tester, const SettingsScreen());
      await _tap(tester, _key('custom-interval-button'));
      expect(pulses, isEmpty);
      await _tap(tester, find.text('保存'));
      expect(scenario.storage.writes, 0);
      expect(pulses, isEmpty);
      await _tap(tester, _key('custom-interval-button'));
      await tester.enterText(_key('custom-interval-field'), '75');
      await _tap(tester, find.text('取消'));
      expect(pulses, isEmpty);
      expect(scenario.storage.writes, 0);

      await _tap(tester, _key('custom-interval-button'));
      await tester.enterText(_key('custom-interval-field'), '120.5');
      await _tap(tester, find.text('保存'));
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
      expect(scenario.storage.writes, 0);
      resetFeedback();
      await tester.enterText(_key('custom-interval-field'), '75');
      scenario.storage.gate = Completer<void>();
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(pulses, isEmpty);
      scenario.storage.gate!.complete();
      await tester.pumpAndSettle();
      expect(scenario.settings.feedIntervalMinutes, 75);
      expect(pulses, ['HapticFeedbackType.selectionClick']);

      resetFeedback();
      scenario.storage.gate = null;
      scenario.storage.fail = true;
      await _tap(tester, _key('custom-interval-button'));
      await tester.enterText(_key('custom-interval-field'), '90');
      await _tap(tester, find.text('保存'));
      expect(scenario.settings.feedIntervalMinutes, 75);
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
    },
  );

  testWidgets('meal amount only signals an effective confirmed change', (
    tester,
  ) async {
    await _launch(tester, const HomeScreen());
    await _tap(tester, _key('adjust-meal-amount'));
    await tester.enterText(_key('milk-amount-input'), '90');
    await _tap(tester, _key('meal-amount-cancel'));
    expect(pulses, isEmpty);
    await _tap(tester, _key('adjust-meal-amount'));
    await _tap(tester, _key('meal-amount-apply'));
    expect(pulses, isEmpty);
    await _tap(tester, _key('adjust-meal-amount'));
    await _tap(tester, _key('meal-amount-reset'));
    expect(pulses, isEmpty);
    await _tap(tester, _key('adjust-meal-amount'));
    await tester.enterText(_key('milk-amount-input'), '90');
    await _tap(tester, _key('meal-amount-apply'));
    expect(pulses, ['HapticFeedbackType.selectionClick']);
    resetFeedback();
    await _tap(tester, _key('adjust-meal-amount'));
    await _tap(tester, _key('meal-amount-reset'));
    expect(pulses, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets(
    'stopping reminder coalesces taps and signals failed then successful persistence',
    (tester) async {
      final scenario = await _launch(tester, const HomeScreen(), record: true);
      scenario.storage.gate = Completer<void>();
      scenario.storage.fail = true;
      final stop = tester
          .widget<AppButton>(
            find.ancestor(
              of: find.text('停止本次提醒'),
              matching: find.byType(AppButton),
            ),
          )
          .onPressed!;
      stop();
      stop();
      await tester.pump();
      expect(pulses, isEmpty);
      expect(scenario.storage.writes, 1);
      scenario.storage.gate!.complete();
      await tester.pumpAndSettle();
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
      expect(scenario.feed.isAlertAcknowledgementPersisted, isFalse);
      await _tap(tester, _key('app-notice-close'));
      resetFeedback();
      scenario.storage.gate = null;
      scenario.storage.fail = false;
      await _tap(tester, find.text('重试保存停止状态'));
      expect(scenario.feed.isAlertAcknowledgementPersisted, isTrue);
      expect(pulses, ['HapticFeedbackType.lightImpact']);
      expect(scenario.storage.writes, 2);
    },
  );

  testWidgets(
    'snooze cancellation is quiet and failures never signal success',
    (tester) async {
      final scenario = await _launch(tester, const HomeScreen(), record: true);
      await _tap(tester, _key('snooze-reminder'));
      await _tap(tester, find.text('取消'));
      expect(pulses, isEmpty);
      scenario.storage.fail = true;
      await _tap(tester, _key('snooze-reminder'));
      await _tap(tester, _key('snooze-10'));
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
      await _tap(tester, _key('app-notice-close'));
      resetFeedback();
      scenario.storage.fail = false;
      await _tap(tester, _key('snooze-reminder'));
      await _tap(tester, _key('snooze-10'));
      expect(pulses, ['HapticFeedbackType.lightImpact']);
    },
  );

  testWidgets(
    'backfill and edits signal validation and persisted outcomes only',
    (tester) async {
      final scenario = await _launch(tester, const HistoryScreen());
      await _tap(tester, _key('history-backfill-button'));
      await tester.enterText(_key('milk-amount-input'), '2001');
      await _tap(tester, _key('add-feed-save'));
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
      resetFeedback();
      await _tap(tester, _key('add-feed-cancel'));
      expect(pulses, isEmpty);
      await _tap(tester, _key('history-backfill-button'));
      scenario.storage.gate = Completer<void>();
      await tester.tap(_key('add-feed-save'));
      await tester.pump();
      expect(pulses, isEmpty);
      scenario.storage.gate!.complete();
      await tester.pumpAndSettle();
      expect(pulses, ['HapticFeedbackType.lightImpact']);
      final record = scenario.feed.feedHistory.single;
      scenario.storage.gate = null;
      resetFeedback();
      await _tap(tester, _key('edit-record-${record.id}'));
      await _tap(tester, _key('add-feed-save'));
      expect(pulses, isEmpty);
      await _tap(tester, _key('edit-record-${record.id}'));
      await tester.enterText(_key('milk-amount-input'), '90');
      scenario.storage.fail = true;
      await _tap(tester, _key('add-feed-save'));
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
      expect(scenario.feed.feedHistory.single.milkAmountMl, 120);
      resetFeedback();
      scenario.storage.fail = false;
      await _tap(tester, _key('add-feed-save'));
      expect(pulses, ['HapticFeedbackType.lightImpact']);
      expect(scenario.feed.feedHistory.single.milkAmountMl, 90);
    },
  );

  testWidgets(
    'deletion only confirms after persistence and cancellation is quiet',
    (tester) async {
      final scenario = await _launch(
        tester,
        const HistoryScreen(),
        record: true,
      );
      await _tap(tester, _key('delete-record-meal'));
      await _tap(tester, _key('cancel-delete-record'));
      expect(pulses, isEmpty);
      scenario.storage.fail = true;
      await _tap(tester, _key('delete-record-meal'));
      await _tap(tester, _key('confirm-delete-record'));
      expect(pulses, ['HapticFeedbackType.mediumImpact']);
      expect(scenario.feed.feedHistory, hasLength(1));
      await _tap(tester, _key('app-notice-close'));
      resetFeedback();
      scenario.storage.fail = false;
      scenario.storage.gate = Completer<void>();
      await _tap(tester, _key('delete-record-meal'));
      await tester.tap(_key('confirm-delete-record'));
      await tester.pump();
      expect(pulses, isEmpty);
      scenario.storage.gate!.complete();
      await tester.pumpAndSettle();
      expect(scenario.feed.feedHistory, isEmpty);
      expect(pulses, ['HapticFeedbackType.lightImpact']);
    },
  );
}
