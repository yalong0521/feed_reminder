import 'package:feed_reminder/screens/privacy_policy_screen.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy entry and return resist repeated activation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              key: const ValueKey('open-test-settings'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: AppButton(
                      key: const ValueKey('open-test-privacy'),
                      onPressed: () => showPrivacyPolicy(context),
                      child: const Text('阅读隐私政策'),
                    ),
                  ),
                ),
              ),
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-test-settings')));
    await tester.pumpAndSettle();
    final open = tester
        .widget<AppButton>(find.byKey(const ValueKey('open-test-privacy')))
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(
      find.byType(PrivacyPolicyScreen, skipOffstage: false),
      findsOneWidget,
    );
    final back = tester
        .widget<AppButton>(find.byKey(const ValueKey('privacy-policy-back')))
        .onPressed!;
    back();
    back();
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen, skipOffstage: false), findsNothing);
    expect(
      find.byKey(const ValueKey('open-test-privacy')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open-test-settings')).hitTestable(),
      findsNothing,
    );

    open();
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
