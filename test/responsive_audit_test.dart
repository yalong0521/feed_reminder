import 'dart:convert';
import 'dart:math' as math;

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:feed_reminder/widgets/milk_volume_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}
  @override
  Future<void> stopReminder() async {}
}

class _Notifications extends NotificationService {
  @override
  bool get isSupported => false;
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
  @override
  Future<void> cancelAll() async {}
}

Future<SettingsProvider> _start(
  WidgetTester tester,
  Size size,
  double scale, {
  int amount = 180,
}) async {
  final now = DateTime(2026, 10, 5, 12);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({
    'acceptedPrivacyPolicyVersion': PrivacyPolicy.version,
    StorageKeys.burnInProtectionEnabled: false,
    StorageKeys.defaultMilkAmountMl: amount,
    StorageKeys.feedHistory: jsonEncode([
      for (var i = 0; i < 30; i++)
        FeedRecord(
          id: 'audit-$i',
          time: now.subtract(Duration(days: i, minutes: 50)),
          milkAmountMl: i % 3 == 0 ? 0 : 180,
        ).toJson(),
    ]),
  });
  final storage = StorageService();
  final settings = SettingsProvider(storage: storage);
  final audio = _Audio();
  final notifications = _Notifications();
  final feed = FeedProvider(
    storage: storage,
    audioService: audio,
    notificationService: notifications,
    startTimer: false,
    clock: () => now,
  );
  await Future.wait([feed.ready, settings.ready]);
  await tester.pumpWidget(
    FeedReminderApp(
      storage: storage,
      feedProvider: feed,
      settingsProvider: settings,
      audioService: audio,
      notificationService: notifications,
      enablePlatformEffects: false,
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    feed.dispose();
    settings.dispose();
  });
  return settings;
}

Finder _key(String key) => find.byKey(ValueKey(key));

double _visibleFontSize(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final transform = paragraph.getTransformTo(null);
  final verticalScale = math.sqrt(
    transform.entry(0, 1) * transform.entry(0, 1) +
        transform.entry(1, 1) * transform.entry(1, 1),
  );
  final fontSize = tester.widget<Text>(text).style!.fontSize!;
  return paragraph.textScaler.scale(fontSize) * verticalScale;
}

Future<void> _reachable(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'Revealing $target');
  expect(target.hitTestable(), findsOneWidget, reason: '$target is reachable');
  final rect = tester.getRect(target);
  final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
  final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(-.1), reason: '$target left');
  expect(
    rect.right,
    lessThanOrEqualTo(viewport.width + .1),
    reason: '$target right',
  );
  expect(rect.top, greaterThanOrEqualTo(-.1), reason: '$target top');
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.height - keyboard + .1),
    reason: '$target bottom',
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await _reachable(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'Opening $key');
}

