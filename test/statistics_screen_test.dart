import 'dart:convert';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/models/milk_statistics.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/screens/statistics_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/milk_volume_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/services.dart';
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

Future<FeedProvider> _provider(List<FeedRecord> records) async {
  SharedPreferences.setMockInitialValues({
    StorageKeys.feedHistory: jsonEncode(
      records.map((record) => record.toJson()).toList(),
    ),
  });
  final provider = FeedProvider(
    storage: StorageService(),
    audioService: _SilentAudio(),
    notificationService: _SilentNotifications(),
    startTimer: false,
    clock: () => DateTime(2026, 10, 3, 12),
  );
  await provider.ready;
  addTearDown(provider.dispose);
  return provider;
}

Widget _app(
  FeedProvider provider, {
  double textScale = 1,
  bool dark = false,
  Widget? home,
}) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home ?? const StatisticsScreen(),
      ),
    );

Future<void> _customRange(
  WidgetTester tester,
  DateTime start,
  DateTime end,
) async {
  final custom = find.byKey(const ValueKey('statistics-range-custom'));
  await tester.ensureVisible(custom);
  await tester.tap(custom);
  await tester.pumpAndSettle();
  for (final field in [('date-range-start', start), ('date-range-end', end)]) {
    final control = find.byKey(ValueKey(field.$1));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoDatePicker>(
          find.byKey(const ValueKey('query-calendar-picker')),
        )
        .onDateTimeChanged(field.$2);
    final done = find.byKey(const ValueKey('query-calendar-done'));
    await tester.ensureVisible(done);
    await tester.tap(done);
    await tester.pumpAndSettle();
  }
  final apply = find.byKey(const ValueKey('date-range-apply'));
  await tester.ensureVisible(apply);
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rapid statistics back returns to its caller only once', (
    tester,
  ) async {
    final provider = await _provider([]);
    await tester.pumpWidget(
      _app(
        provider,
        home: Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              key: const ValueKey('open-statistics'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const StatisticsScreen()),
              ),
              child: const Text('查看统计'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-statistics')));
    await tester.pumpAndSettle();
    final back = tester
        .widget<AppButton>(find.byKey(const ValueKey('statistics-back')))
        .onPressed!;
    back();
    back();
    await tester.pumpAndSettle();

    expect(find.byType(StatisticsScreen), findsNothing);
    expect(find.byKey(const ValueKey('open-statistics')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('open-statistics')));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
  });

  testWidgets(
    'custom periods show exact totals, retain valid day and reset invalid day',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = await _provider([
        FeedRecord(time: DateTime(2026, 9, 1), milkAmountMl: 100),
        FeedRecord(time: DateTime(2026, 9, 30, 12), milkAmountMl: 200),
        FeedRecord(time: DateTime(2026, 10, 3, 9), milkAmountMl: 300),
      ]);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();
      await _customRange(tester, DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      MilkVolumeChart chart() =>
          tester.widget<MilkVolumeChart>(find.byType(MilkVolumeChart));
      expect(chart().days, hasLength(30));
      expect(chart().selectedDate, DateTime(2026, 9, 30));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('statistics-total')))
            .textSpan!
            .toPlainText(),
        '300 mL',
      );
      expect(find.text('150.0 mL'), findsOneWidget);
      chart().onSelectDay(DateTime(2026, 9, 15));
      await tester.pumpAndSettle();
      await _customRange(tester, DateTime(2026, 8, 20), DateTime(2026, 9, 18));
      expect(chart().selectedDate, DateTime(2026, 9, 15));
      final retained = find.byKey(
        ValueKey('milk-chart-day-${DateTime(2026, 9, 15).toIso8601String()}'),
      );
      expect(retained.hitTestable(), findsOneWidget);
      await _customRange(tester, DateTime(2026, 7, 1), DateTime(2026, 7, 30));
      expect(chart().selectedDate, DateTime(2026, 7, 30));
      expect(chart().days.first.date, DateTime(2026, 7, 1));
      expect(find.text('这段时间还没有喂奶记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '366-day range uses disjoint pages of at most 30 days at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = await _provider([
        FeedRecord(time: DateTime(2025, 10, 3, 9), milkAmountMl: 100),
        FeedRecord(time: DateTime(2026, 10, 3, 9), milkAmountMl: 200),
      ]);
      await tester.pumpWidget(_app(provider, textScale: 2, dark: true));
      await tester.pumpAndSettle();
      await _customRange(tester, DateTime(2025, 10, 3), DateTime(2026, 10, 3));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('statistics-total')))
            .textSpan!
            .toPlainText(),
        '300 mL',
      );
      expect(find.text('日均按 366 个自然日计算，包含没有记录的日期。'), findsOneWidget);
      final seen = <DateTime>{};
      for (var page = 0; page < 13; page++) {
        final chart = tester.widget<MilkVolumeChart>(
          find.byType(MilkVolumeChart),
        );
        expect(chart.days.length, lessThanOrEqualTo(30));
        expect(
          seen.intersection(chart.days.map((day) => day.date).toSet()),
          isEmpty,
        );
        seen.addAll(chart.days.map((day) => day.date));
        final previous = find.byKey(
          const ValueKey('statistics-chart-previous'),
        );
        await tester.ensureVisible(previous);
        if (page == 12) {
          expect(tester.widget<AppButton>(previous).onPressed, isNull);
        } else {
          await tester.tap(previous);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
      expect(seen, hasLength(366));
      final next = find.byKey(const ValueKey('statistics-chart-next'));
      await tester.tap(next);
      await tester.pumpAndSettle();
      final chart = tester.widget<MilkVolumeChart>(
        find.byType(MilkVolumeChart),
      );
      expect(chart.days, hasLength(30));
      expect(chart.selectedDate, chart.days.last.date);
      expect(tester.takeException(), isNull);
    },
  );

  for (final settings in [
    (textScale: 1.0, reduceMotion: false),
    (textScale: 2.0, reduceMotion: true),
  ]) {
    testWidgets(
      'keyboard reveals all 30 dates in both directions at '
      '${settings.textScale}x text with reduced motion ${settings.reduceMotion}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final days = MilkStatistics.aggregate(
          [],
          now: DateTime(2026, 10, 3),
          dayCount: 30,
        ).days;
        var selectedDate = days.last.date;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(settings.textScale),
                disableAnimations: settings.reduceMotion,
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setState) => MilkVolumeChart(
                      days: days,
                      selectedDate: selectedDate,
                      onSelectDay: (date) =>
                          setState(() => selectedDate = date),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final plot = find.byKey(const ValueKey('milk-chart-scroll-30'));
        Finder dayControl(DateTime date) =>
            find.byKey(ValueKey('milk-chart-day-${date.toIso8601String()}'));

        void expectFullyVisible(DateTime date) {
          final viewport = tester.getRect(plot);
          final day = tester.getRect(dayControl(date));
          expect(day.left, greaterThanOrEqualTo(viewport.left - .01));
          expect(day.right, lessThanOrEqualTo(viewport.right + .01));
          expect(dayControl(date).hitTestable(), findsOneWidget);
        }

        void expectFocused(DateTime date) {
          final focusBox =
              FocusManager.instance.primaryFocus!.context!.findRenderObject()!
                  as RenderBox;
          final focusRect = focusBox.localToGlobal(Offset.zero) & focusBox.size;
          expect(focusRect, tester.getRect(dayControl(date)));
          expectFullyVisible(date);
        }

        // Opening the chart still starts at the newest date.
        expectFullyVisible(days.last.date);
        expect(tester.getRect(dayControl(days.first.date)).right, lessThan(0));
        for (final day in days) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expectFocused(day.date);
          // Moving focus alone must not change the selected daily details.
          expect(selectedDate, days.last.date);
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (final day in days.reversed.skip(1)) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expectFocused(day.date);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selectedDate, days.first.date);
        expect(
          tester.widget<AppPressable>(dayControl(selectedDate)).selected,
          isTrue,
        );
        expectFullyVisible(selectedDate);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a retained date keeps keyboard focus when the window advances', (
    tester,
  ) async {
    DateTime? activatedDate;
    Widget chart(DateTime now) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MilkVolumeChart(
          days: MilkStatistics.aggregate([], now: now, dayCount: 30).days,
          selectedDate: DateTime(2026, 10, 3),
          onSelectDay: (date) => activatedDate = date,
        ),
      ),
    );

    await tester.pumpWidget(chart(DateTime(2026, 10, 3)));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final retainedDate = DateTime(2026, 9, 5);
    final retainedDay = find.byKey(
      ValueKey('milk-chart-day-${retainedDate.toIso8601String()}'),
    );
    final focusedNode = FocusManager.instance.primaryFocus!;
    expect(
      find.ancestor(
        of: find.byElementPredicate(
          (element) => element == focusedNode.context,
        ),
        matching: retainedDay,
      ),
      findsOneWidget,
    );

    // September 4 leaves the window, but September 5 remains the same control.
    await tester.pumpWidget(chart(DateTime(2026, 10, 4)));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(focusedNode));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(activatedDate, retainedDate);
    expect(retainedDay.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone shows daily bars initially and ignores unchanged clock refreshes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = await _provider([
        FeedRecord(time: DateTime(2026, 10, 3, 9), milkAmountMl: 140),
      ]);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();
      final today = find.byKey(
        ValueKey('milk-chart-day-${DateTime(2026, 10, 3).toIso8601String()}'),
      );
      expect(today.hitTestable(), findsOneWidget);
      expect(tester.getRect(today).bottom, lessThanOrEqualTo(844));
      final chartBefore = tester.widget<MilkVolumeChart>(
        find.byType(MilkVolumeChart),
      );
      await provider.refresh();
      await tester.pumpAndSettle();
      expect(
        identical(
          chartBefore,
          tester.widget<MilkVolumeChart>(find.byType(MilkVolumeChart)),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing a recorded amount refreshes totals and selected day', (
    tester,
  ) async {
    final time = DateTime(2026, 10, 3, 9);
    final provider = await _provider([FeedRecord(id: 'edited', time: time)]);
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(find.text('还没有记录奶量'), findsOneWidget);
    await provider.updateFeedRecord('edited', time: time, milkAmountMl: 175);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('statistics-total')))
          .textSpan!
          .toPlainText(),
      '175 mL',
    );
    expect(find.text('还没有记录奶量'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('statistics-day-detail')),
        matching: find.text('1 次喂奶 · 0 次未记录奶量'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching ranges updates totals and the inclusive day count', (
    tester,
  ) async {
    final provider = await _provider([
      FeedRecord(time: DateTime(2026, 10, 3, 9), milkAmountMl: 140),
      FeedRecord(time: DateTime(2026, 10, 2, 9)),
      FeedRecord(time: DateTime(2026, 9, 20, 9), milkAmountMl: 160),
    ]);
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('statistics-total')))
          .textSpan!
          .toPlainText(),
      '140 mL',
    );
    expect(find.text('20.0 mL'), findsOneWidget);
    expect(
      tester.widget<MilkVolumeChart>(find.byType(MilkVolumeChart)).days,
      hasLength(7),
    );
    await tester.tap(find.byKey(const ValueKey('statistics-range-30')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('statistics-total')))
          .textSpan!
          .toPlainText(),
      '300 mL',
    );
    expect(find.text('10.0 mL'), findsOneWidget);
    expect(find.text('2026.09.04 — 2026.10.03 · 含今天'), findsOneWidget);
    expect(
      tester.widget<MilkVolumeChart>(find.byType(MilkVolumeChart)).days,
      hasLength(30),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no records and unknown milk amounts have distinct empty states',
    (tester) async {
      final empty = await _provider([]);
      await tester.pumpWidget(_app(empty));
      await tester.pumpAndSettle();
      expect(find.text('这段时间还没有喂奶记录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final unknown = await _provider([
        FeedRecord(time: DateTime(2026, 10, 3, 9)),
      ]);
      await tester.pumpWidget(_app(unknown));
      await tester.pumpAndSettle();
      expect(find.text('还没有记录奶量'), findsOneWidget);
      expect(find.text('这段时间还没有喂奶记录'), findsNothing);
      expect(find.text('1 次'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('day selection shows exact volume and unknown feed count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await _provider([
      FeedRecord(time: DateTime(2026, 10, 2, 9), milkAmountMl: 125),
      FeedRecord(time: DateTime(2026, 10, 2, 12)),
      FeedRecord(time: DateTime(2026, 10, 3, 9), milkAmountMl: 140),
    ]);
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();
    final day = find.byKey(
      ValueKey('milk-chart-day-${DateTime(2026, 10, 2).toIso8601String()}'),
    );
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    final detail = find.byKey(const ValueKey('statistics-day-detail'));
    expect(
      find.descendant(of: detail, matching: find.text('125 mL')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('2 次喂奶 · 1 次未记录奶量')),
      findsOneWidget,
    );
    expect(tester.widget<AppPressable>(day).selected, isTrue);
    expect(
      tester.widget<AppPressable>(day).semanticLabel,
      contains('125毫升，2次喂奶，1次未记录奶量'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow dark screen and large text keep 30-day chart usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = await _provider([
      FeedRecord(time: DateTime(2026, 10, 3, 9), milkAmountMl: 140),
    ]);
    await tester.pumpWidget(_app(provider, textScale: 2, dark: true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('statistics-range-30')),
    );
    await tester.tap(find.byKey(const ValueKey('statistics-range-30')));
    await tester.pumpAndSettle();
    final today = find.byKey(
      ValueKey('milk-chart-day-${DateTime(2026, 10, 3).toIso8601String()}'),
    );
    await tester.ensureVisible(find.byType(MilkVolumeChart));
    await tester.pumpAndSettle();
    expect(today.hitTestable(), findsOneWidget);
    expect(tester.widget<AppPressable>(today).selected, isTrue);
    await tester.tap(today);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
