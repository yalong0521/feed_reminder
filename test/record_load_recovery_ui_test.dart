import 'dart:async';

import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/history_screen.dart';
import 'package:feed_reminder/screens/home_screen.dart';
import 'package:feed_reminder/screens/statistics_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/feed_load_failure.dart';
import 'package:feed_reminder/widgets/milk_volume_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage extends StorageService {
  bool fail = true;
  Completer<void>? gate;

  @override
  Future<List<FeedRecord>> getFeedHistory() async {
    await gate?.future;
    if (fail) throw StateError('Temporary read failure');
    return [
      FeedRecord(
        id: 'saved',
        time: DateTime(2026, 10, 3, 10),
        milkAmountMl: 150,
      ),
    ];
  }
}

class _Audio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}
  @override
  Future<void> stopReminder() async {}
}

class _Notifications extends NotificationService {
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
}

void main() {
  for (final page in <String, Widget>{
    'timer': const HomeScreen(),
    'history': const HistoryScreen(),
    'statistics': const StatisticsScreen(),
  }.entries) {
    testWidgets('${page.key} shows unknown data and recovers without restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = page.key == 'timer'
          ? const Size(320, 280)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = _Storage();
      final feed = FeedProvider(
        storage: storage,
        audioService: _Audio(),
        notificationService: _Notifications(),
        startTimer: false,
        clock: () => DateTime(2026, 10, 3, 12),
      );
      final settings = SettingsProvider(storage: storage);
      addTearDown(feed.dispose);
      addTearDown(settings.dispose);
      await Future.wait([feed.ready, settings.ready]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: feed),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(page.key == 'timer' ? 2 : 1),
              ),
              child: child!,
            ),
            home: page.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FeedLoadFailure), findsOneWidget);
      expect(find.byType(MilkVolumeChart), findsNothing);
      expect(find.byKey(const ValueKey('statistics-total')), findsNothing);
      final retry = find.byKey(const ValueKey('retry-feed-loading'));
      await tester.ensureVisible(retry);
      storage.gate = Completer<void>();
      await tester.tap(retry);
      await tester.pump();
      expect(tester.widget<AppButton>(retry).onPressed, isNull);
      expect(find.text('正在重试…'), findsOneWidget);
      storage.fail = false;
      storage.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FeedLoadFailure), findsNothing);
      expect(feed.feedHistory.single.id, 'saved');
      if (page.key == 'statistics') {
        expect(find.byType(MilkVolumeChart), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
