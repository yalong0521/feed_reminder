import 'dart:ui' as ui;

import 'package:feed_reminder/widgets/glass_countdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _countdownKey = ValueKey('test-countdown');
const _color = Color(0xff316057);

Widget _host(
  String text, {
  String? semanticLabel,
  bool highContrast = false,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  bool constrained = false,
}) {
  Widget countdown = GlassCountdownText(
    text,
    key: _countdownKey,
    color: _color,
    fontSize: 100,
    semanticLabel: semanticLabel,
  );
  if (constrained) {
    countdown = SizedBox(
      width: 280,
      child: FittedBox(fit: BoxFit.scaleDown, child: countdown),
    );
  }
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(highContrast: highContrast, textScaler: textScaler),
      child: Theme(
        data: ThemeData(brightness: brightness),
        child: Center(child: countdown),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'glass numerals expose one readable label without a live ticker',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        const label = '距离下次喂奶还有 2 小时 34 分 56 秒';
        await tester.pumpWidget(_host('02:34:56', semanticLabel: label));

        final labelFinder = find.bySemanticsLabel(label);
        expect(labelFinder, findsOneWidget);
        final data = tester.getSemantics(labelFinder).getSemanticsData();
        expect(data.flagsCollection.isLiveRegion, isFalse);
        expect(data.flagsCollection.isButton, isFalse);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(find.byType(BackdropFilter), findsOneWidget);

        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump(const Duration(seconds: 30));
        expect(labelFinder, findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'system high contrast removes glass blur without hiding the time',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_host('01:23:45'));
        final normalSize = tester.getSize(find.byKey(_countdownKey));
        expect(find.byType(BackdropFilter), findsOneWidget);

        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            _host('01:23:45', highContrast: true, brightness: brightness),
          );
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.bySemanticsLabel('01:23:45'), findsOneWidget);
          expect(tester.getSize(find.byKey(_countdownKey)), normalSize);
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(_host('01:23:44'));
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(find.bySemanticsLabel('01:23:44'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'tabular numerals stay stable and long hours scale into a phone',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<Size> sizeFor(String text) async {
        await tester.pumpWidget(_host(text));
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byKey(_countdownKey));
      }

      final narrowDigits = await sizeFor('01:11:11');
      final wideDigits = await sizeFor('88:88:88');
      expect(narrowDigits, wideDigits);
      expect(narrowDigits.width, greaterThan(0));
      final threeHourDigits = await sizeFor('100:00:00');
      final fourHourDigits = await sizeFor('1000:00:00');
      final extraDigitWidth = threeHourDigits.width - wideDigits.width;
      expect(extraDigitWidth, greaterThan(0));
      expect(
        fourHourDigits.width - threeHourDigits.width,
        closeTo(extraDigitWidth, .001),
      );
      expect(threeHourDigits.height, wideDigits.height);
      expect(fourHourDigits.height, wideDigits.height);

      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpWidget(
        _host(
          '1000:00:00',
          textScaler: const TextScaler.linear(2),
          constrained: true,
        ),
      );
      final bounds = tester.getRect(find.byKey(_countdownKey));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(568));
      expect(bounds.width, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown formats fall back to readable text and can recover', (
    tester,
  ) async {
    for (final text in ['', '计时暂停', '1 天 02:03:04']) {
      await tester.pumpWidget(_host(text));
      expect(find.text(text), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(_host('--:--:--'));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.getSize(find.byKey(_countdownKey)).width, greaterThan(0));
    await tester.pumpWidget(_host('00:00:01'));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
