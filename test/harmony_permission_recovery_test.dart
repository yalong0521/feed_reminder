import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PermissionNotifications extends NotificationService {
  _PermissionNotifications({this.harmony = true});

  final bool harmony;
  final permission = Completer<void>();
  final settings = Completer<void>();
  int permissionRequests = 0;
  int settingsOpened = 0;
  NotificationSettingsResult settingsResult = NotificationSettingsResult.opened;
  bool granted = false;
  DateTime? scheduled;

  @override
  bool get isHarmonyOS => harmony;

  @override
  bool get isSupported => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> requestPermissions() async {
    permissionRequests++;
    await permission.future;
    granted = true;
  }

  @override
  Future<NotificationSettingsResult> openNotificationSettings() async {
    settingsOpened++;
    await settings.future;
    return settingsResult;
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
  for (final scenario in [
    (
      name: 'startup permission',
      startup: true,
      resume: false,
      confirmation: false,
      harmony: true,
    ),
    (
      name: 'non-Harmony startup permission',
      startup: true,
      resume: false,
      confirmation: false,
      harmony: false,
    ),
    (
      name: 'settings result',
      startup: false,
      resume: false,
      confirmation: false,
      harmony: true,
    ),
    (
      name: 'resuming from settings',
      startup: false,
      resume: true,
      confirmation: false,
      harmony: true,
    ),
    (
      name: 'legacy settings confirmation',
      startup: false,
      resume: false,
      confirmation: true,
      harmony: true,
    ),
  ]) {
    testWidgets(
      '${scenario.name} restores the pending reminder after permission is granted',
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
        final notifications = _PermissionNotifications(
          harmony: scenario.harmony,
        );
        if (scenario.confirmation) {
          notifications.settingsResult =
              NotificationSettingsResult.needsConfirmation;
        }
        final storage = StorageService();
        await storage.setAcceptedPrivacyPolicyVersion(PrivacyPolicy.version);
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
        await tester.pump();
        expect(feed.feedHistory, hasLength(1));
        expect(feed.error, isNotNull);
        expect(notifications.scheduled, isNull);

        await tester.pumpWidget(
          FeedReminderApp(
            storage: storage,
            feedProvider: feed,
            audioService: audio,
            notificationService: notifications,
            enablePlatformEffects: scenario.startup,
          ),
        );
        await tester.pumpAndSettle();
        if (!scenario.startup) {
          await tester.tap(find.byKey(const ValueKey('nav-settings')));
          await tester.pumpAndSettle();
          final permission = find.text('系统通知权限');
          await tester.ensureVisible(permission);
          await tester.tap(permission);
          await tester.pumpAndSettle();
        }
        expect(notifications.scheduled, isNull);
        expect(notifications.permissionRequests, scenario.startup ? 1 : 0);
        expect(notifications.settingsOpened, scenario.startup ? 0 : 1);
        if (scenario.startup) {
          // The startup prompt must recover scheduling without a resumed event.
          notifications.permission.complete();
        } else if (scenario.confirmation) {
          // Older system sheets only report opening, so the user confirms return.
          notifications.settings.complete();
          await tester.pumpAndSettle();
          expect(notifications.scheduled, isNull);
          notifications.granted = true;
          await tester.tap(
            find.byKey(const ValueKey('notification-settings-complete')),
          );
        } else if (scenario.resume) {
          // Opening a separate system page can finish before access is changed.
          notifications.settings.complete();
          await tester.pumpAndSettle();
          expect(notifications.scheduled, isNull);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pumpAndSettle();
          notifications.granted = true;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          // A system sheet can close without an app lifecycle transition.
          notifications.granted = true;
          notifications.settings.complete();
        }
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
