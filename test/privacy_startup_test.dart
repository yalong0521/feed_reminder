import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/utils/privacy_policy.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _consentStorageKey = 'acceptedPrivacyPolicyVersion';

/// The plugin changes its in-process cache before the native write completes.
/// Failed consent writes must never become effective through that dirty cache.
class _Preferences extends Fake implements SharedPreferences {
  _Preferences(Map<String, Object> initial)
    : disk = Map.of(initial),
      cache = Map.of(initial);

  final Map<String, Object> disk;
  final Map<String, Object> cache;
  Completer<void>? consentWriteGate;
  bool rejectConsentWrite = false;
  int consentWrites = 0;

  @override
  Object? get(String key) => cache[key];
  @override
  bool containsKey(String key) => cache.containsKey(key);
  @override
  String? getString(String key) => cache[key] as String?;
  @override
  int? getInt(String key) => cache[key] as int?;
  @override
  bool? getBool(String key) => cache[key] as bool?;

  Future<bool> _write(String key, Object? value) async {
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    if (key == _consentStorageKey) {
      consentWrites++;
      await consentWriteGate?.future;
      if (rejectConsentWrite) return false;
    }
    if (value == null) {
      disk.remove(key);
    } else {
      disk[key] = value;
    }
    return true;
  }

  @override
  Future<bool> setString(String key, String value) => _write(key, value);
  @override
  Future<bool> setInt(String key, int value) => _write(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);
  @override
  Future<bool> remove(String key) => _write(key, null);

  @override
  Future<void> reload() async {
    cache
      ..clear()
      ..addAll(disk);
  }
}

class _Storage extends StorageService {
  _Storage(Future<SharedPreferences> Function() loader)
    : super(preferencesLoader: loader);

  int historyReads = 0;

  @override
  Future<List<FeedRecord>> getFeedHistory() async {
    historyReads++;
    return super.getFeedHistory();
  }
}

class _Notifications extends NotificationService {
  int initializations = 0;
  int permissionRequests = 0;
  int schedules = 0;
  int cancellations = 0;
  int immediateReminders = 0;

  @override
  bool get isSupported => true;
  @override
  Future<void> init() async => initializations++;
  @override
  Future<void> requestPermissions() async => permissionRequests++;
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async => schedules++;
  @override
  Future<void> cancelAll() async => cancellations++;
  @override
  Future<void> showFeedReminder({bool playSound = true}) async =>
      immediateReminders++;
}

class _Audio extends AudioService {
  int plays = 0;

  @override
  Future<void> playReminder({bool loop = true}) async => plays++;
  @override
  Future<void> stopReminder() async {}
}

Future<void> _mount(
  WidgetTester tester,
  _Storage storage,
  _Notifications notifications,
  _Audio audio, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool waitForConsentRead = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    FeedReminderApp(
      storage: storage,
      notificationService: notifications,
      audioService: audio,
    ),
  );
  if (waitForConsentRead) await tester.pumpAndSettle();
}

