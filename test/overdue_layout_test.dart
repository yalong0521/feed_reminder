import 'dart:convert';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:feed_reminder/utils/time_utils.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:feed_reminder/widgets/overdue_duration.dart';
import 'package:feed_reminder/widgets/overdue_timeline.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}

  @override
  Future<void> stopReminder() async {}
}

class _LocalNotifications extends NotificationService {
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

Future<FeedProvider> _mountOverdue(
  WidgetTester tester, {
  required Size size,
  required DateTime now,
  required Duration overdue,
  DateTime Function()? clock,
  double devicePixelRatio = 1,
  double scale = 1,
  Brightness brightness = Brightness.dark,
  FakeViewPadding padding = FakeViewPadding.zero,
  bool quiet = false,
  bool acknowledged = false,
}) async {
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  final last = now.subtract(overdue + const Duration(hours: 3));
  SharedPreferences.setMockInitialValues({
    'burnInProtectionEnabled': false,
    'nightModeEnabled': quiet,
    'feedHistory': jsonEncode([FeedRecord(time: last).toJson()]),
    if (acknowledged) 'acknowledgedFeedTime': last.millisecondsSinceEpoch,
  });
  final storage = StorageService();
  await storage.setAcceptedPrivacyPolicyVersion(PrivacyPolicy.version);
  final audio = _SilentAudio();
  final notifications = _LocalNotifications();
  final feed = FeedProvider(
    storage: storage,
    audioService: audio,
    notificationService: notifications,
    startTimer: false,
    clock: clock ?? () => now,
  );
  final settings = SettingsProvider(storage: storage);
  await Future.wait([feed.ready, settings.ready]);
  addTearDown(feed.dispose);
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    FeedReminderApp(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      feedProvider: feed,
      settingsProvider: settings,
      enablePlatformEffects: false,
    ),
  );
  await tester.pumpAndSettle();
  return feed;
}

void _expectInside(Rect child, Rect viewport) {
  const tolerance = .1;
  expect(child.left, greaterThanOrEqualTo(viewport.left - tolerance));
  expect(child.top, greaterThanOrEqualTo(viewport.top - tolerance));
  expect(child.right, lessThanOrEqualTo(viewport.right + tolerance));
  expect(child.bottom, lessThanOrEqualTo(viewport.bottom + tolerance));
}

Future<void> _expectOneReadingAxis(
  WidgetTester tester,
  String stopLabel, {
  bool showTimeline = false,
}) async {
  final subtitle = tester.getRect(find.text('该喂奶了'));
  final minutes = tester.getRect(
    find.byKey(const ValueKey('landscape-countdown')),
  );
  final stop = tester.getRect(find.text(stopLabel));
  // The status now reads inline with elapsed minutes. Supporting information
  // shares that row's center rather than opening a second visual column.
  await _expectInlineDuration(tester, showTimeline: showTimeline);
  expect(subtitle.bottom, lessThanOrEqualTo(minutes.top + .1));
  if (showTimeline) {
    final references = tester
        .getRect(find.textContaining(RegExp('^原定 ')))
        .expandToInclude(tester.getRect(find.textContaining(RegExp('^现在 '))));
    expect(references.center.dx, closeTo(minutes.center.dx, 1));
    expect(minutes.bottom, lessThanOrEqualTo(references.top + .1));
    expect(references.bottom, lessThanOrEqualTo(stop.top));
  } else {
    expect(minutes.bottom, lessThanOrEqualTo(stop.top));
  }
  expect(stop.center.dx, closeTo(minutes.center.dx, 16));
}

