import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewport in [
    (size: const Size(320, 640), scale: 2.0),
    (size: const Size(640, 320), scale: 1.8),
    (size: const Size(800, 600), scale: 1.0),
  ]) {
    for (final mode in [
      CupertinoDatePickerMode.date,
      CupertinoDatePickerMode.time,
    ]) {
      testWidgets(
        '$mode heading stays readable and actions work at ${viewport.size} scale ${viewport.scale}',
        (tester) async {
          tester.view.physicalSize = viewport.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final title = mode == CupertinoDatePickerMode.date
              ? '选择喂奶日期'
              : '选择喂奶时间';
          final initial = DateTime(2026, 10, 4, 12, 30);
          DateTime? result;
          var completions = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('zh', 'CN')],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(viewport.scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: AppButton(
                      child: const Text('打开'),
                      onPressed: () async {
                        result = await showAppDateTimePicker(
                          context,
                          initial: initial,
                          mode: mode,
                          title: title,
                        );
                        completions++;
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          final heading = tester.getRect(find.text(title));
          final cancel = find.widgetWithText(AppButton, '取消');
          final confirm = find.widgetWithText(AppButton, '完成');
          // Two lines at the requested text size are readable; a narrow
          // single-character column can still pass overflow checks.
          expect(heading.width, greaterThanOrEqualTo(200));
          expect(
            heading.height,
            lessThanOrEqualTo(24 * viewport.scale * 1.3 * 2 + 2),
          );
          if (viewport.scale > 1) {
            expect(tester.getRect(cancel).top, greaterThan(heading.bottom));
            expect(tester.getRect(confirm).top, greaterThan(heading.bottom));
          } else {
            expect(
              tester.getRect(cancel).center.dy,
              closeTo(heading.center.dy, .01),
            );
          }
          final surface = find.byKey(
            const ValueKey('app-date-time-picker-surface'),
          );
          final surfaceBounds = tester.getRect(surface);
          expect(surfaceBounds.top, greaterThanOrEqualTo(16));
          expect(
            surfaceBounds.bottom,
            lessThanOrEqualTo(viewport.size.height - 16),
          );
          final wheel = find.byKey(const ValueKey('app-date-time-picker'));
          final initialWheelTop = tester.getRect(wheel).top;
          await tester.ensureVisible(wheel);
          expect(wheel.hitTestable(), findsOneWidget);
          expect(tester.getRect(surface), surfaceBounds);
          if (viewport.size.height == 320) {
            expect(tester.getRect(wheel).top, lessThan(initialWheelTop));
          }
          final selection = mode == CupertinoDatePickerMode.date
              ? DateTime(2026, 10, 3, 12, 30)
              : DateTime(2026, 10, 4, 11, 15);
          tester
              .widget<CupertinoDatePicker>(wheel)
              .onDateTimeChanged(selection);
          await tester.ensureVisible(confirm);
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.getRect(surface), surfaceBounds);
          await tester.tap(confirm);
          await tester.pumpAndSettle();
          expect(result, selection);
          expect(completions, 1);
          expect(wheel, findsNothing);

          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(cancel);
          expect(cancel.hitTestable(), findsOneWidget);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(result, isNull);
          expect(completions, 2);
          expect(wheel, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