Future<void> _close(WidgetTester tester, String text) async {
  final button = find.widgetWithText(AppButton, text);
  await _reachable(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _keyboardCheck(
  WidgetTester tester,
  String field,
  String action,
  Size size,
) async {
  await tester.enterText(
    _key(field),
    field == 'custom-interval-field' ? '1440' : '2000',
  );
  tester.view.viewInsets = FakeViewPadding(
    bottom: math.min(260, size.height * .45),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$field keyboard');
  await _reachable(tester, _key(action));
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 720),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('responsive audit pages and dialogs $size scale $scale', (
        tester,
      ) async {
        final settings = await _start(tester, size, scale);
        await _tap(tester, 'adjust-meal-amount');
        await _keyboardCheck(
          tester,
          'milk-amount-input',
          'meal-amount-apply',
          size,
        );
        await _tap(tester, 'meal-amount-cancel');
        await _tap(tester, 'backfill-feed');
        await _keyboardCheck(
          tester,
          'milk-amount-input',
          'add-feed-save',
          size,
        );
        await _tap(tester, 'add-feed-cancel');
        await _tap(tester, 'nav-history');
        await _tap(tester, 'history-query-button');
        await _tap(tester, 'date-range-start');
        await _tap(tester, 'query-calendar-done');
        await _tap(tester, 'date-range-cancel');
        await _tap(tester, 'history-statistics-button');
        await _tap(tester, 'statistics-range-30');
        await tester.ensureVisible(_key('statistics-day-detail'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tap(tester, 'statistics-back');
        await _tap(tester, 'nav-settings');
        await _tap(tester, 'default-milk-amount');
        await _keyboardCheck(
          tester,
          'milk-amount-input',
          'save-default-milk-amount',
          size,
        );
        await _close(tester, '取消');
        await _tap(tester, 'custom-interval-button');
        await tester.enterText(_key('custom-interval-field'), '1440');
        tester.view.viewInsets = FakeViewPadding(
          bottom: math.min(260, size.height * .45),
        );
        await tester.pumpAndSettle();
        await _reachable(tester, find.widgetWithText(AppButton, '保存'));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await _close(tester, '取消');
        await _tap(tester, 'open-data-management');
        for (final key in [
          'backup-export-json',
          'backup-import-json',
          'backup-export-csv',
        ]) {
          await _reachable(tester, _key(key));
        }
        await _tap(tester, 'data-management-back');
        final privacy = find.text('阅读隐私政策');
        await _reachable(tester, privacy);
        await tester.tap(privacy);
        await tester.pumpAndSettle();
        await _tap(tester, 'privacy-policy-back');
        await settings.setFeedInterval(1);
        await _tap(tester, 'nav-home');
        await _tap(tester, 'snooze-reminder');
        for (final key in ['snooze-10', 'snooze-20', 'snooze-30']) {
          await _reachable(tester, _key(key));
        }
        await _close(tester, '取消');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final amount in [0, 180, 2000]) {
    testWidgets(
      'responsive audit 320px milk $amount keeps the main action readable',
      (tester) async {
        await _start(tester, const Size(320, 568), 2, amount: amount);
        final text = find.text('滑动记录喂奶');
        final visibleSize = _visibleFontSize(tester, text);
        expect(
          visibleSize,
          greaterThanOrEqualTo(16),
          reason:
              'Main slide action renders at $visibleSize px despite 2x text',
        );
      },
    );
  }

  testWidgets(
    'responsive audit compact undo failure stays readable and retryable',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: FeedButton(
                  onPressed: () async {},
                  onUndo: () async {
                    if (++attempts == 1) throw StateError('failed undo');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(_key('feed-slide-thumb'), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tester.tap(_key('feed-slide-undo'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      final visibleSize = _visibleFontSize(tester, find.text('撤销失败'));
      expect(
        visibleSize,
        greaterThanOrEqualTo(16),
        reason: 'Undo failure renders at $visibleSize px despite 2x text',
      );
      expect(_key('feed-slide-undo').hitTestable(), findsOneWidget);
      await tester.tap(_key('feed-slide-undo'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(_key('feed-slide-thumb').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'responsive audit statistics accepts its advertised horizontal mouse drag',
    (tester) async {
      await _start(tester, const Size(844, 390), 1);
      await _tap(tester, 'nav-history');
      await _tap(tester, 'history-statistics-button');
      await _tap(tester, 'statistics-range-30');
      final chart = _key('milk-chart-scroll-30');
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: chart, matching: find.byType(Scrollable)).first,
      );
      final before = scrollable.position.pixels;
      final selectedBefore = tester
          .widget<MilkVolumeChart>(find.byType(MilkVolumeChart))
          .selectedDate;
      await tester.drag(
        chart,
        const Offset(220, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        scrollable.position.pixels,
        greaterThan(before),
        reason: 'Dragging towards older dates should reveal them',
      );
      expect(
        tester
            .widget<MilkVolumeChart>(find.byType(MilkVolumeChart))
            .selectedDate,
        selectedBefore,
        reason: 'Dragging must not also select the pressed date',
      );
      final visibleDay = find
          .descendant(
            of: chart,
            matching: find.byWidgetPredicate(
              (widget) => widget is AppPressable && widget.selected == false,
            ),
          )
          .hitTestable()
          .first;
      final selectedKey = tester.widget<AppPressable>(visibleDay).key;
      await tester.tap(visibleDay, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppPressable>(find.byKey(selectedKey!)).selected,
        isTrue,
        reason: 'A mouse click must still select the day after dragging',
      );
    },
  );

  testWidgets('responsive audit chart advertises scrolling only when needed', (
    tester,
  ) async {
    await _start(tester, const Size(1280, 720), 1);
    await _tap(tester, 'nav-history');
    await _tap(tester, 'history-statistics-button');
    final chart = _key('milk-chart-scroll-7');
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: chart, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(find.text('左右滑动查看日期，点按柱形查看明细。'), findsNothing);
    expect(find.text('点按柱形查看明细。'), findsOneWidget);
    await _tap(tester, 'statistics-range-30');
    expect(find.text('左右滑动查看日期，点按柱形查看明细。'), findsOneWidget);
    expect(find.text('点按柱形查看明细。'), findsNothing);
  });
}
