import 'dart:ui' as ui;

import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('numpad Enter confirms a slider only after deliberate steps', (
    tester,
  ) async {
    var recordings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: FeedButton(onPressed: () async => recordings++),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(recordings, 0);
    for (var step = 0; step < 4; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(recordings, 1);
    expect(find.text('已记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed slider save exposes one stable live error and can retry',
    (tester) async {
      var attempts = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: FeedButton(
                    onPressed: () async {
                      if (++attempts == 1) throw StateError('Save failed');
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        for (var step = 0; step < 4; step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        final status = find.byKey(const ValueKey('feed-slide-save-status'));
        final failedSlider = find.bySemanticsLabel('记录未保存，向右滑动重试');
        expect(failedSlider, findsOneWidget);
        final firstStatus = tester.getSemantics(status).getSemanticsData();
        expect(firstStatus.flagsCollection.isLiveRegion, isTrue);
        expect(firstStatus.label, '记录未保存，请向右滑动重试');
        expect(firstStatus.value, isEmpty);
        expect(
          tester
              .getSemantics(failedSlider)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isFalse,
        );
        await tester.pump(const Duration(milliseconds: 100));
        final animatedStatus = tester.getSemantics(status).getSemanticsData();
        expect(animatedStatus.label, firstStatus.label);
        expect(animatedStatus.value, isEmpty);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(failedSlider).getSemanticsData().value,
          '未保存，0%',
        );
        for (var step = 0; step < 4; step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(find.text('已记录'), findsOneWidget);
        expect(failedSlider, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('held activation keys trigger a button only once per key press', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppButton(
              onPressed: () => activations++,
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      final before = activations;
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
      expect(activations, before + 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled slider progress cannot confirm during its return', (
    tester,
  ) async {
    var recordings = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: FeedButton(onPressed: () async => recordings++),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      for (var step = 0; step < 4; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.pump();
      final slider = find.bySemanticsLabel('滑动记录这次喂奶');
      expect(tester.getSemantics(slider).getSemanticsData().value, '100%');

      // No frame has advanced the decorative return animation between keys.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(recordings, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(tester.getSemantics(slider).getSemanticsData().value, '25%');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(recordings, 0);

      for (var step = 0; step < 3; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      tester
          .renderObject(slider)
          .owner!
          .semanticsOwner!
          .performAction(
            tester.getSemantics(slider).id,
            ui.SemanticsAction.increase,
          );
      await tester.pump();
      expect(recordings, 0);
      expect(tester.getSemantics(slider).getSemanticsData().value, '25%');

      for (var step = 0; step < 3; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(recordings, 1);
      expect(find.text('已记录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
