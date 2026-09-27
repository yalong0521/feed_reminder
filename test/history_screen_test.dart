import 'dart:convert';
import 'dart:async';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/screens/history_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
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

class _TestStorage extends StorageService {
  bool failWrites = false;
  Future<void>? pendingWrite;
  int saveCalls = 0;

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    saveCalls++;
    await pendingWrite;
    if (failWrites) throw StateError('Test write failure');
    await super.saveFeedState(records);
  }
}

Future<FeedProvider> _provider(
  List<FeedRecord> records, {
  _TestStorage? storage,
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues({
    StorageKeys.feedHistory: jsonEncode(
      records.map((record) => record.toJson()).toList(),
    ),
  });
  final provider = FeedProvider(
    storage: storage ?? _TestStorage(),
    audioService: _SilentAudio(),
    notificationService: _SilentNotifications(),
    startTimer: false,
    clock: clock,
  );
  await provider.ready;
  addTearDown(provider.dispose);
  return provider;
}

Widget _app(FeedProvider provider, {Widget? home, double textScale = 1}) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home ?? const HistoryScreen(),
    ),
  );
}

Widget _dialogLauncher() => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: AppButton(
        onPressed: () => showAddFeedRecordDialog(context),
        child: const Text('打开补记'),
      ),
    ),
  ),
);

