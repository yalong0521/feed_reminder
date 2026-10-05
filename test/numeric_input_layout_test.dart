import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/settings_screen.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/milk_amount_field.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNotifications extends NotificationService {
  @override
  bool get isSupported => false;
}

Widget _app(Widget home, double scale) {
  final base = AppTheme.light;
  return MaterialApp(
    theme: base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'NumericLayoutTest'),
      cupertinoOverrideTheme: const CupertinoThemeData(
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(
            fontFamily: 'NumericLayoutTest',
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ),
    ),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );
}

void _expectFullNumber(
  WidgetTester tester,
  String key,
  String value,
  double fontSize,
  double scale,
) {
  final editable = tester
      .state<EditableTextState>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
      )
      .renderEditable;
  final painter = TextPainter(
    text: editable.text,
    textDirection: editable.textDirection,
    textScaler: editable.textScaler,
  )..layout();
  expect(editable.text!.toPlainText(), value);
  expect(editable.textScaler.scale(fontSize), closeTo(fontSize * scale, .01));
  expect(
    editable.size.width,
    greaterThanOrEqualTo(painter.width + editable.cursorWidth),
  );
  painter.dispose();
}

void main() {
  setUpAll(() async {
    // Use a bundled real font so the width assertion checks shaped digits,
    // rather than the test runner's square placeholder glyphs.
    final font = FontLoader('NumericLayoutTest')
      ..addFont(rootBundle.load('assets/fonts/Tinos-Regular.ttf'));
    await font.load();
  });

  for (final scale in [1.8, 2.0]) {
    for (final amount in [180, 2000]) {
      testWidgets(
        '320px milk input shows every digit of $amount at $scale scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = TextEditingController(text: '$amount');
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: SingleChildScrollView(
                  // The narrowest 320px dialog leaves 224px for its content.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 24,
                  ),
                  child: MilkAmountField(controller: controller),
                ),
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          _expectFullNumber(tester, 'milk-amount-input', '$amount', 32, scale);

          final decrease = find.byKey(const ValueKey('milk-amount-decrease'));
          final increase = find.byKey(const ValueKey('milk-amount-increase'));
          for (final button in [decrease, increase]) {
            expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
            expect(button.hitTestable(), findsOneWidget);
          }
          await tester.tap(decrease);
          await tester.pumpAndSettle();
          expect(controller.text, '${amount - 10}');
          await tester.tap(increase);
          await tester.pumpAndSettle();
          expect(controller.text, '$amount');
          _expectFullNumber(tester, 'milk-amount-input', '$amount', 32, scale);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '320px custom interval shows all 1440 minutes at $scale scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider(storage: StorageService());
        await settings.ready;
        addTearDown(settings.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              Provider<NotificationService>.value(value: _NoNotifications()),
            ],
            child: _app(const Scaffold(body: SettingsScreen()), scale),
          ),
        );
        await tester.pumpAndSettle();
        final custom = find.byKey(const ValueKey('custom-interval-button'));
        await tester.ensureVisible(custom);
        await tester.pumpAndSettle();
        await tester.tap(custom);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('custom-interval-field')),
          '1440',
        );
        await tester.pumpAndSettle();
        _expectFullNumber(tester, 'custom-interval-field', '1440', 40, scale);
        final save = find.widgetWithText(AppButton, '保存');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(settings.feedIntervalMinutes, 1440);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
