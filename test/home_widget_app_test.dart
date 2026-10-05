import 'dart:async';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/models/home_widget_snapshot.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/home_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/home_widget_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Widgets extends HomeWidgetService {
  _Widgets() : super(supported: false);
  final snapshots = <HomeWidgetSnapshot>[];
  ValueChanged<String>? handler;
  String? pending;
  int reads = 0;
  @override
  bool get isSupported => true;
  @override
  void setActionHandler(ValueChanged<String>? value) => handler = value;
  @override
  Future<void> update(HomeWidgetSnapshot snapshot) async =>
      snapshots.add(snapshot);
  @override
  Future<String?> consumePendingAction() async {
    reads++;
    final value = pending;
    pending = null;
    return value;
  }

  void emit(String action) => handler?.call(action);
}

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
  Future<void> init() async {}
  @override
  Future<void> requestPermissions() async {}
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

class _Storage extends StorageService {
  Completer<void>? readGate;
  Completer<void>? saveGate;
  Completer<void>? acknowledgementGate;
  bool failAcknowledgement = false;
  int historyReads = 0;
  @override
  Future<List<FeedRecord>> getFeedHistory() async {
    historyReads++;
    await readGate?.future;
    return super.getFeedHistory();
  }

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    await saveGate?.future;
    return super.saveFeedState(records);
  }

  @override
  Future<void> setAcknowledgedFeedRecord(FeedRecord? record) async {
    await acknowledgementGate?.future;
    if (failAcknowledgement) throw StateError('acknowledgement save failed');
    return super.setAcknowledgedFeedRecord(record);
  }
}