void main() {
  testWidgets('backfill uses the same clock as the countdown', (tester) async {
    final now = DateTime(2026, 1, 2, 21, 40, 30);
    final provider = await _provider([], clock: () => now);
    await tester.pumpWidget(_app(provider, home: _dialogLauncher()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开补记'));
    await tester.pumpAndSettle();
    expect(find.text('2026年1月2日'), findsOneWidget);
    expect(find.text('21:40'), findsOneWidget);
    final save = find.byKey(const ValueKey('add-feed-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsNothing);
    expect(provider.feedHistory.single.time, DateTime(2026, 1, 2, 21, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history follows the injected day without rebuilding every tick',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = DateTime(2026, 1, 2, 23, 59, 55);
      final provider = await _provider([
        FeedRecord(time: DateTime(2026, 1, 2, 23)),
        FeedRecord(time: DateTime(2026, 1, 1, 23)),
      ], clock: () => now);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();
      expect(find.text('今天 · 2026年1月2日'), findsOneWidget);
      expect(find.text('昨天 · 2026年1月1日'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.textSpan?.toPlainText() == '1 次',
        ),
        findsOneWidget,
      );
      final scroll = find.byKey(const PageStorageKey('feed-history-scroll'));
      final originalList = tester.widget<CustomScrollView>(scroll);

      now = now.add(const Duration(seconds: 1));
      await provider.refresh();
      await tester.pump();
      expect(tester.widget<CustomScrollView>(scroll), same(originalList));

      now = DateTime(2026, 1, 3, 0, 0, 1);
      await provider.refresh();
      await tester.pumpAndSettle();
      expect(
        tester.widget<CustomScrollView>(scroll),
        isNot(same(originalList)),
      );
      expect(find.text('昨天 · 2026年1月2日'), findsOneWidget);
      expect(find.text('2026年1月1日'), findsOneWidget);
      expect(find.text('0 次', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repeated modal actions neither stack backfill nor dismiss it', (
    tester,
  ) async {
    final provider = await _provider([]);
    await tester.pumpWidget(_app(provider, home: _dialogLauncher()));
    final open = tester
        .widget<AppButton>(find.widgetWithText(AppButton, '打开补记'))
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(
      find.byType(AddFeedRecordDialog, skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-feed-time-field')));
    await tester.pumpAndSettle();
    final finish = tester
        .widget<AppButton>(find.widgetWithText(AppButton, '完成'))
        .onPressed!;
    finish();
    finish();
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(provider.feedHistory, isEmpty);

    final cancel = tester
        .widget<AppButton>(find.byKey(const ValueKey('add-feed-cancel')))
        .onPressed!;
    cancel();
    cancel();
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsNothing);
    expect(find.text('打开补记'), findsOneWidget);
    expect(provider.feedHistory, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history groups separate earlier days and shows real totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final older = DateTime(now.year, now.month, now.day - 3, 10);
    final oldest = DateTime(now.year, now.month, now.day - 5, 9);
    final provider = await _provider([
      FeedRecord(time: older),
      FeedRecord(time: oldest),
    ]);

    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    expect(
      find.text('${older.year}年${older.month}月${older.day}日'),
      findsOneWidget,
    );
    expect(
      find.text('${oldest.year}年${oldest.month}月${oldest.day}日'),
      findsOneWidget,
    );
    expect(find.text('更早'), findsNothing);
    expect(find.text('0 次', findRichText: true), findsOneWidget);
    expect(find.text('2 次', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delete uses stable identity when another record changes indexes',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final first = FeedRecord(
        id: 'first',
        time: now.subtract(const Duration(hours: 1)),
      );
      final second = FeedRecord(id: 'same-time', time: first.time);
      final provider = await _provider([first, second]);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-record-first')));
      await tester.pumpAndSettle();
      await provider.addFeedRecordWithTime(
        now.subtract(const Duration(minutes: 10)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-record')));
      await tester.pumpAndSettle();

      expect(provider.feedHistory.length, 2);
      expect(
        provider.feedHistory.any((record) => record.id == 'first'),
        isFalse,
      );
      expect(
        provider.feedHistory.any((record) => record.id == 'same-time'),
        isTrue,
      );
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('failed deletion keeps the record and reports failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _TestStorage();
    final provider = await _provider([
      FeedRecord(time: DateTime.now().subtract(const Duration(hours: 1))),
    ], storage: storage);
    storage.failWrites = true;
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('delete-record-${provider.feedHistory.first.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-record')));
    await tester.pumpAndSettle();
    expect(provider.feedHistory.length, 1);
    expect(find.text('删除失败，请重试'), findsOneWidget);
  });

  testWidgets('small screen and large text keep history and dialog usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await _provider([]);
    await tester.pumpWidget(_app(provider, textScale: 1.5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('补记喂奶'));
    await tester.tap(find.text('补记喂奶'));
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsNothing);
  });

  testWidgets('failed save stays open, then retry saves and closes', (
    tester,
  ) async {
    final storage = _TestStorage();
    final provider = await _provider([], storage: storage);
    await tester.pumpWidget(_app(provider, home: _dialogLauncher()));
    await tester.tap(find.text('打开补记'));
    await tester.pumpAndSettle();
    storage.failWrites = true;
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.byType(AddFeedRecordDialog), findsOneWidget);
    expect(provider.feedHistory, isEmpty);

    storage.failWrites = false;
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsNothing);
    expect(provider.feedHistory.length, 1);
    expect(find.byType(AddFeedRecordDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('time picker opens at selected current time instead of noon', (
    tester,
  ) async {
    final provider = await _provider([]);
    await tester.pumpWidget(_app(provider, home: _dialogLauncher()));
    await tester.tap(find.text('打开补记'));
    await tester.pumpAndSettle();
    final initial = DateTime.now();
    await tester.tap(find.text('喂奶时间'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CupertinoDatePicker>(
      find.byKey(const ValueKey('app-date-time-picker')),
    );
    expect(picker.mode, CupertinoDatePickerMode.time);
    expect(picker.initialDateTime.hour, initial.hour);
    expect(picker.initialDateTime.minute, initial.minute);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'landscape exposes two records and backfill actions without scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final provider = await _provider([
        FeedRecord(
          id: 'first-visible',
          time: DateTime(now.year, now.month, now.day - 1, 12),
        ),
        FeedRecord(
          id: 'second-visible',
          time: DateTime(now.year, now.month, now.day - 1, 9),
        ),
        FeedRecord(time: DateTime(now.year, now.month, now.day - 1, 6)),
      ]);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();
      for (final id in ['first-visible', 'second-visible']) {
        final action = find.byKey(ValueKey('delete-record-$id'));
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(390));
      }
      await tester.tap(find.byKey(const ValueKey('history-backfill-button')));
      await tester.pumpAndSettle();
      for (final key in [
        'add-feed-date-field',
        'add-feed-time-field',
        'add-feed-save',
        'add-feed-cancel',
      ]) {
        final target = find.byKey(ValueKey(key));
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.getRect(target).bottom, lessThanOrEqualTo(390));
      }
      expect(
        find.byWidgetPredicate((widget) => widget is InkResponse),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cupertino backfill keeps date bounds and does not reset the latest cycle',
    (tester) async {
      final now = DateTime.now();
      final latest = now.subtract(const Duration(minutes: 10));
      final yesterday = DateTime(now.year, now.month, now.day - 1, 14, 35);
      final provider = await _provider([FeedRecord(time: latest)]);
      final originalDeadline = provider.nextFeedTime;
      await tester.pumpWidget(_app(provider, home: _dialogLauncher()));
      await tester.tap(find.text('打开补记'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-feed-date-field')));
      await tester.pumpAndSettle();
      final datePicker = tester.widget<CupertinoDatePicker>(
        find.byKey(const ValueKey('app-date-time-picker')),
      );
      expect(datePicker.minimumDate, DateTime(2020));
      expect(datePicker.maximumDate!.isAfter(DateTime.now()), isFalse);
      expect(datePicker.mode, CupertinoDatePickerMode.date);
      datePicker.onDateTimeChanged(yesterday);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-feed-time-field')));
      await tester.pumpAndSettle();
      final timePicker = tester.widget<CupertinoDatePicker>(
        find.byKey(const ValueKey('app-date-time-picker')),
      );
      expect(timePicker.initialDateTime.day, yesterday.day);
      timePicker.onDateTimeChanged(yesterday);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('add-feed-save')));
      await tester.tap(find.byKey(const ValueKey('add-feed-save')));
      await tester.pumpAndSettle();
      expect(provider.feedHistory, hasLength(2));
      expect(provider.feedHistory.last.time, yesterday);
      expect(provider.nextFeedTime, originalDeadline);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving backfill disables repeated submission and cancellation', (
    tester,
  ) async {
    final storage = _TestStorage();
    final completion = Completer<void>();
    final provider = await _provider([], storage: storage);
    storage.pendingWrite = completion.future;
    await tester.pumpWidget(_app(provider, home: _dialogLauncher()));
    await tester.tap(find.text('打开补记'));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('add-feed-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(tester.widget<AppButton>(save).onPressed, isNull);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('add-feed-cancel')))
          .onPressed,
      isNull,
    );
    await tester.tap(save);
    expect(storage.saveCalls, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(provider.feedHistory, hasLength(1));
    expect(find.byType(AddFeedRecordDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
