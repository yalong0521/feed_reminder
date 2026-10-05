import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/app_date_range_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _choose(WidgetTester tester, String field, DateTime value) async {
  final control = find.byKey(ValueKey(field));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  tester
      .widget<CupertinoDatePicker>(
        find.byKey(const ValueKey('query-calendar-picker')),
      )
      .onDateTimeChanged(value);
  final done = find.byKey(const ValueKey('query-calendar-done'));
  await tester.ensureVisible(done);
  await tester.tap(done);
  await tester.pumpAndSettle();
}

Widget _app(
  ValueChanged<DateTimeRange?> result, {
  double scale = 1,
  double inset = 0,
}) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: inset),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => AppButton(
        child: const Text('打开'),
        onPressed: () async => result(
          await showAppDateRangePicker(
            context,
            now: DateTime(2026, 10, 3),
            initial: DateTimeRange(
              start: DateTime(2026, 10, 1),
              end: DateTime(2026, 10, 3),
            ),
            title: '自选统计范围',
            maximumDays: 366,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('rapid activation opens only one date range and can reopen', (
    tester,
  ) async {
    await tester.pumpWidget(_app((_) {}));
    final open = tester.widget<AppButton>(find.widgetWithText(AppButton, '打开'));
    open.onPressed!();
    open.onPressed!();
    await tester.pumpAndSettle();
    expect(
      find.byType(AppDateRangePicker, skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('date-range-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(AppDateRangePicker, skipOffstage: false), findsNothing);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDateRangePicker), findsOneWidget);
  });

  testWidgets(
    'invalid order and length stay local; valid inclusive dates apply',
    (tester) async {
      DateTimeRange? selected;
      await tester.pumpWidget(_app((value) => selected = value));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await _choose(tester, 'date-range-end', DateTime(2026, 9, 30));
      expect(find.text('开始日期不能晚于结束日期'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('date-range-apply')))
            .onPressed,
        isNull,
      );
      await _choose(tester, 'date-range-start', DateTime(2025, 9, 1));
      expect(find.text('最多选择 366 个自然日，请缩短日期范围'), findsOneWidget);
      expect(selected, isNull);
      await _choose(tester, 'date-range-start', DateTime(2026, 9, 1));
      expect(find.text('共 30 个自然日，包含起止日期。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('date-range-apply')));
      await tester.pumpAndSettle();
      expect(
        selected,
        DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('range and wheel remain reachable at 2x text on $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTimeRange? selected;
      await tester.pumpWidget(_app((value) => selected = value, scale: 2));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await _choose(tester, 'date-range-start', DateTime(2026, 9, 29));
      final apply = find.byKey(const ValueKey('date-range-apply'));
      await tester.ensureVisible(apply);
      expect(apply.hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.byType(AppDateRangePicker), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'keyboard inset keeps cancel reachable without applying changes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var completed = false;
      await tester.pumpWidget(
        _app(
          (value) {
            completed = true;
            expect(value, isNull);
          },
          scale: 2,
          inset: 360,
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final cancel = find.byKey(const ValueKey('date-range-cancel'));
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