class _Fixture {
  _Fixture(this.storage, this.widgets) {
    settings = SettingsProvider(storage: storage);
    feed = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      startTimer: false,
      clock: () => DateTime(2026, 10, 3, 12),
    );
  }
  final _Storage storage;
  final _Widgets widgets;
  final audio = _Audio();
  final notifications = _Notifications();
  late final FeedProvider feed;
  late final SettingsProvider settings;
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(
      FeedReminderApp(
        storage: storage,
        homeWidgetService: widgets,
        audioService: audio,
        notificationService: notifications,
        feedProvider: feed,
        settingsProvider: settings,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    feed.dispose();
    settings.dispose();
    widgets.dispose();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'acceptedPrivacyPolicyVersion': PrivacyPolicy.version,
      'defaultMilkAmountMl': 120,
    });
  });

  void screen(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  testWidgets('consent gate leaves launch request and records untouched', (
    tester,
  ) async {
    screen(tester);
    SharedPreferences.setMockInitialValues({'defaultMilkAmountMl': 120});
    final storage = _Storage();
    final widgets = _Widgets()..pending = 'record_feed';
    await tester.pumpWidget(
      FeedReminderApp(
        storage: storage,
        homeWidgetService: widgets,
        audioService: _Audio(),
        notificationService: _Notifications(),
      ),
    );
    await tester.pumpAndSettle();
    expect(storage.historyReads, 0);
    expect(widgets.reads, 0);
    expect(widgets.snapshots, isEmpty);
    expect(widgets.handler, isNull);
    expect(widgets.pending, 'record_feed');
    await tester.tap(find.byKey(const ValueKey('privacy-consent-accept')));
    await tester.pumpAndSettle();
    expect(find.byType(AddFeedRecordDialog), findsOneWidget);
    expect(widgets.pending, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    widgets.dispose();
  });

  testWidgets(
    'cold record action waits for loaded providers and reads configured milk',
    (tester) async {
      screen(tester);
      final gate = Completer<void>();
      final storage = _Storage()..readGate = gate;
      final widgets = _Widgets()..pending = 'record_feed';
      final fixture = _Fixture(storage, widgets);
      await fixture.mount(tester, settle: false);
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      expect(widgets.snapshots, isEmpty);
      expect(widgets.reads, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      expect(
        tester
            .widget<AddFeedRecordDialog>(find.byType(AddFeedRecordDialog))
            .defaultMilkAmountMl,
        120,
      );
      expect(fixture.feed.feedHistory, isEmpty);
      await tester.tap(find.byKey(const ValueKey('add-feed-save')));
      await tester.pumpAndSettle();
      expect(fixture.feed.feedHistory.single.milkAmountMl, 120);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'background launch waits for resume and repeated action has one confirmation',
    (tester) async {
      screen(tester);
      final widgets = _Widgets();
      final fixture = _Fixture(_Storage(), widgets);
      await fixture.mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      widgets.emit('record_feed');
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      widgets.emit('record_feed');
      widgets.emit('record_feed');
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-feed-cancel')));
      await tester.pumpAndSettle();
      expect(fixture.feed.feedHistory, isEmpty);
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets('open timer returns from a pushed page to the timer root', (
    tester,
  ) async {
    screen(tester);
    final widgets = _Widgets();
    final fixture = _Fixture(_Storage(), widgets);
    await fixture.mount(tester);
    final context = tester.element(find.byType(HomeScreen));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('widget-route-probe')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('widget-route-probe'), findsOneWidget);
    widgets.emit('open_timer');
    await tester.pumpAndSettle();
    expect(find.text('widget-route-probe'), findsNothing);
    expect(
      find.byKey(const ValueKey('nav-home')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('open timer preserves an unfinished popup', (tester) async {
    screen(tester);
    final widgets = _Widgets();
    final fixture = _Fixture(_Storage(), widgets);
    await fixture.mount(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(HomeScreen)),
        builder: (_) => const AlertDialog(content: Text('unfinished-input')),
      ),
    );
    await tester.pumpAndSettle();
    widgets.emit('open_timer');
    await tester.pumpAndSettle();
    expect(find.text('unfinished-input'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets('snapshot publishes after a successful feed write only', (
    tester,
  ) async {
    screen(tester);
    final widgets = _Widgets();
    final storage = _Storage();
    final fixture = _Fixture(storage, widgets);
    await fixture.mount(tester);
    final initial = widgets.snapshots.length;
    final gate = Completer<void>();
    storage.saveGate = gate;
    final saving = fixture.feed.addFeedRecordWithTime(
      DateTime(2026, 10, 3, 11),
      milkAmountMl: 90,
    );
    await tester.pump();
    expect(fixture.feed.isSaving, isTrue);
    expect(widgets.snapshots.length, initial);
    gate.complete();
    await saving;
    await tester.pumpAndSettle();
    expect(widgets.snapshots.last.dayTotalMl, 90);
    expect(widgets.snapshots.last.dayCount, 1);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets(
    'snapshot acknowledges a stopped reminder only after successful persistence',
    (tester) async {
      screen(tester);
      final storage = _Storage();
      await storage.saveFeedState([
        FeedRecord(time: DateTime(2026, 10, 3, 8), milkAmountMl: 120),
      ]);
      final widgets = _Widgets();
      final fixture = _Fixture(storage, widgets);
      await fixture.mount(tester);
      expect(widgets.snapshots.last.reminderAcknowledged, isFalse);

      final gate = Completer<void>();
      storage.acknowledgementGate = gate;
      storage.failAcknowledgement = true;
      final stopping = fixture.feed.stopAlert();
      final failed = expectLater(stopping, throwsStateError);
      await tester.pump();
      expect(fixture.feed.isAlertAcknowledged, isTrue);
      expect(
        widgets.snapshots.every((snapshot) => !snapshot.reminderAcknowledged),
        isTrue,
      );

      gate.complete();
      await failed;
      await tester.pumpAndSettle();
      expect(widgets.snapshots.last.reminderAcknowledged, isFalse);

      storage.acknowledgementGate = null;
      storage.failAcknowledgement = false;
      await fixture.feed.stopAlert();
      await tester.pumpAndSettle();
      expect(widgets.snapshots.last.reminderAcknowledged, isTrue);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'clock rollback snapshot keeps the timer current meal and deadline',
    (tester) async {
      screen(tester);
      final storage = _Storage();
      final future = FeedRecord(
        time: DateTime(2026, 10, 3, 13),
        milkAmountMl: 180,
      );
      await storage.saveFeedState([
        FeedRecord(time: DateTime(2026, 10, 3, 10), milkAmountMl: 90),
        future,
      ]);
      final widgets = _Widgets();
      final fixture = _Fixture(storage, widgets);
      await fixture.mount(tester);
      final value = widgets.snapshots.last;
      expect(
        value.latestTimeMs,
        fixture.feed.lastFeedTime!.millisecondsSinceEpoch,
      );
      expect(value.latestMilkAmountMl, 180);
      expect(
        value.nextFeedTimeMs,
        fixture.feed.nextFeedTime!.millisecondsSinceEpoch,
      );
      expect(value.dayTotalMl, 90);
      expect(value.dayCount, 1);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'widget action wakes standby and restores visible timer controls',
    (tester) async {
      screen(tester);
      final storage = _Storage();
      await storage.saveFeedState([
        FeedRecord(time: DateTime(2026, 10, 3, 11)),
      ]);
      final widgets = _Widgets();
      final fixture = _Fixture(storage, widgets);
      await fixture.mount(tester);
      await fixture.settings.setBurnInProtectionEnabled(true);
      await tester.pump(const Duration(seconds: 35));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsOneWidget);
      widgets.emit('open_timer');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('standby-screen')), findsNothing);
      expect(
        find.byKey(const ValueKey('nav-home')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );
}
