import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BoxDecoration _focusDecoration(WidgetTester tester, Finder button) {
  final foreground = find.descendant(
    of: button,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.position == DecorationPosition.foreground,
    ),
  );
  return tester.widget<DecoratedBox>(foreground).decoration as BoxDecoration;
}

void main() {
  for (final dark in [false, true]) {
    for (final filled in [false, true]) {
      testWidgets(
        '${dark ? 'dark' : 'light'} ${filled ? 'filled' : 'outlined'} button keyboard focus follows its surface',
        (tester) async {
          final strategy = FocusManager.instance.highlightStrategy;
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic;
          addTearDown(() {
            FocusManager.instance.highlightStrategy = strategy;
          });
          var activations = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        key: const ValueKey('subject'),
                        radius: filled ? 24 : 14,
                        filled: filled,
                        onPressed: () => activations++,
                        child: const Text('完成'),
                      ),
                      AppButton(onPressed: () {}, child: const Text('另一个操作')),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();
          final button = find.byKey(const ValueKey('subject'));
          expect(_focusDecoration(tester, button).border, isNull);

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final decoration = _focusDecoration(tester, button);
          final surface = tester.widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)),
          );
          final shape = surface.shape! as RoundedRectangleBorder;
          expect(decoration.borderRadius, shape.borderRadius);
          final border = decoration.border! as Border;
          final palette = dark ? AppPalette.dark : AppPalette.light;
          expect(
            border.top.color,
            filled ? palette.onPrimary : palette.primary,
          );
          final foregroundLuminance = border.top.color.computeLuminance();
          final backgroundLuminance = surface.color!.computeLuminance();
          final lighter = foregroundLuminance > backgroundLuminance
              ? foregroundLuminance
              : backgroundLuminance;
          final darker = foregroundLuminance < backgroundLuminance
              ? foregroundLuminance
              : backgroundLuminance;
          expect((lighter + .05) / (darker + .05), greaterThanOrEqualTo(3));

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(activations, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(_focusDecoration(tester, button).border, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
