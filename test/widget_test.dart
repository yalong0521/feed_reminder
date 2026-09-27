import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/home_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:feed_reminder/widgets/app_glass.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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

class _FailFirstAcknowledgementStorage extends StorageService {
  int acknowledgementAttempts = 0;

  @override
  Future<void> setAcknowledgedFeedTime(DateTime? time) async {
    acknowledgementAttempts++;
    if (acknowledgementAttempts == 1) {
      throw StateError('Simulated acknowledgement write failure');
    }
    await super.setAcknowledgedFeedTime(time);
  }
}

class _DelayedFailFirstFeedStorage extends StorageService {
  final firstWrite = Completer<void>();
  int attempts = 0;

  @override
  Future<void> setFeedHistory(List<FeedRecord> records) async {
    attempts++;
    if (attempts == 1) {
      await firstWrite.future;
      throw StateError('Simulated feed write failure');
    }
    await super.setFeedHistory(records);
  }
}

class _FailFirstUndoStorage extends StorageService {
  int undoAttempts = 0;
  bool failNextUndo = true;

  @override
  Future<void> setFeedHistory(List<FeedRecord> records) async {
    if (records.isEmpty) {
      undoAttempts++;
      if (failNextUndo) {
        failNextUndo = false;
        throw StateError('Simulated undo write failure');
      }
    }
    await super.setFeedHistory(records);
  }
}

void _expectNoMaterialInteractions() {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is InkResponse ||
          widget is ButtonStyleButton ||
          widget is MaterialButton ||
          widget is IconButton ||
          widget is FloatingActionButton ||
          widget is ChoiceChip ||
          widget is ActionChip ||
          widget is FilterChip ||
          widget is Switch ||
          widget is TextField ||
          widget is SnackBar,
      description: 'Material controls, ripple interactions, or Snackbar',
    ),
    findsNothing,
  );
}

Color _solidGlassColor(WidgetTester tester, Finder surface) => tester
    .widget<Material>(
      find.descendant(of: surface, matching: find.byType(Material)).first,
    )
    .color!;

Future<void> _slideToRecord(WidgetTester tester) async {
  final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
  await tester.ensureVisible(thumb);
  final start = tester.getCenter(thumb);
  final track = tester.getRect(find.byKey(const ValueKey('feed-slide-track')));
  await tester.dragFrom(start, Offset(track.right - 4 - start.dx, 0));
}

Future<({FeedProvider feed, SettingsProvider settings})> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool seeded = false,
  List<FeedRecord>? seededRecords,
  bool burnInProtection = false,
  Brightness brightness = Brightness.light,
  FakeViewPadding padding = FakeViewPadding.zero,
  StorageService? storageOverride,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.view.viewInsets = FakeViewPadding.zero;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  SharedPreferences.setMockInitialValues({
    'burnInProtectionEnabled': burnInProtection,
    if (seeded || seededRecords != null)
      'feedHistory': jsonEncode(
        (seededRecords ??
                [
                  FeedRecord(
                    time: DateTime.now().subtract(const Duration(minutes: 50)),
                  ),
                  FeedRecord(
                    time: DateTime.now().subtract(const Duration(hours: 4)),
                  ),
                ])
            .map((record) => record.toJson())
            .toList(),
      ),
  });
  final storage = storageOverride ?? StorageService();
  final audio = _Audio();
  final notifications = _Notifications();
  final feed = FeedProvider(
    storage: storage,
    audioService: audio,
    notificationService: notifications,
    startTimer: false,
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
  return (feed: feed, settings: settings);
}

