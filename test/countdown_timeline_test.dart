import 'dart:ui' as ui;

import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/countdown_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _frameKey = ValueKey('timeline-frame');

Widget _host({
  required DateTime? last,
  required DateTime? next,
  required DateTime now,
  double width = 320,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool highContrast = false,
}) => MaterialApp(
  theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        highContrast: highContrast,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            key: _frameKey,
            width: width,
            child: CountdownTimeline(
              lastFeedTime: last,
              nextFeedTime: next,
              now: now,
              color: AppPalette.of(context).primary,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('current time moves right and stays inside both endpoints', (
    tester,
  ) async {
    final last = DateTime(2026, 9, 30, 10);
    final next = DateTime(2026, 9, 30, 13);
    final positions = <double>[];
    for (final (time, label) in [
      (last, '现在 10:00'),
      (DateTime(2026, 9, 30, 11, 30), '现在 11:30'),
      (next, '现在 13:00'),
    ]) {
      await tester.pumpWidget(_host(last: last, next: next, now: time));
      final bounds = tester.getRect(find.byKey(_frameKey));
      final current = tester.getRect(find.text(label));
      positions.add(current.center.dx);
      expect(current.left, greaterThanOrEqualTo(bounds.left - .001));
      expect(current.right, lessThanOrEqualTo(bounds.right + .001));
      if (time == last) {
        expect(current.left, closeTo(bounds.left, .001));
      } else if (time == next) {
        expect(current.right, closeTo(bounds.right, .001));
      } else {
        expect(current.center.dx, closeTo(bounds.center.dx, .001));
      }
      expect(tester.takeException(), isNull);
    }
    expect(positions[0], lessThan(positions[1]));
    expect(positions[1], lessThan(positions[2]));
  });

  testWidgets('overnight, due and corrected clocks retain their actual times', (
    tester,
  ) async {
    final last = DateTime(2026, 9, 30, 23, 30);
    final next = DateTime(2026, 10, 1, 2, 30);
    await tester.pumpWidget(
      _host(last: last, next: next, now: DateTime(2026, 10, 1, 0, 30)),
    );
    expect(find.text('上次 9/30 23:30'), findsOneWidget);
    expect(find.text('现在 10/1 00:30'), findsOneWidget);
    expect(find.text('下一次 10/1 02:30'), findsOneWidget);

    for (final (time, label) in [
      (next, '现在 10/1 02:30'),
      (DateTime(2026, 10, 2, 3), '现在 10/2 03:00'),
    ]) {
      await tester.pumpWidget(_host(last: last, next: next, now: time));
      expect(find.text('上次 9/30 23:30'), findsOneWidget);
      expect(find.text('原定 10/1 02:30'), findsOneWidget);
      expect(find.text('下一次 10/1 02:30'), findsNothing);
      final current = tester.getRect(find.text(label));
      final bounds = tester.getRect(find.byKey(_frameKey));
      expect(current.right, closeTo(bounds.right, .001));
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(
      _host(last: last, next: next, now: DateTime(2026, 9, 30, 22, 30)),
    );
    expect(find.text('现在 9/30 22:30'), findsOneWidget);
    expect(find.text('上次 9/30 23:30'), findsOneWidget);
    expect(find.text('下一次 10/1 02:30'), findsOneWidget);
    expect(
      tester.getRect(find.text('现在 9/30 22:30')).left,
      closeTo(tester.getRect(find.byKey(_frameKey)).left, .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing records and invalid intervals show no invented times', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 30, 10);
    final intervals = <(DateTime?, DateTime?)>[
      (null, null),
      (null, now),
      (now, null),
      (now, now),
      (now, now.subtract(const Duration(hours: 1))),
    ];
    for (final (last, next) in intervals) {
      await tester.pumpWidget(_host(last: last, next: next, now: now));
      final timeline = find.byType(CountdownTimeline);
      expect(
        find.descendant(of: timeline, matching: find.byType(Text)),
        findsNothing,
      );
      expect(tester.getSize(timeline).height, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'narrow timelines grow for large text without overlapping labels',
    (tester) async {
      final last = DateTime(2026, 9, 30, 23, 30);
      final next = DateTime(2026, 10, 1, 2, 30);
      final now = DateTime(2026, 10, 1, 0, 30);
      for (final width in [180.0, 240.0]) {
        await tester.pumpWidget(
          _host(last: last, next: next, now: now, width: width),
        );
        final unscaledHeight = tester.getSize(find.byKey(_frameKey)).height;
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            _host(
              last: last,
              next: next,
              now: now,
              width: width,
              textScale: 1.8,
              brightness: brightness,
              highContrast: true,
            ),
          );
          final bounds = tester.getRect(find.byKey(_frameKey));
          final current = tester.getRect(find.text('现在 10/1 00:30'));
          final left = tester.getRect(find.text('上次 9/30 23:30'));
          final right = tester.getRect(find.text('下一次 10/1 02:30'));
          expect(bounds.height, greaterThan(unscaledHeight));
          expect(left.overlaps(right), isFalse);
          expect(left.right, lessThan(right.left));
          expect(current.bottom, lessThan(left.top));
          expect(current.bottom, lessThan(right.top));
          for (final label in [current, left, right]) {
            expect(label.left, greaterThanOrEqualTo(bounds.left - .001));
            expect(label.right, lessThanOrEqualTo(bounds.right + .001));
            expect(label.top, greaterThanOrEqualTo(bounds.top - .001));
            expect(label.bottom, lessThanOrEqualTo(bounds.bottom + .001));
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('timeline exposes one readable summary without live updates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final last = DateTime(2026, 9, 30, 10);
      final next = DateTime(2026, 9, 30, 13);
      for (final (time, label) in [
        (DateTime(2026, 9, 30, 11), '上次 10:00，现在 11:00，下一次 13:00'),
        (DateTime(2026, 9, 30, 13, 15), '上次 10:00，现在 13:15，原定 13:00'),
      ]) {
        await tester.pumpWidget(_host(last: last, next: next, now: time));
        final summary = find.bySemanticsLabel(label);
        expect(summary, findsOneWidget);
        final data = tester.getSemantics(summary).getSemanticsData();
        expect(data.flagsCollection.isLiveRegion, isFalse);
        expect(data.flagsCollection.isButton, isFalse);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(find.bySemanticsLabel('上次 10:00'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });
}