Future<void> _expectInlineDuration(
  WidgetTester tester, {
  bool showTimeline = false,
}) async {
  final duration = find.byType(OverdueDuration);
  expect(duration, findsOneWidget);
  final overdue = tester.widget<OverdueDuration>(duration).duration;
  expect(find.text('已超时'), findsNothing);
  expect(find.textContaining('超出原定时间'), findsNothing);
  final referenceCount = showTimeline ? findsOneWidget : findsNothing;
  expect(find.byType(OverdueTimeline), referenceCount);
  expect(find.textContaining(RegExp('^原定 ')), referenceCount);
  expect(find.textContaining(RegExp('^现在 ')), referenceCount);
  final semantics = tester.ensureSemantics();
  try {
    await tester.pump();
    expect(
      find.bySemanticsLabel('超时 ${TimeUtils.formatDuration(overdue)}'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('(^|，)(原定|现在) ')), referenceCount);
  } finally {
    semantics.dispose();
  }
  final prefix = find.descendant(of: duration, matching: find.text('超时'));
  final minutes = overdue.inMinutes;
  final number = find.descendant(of: duration, matching: find.text('$minutes'));
  final unit = find.descendant(of: duration, matching: find.text('分钟'));
  expect(find.text('超时'), findsOneWidget);
  expect(prefix, findsOneWidget);
  expect(number, findsOneWidget);
  expect(unit, findsOneWidget);
  final prefixBounds = tester.getRect(prefix);
  final numberBounds = tester.getRect(number);
  final unitBounds = tester.getRect(unit);
  expect(numberBounds.center.dx, closeTo(tester.getCenter(duration).dx, .1));
  expect(prefixBounds.right, lessThanOrEqualTo(numberBounds.left));
  expect(numberBounds.right, lessThanOrEqualTo(unitBounds.left));
  double baseline(Finder text) {
    final box = tester.renderObject<RenderBox>(text);
    return box
        .localToGlobal(
          Offset(
            0,
            box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!,
          ),
        )
        .dy;
  }

  expect(baseline(prefix), closeTo(baseline(number), .1));
  expect(baseline(unit), closeTo(baseline(number), .1));
}