void main() {
  testWidgets(
    'recording requires a completed right swipe from the thumb and stays inline',
    (tester) async {
      final app = await _mount(tester, size: const Size(844, 390));
      final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
      final track = find.byKey(const ValueKey('feed-slide-track'));
      final start = tester.getCenter(thumb);
      final bounds = tester.getRect(track);

      await tester.tap(track);
      await tester.tap(thumb);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);
      await tester.dragFrom(start, Offset(bounds.width * .35, 0));
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);
      expect(tester.getCenter(thumb).dx, closeTo(start.dx, 1));
      await tester.dragFrom(start, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);
      await tester.dragFrom(
        bounds.center,
        Offset(bounds.right - 4 - bounds.center.dx, 0),
      );
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);

      final cancelled = await tester.startGesture(tester.getCenter(thumb));
      await cancelled.moveBy(const Offset(24, 0));
      await cancelled.moveTo(Offset(bounds.right - 4, bounds.center.dy));
      await tester.pump();
      expect(find.text('松开确认'), findsOneWidget);
      expect(
        app.feed.feedHistory,
        isEmpty,
        reason: 'Crossing the end alone does not confirm before release.',
      );
      // On Flutter 3.47 an accepted drag can dispatch onEnd for a raw pointer
      // cancellation. The application must still distinguish it from release.
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);
      expect(tester.getCenter(thumb).dx, closeTo(start.dx, 1));

      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(1));
      expect(find.text('已记录'), findsOneWidget);
      expect(
        find
            .descendant(
              of: find.byType(FeedButton),
              matching: find.byKey(const ValueKey('feed-slide-undo')),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(thumb.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-slide-undo')), findsNothing);
      expect(app.feed.feedHistory, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'one pointer move across the track confirms exactly once on release',
    (tester) async {
      final app = await _mount(tester, size: const Size(844, 390));
      final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
      final track = tester.getRect(
        find.byKey(const ValueKey('feed-slide-track')),
      );
      final swipe = await tester.startGesture(tester.getCenter(thumb));
      // Unlike WidgetTester.dragFrom, send exactly one move. Losing the first
      // accepted drag delta would make this otherwise complete swipe a no-op.
      await swipe.moveTo(Offset(track.right - 4, track.center.dy));
      await tester.pump();
      expect(find.text('松开确认'), findsOneWidget);
      expect(app.feed.feedHistory, isEmpty);
      await swipe.up();
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(1));
      expect(find.text('已记录'), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-slide-undo')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'inline undo removes the newly inserted record after the system clock moves backwards',
    (tester) async {
      final now = DateTime.now();
      final originalRecords = [
        FeedRecord(
          id: 'saved-before-clock-correction',
          time: now.add(const Duration(hours: 1)),
        ),
        FeedRecord(
          id: 'older-feeding',
          time: now.subtract(const Duration(hours: 2)),
        ),
      ];
      final app = await _mount(tester, seededRecords: originalRecords);
      final originalIds = originalRecords.map((record) => record.id).toList();
      final deadline = app.feed.nextFeedTime;
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(3));
      expect(app.feed.feedHistory.first.id, originalRecords.first.id);
      final insertedId = app.feed.feedHistory
          .singleWhere((record) => !originalIds.contains(record.id))
          .id;

      await tester.tap(find.byKey(const ValueKey('feed-slide-undo')));
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory.map((record) => record.id), originalIds);
      expect(
        app.feed.feedHistory.map((record) => record.id),
        isNot(contains(insertedId)),
      );
      expect(
        (await StorageService().getFeedHistory()).map((record) => record.id),
        originalIds,
      );
      expect(app.feed.nextFeedTime, deadline);
      expect(
        find.byKey(const ValueKey('feed-slide-thumb')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed inline undo can retry within its window and expiry restores recording',
    (tester) async {
      final storage = _FailFirstUndoStorage();
      final app = await _mount(tester, storageOverride: storage);
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(1));
      final recordedId = app.feed.feedHistory.single.id;
      final deadline = app.feed.nextFeedTime;
      final undo = find.byKey(const ValueKey('feed-slide-undo'));
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(storage.undoAttempts, 1);
      expect(find.text('撤销失败'), findsOneWidget);
      expect(app.feed.feedHistory.single.id, recordedId);
      expect((await storage.getFeedHistory()).single.id, recordedId);
      expect(app.feed.nextFeedTime, deadline);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(CupertinoAlertDialog), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(undo.hitTestable(), findsOneWidget);
      expect(find.text('撤销失败'), findsOneWidget);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(storage.undoAttempts, 2);
      expect(app.feed.feedHistory, isEmpty);
      expect(await storage.getFeedHistory(), isEmpty);
      expect(app.feed.lastFeedTime, isNull);
      expect(app.feed.nextFeedTime, isNull);
      expect(
        find.byKey(const ValueKey('feed-slide-thumb')).hitTestable(),
        findsOneWidget,
      );
      expect(undo, findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      final retainedId = app.feed.feedHistory.single.id;
      final retainedDeadline = app.feed.nextFeedTime;
      storage.failNextUndo = true;
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(storage.undoAttempts, 3);
      expect(find.text('撤销失败'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(undo, findsNothing);
      expect(app.feed.feedHistory.single.id, retainedId);
      expect((await storage.getFeedHistory()).single.id, retainedId);
      expect(app.feed.nextFeedTime, retainedDeadline);
      expect(
        find.byKey(const ValueKey('feed-slide-thumb')).hitTestable(),
        findsOneWidget,
      );
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(2));
      expect(
        app.feed.feedHistory.map((record) => record.id),
        contains(retainedId),
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'resizing during a partial swipe never turns it into a recorded feeding',
    (tester) async {
      final app = await _mount(tester, size: const Size(844, 390));
      final thumb = find.byKey(const ValueKey('feed-slide-thumb'));
      final track = tester.getRect(
        find.byKey(const ValueKey('feed-slide-track')),
      );
      final start = tester.getCenter(thumb);
      final swipe = await tester.startGesture(start);
      await swipe.moveBy(const Offset(24, 0));
      await swipe.moveBy(Offset(track.width * .55 - 24, 0));
      await tester.pump();
      expect(tester.getCenter(thumb).dx, greaterThan(start.dx));
      expect(app.feed.feedHistory, isEmpty);
      tester.view.physicalSize = const Size(640, 320);
      await tester.pumpAndSettle();
      await swipe.up();
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);
      expect(tester.takeException(), isNull);
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'accessible slider adjusts in steps without exposing a tap-to-record action',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final app = await _mount(tester, size: const Size(844, 390));
        final slider = find.bySemanticsLabel('滑动记录这次喂奶');
        Future<void> adjust(ui.SemanticsAction action) async {
          final node = tester.getSemantics(slider);
          tester
              .renderObject(slider)
              .owner!
              .semanticsOwner!
              .performAction(node.id, action);
          await tester.pumpAndSettle();
        }

        final initial = tester.getSemantics(slider).getSemanticsData();
        expect(initial.flagsCollection.isSlider, isTrue);
        expect(initial.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(initial.value, '0%');
        await adjust(ui.SemanticsAction.increase);
        expect(tester.getSemantics(slider).getSemanticsData().value, '25%');
        expect(app.feed.feedHistory, isEmpty);
        await adjust(ui.SemanticsAction.decrease);
        expect(tester.getSemantics(slider).getSemanticsData().value, '0%');
        for (final expectedProgress in ['25%', '50%', '75%']) {
          await adjust(ui.SemanticsAction.increase);
          expect(
            tester.getSemantics(slider).getSemanticsData().value,
            expectedProgress,
          );
          expect(app.feed.feedHistory, isEmpty);
        }
        await adjust(ui.SemanticsAction.increase);
        expect(app.feed.feedHistory, hasLength(1));
        expect(find.byKey(const ValueKey('feed-slide-undo')), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'glass controls respond to press and keyboard without activating when disabled',
    (tester) async {
      var activations = 0;
      var enabled = true;
      var reduceMotion = false;
      late StateSetter updateControls;
      const buttonKey = ValueKey('interaction-test-button');
      const contentKey = ValueKey('interaction-test-content');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  updateControls = setState;
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(disableAnimations: reduceMotion),
                    child: AppButton(
                      key: buttonKey,
                      filled: true,
                      onPressed: enabled ? () => activations++ : null,
                      child: const SizedBox(
                        key: contentKey,
                        width: 120,
                        height: 32,
                        child: Center(child: Text('查看设置')),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final button = find.byKey(buttonKey);
      final content = find.byKey(contentKey);
      final restingWidth = tester.getRect(content).width;
      final cancelledPress = await tester.startGesture(
        tester.getCenter(button),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(content).width, lessThan(restingWidth));
      expect(activations, 0);
      _expectNoMaterialInteractions();
      await cancelledPress.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(content).width, closeTo(restingWidth, .01));
      expect(activations, 0);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(activations, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activations, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(activations, 3);

      updateControls(() => enabled = false);
      await tester.pumpAndSettle();
      await tester.tap(button, warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(activations, 3);

      updateControls(() {
        enabled = true;
        reduceMotion = true;
      });
      await tester.pumpAndSettle();
      final reducedPress = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(content).width, closeTo(restingWidth, .01));
      await reducedPress.up();
      await tester.pumpAndSettle();
      expect(activations, 4);
      _expectNoMaterialInteractions();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'recording stays disabled during storage work and a failed save retries only once',
    (tester) async {
      final storage = _DelayedFailFirstFeedStorage();
      final app = await _mount(tester, storageOverride: storage);
      final button = find.byType(FeedButton);
      final start = tester.getCenter(
        find.byKey(const ValueKey('feed-slide-thumb')),
      );
      final track = tester.getRect(
        find.byKey(const ValueKey('feed-slide-track')),
      );
      final distance = Offset(track.right - 4 - start.dx, 0);
      await _slideToRecord(tester);
      await tester.pump();
      expect(storage.attempts, 1);
      expect(app.feed.isSaving, isTrue);
      expect(app.feed.feedHistory, isEmpty);

      // Rebuilding the optical decoration must not recreate an in-flight
      // button or enable a second write while its first action is pending.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(button, warnIfMissed: false);
      await tester.dragFrom(start, distance);
      await tester.dragFrom(start, distance);
      await tester.pump();
      expect(storage.attempts, 1);
      expect(app.feed.feedHistory, isEmpty);
      storage.firstWrite.complete();
      await tester.pumpAndSettle();
      expect(find.text('未保存，右滑重试'), findsOneWidget);
      expect(app.feed.isSaving, isFalse);
      expect(app.feed.feedHistory, isEmpty);
      _expectNoMaterialInteractions();

      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(storage.attempts, 2);
      expect(app.feed.feedHistory, hasLength(1));
      expect(await storage.getFeedHistory(), hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'every app flow uses Cupertino or glass actions without Material ripples',
    (tester) async {
      final app = await _mount(tester, seeded: true);
      _expectNoMaterialInteractions();
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      _expectNoMaterialInteractions();
      await tester.tap(find.byKey(const ValueKey('feed-slide-undo')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(app.feed.feedHistory, hasLength(2));

      await tester.ensureVisible(find.byKey(const ValueKey('backfill-feed')));
      await tester.tap(find.byKey(const ValueKey('backfill-feed')));
      await tester.pumpAndSettle();
      _expectNoMaterialInteractions();
      for (final field in ['add-feed-date-field', 'add-feed-time-field']) {
        await tester.ensureVisible(find.byKey(ValueKey(field)));
        await tester.tap(find.byKey(ValueKey(field)));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoDatePicker), findsOneWidget);
        _expectNoMaterialInteractions();
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('add-feed-cancel')));
      await tester.tap(find.byKey(const ValueKey('add-feed-cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      _expectNoMaterialInteractions();
      final delete = find.byKey(
        ValueKey('delete-record-${app.feed.feedHistory.first.id}'),
      );
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      _expectNoMaterialInteractions();
      await tester.tap(find.byKey(const ValueKey('cancel-delete-record')));
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(2));

      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      _expectNoMaterialInteractions();
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-interval-button')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-interval-button')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoTextField), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField), '75');
      _expectNoMaterialInteractions();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(app.settings.feedIntervalMinutes, 75);
      await app.settings.setNightModeEnabled(true);
      await tester.pumpAndSettle();
      final nightStart = find.byKey(const ValueKey('night-start-time'));
      await tester.ensureVisible(nightStart);
      await tester.tap(nightStart);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      _expectNoMaterialInteractions();
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unavailable glass shaders keep an opaque, accessible recording action',
    (tester) async {
      // Unit tests deliberately omit shader startup. This exercises the same
      // decoration fallback used if shader initialization fails on a device.
      expect(AppGlass.isReady, isFalse);
      final semantics = tester.ensureSemantics();
      try {
        final app = await _mount(tester, size: const Size(640, 320));
        final dock = find.byKey(const ValueKey('feed-control-dock'));
        expect(dock, findsOneWidget);
        expect(find.byType(GlassContainer), findsNothing);
        final surface = tester.widget<Material>(
          find.descendant(of: dock, matching: find.byType(Material)).first,
        );
        expect(surface.color, AppPalette.light.surface);
        expect(surface.color!.a, 1);
        final data = tester
            .getSemantics(find.bySemanticsLabel('滑动记录这次喂奶'))
            .getSemanticsData();
        expect(data.flagsCollection.isSlider, isTrue);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(data.hasAction(ui.SemanticsAction.increase), isTrue);
        expect(data.value, '0%');
        expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
        await _slideToRecord(tester);
        await tester.pumpAndSettle();
        expect(app.feed.feedHistory, hasLength(1));
        expect(app.feed.nextFeedTime, isNotNull);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'high contrast removes decorative imagery and keeps dark and light glass controls usable',
    (tester) async {
      final app = await _mount(
        tester,
        size: const Size(740, 360),
        seeded: true,
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      for (final brightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final dock = find.byKey(const ValueKey('feed-control-dock'));
        expect(MediaQuery.highContrastOf(tester.element(dock)), isTrue);
        expect(find.byType(GlassContainer), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AppGlassBackdrop),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        for (final element in find.byType(AppGlassSurface).evaluate()) {
          final glass = element.widget as AppGlassSurface;
          final palette = AppPalette.of(element);
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: find.byWidget(glass),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(
            material.color,
            glass.tinted ? palette.primary : palette.surface,
          );
          expect(material.color!.a, 1);
        }
        expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
        expect(
          find.byKey(const ValueKey('backfill-feed')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      expect(find.text('喂奶记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'record a feeding, undo, and navigate without losing current state',
    (tester) async {
      final app = await _mount(tester);
      expect(find.text('等待第一条记录'), findsOneWidget);
      await _slideToRecord(tester);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(1));
      expect(app.feed.nextFeedTime, isNotNull);
      await tester.tap(find.byKey(const ValueKey('feed-slide-undo')));
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, isEmpty);
      expect(app.feed.lastFeedTime, isNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      expect(find.text('喂奶记录'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      expect(find.text('提醒偏好'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('settings update the live countdown without another feeding', (
    tester,
  ) async {
    final app = await _mount(tester, seeded: true);
    final last = app.feed.lastFeedTime;
    await app.settings.setFeedInterval(120);
    await tester.pumpAndSettle();
    expect(app.feed.feedIntervalMinutes, 120);
    expect(app.feed.nextFeedTime, last!.add(const Duration(minutes: 120)));
    expect(app.feed.feedHistory, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(640, 320),
    const Size(740, 360),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'landscape $size at scale $scale keeps navigation, countdown and record action visible',
        (tester) async {
          final app = await _mount(
            tester,
            size: size,
            scale: scale,
            seeded: true,
          );
          expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
          expect(find.byKey(const ValueKey('landscape-home')), findsOneWidget);

          for (final target in [
            find.byKey(const ValueKey('landscape-countdown')),
            find.byType(FeedButton),
          ]) {
            expect(target, findsOneWidget);
            final bounds = tester.getRect(target);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.top, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(bounds.bottom, lessThanOrEqualTo(size.height));
          }
          expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
          await _slideToRecord(tester);
          await tester.pumpAndSettle();
          expect(app.feed.feedHistory, hasLength(3));

          for (final tab in ['nav-history', 'nav-settings', 'nav-home']) {
            final tapTarget = find.byKey(ValueKey(tab));
            final targetSize = tester.getSize(tapTarget);
            expect(targetSize.width, greaterThanOrEqualTo(48));
            expect(targetSize.height, greaterThanOrEqualTo(48));
            expect(
              tapTarget.hitTestable(),
              findsOneWidget,
              reason: '$tab at ${tester.getRect(tapTarget)}',
            );
            await tester.tap(tapTarget);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'rotation preserves selected page, current cycle and home state',
    (tester) async {
      final app = await _mount(tester, seeded: true);
      final home = find.byType(HomeScreen, skipOffstage: false);
      final originalHomeState = tester.state(home);
      final latestRecord = app.feed.feedHistory.first.id;
      final deadline = app.feed.nextFeedTime;

      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(740, 360);
      await tester.pumpAndSettle();
      expect(find.text('喂奶记录'), findsOneWidget);
      expect(tester.state(home), same(originalHomeState));
      expect(app.feed.feedHistory.first.id, latestRecord);
      expect(app.feed.nextFeedTime, deadline);

      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.text('提醒偏好'), findsOneWidget);
      expect(tester.state(home), same(originalHomeState));
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(2));
      expect(app.feed.nextFeedTime, deadline);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'standby consumes a held activation key before restoring the focused record action',
    (tester) async {
      final app = await _mount(
        tester,
        size: const Size(740, 360),
        seeded: true,
        burnInProtection: true,
      );
      final home = find.byType(HomeScreen);
      final originalHomeState = tester.state(home);
      final record = find.byType(FeedButton);
      final originalIds = app.feed.feedHistory
          .map((record) => record.id)
          .toList();
      final deadline = app.feed.nextFeedTime;
      final standby = find.byKey(const ValueKey('standby-screen'));

      bool recordHasKeyboardFocus() {
        final target = tester.element(record);
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext == null) return false;
        if (identical(focusContext, target)) return true;
        var withinRecord = false;
        focusContext.visitAncestorElements((ancestor) {
          if (identical(ancestor, target)) {
            withinRecord = true;
            return false;
          }
          return true;
        });
        return withinRecord;
      }

      Future<void> tabToRecord() async {
        for (
          var attempt = 0;
          attempt < 20 && !recordHasKeyboardFocus();
          attempt++
        ) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(
          recordHasKeyboardFocus(),
          isTrue,
          reason: 'The record action remains reachable by keyboard.',
        );
      }

      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        await tabToRecord();
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
        expect(standby, findsOneWidget);
        expect(recordHasKeyboardFocus(), isFalse);

        await tester.sendKeyDownEvent(key);
        await tester.pumpAndSettle();
        expect(standby, findsNothing);
        expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
        await tester.sendKeyRepeatEvent(key);
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
        expect(app.feed.feedHistory.map((record) => record.id), originalIds);
        expect(app.feed.nextFeedTime, deadline);
        expect(tester.state(home), same(originalHomeState));
        expect(tester.takeException(), isNull);
      }

      // A lone activation key must never record, including after waking.
      await tabToRecord();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(2));
      for (var step = 0; step < 4; step++) {
        if (step == 0) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        }
        await tester.pumpAndSettle();
        if (step < 3) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        }
        expect(app.feed.feedHistory, hasLength(2));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.feed.feedHistory, hasLength(3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'idle display hides navigation and wakes without recording a feed',
    (tester) async {
      final app = await _mount(
        tester,
        size: const Size(740, 360),
        seeded: true,
        burnInProtection: true,
      );
      final home = find.byType(HomeScreen);
      final originalHomeState = tester.state(home);
      final deadline = app.feed.nextFeedTime;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('app-navigation')), findsNothing);
      expect(tester.state(home), same(originalHomeState));

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-navigation')), findsNothing);
      expect(tester.state(home), same(originalHomeState));
      await tester.tap(find.byKey(const ValueKey('standby-screen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsNothing);
      expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
      expect(tester.state(home), same(originalHomeState));
      expect(app.feed.nextFeedTime, deadline);
      expect(app.feed.feedHistory, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'feeding alert immediately restores navigation and focus from standby',
    (tester) async {
      final app = await _mount(
        tester,
        size: const Size(740, 360),
        seeded: true,
        burnInProtection: true,
      );
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('app-navigation')), findsNothing);
      await app.settings.setFeedInterval(1);
      await tester.pumpAndSettle();
      expect(app.feed.state, FeedState.alerting);
      expect(find.byKey(const ValueKey('standby-screen')), findsNothing);
      expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
      expect(find.text('停止本次提醒').hitTestable(), findsOneWidget);
      final homeFocus = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(ExcludeFocus),
      );
      expect(tester.widget<ExcludeFocus>(homeFocus).excluding, isFalse);
      expect(app.feed.feedHistory, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disabling standby restores the visible controls without an idle tick',
    (tester) async {
      final app = await _mount(tester, seeded: true, burnInProtection: true);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsOneWidget);
      await app.settings.setBurnInProtectionEnabled(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsNothing);
      expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
      final homeFocus = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(ExcludeFocus),
      );
      expect(tester.widget<ExcludeFocus>(homeFocus).excluding, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'standby covers system insets in dark color and survives system theme changes',
    (tester) async {
      final app = await _mount(
        tester,
        size: const Size(740, 360),
        seeded: true,
        burnInProtection: true,
        padding: const FakeViewPadding(left: 24, right: 24, bottom: 16),
      );
      final home = find.byType(HomeScreen);
      final originalHomeState = tester.state(home);
      final deadline = app.feed.nextFeedTime;
      final standby = find.byKey(const ValueKey('standby-screen'));
      final outerScaffold = find.byType(Scaffold).first;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      for (final brightness in [
        Brightness.light,
        Brightness.dark,
        Brightness.light,
      ]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(home)).brightness, brightness);
        expect(standby, findsOneWidget);
        expect(find.byKey(const ValueKey('app-navigation')), findsNothing);
        // SafeArea sits inside this full-screen Scaffold, so this background
        // also paints the system-inset strips around the standby clock.
        expect(
          tester.widget<Scaffold>(outerScaffold).backgroundColor,
          AppPalette.dark.background,
        );
        expect(
          tester.getRect(outerScaffold),
          const Rect.fromLTWH(0, 0, 740, 360),
        );
        expect(tester.state(home), same(originalHomeState));
        expect(app.feed.nextFeedTime, deadline);
        expect(app.feed.feedHistory, hasLength(2));
        expect(tester.takeException(), isNull);
      }

      await tester.tap(standby);
      await tester.pumpAndSettle();
      expect(standby, findsNothing);
      expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
      expect(
        tester.widget<Scaffold>(outerScaffold).backgroundColor,
        AppPalette.light.background,
      );
      expect(tester.state(home), same(originalHomeState));
      expect(app.feed.nextFeedTime, deadline);
      expect(app.feed.feedHistory, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'approaching feeding time remains visible after a dark theme change and rotation',
    (tester) async {
      final app = await _mount(tester, seeded: true);
      final home = find.byType(HomeScreen);
      final originalHomeState = tester.state(home);
      final lastFeed = app.feed.lastFeedTime;
      expect(app.feed.state, FeedState.normal);
      expect(find.text('快到喂奶时间'), findsNothing);

      await app.settings.setFeedInterval(60);
      await tester.pumpAndSettle();
      expect(app.feed.state, FeedState.warning);
      expect(find.text('快到喂奶时间'), findsOneWidget);
      expect(app.feed.nextFeedTime, lastFeed!.add(const Duration(hours: 1)));

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(home)).brightness, Brightness.dark);
      expect(find.text('快到喂奶时间'), findsOneWidget);
      tester.view.physicalSize = const Size(740, 360);
      await tester.pumpAndSettle();
      expect(find.text('快到喂奶时间').hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('landscape-countdown')), findsOneWidget);
      expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
      expect(tester.state(home), same(originalHomeState));
      expect(app.feed.state, FeedState.warning);
      expect(app.feed.feedHistory, hasLength(2));

      await app.settings.setFeedInterval(180);
      await tester.pumpAndSettle();
      expect(app.feed.state, FeedState.normal);
      expect(find.text('快到喂奶时间'), findsNothing);
      expect(app.feed.nextFeedTime, lastFeed.add(const Duration(hours: 3)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('compact landscape respects system insets with large text', (
    tester,
  ) async {
    const size = Size(640, 320);
    const padding = FakeViewPadding(left: 24, right: 24, bottom: 16);
    await _mount(
      tester,
      size: size,
      scale: 1.8,
      seeded: true,
      padding: padding,
    );
    for (final target in [
      find.byKey(const ValueKey('landscape-countdown')),
      find.byType(FeedButton),
    ]) {
      final bounds = tester.getRect(target);
      expect(bounds.left, greaterThanOrEqualTo(padding.left));
      expect(bounds.top, greaterThanOrEqualTo(padding.top));
      expect(bounds.right, lessThanOrEqualTo(size.width - padding.right));
      expect(bounds.bottom, lessThanOrEqualTo(size.height - padding.bottom));
    }
    expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
    for (final tab in ['nav-history', 'nav-settings', 'nav-home']) {
      await tester.tap(find.byKey(ValueKey(tab)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(640, 320), const Size(740, 360)]) {
    for (final keyboardHeight in [180.0, 200.0]) {
      testWidgets(
        'alert landscape $size handles a $keyboardHeight keyboard in backfill and settings',
        (tester) async {
          final app = await _mount(tester, size: size, seeded: true);
          await app.settings.setFeedInterval(1);
          await tester.pumpAndSettle();
          expect(app.feed.state, FeedState.alerting);

          await tester.tap(find.byKey(const ValueKey('backfill-feed')));
          await tester.pumpAndSettle();
          expect(find.byType(AddFeedRecordDialog), findsOneWidget);
          tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('add-feed-cancel')),
          );
          await tester.tap(find.byKey(const ValueKey('add-feed-cancel')));
          await tester.pumpAndSettle();
          expect(find.byType(AddFeedRecordDialog), findsNothing);
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const ValueKey('nav-settings')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('自定义'));
          await tester.tap(find.text('自定义'));
          await tester.pumpAndSettle();
          expect(find.text('自定义喂奶间隔'), findsOneWidget);
          await tester.enterText(find.byType(CupertinoTextField), '15');
          tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
          await tester.pumpAndSettle();
          // IndexedStack still lays out the alerting Home while Settings is
          // visible, so keyboard insets must also fit its hidden landscape UI.
          expect(
            find.byKey(const ValueKey('landscape-home'), skipOffstage: false),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('取消'));
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.text('自定义喂奶间隔'), findsNothing);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(app.settings.feedIntervalMinutes, 1);
          expect(app.feed.feedHistory, hasLength(2));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'acknowledged alert remains actionable after a persistence failure',
    (tester) async {
      final storage = _FailFirstAcknowledgementStorage();
      final app = await _mount(
        tester,
        size: const Size(740, 360),
        seeded: true,
        storageOverride: storage,
      );
      await app.settings.setFeedInterval(1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止本次提醒'));
      await tester.pumpAndSettle();
      expect(app.feed.isAlertAcknowledged, isTrue);
      expect(storage.acknowledgementAttempts, 1);
      expect(find.byKey(const ValueKey('app-notice-dialog')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('app-notice-close')));
      await tester.pumpAndSettle();
      final retry = find.widgetWithText(AppButton, '本次提醒已停止');
      expect(tester.widget<AppButton>(retry).onPressed, isNotNull);
      expect(retry.hitTestable(), findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(storage.acknowledgementAttempts, 2);
      expect(await storage.getAcknowledgedFeedTime(), app.feed.lastFeedTime);
      expect(app.feed.feedHistory, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'appearance choices override system brightness and persist without changing the feeding cycle',
    (tester) async {
      final app = await _mount(tester, seeded: true);
      await app.settings.updateSettings(
        nightModeEnabled: true,
        nightStartTime: '22:15',
        nightEndTime: '05:45',
      );
      await tester.pumpAndSettle();
      final home = find.byType(HomeScreen, skipOffstage: false);
      final originalHomeState = tester.state(home);
      final recordIds = app.feed.feedHistory
          .map((record) => record.id)
          .toList();
      final deadline = app.feed.nextFeedTime;
      final feedState = app.feed.state;
      expect(app.settings.themeMode, ThemeMode.system);
      expect(Theme.of(tester.element(home)).brightness, Brightness.light);
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();

      void expectCurrentState(Brightness brightness) {
        expect(Theme.of(tester.element(home)).brightness, brightness);
        expect(find.text('提醒偏好'), findsOneWidget);
        expect(tester.state(home), same(originalHomeState));
        expect(app.feed.feedHistory.map((record) => record.id), recordIds);
        expect(app.feed.nextFeedTime, deadline);
        expect(app.feed.state, feedState);
        expect(app.settings.nightModeEnabled, isTrue);
        expect(app.settings.nightStartTime, '22:15');
        expect(app.settings.nightEndTime, '05:45');
        expect(tester.takeException(), isNull);
      }

      Future<void> chooseMode(ThemeMode mode, Brightness brightness) async {
        final chip = find.byKey(ValueKey('theme-mode-${mode.name}'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: chip,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.selected == true,
            ),
          ),
          findsWidgets,
        );
        expect(app.settings.themeMode, mode);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          mode,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(StorageKeys.themeMode), mode.name);
        // A fresh provider reads the stored selection, independent of the
        // current page's in-memory state or the system's brightness.
        final restored = SettingsProvider(storage: StorageService());
        await restored.ready;
        expect(restored.themeMode, mode);
        expect(restored.nightModeEnabled, isTrue);
        expect(restored.nightStartTime, '22:15');
        expect(restored.nightEndTime, '05:45');
        restored.dispose();
        expectCurrentState(brightness);
      }

      await chooseMode(ThemeMode.dark, Brightness.dark);
      for (final systemBrightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue =
            systemBrightness;
        await tester.pumpAndSettle();
        expectCurrentState(Brightness.dark);
      }

      await chooseMode(ThemeMode.light, Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expectCurrentState(Brightness.light);

      await chooseMode(ThemeMode.system, Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expectCurrentState(Brightness.light);
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(tester.state(home), same(originalHomeState));
      expect(app.feed.feedHistory.map((record) => record.id), recordIds);
      expect(app.feed.nextFeedTime, deadline);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'system theme changes recolor pages and open pickers without changing feeding or quiet hours',
    (tester) async {
      final app = await _mount(tester, seeded: true);
      await app.settings.updateSettings(
        nightModeEnabled: true,
        nightStartTime: '22:15',
        nightEndTime: '05:45',
      );
      await tester.pumpAndSettle();
      final home = find.byType(HomeScreen, skipOffstage: false);
      final originalHomeState = tester.state(home);
      final records = app.feed.feedHistory.map((record) => record.id).toList();
      final deadline = app.feed.nextFeedTime;
      final feedState = app.feed.state;

      void expectUnchangedData() {
        expect(tester.state(home), same(originalHomeState));
        expect(app.feed.feedHistory.map((record) => record.id), records);
        expect(app.feed.nextFeedTime, deadline);
        expect(app.feed.state, feedState);
        expect(app.settings.nightModeEnabled, isTrue);
        expect(app.settings.nightStartTime, '22:15');
        expect(app.settings.nightEndTime, '05:45');
      }

      Future<void> setSystemBrightness(Brightness brightness) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final context = tester.element(home);
        final theme = Theme.of(context);
        final palette = AppPalette.of(context);
        expect(theme.brightness, brightness);
        expect(theme.scaffoldBackgroundColor, palette.background);
        expect(
          palette.background,
          brightness == Brightness.dark
              ? AppPalette.dark.background
              : AppPalette.light.background,
        );
        expectUnchangedData();
        expect(tester.takeException(), isNull);
      }

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      await setSystemBrightness(Brightness.dark);
      await tester.ensureVisible(find.byKey(const ValueKey('backfill-feed')));
      await tester.tap(find.byKey(const ValueKey('backfill-feed')));
      await tester.pumpAndSettle();
      final backfill = find.byType(AddFeedRecordDialog);
      expect(backfill, findsOneWidget);
      expect(
        _solidGlassColor(
          tester,
          find.byKey(const ValueKey('add-feed-record-surface')),
        ),
        AppPalette.dark.surface,
      );

      await tester.tap(find.text('喂奶日期'));
      await tester.pumpAndSettle();
      final datePicker = find.byKey(const ValueKey('app-date-time-picker'));
      final datePickerContext = tester.element(datePicker);
      expect(
        tester.widget<CupertinoDatePicker>(datePicker).mode,
        CupertinoDatePickerMode.date,
      );
      expect(Theme.of(datePickerContext).brightness, Brightness.dark);
      expect(
        _solidGlassColor(
          tester,
          find
              .ancestor(of: datePicker, matching: find.byType(AppGlassSurface))
              .first,
        ),
        AppPalette.dark.surface,
      );
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('喂奶时间'));
      await tester.pumpAndSettle();
      final timePicker = find.byKey(const ValueKey('app-date-time-picker'));
      final timePickerContext = tester.element(timePicker);
      expect(
        tester.widget<CupertinoDatePicker>(timePicker).mode,
        CupertinoDatePickerMode.time,
      );
      expect(Theme.of(timePickerContext).brightness, Brightness.dark);
      expect(
        _solidGlassColor(
          tester,
          find
              .ancestor(of: timePicker, matching: find.byType(AppGlassSurface))
              .first,
        ),
        AppPalette.dark.surface,
      );
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      await setSystemBrightness(Brightness.light);
      expect(
        _solidGlassColor(
          tester,
          find.byKey(const ValueKey('add-feed-record-surface')),
        ),
        AppPalette.light.surface,
      );
      expect(
        tester.widget<Text>(find.text('添加喂奶记录')).style?.color,
        AppPalette.light.textPrimary,
      );
      await tester.tap(find.byKey(const ValueKey('add-feed-cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      await setSystemBrightness(Brightness.dark);
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpAndSettle();
      expect(find.text('喂奶记录'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('喂奶记录')).style?.color,
        AppPalette.dark.textPrimary,
      );
      expectUnchangedData();

      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await setSystemBrightness(Brightness.light);
      expect(find.text('提醒偏好'), findsOneWidget);
      await setSystemBrightness(Brightness.dark);
      expect(find.text('提醒偏好'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('提醒偏好')).style?.color,
        AppPalette.dark.textPrimary,
      );
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
      expectUnchangedData();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final viewport in [
    (size: const Size(320, 640), scale: 1.0, brightness: Brightness.light),
    (size: const Size(390, 844), scale: 1.8, brightness: Brightness.light),
    (size: const Size(844, 390), scale: 1.0, brightness: Brightness.light),
    (size: const Size(1280, 900), scale: 1.0, brightness: Brightness.light),
    (size: const Size(320, 568), scale: 1.0, brightness: Brightness.dark),
    (size: const Size(768, 1024), scale: 1.0, brightness: Brightness.dark),
    (size: const Size(1024, 768), scale: 1.0, brightness: Brightness.dark),
  ]) {
    testWidgets(
      'all pages fit ${viewport.size} at scale ${viewport.scale} in ${viewport.brightness}',
      (tester) async {
        final app = await _mount(
          tester,
          size: viewport.size,
          scale: viewport.scale,
          seeded: true,
          brightness: viewport.brightness,
        );
        expect(tester.takeException(), isNull);
        for (final tab in ['nav-history', 'nav-settings', 'nav-home']) {
          await tester.tap(find.byKey(ValueKey(tab)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        // Small portrait screens can scroll secondary content; the two recording
        // actions must remain reachable even at the largest supported text size.
        final backfill = find.byKey(const ValueKey('backfill-feed'));
        await tester.ensureVisible(backfill);
        expect(backfill.hitTestable(), findsOneWidget);
        await tester.tap(backfill);
        await tester.pumpAndSettle();
        expect(find.byType(AddFeedRecordDialog), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('add-feed-cancel')),
        );
        await tester.tap(find.byKey(const ValueKey('add-feed-cancel')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(FeedButton));
        expect(find.byType(FeedButton).hitTestable(), findsOneWidget);
        await _slideToRecord(tester);
        await tester.pumpAndSettle();
        expect(app.feed.feedHistory, hasLength(3));
        // Confirmation expires in place and restores the slider affordance.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('feed-slide-thumb')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
