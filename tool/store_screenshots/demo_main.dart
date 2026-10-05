// Dedicated store capture build. Never use as the application release target.
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
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const screenshotLogicalSize = Size(540, 960);
final screenshotTime = DateTime(2026, 10, 6, 10, 20);
SemanticsHandle? _captureSemantics;

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
  Future<void> init() async {}
  @override
  Future<void> requestPermissions() async {}
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

List<FeedRecord> _records({required bool overdue}) => [
  for (var day = 6; day >= 1; day--)
    for (var meal = 0; meal < 6; meal++)
      FeedRecord(
        id: 'store-day-$day-meal-$meal',
        time: DateTime(2026, 10, 6 - day, 3 + meal * 3),
        // Vary each complete day's total as well as meal order, so the chart
        // demonstrates a real trend instead of six identical daily sums.
        milkAmountMl:
            [150, 180, 160, 180, 150, 170][(meal + day) % 6] +
            [0, 10, -5, 15, 5, -10, -15][day],
      ),
  // Match the demonstration desktop cards: four meals, total 720 mL.
  for (final hour in [0, 3, 6, if (!overdue) 9])
    FeedRecord(
      id: 'store-today-$hour',
      time: DateTime(2026, 10, 6, hour, overdue && hour == 6 ? 40 : 0),
      milkAmountMl: 180,
    ),
];

Future<void> _loadCaptureFonts() async {
  // The local build script supplies these explicit web asset paths. They are
  // intentionally outside pubspec so the application never distributes them.
  final regular = await rootBundle.load('capture-fonts/msyh.ttc');
  final bold = await rootBundle.load('capture-fonts/msyhbd.ttc');
  for (final family in [
    'Microsoft YaHei',
    'Roboto',
    'Arial',
    'Segoe UI',
    'sans-serif',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)
          ..addFont(Future.value(regular))
          ..addFont(Future.value(bold)))
        .load();
  }
  await (FontLoader('JournalSerif')
        ..addFont(rootBundle.load('assets/fonts/Tinos-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Tinos-Bold.ttf')))
      .load();

  double measure(String text, String? family) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 24, fontFamily: family),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // Include unstyled custom painters, not just themed Text widgets.
  for (final family in <String?>[null, 'Roboto', 'JournalSerif']) {
    if (measure('MMMM', family) <= measure('iiii', family) * 1.5) {
      throw StateError('Screenshot requires real text glyphs: $family');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _captureSemantics ??= SemanticsBinding.instance.ensureSemantics();
  final parameters = Uri.base.queryParameters;
  final overdue = parameters['state'] == 'overdue';
  final dark = parameters['theme'] == 'dark';
  try {
    await _loadCaptureFonts();
    // This local capture entry point must never read or write browser user data.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'acceptedPrivacyPolicyVersion': PrivacyPolicy.version,
      StorageKeys.feedHistory: jsonEncode(
        _records(overdue: overdue).map((record) => record.toJson()).toList(),
      ),
      StorageKeys.feedIntervalMinutes: 180,
      StorageKeys.defaultMilkAmountMl: 180,
      StorageKeys.burnInProtectionEnabled: false,
      StorageKeys.nightModeEnabled: true,
      StorageKeys.nightStartTime: '22:00',
      StorageKeys.nightEndTime: '06:00',
      StorageKeys.themeMode: dark ? 'dark' : 'light',
    });
    final storage = StorageService();
    final audio = _SilentAudio();
    final notifications = _SilentNotifications();
    final settings = SettingsProvider(storage: storage);
    final feed = FeedProvider(
      storage: storage,
      audioService: audio,
      notificationService: notifications,
      clock: () => screenshotTime,
      startTimer: false,
    );
    await Future.wait([feed.ready, settings.ready]);
    if (!feed.isAvailable || !settings.isAvailable) {
      throw StateError('Screenshot fixture did not initialize');
    }
    runApp(
      _CaptureFrame(
        dark: dark,
        child: FeedReminderApp(
          storage: storage,
          audioService: audio,
          notificationService: notifications,
          feedProvider: feed,
          settingsProvider: settings,
          enablePlatformEffects: false,
        ),
      ),
    );
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Colors.white,
          child: Center(
            child: Text(
              'Screenshot setup failed: $error',
              style: const TextStyle(color: Colors.red, fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureFrame extends StatelessWidget {
  const _CaptureFrame({required this.child, required this.dark});
  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xffd2d0cb),
    child: SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: screenshotLogicalSize.width,
          height: screenshotLogicalSize.height,
          child: MediaQuery(
            data: MediaQueryData(
              size: screenshotLogicalSize,
              devicePixelRatio: 1.6,
              textScaler: TextScaler.noScaling,
              disableAnimations: true,
              platformBrightness: dark ? Brightness.dark : Brightness.light,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
