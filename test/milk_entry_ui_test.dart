import 'dart:convert';
import 'dart:async';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/history_screen.dart';
import 'package:feed_reminder/screens/settings_screen.dart';
import 'package:feed_reminder/screens/statistics_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}
  @override
  Future<void> stopReminder() async {}
}

class _SilentNotifications extends NotificationService {
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
  bool failWrites = false;
  Future<void>? settingsReadGate;
  bool failSettingsRead = false;
  @override
  Future<int> getDefaultMilkAmountMl() async {
    await settingsReadGate;
    if (failSettingsRead) throw StateError('settings read failed');
    return super.getDefaultMilkAmountMl();
  }

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    if (failWrites) throw StateError('write failed');
    await super.saveFeedState(records);
  }
}

void main() {
  final now = DateTime(2026, 10, 3, 14, 30);
  late FeedProvider feed;
  late SettingsProvider settings;
  late _Storage storage;

  Future<void> launch(
    WidgetTester tester, {
    List<FeedRecord> records = const [],
    Widget home = const HistoryScreen(),
    int defaultAmount = 0,
    _Storage? initialStorage,
    bool waitForSettings = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.feedHistory: jsonEncode(
        records.map((r) => r.toJson()).toList(),
      ),
      StorageKeys.defaultMilkAmountMl: defaultAmount,
    });
    storage = initialStorage ?? _Storage();
    settings = SettingsProvider(storage: storage);
    feed = FeedProvider(
      storage: storage,
      audioService: _SilentAudio(),
      notificationService: _SilentNotifications(),
      startTimer: false,
      clock: () => now,
    );
    await feed.ready;
    if (waitForSettings) await settings.ready;
    addTearDown(feed.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: feed),
          ChangeNotifierProvider.value(value: settings),
          Provider<NotificationService>.value(value: _SilentNotifications()),
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
  }

  Future<void> tapVisible(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterAmount(WidgetTester tester, int amount) async {
    final input = find.byKey(const ValueKey('milk-amount-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '$amount');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'backfill waits for stored default and prevents duplicate dialogs',
    (tester) async {
      final gate = Completer<void>();
      await launch(
        tester,
        defaultAmount: 120,
        initialStorage: _Storage()..settingsReadGate = gate.future,
        waitForSettings: false,
      );
      await tapVisible(tester, 'history-backfill-button');
      await tapVisible(tester, 'history-backfill-button');
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      gate.complete();
      await settings.ready;
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('milk-amount-input')),
            )
            .controller!
            .text,
        '120',
      );
      await tapVisible(tester, 'add-feed-save');
      expect(feed.feedHistory.single.milkAmountMl, 120);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed settings read prevents adding a record with a false zero default',
    (tester) async {
      await launch(tester, initialStorage: _Storage()..failSettingsRead = true);
      await tapVisible(tester, 'history-backfill-button');
      expect(find.text('默认奶量设置未能读取，请重新打开应用后重试。'), findsOneWidget);
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      expect(feed.feedHistory, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'historical editing uses original amount while settings are still loading',
    (tester) async {
      final gate = Completer<void>();
      await launch(
        tester,
        records: [
          FeedRecord(
            id: 'during-load',
            time: now.subtract(const Duration(hours: 1)),
            milkAmountMl: 90,
          ),
        ],
        initialStorage: _Storage()..settingsReadGate = gate.future,
        waitForSettings: false,
      );
      await tapVisible(tester, 'edit-record-during-load');
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('milk-amount-input')),
            )
            .controller!
            .text,
        '90',
      );
      gate.complete();
      await settings.ready;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('milk input never silently changes pasted invalid amounts', (
    tester,
  ) async {
    await launch(tester);
    await tapVisible(tester, 'history-backfill-button');
    for (final invalid in ['120.5', '-50', '20000', '']) {
      final input = find.byKey(const ValueKey('milk-amount-input'));
      await tester.enterText(input, invalid);
      await tapVisible(tester, 'add-feed-save');
      expect(
        tester.widget<CupertinoTextField>(input).controller!.text,
        invalid,
      );
      expect(find.text('请输入 0–2000 之间的整数（mL）'), findsOneWidget);
      expect(feed.feedHistory, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default amount editor validates and persists input and step changes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await launch(tester, home: const SettingsScreen());
        await tapVisible(tester, 'default-milk-amount');
        final titleSemantics = tester
            .getSemantics(find.text('设置默认奶量'))
            .getSemanticsData();
        expect(titleSemantics.flagsCollection.isHeader, isTrue);
        expect(titleSemantics.flagsCollection.namesRoute, isTrue);
        await tester.enterText(
          find.byKey(const ValueKey('milk-amount-input')),
          '2001',
        );
        await tapVisible(tester, 'save-default-milk-amount');
        expect(find.text('请输入 0–2000 之间的整数（mL）'), findsOneWidget);
        expect(settings.defaultMilkAmountMl, 0);
        await enterAmount(tester, 150);
        await tapVisible(tester, 'milk-amount-increase');
        await tapVisible(tester, 'save-default-milk-amount');
        expect(settings.defaultMilkAmountMl, 160);
        expect(find.text('160 mL'), findsOneWidget);
        final reloaded = SettingsProvider(storage: storage);
        await reloaded.ready;
        expect(reloaded.defaultMilkAmountMl, 160);
        reloaded.dispose();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('backfill starts from default while old records remain unknown', (
    tester,
  ) async {
    await launch(
      tester,
      records: [
        FeedRecord(id: 'old', time: now.subtract(const Duration(hours: 2))),
      ],
      defaultAmount: 120,
    );
    expect(find.text('0 mL · 未记录'), findsOneWidget);
    await tapVisible(tester, 'history-backfill-button');
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('milk-amount-input')),
    );
    expect(field.controller!.text, '120');
    await tapVisible(tester, 'add-feed-save');
    expect(feed.feedHistory.first.milkAmountMl, 120);
    expect(feed.feedHistory.last.milkAmountMl, 0);
    expect(find.text('2 条 · 120 mL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing milk preserves record identity exact time and deadline',
    (tester) async {
      final originalTime = now.subtract(
        const Duration(hours: 1, seconds: 12, milliseconds: 345),
      );
      await launch(
        tester,
        records: [
          FeedRecord(id: 'original', time: originalTime, milkAmountMl: 90),
        ],
        defaultAmount: 180,
      );
      final deadline = feed.nextFeedTime;
      await tapVisible(tester, 'edit-record-original');
      expect(find.text('修改喂奶记录'), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('milk-amount-input')),
            )
            .controller!
            .text,
        '90',
      );
      await enterAmount(tester, 150);
      await tapVisible(tester, 'add-feed-save');
      expect(feed.feedHistory.single.id, 'original');
      expect(feed.feedHistory.single.time, originalTime);
      expect(feed.feedHistory.single.milkAmountMl, 150);
      expect(feed.nextFeedTime, deadline);
      expect((await storage.getFeedHistory()).single.milkAmountMl, 150);
      expect(tester.takeException(), isNull);
    },
  );

  for (final originalTime in [
    DateTime(2019, 12, 31, 23, 59, 12, 345),
    now.add(const Duration(hours: 1, seconds: 12, milliseconds: 345)),
  ]) {
    testWidgets(
      'amount-only history edit preserves out-of-range timestamp $originalTime',
      (tester) async {
        await launch(
          tester,
          records: [FeedRecord(id: 'original', time: originalTime)],
        );
        final deadline = feed.nextFeedTime;
        await tapVisible(tester, 'edit-record-original');
        await enterAmount(tester, 120);
        await tapVisible(tester, 'add-feed-save');
        expect(feed.feedHistory.single.time, originalTime);
        expect(feed.feedHistory.single.milkAmountMl, 120);
        expect(feed.nextFeedTime, deadline);
        expect((await storage.getFeedHistory()).single.time, originalTime);
        expect((await storage.getFeedHistory()).single.milkAmountMl, 120);
        expect(find.byType(AddFeedRecordDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed edit keeps original data and retries the entered amount',
    (tester) async {
      await launch(
        tester,
        records: [
          FeedRecord(
            id: 'retry',
            time: now.subtract(const Duration(hours: 1)),
            milkAmountMl: 60,
          ),
        ],
      );
      await tapVisible(tester, 'edit-record-retry');
      await enterAmount(tester, 120);
      storage.failWrites = true;
      await tapVisible(tester, 'add-feed-save');
      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      expect(feed.feedHistory.single.milkAmountMl, 60);
      storage.failWrites = false;
      await tapVisible(tester, 'add-feed-save');
      expect(feed.feedHistory.single.milkAmountMl, 120);
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history opens milk statistics with the current records', (
    tester,
  ) async {
    await launch(
      tester,
      records: [
        FeedRecord(
          id: 'stats',
          time: now.subtract(const Duration(hours: 1)),
          milkAmountMl: 120,
        ),
      ],
    );
    await tapVisible(tester, 'history-statistics-button');
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
