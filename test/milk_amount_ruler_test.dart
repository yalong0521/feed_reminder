import 'dart:ui' as ui;

import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/milk_amount_field.dart';
import 'package:feed_reminder/widgets/milk_amount_ruler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _fieldApp(
  TextEditingController controller, {
  bool enabled = true,
  VoidCallback? onChanged,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 320,
          child: Directionality(
            textDirection: direction,
            child: MilkAmountField(
              controller: controller,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  ),
);

Finder get _input => find.byKey(const ValueKey('milk-amount-input'));
Finder get _ruler => find.byKey(const ValueKey('milk-amount-ruler'));
Finder get _rulerScroll =>
    find.byKey(const ValueKey('milk-amount-ruler-scroll'));

int? _rulerValue(WidgetTester tester) =>
    tester.widget<MilkAmountRuler>(find.byType(MilkAmountRuler)).value;

ScrollPosition _rulerPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _ruler, matching: find.byType(Scrollable)),
    )
    .position;

Future<void> _dragRuler(WidgetTester tester, double dx) async {
  await tester.ensureVisible(_rulerScroll);
  await tester.pumpAndSettle();
  await tester.drag(_rulerScroll, Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typed integers keep their exact value while the ruler follows', (
    tester,
  ) async {
    final controller = TextEditingController(text: '120');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_fieldApp(controller));
    await tester.pumpAndSettle();
    final extent = _rulerPosition(tester).maxScrollExtent;
    expect(find.text('0–2000 mL'), findsOneWidget);

    for (final value in [137, 361, 1999, 2000, 93]) {
      await tester.enterText(_input, '$value');
      await tester.pumpAndSettle();
      expect(controller.text, '$value');
      expect(_rulerValue(tester), value);
      expect(_rulerPosition(tester).outOfRange, isFalse);
      expect(_rulerPosition(tester).maxScrollExtent, extent);
      expect(find.text('0–2000 mL'), findsOneWidget);
      if (value == 2000) {
        expect(_rulerPosition(tester).pixels, extent);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging updates the input before releasing the ruler', (
    tester,
  ) async {
    final controller = TextEditingController(text: '120');
    addTearDown(controller.dispose);
    var changes = 0;
    await tester.pumpWidget(_fieldApp(controller, onChanged: () => changes++));
    await tester.pumpAndSettle();
    expect(changes, 0);
    await tester.ensureVisible(_rulerScroll);
    final gesture = await tester.startGesture(tester.getCenter(_rulerScroll));
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();

    final whileDragging = int.parse(controller.text);
    expect(whileDragging, greaterThan(120));
    expect(whileDragging, lessThanOrEqualTo(360));
    expect(_rulerValue(tester), whileDragging);
    expect(changes, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_rulerValue(tester), int.parse(controller.text));
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing repositions the ruler and the next drag starts there', (
    tester,
  ) async {
    final controller = TextEditingController(text: '91');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_fieldApp(controller));
    await tester.pumpAndSettle();
    final before = _rulerPosition(tester).pixels;
    await tester.enterText(_input, '193');
    await tester.pumpAndSettle();
    expect(_rulerPosition(tester).pixels, greaterThan(before));
    expect(controller.text, '193');
    await _dragRuler(tester, 70);
    expect(int.parse(controller.text), inInclusiveRange(0, 192));
    expect(_rulerValue(tester), int.parse(controller.text));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ruler passes 360 without expansion and stops at zero and 2000', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_fieldApp(controller));
    await tester.pumpAndSettle();
    await _dragRuler(tester, 160);
    expect(controller.text, '0');

    await tester.enterText(_input, '360');
    await tester.pumpAndSettle();
    await _dragRuler(tester, -160);
    expect(int.parse(controller.text), greaterThan(360));
    expect(_rulerValue(tester), int.parse(controller.text));

    await tester.enterText(_input, '2000');
    await tester.pumpAndSettle();
    expect(_rulerValue(tester), 2000);
    await _dragRuler(tester, -160);
    expect(controller.text, '2000');
    await _dragRuler(tester, 90);
    expect(int.parse(controller.text), inInclusiveRange(0, 1999));
    expect(_rulerValue(tester), int.parse(controller.text));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled ruler cannot change the amount or emit a user change', (
    tester,
  ) async {
    final controller = TextEditingController(text: '180');
    addTearDown(controller.dispose);
    var changes = 0;
    await tester.pumpWidget(
      _fieldApp(controller, enabled: false, onChanged: () => changes++),
    );
    await tester.pumpAndSettle();
    await _dragRuler(tester, -110);
    await _dragRuler(tester, 110);
    expect(controller.text, '180');
    expect(_rulerValue(tester), 180);
    expect(changes, 0);

    controller.text = '137';
    await tester.pumpAndSettle();
    expect(_rulerValue(tester), 137);
    expect(controller.text, '137');
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid typed input remains available for correction', (
    tester,
  ) async {
    final controller = TextEditingController(text: '120');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_fieldApp(controller));
    await tester.pumpAndSettle();
    for (final invalid in ['12.5', '-1', '2001', '']) {
      await tester.enterText(_input, invalid);
      await tester.pumpAndSettle();
      expect(controller.text, invalid);
      expect(MilkAmountField.validate(controller.text), isNotNull);
    }
    await tester.enterText(_input, '137');
    await tester.pumpAndSettle();
    expect(controller.text, '137');
    expect(_rulerValue(tester), 137);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an input edit takes ownership from an ongoing ruler fling', (
    tester,
  ) async {
    final controller = TextEditingController(text: '120');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_fieldApp(controller));
    await tester.pumpAndSettle();
    for (final replacement in ['137', '']) {
      controller.text = '120';
      await tester.pumpAndSettle();
      await tester.fling(_rulerScroll, const Offset(-100, 0), 3000);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_rulerPosition(tester).isScrollingNotifier.value, isTrue);

      await tester.enterText(_input, replacement);
      await tester.pumpAndSettle();
      expect(controller.text, replacement);
      expect(_rulerValue(tester), int.tryParse(replacement));
      expect(_rulerPosition(tester).isScrollingNotifier.value, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.text, replacement);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse dragging and arrow keys keep numeric direction in RTL', (
    tester,
  ) async {
    final controller = TextEditingController(text: '137');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _fieldApp(controller, direction: TextDirection.rtl),
    );
    await tester.pumpAndSettle();

    Future<int> mouseDrag(double dx) async {
      final mouse = await tester.startGesture(
        tester.getCenter(_rulerScroll),
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.moveBy(Offset(dx, 0));
      await tester.pump();
      final duringDrag = int.parse(controller.text);
      await mouse.up();
      await tester.pumpAndSettle();
      return duringDrag;
    }

    // Moving the scale left puts a larger number under the fixed pointer,
    // even when the surrounding controls use a right-to-left layout.
    final increased = await mouseDrag(-90);
    expect(increased, greaterThan(137));
    final decreased = await mouseDrag(70);
    expect(decreased, lessThan(increased));

    controller.text = '137';
    await tester.pumpAndSettle();
    Focus.of(tester.element(_rulerScroll)).requestFocus();
    await tester.pump();
    for (final step in [
      (LogicalKeyboardKey.arrowRight, 138),
      (LogicalKeyboardKey.arrowLeft, 137),
      (LogicalKeyboardKey.arrowUp, 147),
      (LogicalKeyboardKey.arrowDown, 137),
    ]) {
      await tester.sendKeyEvent(step.$1);
      await tester.pumpAndSettle();
      expect(controller.text, '${step.$2}');
      expect(_rulerValue(tester), step.$2);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling during a fling freezes its current amount', (
    tester,
  ) async {
    final controller = TextEditingController(text: '120');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_fieldApp(controller));
    await tester.pumpAndSettle();
    await tester.fling(_rulerScroll, const Offset(-100, 0), 3000);
    await tester.pump(const Duration(milliseconds: 16));
    expect(_rulerPosition(tester).isScrollingNotifier.value, isTrue);
    final frozen = controller.text;

    await tester.pumpWidget(_fieldApp(controller, enabled: false));
    await tester.pumpAndSettle();
    expect(controller.text, frozen);
    expect(_rulerValue(tester), int.parse(frozen));
    expect(_rulerPosition(tester).isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.text, frozen);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one accessible slider adjusts exact values and respects disabled state',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final controller = TextEditingController(text: '137');
        addTearDown(controller.dispose);
        await tester.pumpWidget(_fieldApp(controller));
        await tester.pumpAndSettle();
        final slider = find.bySemanticsLabel('本次奶量刻度');
        expect(slider, findsOneWidget);
        final owner = tester.renderObject(slider).owner!.semanticsOwner!;
        var sliderCount = 0;
        void countSliders(SemanticsNode node) {
          if (node.getSemanticsData().flagsCollection.isSlider) sliderCount++;
          node.visitChildren((child) {
            countSliders(child);
            return true;
          });
        }

        countSliders(owner.rootSemanticsNode!);
        expect(sliderCount, 1);
        final initial = tester.getSemantics(slider).getSemanticsData();
        expect(initial.value, '137 毫升');
        expect(initial.hasAction(ui.SemanticsAction.increase), isTrue);
        expect(initial.hasAction(ui.SemanticsAction.decrease), isTrue);
        owner.performAction(
          tester.getSemantics(slider).id,
          ui.SemanticsAction.increase,
        );
        await tester.pumpAndSettle();
        expect(controller.text, '147');
        owner.performAction(
          tester.getSemantics(slider).id,
          ui.SemanticsAction.decrease,
        );
        await tester.pumpAndSettle();
        expect(controller.text, '137');

        controller.text = '360';
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(slider).getSemanticsData().increasedValue,
          '370 毫升',
        );
        owner.performAction(
          tester.getSemantics(slider).id,
          ui.SemanticsAction.increase,
        );
        await tester.pumpAndSettle();
        expect(controller.text, '370');

        controller.text = '0';
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(slider)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.decrease),
          isFalse,
        );
        controller.text = '2000';
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(slider)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.increase),
          isFalse,
        );

        await tester.pumpWidget(_fieldApp(controller, enabled: false));
        await tester.pumpAndSettle();
        final disabled = tester.getSemantics(slider).getSemanticsData();
        expect(disabled.flagsCollection.isEnabled, ui.Tristate.isFalse);
        expect(disabled.hasAction(ui.SemanticsAction.increase), isFalse);
        expect(disabled.hasAction(ui.SemanticsAction.decrease), isFalse);
        expect(controller.text, '2000');
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );
}
