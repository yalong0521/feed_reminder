import 'dart:async';

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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
  Future<void> showFeedReminder({bool playSound = true}) async {}

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}

  @override
  Future<void> cancelAll() async {}
}

class _Storage extends StorageService {
  Completer<void>? pending;

  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    await pending?.future;
    await super.saveFeedState(records);
  }
}

class _Routes extends NavigatorObserver {
  final dialogs = <PopupRoute<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) dialogs.add(route);
  }
}

enum _Entry { interval, defaultMilk, backfill, date, time }

Future<({FeedProvider feed, _Storage storage, _Routes routes})> _mount(
  WidgetTester tester,
  _Entry entry, {
  required bool reduceMotion,
}) async {
  final storage = _Storage();
  final feed = FeedProvider(
    storage: storage,
    audioService: _Audio(),
    notificationService: _Notifications(),
    clock: () => DateTime(2026, 10, 5, 12),
    startTimer: false,
  );
  final settings = SettingsProvider(storage: storage);
  await Future.wait([feed.ready, settings.ready]);
  addTearDown(feed.dispose);
  addTearDown(settings.dispose);
  final routes = _Routes();
  final isSettings = entry == _Entry.interval || entry == _Entry.defaultMilk;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        Provider<NotificationService>.value(value: _Notifications()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        navigatorObservers: [routes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        // Keep FeedProvider below the Navigator: the real backfill entry must
        // carry its provider into the new route instead of losing page scope.
        home: ChangeNotifierProvider.value(
          value: feed,
          child: Scaffold(
            body: isSettings
                ? const SettingsScreen()
                : Builder(
                    builder: (context) => AppButton(
                      key: const ValueKey('open-motion-backfill'),
                      onPressed: () => showAddFeedRecordDialog(context),
                      child: const Text('补记喂奶'),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (feed: feed, storage: storage, routes: routes);
}

Future<Finder> _open(WidgetTester tester, _Entry entry) async {
  final key = switch (entry) {
    _Entry.interval => 'custom-interval-button',
    _Entry.defaultMilk => 'default-milk-amount',
    _ => 'open-motion-backfill',
  };
  final opener = find.byKey(ValueKey(key));
  await tester.ensureVisible(opener);
  await tester.pumpAndSettle();
  await tester.tap(opener);
  if (entry == _Entry.date || entry == _Entry.time) {
    await tester.pumpAndSettle();
    final field = find.byKey(
      ValueKey(
        entry == _Entry.date ? 'add-feed-date-field' : 'add-feed-time-field',
      ),
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
  }
  return switch (entry) {
    _Entry.interval => find.byKey(
      const ValueKey('custom-interval-editor-surface'),
    ),
    _Entry.defaultMilk => find.byKey(
      const ValueKey('default-milk-amount-editor-surface'),
    ),
    _Entry.backfill => find.byType(AddFeedRecordDialog),
    _Entry.date ||
    _Entry.time => find.byKey(const ValueKey('app-date-time-picker-surface')),
  };
}

double _opacity(WidgetTester tester, Finder surface) => tester
    .widget<FadeTransition>(
      find.ancestor(of: surface, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

double _scale(WidgetTester tester, Finder surface) => tester
    .widget<ScaleTransition>(
      find.ancestor(of: surface, matching: find.byType(ScaleTransition)).first,
    )
    .scale
    .value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in _Entry.values) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
        '${entry.name} dialog opens and closes with ${reduceMotion ? 'reduced' : 'shared'} motion',
        (tester) async {
          final app = await _mount(tester, entry, reduceMotion: reduceMotion);
          final surface = await _open(tester, entry);
          await tester.pump();
          final route = app.routes.dialogs.last;
          expect(route.barrierColor, Colors.black.withValues(alpha: .3));
          expect(
            route.transitionDuration,
            Duration(milliseconds: reduceMotion ? 0 : 180),
          );
          expect(route.reverseTransitionDuration, route.transitionDuration);
          if (!reduceMotion) {
            expect(_opacity(tester, surface), closeTo(0, .001));
            expect(_scale(tester, surface), closeTo(.97, .001));
            await tester.pump(const Duration(milliseconds: 90));
            expect(_opacity(tester, surface), inExclusiveRange(0, 1));
            expect(_scale(tester, surface), inExclusiveRange(.97, 1));
            await tester.pump(const Duration(milliseconds: 90));
          }
          expect(surface, findsOneWidget);
          expect(_opacity(tester, surface), 1);
          expect(_scale(tester, surface), 1);
          if (entry == _Entry.interval) {
            final input = find.descendant(
              of: surface,
              matching: find.byType(EditableText),
            );
            expect(
              tester.widget<EditableText>(input).focusNode.hasFocus,
              isTrue,
            );
            // Traverse beyond the editor's input and two actions. Repeated
            // Tab must wrap inside this modal rather than reach its opener.
            for (var step = 0; step < 6; step++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pump();
              final focusedContext =
                  FocusManager.instance.primaryFocus!.context!;
              expect(ModalRoute.of(focusedContext), same(route));
            }
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          if (!reduceMotion) {
            expect(surface, findsOneWidget);
            await tester.pump(const Duration(milliseconds: 90));
            expect(_opacity(tester, surface), inExclusiveRange(0, 1));
            expect(_scale(tester, surface), inExclusiveRange(.97, 1));
            await tester.pump(const Duration(milliseconds: 90));
            expect(route.animation!.value, closeTo(0, .001));
            expect(route.isActive, isFalse);
            // At exactly 180 ms the reverse interpolation has reached zero,
            // but its simulation completes only after crossing that boundary.
            // Advance minimally so Navigator can remove the exited route.
            await tester.pump(const Duration(milliseconds: 1));
          }
          await tester.pump();
          expect(surface, findsNothing);
          expect(app.feed.feedHistory, isEmpty);
          if (entry == _Entry.date || entry == _Entry.time) {
            // Escape dismisses only the top picker, preserving unsaved backfill.
            expect(find.byType(AddFeedRecordDialog), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('Escape cannot close backfill while its save is pending', (
    tester,
  ) async {
    final app = await _mount(tester, _Entry.backfill, reduceMotion: false);
    final pending = Completer<void>();
    app.storage.pending = pending;
    try {
      await _open(tester, _Entry.backfill);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('add-feed-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<AppButton>(save).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AddFeedRecordDialog), findsOneWidget);
      expect(app.feed.feedHistory, isEmpty);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedRecordDialog), findsNothing);
      expect(app.feed.feedHistory, hasLength(1));
    } finally {
      if (!pending.isCompleted) pending.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
