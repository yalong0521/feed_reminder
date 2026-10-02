import 'package:feed_reminder/app.dart';
import 'package:feed_reminder/screens/privacy_policy_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/privacy_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/feed_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage extends StorageService {
  int localConsentReads = 0;

  @override
  Future<String?> getAcceptedPrivacyPolicyVersion() async {
    localConsentReads++;
    return null;
  }
}

class _Notifications extends NotificationService {
  int permissionRequests = 0;

  @override
  bool get isSupported => false;
  @override
  Future<void> init() async {}
  @override
  Future<void> requestPermissions() async => permissionRequests++;
  @override
  Future<void> cancelAll() async {}
}

Future<void> _mount(WidgetTester tester, _Storage storage) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FeedReminderApp(
      storage: storage,
      notificationService: _Notifications(),
      audioService: AudioService(),
      enablePlatformEffects: false,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openFromSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-settings')));
  await tester.pumpAndSettle();
  final link = find.text('阅读隐私政策');
  await tester.ensureVisible(link);
  await tester.tap(link);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('feed_reminder/privacy');
  final harmony = TargetPlatform.values
      .where((platform) => platform.name == 'ohos')
      .firstOrNull;
  final variant = TargetPlatformVariant({harmony ?? TargetPlatform.android});
  // The official Flutter SDK has no OH enum; run these variants with tool/ohos.sh.
  final skip = harmony == null;
  late List<MethodCall> calls;
  var failNextOpen = false;

  setUp(() {
    calls = [];
    failNextOpen = false;
    SharedPreferences.setMockInitialValues({
      StorageKeys.burnInProtectionEnabled: false,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (failNextOpen) {
            failNextOpen = false;
            throw PlatformException(code: 'privacy_policy_unavailable');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'hosted policy bridge delegates opening to the native platform',
    () async {
      await PrivacyService.openHostedPolicy();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'openHostedPrivacyPolicy');
      expect(calls.single.arguments, isNull);
    },
  );

  test(
    'hosted policy bridge preserves failure and allows a fresh retry',
    () async {
      failNextOpen = true;
      await expectLater(
        PrivacyService.openHostedPolicy(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'privacy_policy_unavailable',
          ),
        ),
      );
      await PrivacyService.openHostedPolicy();
      expect(calls.map((call) => call.method), [
        'openHostedPrivacyPolicy',
        'openHostedPrivacyPolicy',
      ]);
    },
  );

  testWidgets(
    'HarmonyOS relies on the platform hosted policy without a second app gate',
    (tester) async {
      final storage = _Storage();
      await _mount(tester, storage);
      expect(PrivacyService.usesHostedPolicy, isTrue);
      expect(storage.localConsentReads, 0);
      expect(
        find.byKey(const ValueKey('privacy-consent-dialog')),
        findsNothing,
      );
      expect(find.byType(FeedButton), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: variant,
    skip: skip,
  );

  testWidgets(
    'HarmonyOS settings opens the hosted policy and never the bundled reader',
    (tester) async {
      await _mount(tester, _Storage());
      await _openFromSettings(tester);
      expect(calls.map((call) => call.method), ['openHostedPrivacyPolicy']);
      expect(find.byType(PrivacyPolicyScreen), findsNothing);
      expect(find.text('奶点记隐私政策'), findsNothing);
      expect(
        find.byKey(const ValueKey('privacy-consent-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: variant,
    skip: skip,
  );

  testWidgets(
    'HarmonyOS hosted policy failure offers retry without an offline fallback',
    (tester) async {
      failNextOpen = true;
      await _mount(tester, _Storage());
      await _openFromSettings(tester);
      expect(find.text('隐私政策暂时无法打开，请检查网络后重试。'), findsOneWidget);
      expect(find.byType(PrivacyPolicyScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('privacy-consent-dialog')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('app-notice-action')));
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), [
        'openHostedPrivacyPolicy',
        'openHostedPrivacyPolicy',
      ]);
      expect(find.byType(PrivacyPolicyScreen), findsNothing);
      expect(find.byKey(const ValueKey('app-notice-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: variant,
    skip: skip,
  );
}
