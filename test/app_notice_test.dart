import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/app_message_dialog.dart';
import 'package:feed_reminder/widgets/app_surface.dart';
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

void _expectJournalDialog() {
  expect(find.byType(AppMessageDialog), findsOneWidget);
  expect(find.byType(CupertinoAlertDialog), findsNothing);
  expect(find.byType(CupertinoDialogAction), findsNothing);
  expect(
    find.byWidgetPredicate((widget) => widget is InkResponse),
    findsNothing,
  );
}

Color _dialogSurfaceColor(WidgetTester tester) {
  final surface = find
      .descendant(of: _dialog, matching: find.byType(AppSurface))
      .first;
  return tester
      .widget<Material>(
        find.descendant(of: surface, matching: find.byType(Material)).first,
      )
      .color!;
}

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
    _expectJournalDialog();
    expect(find.text('第一次保存失败'), findsNothing);
    expect(find.text('第二次保存失败'), findsNothing);
    expect(find.text('旧操作'), findsNothing);
    expect(find.text('请重试最后一次保存'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);

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
    expect(Theme.of(tester.element(_dialog)).brightness, Brightness.light);
    expect(_dialogSurfaceColor(tester), AppPalette.light.surface);

    host.setTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(message).style!.color,
      AppPalette.dark.textSecondary,
    );
    expect(Theme.of(tester.element(_dialog)).brightness, Brightness.dark);
    expect(_dialogSurfaceColor(tester), AppPalette.dark.surface);
    _expectJournalDialog();
    expect(host.observer.dialogPushes, 1);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (
      size: const Size(640, 320),
      scale: 1.0,
      keyboard: 0.0,
      padding: const FakeViewPadding(left: 24, right: 24, bottom: 16),
    ),
    (
      size: const Size(320, 640),
      scale: 2.0,
      keyboard: 0.0,
      padding: const FakeViewPadding(top: 24, bottom: 24),
    ),
    (
      size: const Size(640, 320),
      scale: 1.0,
      keyboard: 200.0,
      padding: const FakeViewPadding(top: 24, left: 24, right: 24),
    ),
    (
      size: const Size(640, 320),
      scale: 1.8,
      keyboard: 200.0,
      padding: const FakeViewPadding(top: 24, left: 24, right: 24),
    ),
  ]) {
    testWidgets(
      'long journal notice stays usable in ${layout.size} at ${layout.scale}x text '
      'with ${layout.keyboard}px keyboard',
      (tester) async {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = layout.padding;
        tester.view.viewPadding = layout.padding;
        tester.view.viewInsets = FakeViewPadding(bottom: layout.keyboard);
        tester.platformDispatcher.textScaleFactorTestValue = layout.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final host = await _mount(tester);
        var retries = 0;
        const message =
            '记录暂时无法保存。当前喂奶记录仍然保留，请检查设备存储空间后重试。'
            '如果问题持续，可以先关闭提示，稍后重新打开应用。\n'
            '关闭此提示不会删除现有记录，也不会重复添加刚刚尝试保存的记录。';
        showAppNotice(
          host.sourceContext,
          message,
          actionLabel: '重新尝试保存',
          onAction: () => retries++,
        );
        await tester.pumpAndSettle();

        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          host.setTheme(mode);
          await tester.pumpAndSettle();
          _expectJournalDialog();
          expect(find.text(message), findsOneWidget);
          expect(
            _dialogSurfaceColor(tester),
            mode == ThemeMode.dark
                ? AppPalette.dark.surface
                : AppPalette.light.surface,
          );
          for (final action in [_close, _action]) {
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(tester.widget(action), isA<AppButton>());
            expect(action.hitTestable(), findsOneWidget);
            final rect = tester.getRect(action);
            expect(rect.left, greaterThanOrEqualTo(layout.padding.left));
            expect(
              rect.right,
              lessThanOrEqualTo(layout.size.width - layout.padding.right),
            );
            if (layout.keyboard > 0) {
              // A large button can exceed the short viewport. Its visible,
              // hit-testable center must remain reachable above the keyboard.
              expect(rect.center.dy, greaterThanOrEqualTo(layout.padding.top));
              expect(
                rect.center.dy,
                lessThanOrEqualTo(layout.size.height - layout.keyboard),
              );
            } else {
              expect(rect.top, greaterThanOrEqualTo(layout.padding.top));
              expect(
                rect.bottom,
                lessThanOrEqualTo(layout.size.height - layout.padding.bottom),
              );
            }
          }
          expect(host.observer.dialogPushes, 1);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(_action);
        await tester.pumpAndSettle();
        expect(retries, 1);
        expect(_dialog, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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