Future<void> _expectFirstFrame(
  WidgetTester tester,
  Size size, {
  required bool showTimeline,
}) async {
  final details = tester.getRect(
    find.byKey(const ValueKey('countdown-details-scroll')),
  );
  final duration = find.byKey(const ValueKey('landscape-countdown'));
  for (final target in [
    find.text('超时'),
    find.text('该喂奶了'),
    duration,
    if (showTimeline) ...[
      find.textContaining(RegExp('^原定 ')),
      find.textContaining(RegExp('^现在 ')),
    ],
  ]) {
    _expectInside(tester.getRect(target), details);
    expect(target.hitTestable(), findsOneWidget);
  }
  if (showTimeline) {
    _expectInside(tester.getRect(find.byType(OverdueTimeline)), details);
  }
  expect(tester.getSize(duration).height, greaterThan(48));
  await _expectOneReadingAxis(tester, '本次提醒已停止', showTimeline: showTimeline);
  expect(find.text('本次提醒已停止').hitTestable(), findsOneWidget);
  expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
  final viewport = Offset.zero & size;
  _expectInside(tester.getRect(find.text('本次提醒已停止')), viewport);
  _expectInside(
    tester.getRect(find.byKey(const ValueKey('feed-control-dock'))),
    viewport,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('assets/fonts/Tinos-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Tinos-Bold.ttf'));
    await font.load();
  });

  for (final size in [
    const Size(1024, 600),
    const Size(640, 320),
    const Size(640, 280),
  ]) {
    testWidgets('stopped quiet overdue stays on one reading axis at $size', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 2, 23, 24, 20);
      final feed = await _mountOverdue(
        tester,
        size: size,
        now: now,
        overdue: const Duration(hours: 9, minutes: 21, seconds: 20),
        quiet: true,
        acknowledged: true,
      );
      expect(feed.isAlertAcknowledged, isTrue);
      expect(find.byIcon(CupertinoIcons.moon), findsOneWidget);
      expect(find.text('561').hitTestable(), findsOneWidget);
      await _expectOneReadingAxis(
        tester,
        '本次提醒已停止',
        showTimeline: size.height == 600,
      );
      final details = tester.getRect(
        find.byKey(const ValueKey('countdown-details-scroll')),
      );
      _expectInside(details, Offset.zero & size);
      _expectInside(tester.getRect(find.text('超时')), details);
      _expectInside(
        tester.getRect(find.byKey(const ValueKey('landscape-countdown'))),
        details,
      );
      if (size.height == 600) {
        expect(find.text('原定 14:03').hitTestable(), findsOneWidget);
        expect(find.text('现在 23:24').hitTestable(), findsOneWidget);
      }
      expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final scenario in [
    (const Size(640, 320), const Duration(hours: 1)),
    (
      const Size(640, 320),
      const Duration(days: 7, hours: 23, minutes: 59, seconds: 59),
    ),
    (const Size(640, 280), const Duration(hours: 1)),
    (
      const Size(640, 280),
      const Duration(days: 7, hours: 23, minutes: 59, seconds: 59),
    ),
  ]) {
    final (size, overtime) = scenario;
    testWidgets(
      'short landscape $size keeps $overtime readable with large text and insets',
      (tester) async {
        const padding = FakeViewPadding(
          top: 20,
          left: 24,
          right: 24,
          bottom: 16,
        );
        final now = DateTime(2026, 10, 2, 23, 24, 20);
        final feed = await _mountOverdue(
          tester,
          size: size,
          now: now,
          overdue: overtime,
          scale: 1.8,
          brightness: Brightness.light,
          padding: padding,
          quiet: true,
        );
        final number = find.text('${overtime.inMinutes}');
        expect(number.hitTestable(), findsOneWidget);
        final details = find.byKey(const ValueKey('countdown-details-scroll'));
        _expectInside(tester.getRect(find.text('超时')), tester.getRect(details));
        _expectInside(
          tester.getRect(find.byKey(const ValueKey('landscape-countdown'))),
          tester.getRect(details),
        );
        expect(tester.getRect(number).height, greaterThan(48));
        await _expectInlineDuration(tester);
        final stop = find.text('停止本次提醒');
        final dock = find.byKey(const ValueKey('feed-control-dock'));
        final dockBounds = tester.getRect(dock);
        final usable = Rect.fromLTRB(
          padding.left,
          padding.top,
          size.width - padding.right,
          size.height - padding.bottom,
        );
        _expectInside(dockBounds, usable);
        final adjust = find.byKey(const ValueKey('adjust-meal-amount'));
        expect(adjust.hitTestable(), findsOneWidget);
        _expectInside(tester.getRect(adjust), dockBounds);
        expect(
          find.byKey(const ValueKey('snooze-reminder')).hitTestable(),
          findsOneWidget,
        );
        expect(stop.hitTestable(), findsOneWidget);

        for (final target in [number, find.text('该喂奶了')]) {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          _expectInside(tester.getRect(target), tester.getRect(details));
          _expectInside(tester.getRect(stop), usable);
          _expectInside(tester.getRect(dock), usable);
          expect(stop.hitTestable(), findsOneWidget);
          expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
        }
        await tester.tap(stop);
        await tester.pumpAndSettle();
        expect(feed.isAlertAcknowledged, isTrue);
        expect(feed.feedHistory, hasLength(1));
        expect(find.text('本次提醒已停止').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final scenario in [
    (const Size(1032, 583), 1.5, true),
    (const Size(1024, 520), 1.0, true),
    (const Size(844, 390), 1.0, true),
    (const Size(640, 320), 1.0, false),
    (const Size(640, 280), 1.0, false),
  ]) {
    final (size, devicePixelRatio, showTimeline) = scenario;
    testWidgets(
      'landscape $size at ${devicePixelRatio}x fits visible content on its first frame',
      (tester) async {
        await _mountOverdue(
          tester,
          size: size,
          devicePixelRatio: devicePixelRatio,
          now: DateTime(2026, 10, 2, 23, 24, 20),
          overdue: const Duration(hours: 9, minutes: 21, seconds: 20),
          quiet: true,
          acknowledged: true,
        );
        await _expectFirstFrame(tester, size, showTimeline: showTimeline);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('same window adapts its timeline to larger text and back', (
    tester,
  ) async {
    const size = Size(844, 430);
    final feed = await _mountOverdue(
      tester,
      size: size,
      now: DateTime(2026, 10, 2, 23, 24, 20),
      overdue: const Duration(hours: 9, minutes: 21, seconds: 20),
      quiet: true,
      acknowledged: true,
    );
    final ids = feed.feedHistory.map((record) => record.id).toList();
    final slider = find.byType(FeedButton);
    final sliderState = tester.state(slider);
    await _expectFirstFrame(tester, size, showTimeline: true);

    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    await tester.pumpAndSettle();
    await _expectFirstFrame(tester, size, showTimeline: false);

    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    await _expectFirstFrame(tester, size, showTimeline: true);
    expect(tester.state(slider), same(sliderState));
    expect(feed.feedHistory.map((record) => record.id), ids);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(1200, 820), const Size(600, 960)]) {
    testWidgets(
      'normal and overdue keep the same visible digit height at $size',
      (tester) async {
        final started = DateTime(2026, 10, 2, 12);
        var now = started;
        final feed = await _mountOverdue(
          tester,
          size: size,
          now: started,
          overdue: const Duration(hours: -1),
          clock: () => now,
        );
        expect(feed.state, FeedState.normal);
        final ids = feed.feedHistory.map((record) => record.id).toList();
        final normalClock = find.text('01:00:00');
        expect(normalClock.hitTestable(), findsOneWidget);
        final normalBounds = tester.getRect(normalClock);
        expect(normalBounds.height, greaterThan(100));

        now = started.add(const Duration(hours: 1, minutes: 15));
        await feed.refresh();
        await tester.pumpAndSettle();
        expect(feed.state, FeedState.alerting);
        final overdueNumber = find.descendant(
          of: find.byType(OverdueDuration),
          matching: find.text('15'),
        );
        expect(overdueNumber.hitTestable(), findsOneWidget);
        final overdueBounds = tester.getRect(overdueNumber);
        // Compare the laid-out texts after every parent scale, not source sizes.
        expect(overdueBounds.height, closeTo(normalBounds.height, .1));
        await _expectInlineDuration(tester, showTimeline: true);
        final details = tester.getRect(
          find.byKey(const ValueKey('countdown-details-scroll')),
        );
        _expectInside(overdueBounds, details);
        _expectInside(tester.getRect(find.byType(OverdueTimeline)), details);
        _expectInside(
          tester.getRect(find.byKey(const ValueKey('feed-control-dock'))),
          Offset.zero & size,
        );
        expect(feed.feedHistory.map((record) => record.id), ids);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('rotation cancels an unfinished slide and preserves saved undo', (
    tester,
  ) async {
    final feed = await _mountOverdue(
      tester,
      size: const Size(1024, 600),
      now: DateTime(2026, 10, 2, 23, 24, 20),
      overdue: const Duration(hours: 9, minutes: 21, seconds: 20),
      quiet: true,
      acknowledged: true,
    );
    final ids = feed.feedHistory.map((record) => record.id).toList();
    final slider = find.byType(FeedButton);
    final originalSliderState = tester.state(slider);
    final start = tester.getCenter(
      find.byKey(const ValueKey('feed-slide-thumb')),
    );
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.state(slider), same(originalSliderState));
    expect(feed.feedHistory.map((record) => record.id), ids);
    expect(find.text('已记录'), findsNothing);

    tester.view.physicalSize = const Size(640, 320);
    await tester.pumpAndSettle();
    await _expectOneReadingAxis(tester, '本次提醒已停止');
    final thumb = tester.getCenter(
      find.byKey(const ValueKey('feed-slide-thumb')),
    );
    final track = tester.getRect(
      find.byKey(const ValueKey('feed-slide-track')),
    );
    await tester.dragFrom(thumb, Offset(track.right - 4 - thumb.dx, 0));
    await tester.pumpAndSettle();
    expect(feed.feedHistory, hasLength(2));
    expect(find.text('超时'), findsNothing);
    expect(find.text('已记录'), findsOneWidget);
    for (final size in [const Size(390, 844), const Size(1024, 600)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.state(slider), same(originalSliderState));
      expect(
        find.byKey(const ValueKey('feed-slide-undo')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('feed-slide-undo')));
    await tester.pumpAndSettle();
    expect(feed.feedHistory.map((record) => record.id), ids);
    expect(find.text('超时').hitTestable(), findsOneWidget);
    await _expectOneReadingAxis(tester, '本次提醒已停止', showTimeline: true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
