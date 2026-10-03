import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpSlider(
  WidgetTester tester, {
  required Future<void> Function() onRecord,
  bool dark = false,
}) async {
  final originalStrategy = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  addTearDown(() {
    FocusManager.instance.highlightStrategy = originalStrategy;
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 360, child: FeedButton(onPressed: onRecord)),
              AppButton(onPressed: () {}, child: const Text('另一个操作')),
            ],
          ),
        ),
      ),
    ),
  );
  // Reset the previous test's input modality using an actual touch event.
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

Border? _sliderFocusBorder(WidgetTester tester) {
  final foreground = find.descendant(
    of: find.byType(FeedButton),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.position == DecorationPosition.foreground,
    ),
  );
  expect(foreground, findsOneWidget);
  return (tester.widget<DecoratedBox>(foreground).decoration as BoxDecoration)
          .border
      as Border?;
}

void _expectKeyboardRing(WidgetTester tester, {bool dark = false}) {
  final border = _sliderFocusBorder(tester);
  expect(border, isNotNull);
  expect(border!.top.width, 2);
  expect(
    border.top.color,
    dark ? AppPalette.dark.primary : AppPalette.light.primary,
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} touch press and incomplete drag leave no focus ring',
      (tester) async {
        var recordings = 0;
        await _pumpSlider(
          tester,
          dark: dark,
          onRecord: () async => recordings++,
        );
        expect(_sliderFocusBorder(tester), isNull);

        final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
        await tester.tap(thumb);
        await tester.pumpAndSettle();
        expect(_sliderFocusBorder(tester), isNull);

        final drag = await tester.startGesture(tester.getCenter(thumb));
        await drag.moveBy(const Offset(90, 0));
        await tester.pump();
        expect(_sliderFocusBorder(tester), isNull);
        await drag.up();
        await tester.pumpAndSettle();
        expect(_sliderFocusBorder(tester), isNull);
        expect(recordings, 0);
        expect(
          tester.getTopLeft(thumb).dx,
          tester.getTopLeft(find.byKey(const ValueKey('feed-slide-track'))).dx +
              6,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancelled touch drag keeps the idle track without a focus ring',
    (tester) async {
      var recordings = 0;
      await _pumpSlider(tester, onRecord: () async => recordings++);
      final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
      final drag = await tester.startGesture(tester.getCenter(thumb));
      await drag.moveBy(const Offset(300, 0));
      await tester.pump();
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(_sliderFocusBorder(tester), isNull);
      expect(recordings, 0);
      expect(
        tester.getTopLeft(thumb).dx,
        tester.getTopLeft(find.byKey(const ValueKey('feed-slide-track'))).dx +
            6,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard navigation shows focus and confirms only after steps', (
    tester,
  ) async {
    var recordings = 0;
    await _pumpSlider(tester, onRecord: () async => recordings++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    _expectKeyboardRing(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(recordings, 0);
    for (var step = 0; step < 4; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pump();
    _expectKeyboardRing(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(recordings, 1);
    expect(find.text('已记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touch hides keyboard focus and later keyboard input restores it',
    (tester) async {
      var recordings = 0;
      await _pumpSlider(tester, dark: true, onRecord: () async => recordings++);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      _expectKeyboardRing(tester, dark: true);

      final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
      final drag = await tester.startGesture(tester.getCenter(thumb));
      await drag.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(_sliderFocusBorder(tester), isNull);
      await drag.up();
      await tester.pumpAndSettle();
      expect(_sliderFocusBorder(tester), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      _expectKeyboardRing(tester, dark: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_sliderFocusBorder(tester), isNull);
      expect(recordings, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mouse press clears a keyboard ring without losing keyboard input',
    (tester) async {
      var recordings = 0;
      await _pumpSlider(tester, onRecord: () async => recordings++);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      _expectKeyboardRing(tester);
      final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
      final drag = await tester.startGesture(
        tester.getCenter(thumb),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(_sliderFocusBorder(tester), isNull);
      await drag.up();
      await tester.pumpAndSettle();
      expect(_sliderFocusBorder(tester), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      _expectKeyboardRing(tester);
      expect(recordings, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled mouse drag leaves no focus ring or saved record', (
    tester,
  ) async {
    var recordings = 0;
    await _pumpSlider(tester, dark: true, onRecord: () async => recordings++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    _expectKeyboardRing(tester, dark: true);
    final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
    final drag = await tester.startGesture(
      tester.getCenter(thumb),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(300, 0));
    await tester.pump();
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(_sliderFocusBorder(tester), isNull);
    expect(recordings, 0);
    expect(
      tester.getTopLeft(thumb).dx,
      tester.getTopLeft(find.byKey(const ValueKey('feed-slide-track'))).dx + 6,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved keyboard confirmation returns to idle without a stale ring',
    (tester) async {
      var recordings = 0;
      await _pumpSlider(tester, onRecord: () async => recordings++);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      _expectKeyboardRing(tester);
      for (var step = 0; step < 4; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(recordings, 1);
      expect(find.text('已记录'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('滑动记录喂奶'), findsOneWidget);
      expect(_sliderFocusBorder(tester), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      _expectKeyboardRing(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard retry restores focus feedback after a quick save failure',
    (tester) async {
      var attempts = 0;
      await _pumpSlider(
        tester,
        onRecord: () async {
          attempts++;
          if (attempts == 1) throw StateError('Simulated save failure');
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      for (var step = 0; step < 4; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('未保存，右滑重试'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      _expectKeyboardRing(tester);
      for (var step = 0; step < 3; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('已记录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