void _expectNotStarted(
  _Storage storage,
  _Notifications notifications,
  _Audio audio,
) {
  expect(find.byType(FeedButton), findsNothing);
  expect(find.byKey(const ValueKey('nav-home')), findsNothing);
  expect(storage.historyReads, 0);
  expect(notifications.initializations, 0);
  expect(notifications.permissionRequests, 0);
  expect(notifications.schedules, 0);
  expect(notifications.cancellations, 0);
  expect(notifications.immediateReminders, 0);
  expect(audio.plays, 0);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('feed_reminder/system_ui'),
      (call) async => null,
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('feed_reminder/system_ui'),
      null,
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      null,
    );
  });

  testWidgets(
    'reading, returning and declining never restore records or request permissions',
    (tester) async {
      final record = FeedRecord(
        time: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final prefs = _Preferences({
        StorageKeys.feedHistory: jsonEncode([record.toJson()]),
        StorageKeys.burnInProtectionEnabled: false,
      });
      final storage = _Storage(() async => prefs);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(tester, storage, notifications, audio);
      _expectNotStarted(storage, notifications, audio);

      await _tap(tester, 'privacy-policy-read');
      expect(find.byKey(const ValueKey('privacy-policy-back')), findsOneWidget);
      expect(find.text('奶点记隐私政策'), findsOneWidget);
      expect(find.textContaining('10295010@qq.com'), findsOneWidget);
      expect(find.text('三、第三方组件'), findsOneWidget);
      _expectNotStarted(storage, notifications, audio);
      await _tap(tester, 'privacy-policy-back');
      expect(
        find.byKey(const ValueKey('privacy-consent-accept')),
        findsOneWidget,
      );
      expect(prefs.consentWrites, 0);
      await _tap(tester, 'privacy-consent-decline');
      _expectNotStarted(storage, notifications, audio);
      expect(prefs.disk.containsKey(_consentStorageKey), isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      _expectNotStarted(storage, notifications, audio);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'consent must finish saving; a failed platform write stays gated and retries',
    (tester) async {
      final prefs = _Preferences({StorageKeys.burnInProtectionEnabled: false});
      final storage = _Storage(() async => prefs);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(tester, storage, notifications, audio);
      prefs.consentWriteGate = Completer<void>();
      prefs.rejectConsentWrite = true;
      await tester.tap(find.byKey(const ValueKey('privacy-consent-accept')));
      await tester.pump();
      expect(prefs.consentWrites, 1);
      expect(prefs.cache[_consentStorageKey], PrivacyPolicy.version);
      expect(prefs.disk.containsKey(_consentStorageKey), isFalse);
      _expectNotStarted(storage, notifications, audio);

      prefs.consentWriteGate!.complete();
      await tester.pumpAndSettle();
      _expectNotStarted(storage, notifications, audio);
      expect(prefs.cache.containsKey(_consentStorageKey), isFalse);
      expect(await storage.getAcceptedPrivacyPolicyVersion(), isNull);
      expect(find.textContaining('隐私确认保存失败'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('privacy-consent-accept')),
        findsOneWidget,
      );

      prefs.rejectConsentWrite = false;
      prefs.consentWriteGate = null;
      await _tap(tester, 'privacy-consent-accept');
      expect(prefs.consentWrites, 2);
      expect(prefs.disk[_consentStorageKey], PrivacyPolicy.version);
      expect(find.byType(FeedButton), findsOneWidget);
      expect(notifications.initializations, 1);
      expect(notifications.permissionRequests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a consent read completed in background defers permission and audio until resume',
    (tester) async {
      final prefs = _Preferences({
        _consentStorageKey: PrivacyPolicy.version,
        StorageKeys.feedHistory: jsonEncode([
          FeedRecord(
            time: DateTime.now().subtract(const Duration(hours: 2)),
          ).toJson(),
        ]),
        StorageKeys.feedIntervalMinutes: 60,
        StorageKeys.soundEnabled: true,
        StorageKeys.soundLoopEnabled: true,
        StorageKeys.nightModeEnabled: false,
        StorageKeys.burnInProtectionEnabled: false,
      });
      final readGate = Completer<SharedPreferences>();
      final storage = _Storage(() => readGate.future);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(
        tester,
        storage,
        notifications,
        audio,
        waitForConsentRead: false,
      );
      _expectNotStarted(storage, notifications, audio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      readGate.complete(prefs);
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 0);
      expect(audio.plays, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 1);
      expect(audio.plays, greaterThan(0));
      expect(find.byType(FeedButton), findsOneWidget);
      expect(prefs.consentWrites, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a consent save completed in background defers permission and audio until resume',
    (tester) async {
      final prefs = _Preferences({
        StorageKeys.feedHistory: jsonEncode([
          FeedRecord(
            time: DateTime.now().subtract(const Duration(hours: 2)),
          ).toJson(),
        ]),
        StorageKeys.feedIntervalMinutes: 60,
        StorageKeys.soundEnabled: true,
        StorageKeys.soundLoopEnabled: true,
        StorageKeys.nightModeEnabled: false,
        StorageKeys.burnInProtectionEnabled: false,
      });
      final storage = _Storage(() async => prefs);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(tester, storage, notifications, audio);
      prefs.consentWriteGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('privacy-consent-accept')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      prefs.consentWriteGate!.complete();
      await tester.pumpAndSettle();
      expect(prefs.disk[_consentStorageKey], PrivacyPolicy.version);
      expect(notifications.permissionRequests, 0);
      expect(audio.plays, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 1);
      expect(audio.plays, greaterThan(0));
      expect(find.byType(FeedButton), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'saved consent survives recreation and policy remains in settings',
    (tester) async {
      final prefs = _Preferences({StorageKeys.burnInProtectionEnabled: false});
      final storage = _Storage(() async => prefs);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(tester, storage, notifications, audio);
      await _tap(tester, 'privacy-consent-accept');
      expect(prefs.consentWrites, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, _Storage(() async => prefs), notifications, audio);
      expect(
        find.byKey(const ValueKey('privacy-consent-accept')),
        findsNothing,
      );
      expect(find.byType(FeedButton), findsOneWidget);
      expect(notifications.permissionRequests, 2);
      await _tap(tester, 'nav-settings');
      final policyLink = find.text('阅读隐私政策');
      await tester.ensureVisible(policyLink);
      await tester.tap(policyLink);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('privacy-policy-back')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('privacy-consent-accept')),
        findsNothing,
      );
      await _tap(tester, 'privacy-policy-back');
      expect(find.text('偏好设置'), findsOneWidget);
      expect(prefs.consentWrites, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'upgrading keeps existing records and preferences after agreement',
    (tester) async {
      final record = FeedRecord(
        id: 'saved-before-privacy-update',
        time: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final encoded = jsonEncode([record.toJson()]);
      final prefs = _Preferences({
        StorageKeys.feedHistory: encoded,
        StorageKeys.feedIntervalMinutes: 150,
        StorageKeys.soundEnabled: false,
        StorageKeys.burnInProtectionEnabled: false,
        StorageKeys.themeMode: 'dark',
      });
      final storage = _Storage(() async => prefs);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(tester, storage, notifications, audio);
      _expectNotStarted(storage, notifications, audio);
      expect(prefs.disk[StorageKeys.feedHistory], encoded);
      await _tap(tester, 'privacy-consent-accept');
      final context = tester.element(find.byType(FeedButton));
      final feed = context.read<FeedProvider>();
      final settings = context.read<SettingsProvider>();
      expect(feed.feedHistory.map((entry) => entry.id), [record.id]);
      expect(
        feed.lastFeedTime!.millisecondsSinceEpoch,
        record.time.millisecondsSinceEpoch,
      );
      expect(settings.feedIntervalMinutes, 150);
      expect(settings.soundEnabled, isFalse);
      expect(settings.themeMode, ThemeMode.dark);
      expect(prefs.disk[StorageKeys.feedHistory], encoded);
      expect(notifications.schedules, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an older accepted policy requires current explicit agreement', (
    tester,
  ) async {
    final prefs = _Preferences({_consentStorageKey: '2026-09-30'});
    final storage = _Storage(() async => prefs);
    final notifications = _Notifications();
    final audio = _Audio();
    await _mount(tester, storage, notifications, audio);
    expect(
      find.byKey(const ValueKey('privacy-consent-accept')),
      findsOneWidget,
    );
    _expectNotStarted(storage, notifications, audio);
    expect(prefs.disk[_consentStorageKey], '2026-09-30');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed initial consent read stays gated and can retry', (
    tester,
  ) async {
    final prefs = _Preferences({_consentStorageKey: PrivacyPolicy.version});
    var loads = 0;
    final storage = _Storage(() async {
      if (loads++ == 0) throw StateError('temporary native storage failure');
      return prefs;
    });
    final notifications = _Notifications();
    final audio = _Audio();
    await _mount(tester, storage, notifications, audio);
    _expectNotStarted(storage, notifications, audio);
    expect(find.byKey(const ValueKey('privacy-consent-retry')), findsOneWidget);
    await _tap(tester, 'privacy-consent-retry');
    expect(find.byType(FeedButton), findsOneWidget);
    expect(prefs.consentWrites, 0);
    expect(notifications.permissionRequests, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('privacy pages fit ${size.width}x${size.height} at 2x text', (
      tester,
    ) async {
      final prefs = _Preferences({});
      final storage = _Storage(() async => prefs);
      final notifications = _Notifications();
      final audio = _Audio();
      await _mount(tester, storage, notifications, audio, size: size, scale: 2);
      expect(tester.takeException(), isNull);
      for (final key in ['privacy-consent-accept', 'privacy-consent-decline']) {
        final button = find.byKey(ValueKey(key));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await _tap(tester, 'privacy-policy-read');
      expect(tester.takeException(), isNull);
      final contact = find.textContaining('10295010@qq.com');
      await tester.ensureVisible(contact);
      await tester.pumpAndSettle();
      expect(contact.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'privacy-policy-back');
      _expectNotStarted(storage, notifications, audio);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
