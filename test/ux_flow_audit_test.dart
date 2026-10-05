import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/history_screen.dart';
import 'package:feed_reminder/screens/settings_screen.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:feed_reminder/widgets/meal_amount_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNotifications extends NotificationService {
  @override
  bool get isSupported => false;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
}

class _SilentAudio extends AudioService {
  @override
  Future<void> stopReminder() async {}
}

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: home,
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'delete confirmation identifies milk amount for same-minute meals',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final feed = FeedProvider(
        storage: StorageService(),
        notificationService: _NoNotifications(),
        audioService: _SilentAudio(),
        startTimer: false,
        clock: () => DateTime(2026, 10, 5, 12),
      );
      await feed.ready;
      addTearDown(feed.dispose);
      final time = DateTime(2026, 10, 5, 11);
      await feed.addFeedRecordWithTime(time, milkAmountMl: 0);
      await feed.addFeedRecordWithTime(time, milkAmountMl: 120);
      final originalIds = feed.feedHistory.map((record) => record.id).toList();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: feed,
          child: _app(const HistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      for (final record in feed.feedHistory.toList()) {
        await _tap(tester, find.byKey(ValueKey('delete-record-${record.id}')));
        final amount = tester.widget<Text>(
          find.byKey(const ValueKey('delete-record-milk-amount')),
        );
        expect(
          amount.data,
          record.milkAmountMl == 0 ? '本次奶量 · 未记录' : '本次奶量 · 120 mL',
        );
        expect(find.text('删除后无法恢复，请确认这是要移除的一餐。'), findsOneWidget);
        await _tap(tester, find.byKey(const ValueKey('cancel-delete-record')));
      }
      expect(feed.feedHistory.map((record) => record.id), originalIds);
      expect(tester.takeException(), isNull);
    },
  );

  for (final backfill in [false, true]) {
    testWidgets(
      '${backfill ? 'backfill' : 'default'} milk error is visible after keyboard submit',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        final settings = SettingsProvider(storage: storage);
        final feed = FeedProvider(
          storage: storage,
          notificationService: _NoNotifications(),
          audioService: _SilentAudio(),
          startTimer: false,
          clock: () => DateTime(2026, 10, 5, 12),
        );
        await settings.ready;
        await feed.ready;
        addTearDown(settings.dispose);
        addTearDown(feed.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider.value(value: feed),
              Provider<NotificationService>.value(value: _NoNotifications()),
            ],
            child: _app(
              Scaffold(
                body: backfill
                    ? Builder(
                        builder: (context) => AppButton(
                          key: const ValueKey('open-backfill'),
                          onPressed: () => showAddFeedRecordDialog(context),
                          child: const Text('补记'),
                        ),
                      )
                    : const SettingsScreen(),
              ),
              scale: 2,
            ),
          ),
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey(backfill ? 'open-backfill' : 'default-milk-amount'),
          ),
        );
        final input = find.byKey(const ValueKey('milk-amount-input'));
        await tester.ensureVisible(input);
        await tester.enterText(input, '2001');
        final error = find.text('请输入 0–2000 之间的整数（mL）');
        final body = find.ancestor(
          of: input,
          matching: find.byType(Scrollable),
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.ensureVisible(input);
          await tester.showKeyboard(input);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(error.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(error).top,
            greaterThanOrEqualTo(tester.getRect(body).top - 1),
          );
          expect(
            tester.getRect(error).bottom,
            lessThanOrEqualTo(tester.getRect(body).bottom + 1),
          );
        }
        await _tap(
          tester,
          backfill
              ? find.byKey(const ValueKey('add-feed-cancel'))
              : find.text('取消'),
        );
        expect(input, findsNothing);
        expect(feed.feedHistory, isEmpty);
        expect(settings.defaultMilkAmountMl, 0);
        expect(await storage.getFeedHistory(), isEmpty);
        expect(await storage.getDefaultMilkAmountMl(), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final invalid in ['120.5', '-50']) {
    testWidgets(
      'interval input rejects $invalid without changing its meaning',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider(storage: StorageService());
        await settings.ready;
        addTearDown(settings.dispose);
        final original = settings.feedIntervalMinutes;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              Provider<NotificationService>.value(value: _NoNotifications()),
            ],
            child: _app(const Scaffold(body: SettingsScreen())),
          ),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('custom-interval-button')),
        );
        final field = find.byKey(const ValueKey('custom-interval-field'));
        await tester.enterText(field, invalid);
        await _tap(tester, find.text('保存'));

        expect(settings.feedIntervalMinutes, original);
        expect(find.text('自定义喂奶间隔'), findsOneWidget);
        expect(
          tester.widget<CupertinoTextField>(field).controller!.text,
          invalid,
        );
        expect(find.text('请输入 1–1440 之间的整数').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('meal validation feedback is visible after a fixed-footer submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MealAmountSelection? result;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              key: const ValueKey('open-meal-editor'),
              onPressed: () async {
                result = await showMealAmountDialog(
                  context,
                  currentAmount: 120,
                  defaultAmount: 120,
                );
              },
              child: const Text('调整奶量'),
            ),
          ),
        ),
        scale: 2,
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('open-meal-editor')));
    final input = find.byKey(const ValueKey('milk-amount-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '2001');
    final body = find.ancestor(of: input, matching: find.byType(Scrollable));
    // Users can return to the explanatory text, then submit from the fixed
    // action bar. The resulting validation message must bring itself into view.
    final error = find.text('请输入 0–2000 之间的整数（mL）');
    for (var attempt = 0; attempt < 2; attempt++) {
      tester.state<ScrollableState>(body).position.jumpTo(0);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('meal-amount-apply')));
      expect(error.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(error).top,
        greaterThanOrEqualTo(tester.getRect(body).top - 1),
      );
      expect(
        tester.getRect(error).bottom,
        lessThanOrEqualTo(tester.getRect(body).bottom + 1),
      );
    }
    expect(result, isNull);
    await _tap(tester, find.byKey(const ValueKey('meal-amount-cancel')));
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
