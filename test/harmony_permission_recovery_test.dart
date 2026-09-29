import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PermissionNotifications extends NotificationService {
  final permission = Completer<void>();
  bool granted = false;
  DateTime? scheduled;

  @override
  bool get isHarmonyOS => true;

  @override
  bool get isSupported => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> requestPermissions() async {
    await permission.future;
    granted = true;
  }

  @override
  Future<void> cancelAll() async {
    scheduled = null;
  }

  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {
    if (!granted) {
      throw PlatformException(code: 'notification_permission_denied');
    }
    scheduled = when;
  }
}

class _QuietAudio extends AudioService {
  @override
  Future<void> stopReminder() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  for (final startup in [true, false]) {
    testWidgets(
      '${startup ? 'startup' : 'settings'} permission grant restores the pending reminder',
      (tester) async {
        final now = DateTime.now();
        SharedPreferences.setMockInitialValues({
          StorageKeys.feedHistory: jsonEncode([
            FeedRecord(
              time: now.subtract(const Duration(minutes: 10)),
            ).toJson(),
          ]),
          StorageKeys.feedIntervalMinutes: 120,
          StorageKeys.nightModeEnabled: false,
          StorageKeys.burnInProtectionEnabled: false,
        });
        final notifications = _PermissionNotifications();
        final storage = StorageService();
        final audio = _QuietAudio();
        final feed = FeedProvider(
          storage: storage,
          audioService: audio,
          notificationService: notifications,
          clock: () => now,
          startTimer: false,
        );
        addTearDown(feed.dispose);
        addTearDown(audio.dispose);
        await feed.ready;
        expect(feed.feedHistory, hasLength(1));
        expect(feed.error, isNotNull);
        expect(notifications.scheduled, isNull);

        await tester.pumpWidget(
          FeedReminderApp(
            storage: storage,
            feedProvider: feed,
            audioService: audio,
            notificationService: notifications,
            enablePlatformEffects: startup,
          ),
        );
        await tester.pumpAndSettle();
        if (!startup) {
          await tester.tap(find.byKey(const ValueKey('nav-settings')));
          await tester.pumpAndSettle();
          final permission = find.text('系统通知权限');
          await tester.ensureVisible(permission);
          await tester.tap(permission);
          await tester.pumpAndSettle();
        }
        expect(notifications.scheduled, isNull);
        // No lifecycle change is sent: the authorization result itself must
        // recover the failed schedule even if no resumed event follows it.
        notifications.permission.complete();
        await tester.pumpAndSettle();
        expect(notifications.scheduled, feed.nextFeedTime);
        expect(feed.error, isNull);
        expect(feed.feedHistory, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
