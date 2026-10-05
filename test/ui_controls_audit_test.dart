import 'dart:async';
import 'dart:ui' as ui;

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/settings_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/add_feed_record_dialog.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/landscape_feed_panel.dart';
import 'package:feed_reminder/widgets/milk_amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}

  @override
  Future<void> stopReminder() async {}
}

class _SilentNotifications extends NotificationService {
  @override
  bool get isSupported => false;

  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}

  @override
  Future<void> cancelAll() async {}
}

class _PendingStorage extends StorageService {
  final pending = Completer<void>();

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    await pending.future;
    await super.saveFeedState(records);
  }
}

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'backfill save keeps an accessible name while storage is pending',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final storage = _PendingStorage();
      final feed = FeedProvider(
        storage: storage,
        audioService: _SilentAudio(),
        notificationService: _SilentNotifications(),
        startTimer: false,
      );
      await feed.ready;
      try {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: feed,
            child: _app(
              Scaffold(
                body: Builder(
                  builder: (context) => AppButton(
                    onPressed: () => showAddFeedRecordDialog(context),
                    child: const Text('补记'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('补记'));
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('add-feed-save'));
        await tester.ensureVisible(save);
        expect(tester.getSemantics(save).getSemanticsData().label, '保存记录');
        await tester.tap(save);
        await tester.pump();
        final pending = tester.getSemantics(save).getSemanticsData();
        expect(pending.label, '正在保存记录');
        expect(pending.flagsCollection.isEnabled, ui.Tristate.isFalse);
        expect(pending.flagsCollection.isLiveRegion, isTrue);
        storage.pending.complete();
        await tester.pumpAndSettle();
        expect(feed.feedHistory, hasLength(1));
        expect(find.byType(AddFeedRecordDialog), findsNothing);
      } finally {
        if (!storage.pending.isCompleted) storage.pending.complete();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        feed.dispose();
      }
    },
  );

  testWidgets('settings data action exposes its purpose to screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final settings = SettingsProvider(storage: StorageService());
    await settings.ready;
    try {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            Provider<NotificationService>.value(value: _SilentNotifications()),
          ],
          child: _app(const Scaffold(body: SettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('open-data-management'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      final data = tester.getSemantics(action).getSemanticsData();
      expect(data.label, '管理喂奶记录，本地备份、合并恢复与 CSV 导出');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      settings.dispose();
    }
  });

  testWidgets(
    'milk ruler at 180 exposes enabled semantics and responds to increase',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: '180');
      try {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SingleChildScrollView(
                child: MilkAmountField(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final slider = find.bySemanticsLabel('本次奶量刻度');
        final node = tester.getSemantics(slider);
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isSlider, isTrue);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.hasAction(ui.SemanticsAction.increase), isTrue);
        expect(data.hasAction(ui.SemanticsAction.decrease), isTrue);
        tester
            .renderObject(slider)
            .owner!
            .semanticsOwner!
            .performAction(node.id, ui.SemanticsAction.increase);
        await tester.pumpAndSettle();
        expect(controller.text, '190');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        controller.dispose();
      }
    },
  );

  testWidgets(
    'successfully stopped reminder is a status instead of another action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final now = DateTime(2026, 10, 5, 12);
      final feed = FeedProvider(
        storage: StorageService(),
        audioService: _SilentAudio(),
        notificationService: _SilentNotifications(),
        startTimer: false,
        clock: () => now,
      );
      await feed.ready;
      await feed.addFeedRecordWithTime(now.subtract(const Duration(hours: 4)));
      try {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ListenableBuilder(
                listenable: feed,
                builder: (context, _) => LandscapeFeedPanel(
                  feed: feed,
                  quiet: false,
                  pulseEnabled: false,
                  onRecord: () async {},
                  onUndo: () async {},
                  onStopAlert: feed.stopAlert,
                  onBackfill: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('停止本次提醒'));
        await tester.pumpAndSettle();
        expect(feed.isAlertAcknowledgementPersisted, isTrue);
        final status = find.text('本次提醒已停止');
        expect(status, findsOneWidget);
        final data = tester.getSemantics(status).getSemanticsData();
        expect(data.flagsCollection.isButton, isFalse);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(find.widgetWithText(AppButton, '本次提醒已停止'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        feed.dispose();
      }
    },
  );
}
