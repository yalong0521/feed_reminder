import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoticeObserver extends NavigatorObserver {
  int dialogPushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'app-error-dialog') {
      dialogPushes++;
    }
    super.didPush(route, previousRoute);
  }
}

class _NoticeHarness extends StatefulWidget {
  const _NoticeHarness({super.key});

  @override
  State<_NoticeHarness> createState() => _NoticeHarnessState();
}

class _NoticeHarnessState extends State<_NoticeHarness> {
  final observer = _NoticeObserver();
  late BuildContext sourceContext;
  ThemeMode themeMode = ThemeMode.light;
  bool showSource = true;

  void setTheme(ThemeMode next) => setState(() => themeMode = next);
  void removeSource() => setState(() => showSource = false);

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: themeMode,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    navigatorObservers: [observer],
    home: Scaffold(
      body: showSource
          ? Builder(
              builder: (context) {
                sourceContext = context;
                return const SizedBox.expand();
              },
            )
          : const SizedBox.shrink(),
    ),
  );
}

Future<_NoticeHarnessState> _mount(WidgetTester tester) async {
  final key = GlobalKey<_NoticeHarnessState>();
  await tester.pumpWidget(_NoticeHarness(key: key));
  await tester.pumpAndSettle();
  return key.currentState!;
}

final _dialog = find.byKey(const ValueKey('app-notice-dialog'));
final _close = find.byKey(const ValueKey('app-notice-close'));
final _action = find.byKey(const ValueKey('app-notice-action'));

void main() {
  testWidgets('consecutive errors replace one dialog without an old queue', (
    tester,
  ) async {
    final host = await _mount(tester);
    var oldActionCalls = 0;
    var latestActionCalls = 0;
    showAppNotice(
      host.sourceContext,
      '第一次保存失败',
      actionLabel: '旧操作',
      onAction: () => oldActionCalls++,
    );
    await tester.pumpAndSettle();
    showAppNotice(host.sourceContext, '第二次保存失败');
    showAppNotice(
      host.sourceContext,
      '请重试最后一次保存',
      actionLabel: '重试保存',
      onAction: () => latestActionCalls++,
    );
    await tester.pumpAndSettle();

    expect(host.observer.dialogPushes, 1);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('第一次保存失败'), findsNothing);
    expect(find.text('第二次保存失败'), findsNothing);
    expect(find.text('旧操作'), findsNothing);
    expect(find.text('请重试最后一次保存'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);

    // Errors remain visible until explicitly acknowledged, regardless of the
    // duration accepted by the old helper API.
    await tester.pump(const Duration(minutes: 1));
    expect(_dialog, findsOneWidget);
    await tester.tap(_action);
    await tester.tap(_action);
    await tester.pumpAndSettle();
    expect(latestActionCalls, 1);
    expect(oldActionCalls, 0);
    expect(_dialog, findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(_dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replacement removes an obsolete optional action', (
    tester,
  ) async {
    final host = await _mount(tester);
    showAppNotice(
      host.sourceContext,
      '可重试的错误',
      actionLabel: '重试',
      onAction: () {},
    );
    await tester.pumpAndSettle();
    showAppNotice(host.sourceContext, '请检查设置后再次操作');
    await tester.pumpAndSettle();
    expect(_action, findsNothing);
    expect(_close, findsOneWidget);
    expect(host.observer.dialogPushes, 1);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
  });

  testWidgets('an open error follows theme changes without another route', (
    tester,
  ) async {
    final host = await _mount(tester);
    showAppNotice(host.sourceContext, '状态保存失败');
    await tester.pumpAndSettle();
    final message = find.byKey(const ValueKey('app-notice-message'));
    expect(
      tester.widget<Text>(message).style!.color,
      AppPalette.light.textSecondary,
    );
    expect(
      CupertinoTheme.of(tester.element(_dialog)).brightness,
      Brightness.light,
    );

    host.setTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(message).style!.color,
      AppPalette.dark.textSecondary,
    );
    expect(
      CupertinoTheme.of(tester.element(_dialog)).brightness,
      Brightness.dark,
    );
    expect(host.observer.dialogPushes, 1);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back closes the dialog and a later error can reopen', (
    tester,
  ) async {
    final host = await _mount(tester);
    showAppNotice(host.sourceContext, '保存失败');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);

    showAppNotice(host.sourceContext, '再次保存失败');
    await tester.pumpAndSettle();
    expect(find.text('再次保存失败'), findsOneWidget);
    expect(host.observer.dialogPushes, 2);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('new error survives an older dialog finishing its exit', (
    tester,
  ) async {
    final host = await _mount(tester);
    showAppNotice(host.sourceContext, '旧错误');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 50));
    showAppNotice(host.sourceContext, '新错误');
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(find.text('旧错误'), findsNothing);
    expect(find.text('新错误'), findsOneWidget);

    showAppNotice(host.sourceContext, '新错误已更新');
    await tester.pumpAndSettle();
    expect(host.observer.dialogPushes, 2);
    expect(find.text('新错误已更新'), findsOneWidget);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed source cannot reopen or invoke a stale callback', (
    tester,
  ) async {
    final host = await _mount(tester);
    final originalContext = host.sourceContext;
    var actionCalls = 0;
    showAppNotice(
      originalContext,
      '保存失败',
      actionLabel: '重试',
      onAction: () => actionCalls++,
    );
    await tester.pumpAndSettle();
    host.removeSource();
    await tester.pumpAndSettle();
    expect(originalContext.mounted, isFalse);
    await tester.tap(_action);
    await tester.pumpAndSettle();
    expect(actionCalls, 0);
    expect(_dialog, findsNothing);

    // Deliberately exercise the helper's stale-context guard.
    // ignore: use_build_context_synchronously
    showAppNotice(originalContext, '迟到的错误');
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the navigator also disposes an open error safely', (
    tester,
  ) async {
    final host = await _mount(tester);
    showAppNotice(host.sourceContext, '保存失败');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final replacement = await _mount(tester);
    showAppNotice(replacement.sourceContext, '新页面保存失败');
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(find.text('新页面保存失败'), findsOneWidget);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
