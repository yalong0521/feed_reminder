import 'dart:async';

import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/screens/settings_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:feed_reminder/widgets/app_message_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNotifications extends NotificationService {
  @override
  bool get isSupported => false;
}

class _FailingStorage extends StorageService {
  @override
  Future<void> setFeedInterval(int minutes) async {
    throw StateError('Unable to save');
  }
}

class _FailFirstThemeStorage extends StorageService {
  int attempts = 0;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    attempts++;
    if (attempts == 1) throw StateError('Unable to save appearance');
    await super.setThemeMode(mode);
  }
}

class _PreviewAudio extends AudioService {
  bool playing = false;
  bool failPlayback = false;
  bool disposed = false;
  bool? lastLoop;
  int playCount = 0;
  int stopCount = 0;
  Completer<void>? playGate;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> playReminder({bool loop = true}) async {
    playCount++;
    lastLoop = loop;
    if (failPlayback) throw StateError('Preview unavailable');
    await playGate?.future;
    playing = true;
  }

  @override
  Future<void> stopReminder() async {
    stopCount++;
    playing = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playing = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsProvider> showSettings(
    WidgetTester tester, {
    StorageService? storage,
    double textScale = 1,
    AudioService? previewAudio,
    ValueNotifier<bool>? active,
  }) async {
    final settings = SettingsProvider(storage: storage ?? StorageService());
    await settings.ready;
    final activeState = active ?? ValueNotifier(true);
    if (active == null) addTearDown(activeState.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<NotificationService>(create: (_) => _NoNotifications()),
        ],
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: ValueListenableBuilder<bool>(
              valueListenable: activeState,
              builder: (context, isActive, _) => Scaffold(
                body: SettingsScreen(
                  isActive: isActive,
                  previewAudioFactory: previewAudio == null
                      ? null
                      : () => previewAudio,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> closeErrorDialog(WidgetTester tester) async {
    expect(find.byType(AppMessageDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byType(CupertinoDialogAction), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is InkResponse),
      findsNothing,
    );
    expect(find.widgetWithText(AppButton, '关闭'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-notice-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AppMessageDialog), findsNothing);
  }

  testWidgets('settings fit a 320 pixel screen at 200 percent text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = await showSettings(tester, textScale: 2);
    expect(find.text('提醒偏好'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
      final chip = find.byKey(ValueKey('theme-mode-${mode.name}'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      expect(chip.hitTestable(), findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(settings.themeMode, mode);
      expect(tester.widget<AppPressable>(chip).selected, isTrue);
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('防烧屏保护'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义喂奶间隔'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interval presets persist the selected value', (tester) async {
    final settings = await showSettings(tester);
    await tester.tap(find.byKey(const ValueKey('interval-preset-120')));
    await tester.pumpAndSettle();
    expect(settings.feedIntervalMinutes, 120);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(StorageKeys.feedIntervalMinutes), 120);
    expect(
      tester
          .widget<AppPressable>(
            find.byKey(const ValueKey('interval-preset-120')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('repeated custom interval actions keep a single editor route', (
    tester,
  ) async {
    final settings = await showSettings(tester);
    final open = tester
        .widget<AppButton>(find.byKey(const ValueKey('custom-interval-button')))
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    final field = find.byKey(
      const ValueKey('custom-interval-field'),
      skipOffstage: false,
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, '75');
    final submitted = tester.widget<CupertinoTextField>(field).onSubmitted!;
    final save = tester
        .widget<AppButton>(find.widgetWithText(AppButton, '保存'))
        .onPressed!;
    save();
    submitted('75');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(settings.feedIntervalMinutes, 75);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom interval rejects out of range input then persists minutes',
    (tester) async {
      final settings = await showSettings(tester);
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-interval-field')),
        '0',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–1440 之间的整数'), findsOneWidget);
      expect(settings.feedIntervalMinutes, 180);
      await tester.enterText(
        find.byKey(const ValueKey('custom-interval-field')),
        '1441',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–1440 之间的整数'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('custom-interval-field')),
        '75',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('自定义喂奶间隔'), findsNothing);
      expect(find.text('1 小时 15 分钟'), findsOneWidget);
      expect(settings.feedIntervalMinutes, 75);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(StorageKeys.feedIntervalMinutes), 75);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sound off disables loop and preview while preserving loop preference',
    (tester) async {
      final settings = await showSettings(tester);
      final soundSwitch = find.byType(CupertinoSwitch).at(1);
      await tester.ensureVisible(soundSwitch);
      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();
      expect(settings.soundEnabled, isFalse);
      expect(settings.soundLoopEnabled, isTrue);
      expect(
        tester
            .widget<CupertinoSwitch>(find.byType(CupertinoSwitch).at(2))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('sound-preview-button')),
            )
            .onPressed,
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(StorageKeys.soundEnabled), isFalse);
    },
  );

  testWidgets('night mode and burn in protection persist independently', (
    tester,
  ) async {
    final settings = await showSettings(tester);
    await tester.ensureVisible(find.byType(CupertinoSwitch).first);
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(settings.nightModeEnabled, isTrue);
    await tester.ensureVisible(find.byType(CupertinoSwitch).last);
    await tester.tap(find.byType(CupertinoSwitch).last);
    await tester.pumpAndSettle();
    expect(settings.burnInProtectionEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(StorageKeys.nightModeEnabled), isTrue);
    expect(prefs.getBool(StorageKeys.burnInProtectionEnabled), isFalse);
  });

  testWidgets(
    'save failures show an error dialog and keep the previous interval',
    (tester) async {
      final settings = await showSettings(tester, storage: _FailingStorage());
      await tester.tap(find.byKey(const ValueKey('interval-preset-120')));
      await tester.pumpAndSettle();
      expect(find.text('未能保存设置，请重试。'), findsOneWidget);
      await closeErrorDialog(tester);
      expect(settings.feedIntervalMinutes, 180);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance save failure restores the selected theme and can retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({StorageKeys.themeMode: 'light'});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final storage = _FailFirstThemeStorage();
      final settings = await showSettings(tester, storage: storage);
      final screen = find.byType(SettingsScreen);
      final light = find.byKey(const ValueKey('theme-mode-light'));
      final dark = find.byKey(const ValueKey('theme-mode-dark'));
      expect(settings.themeMode, ThemeMode.light);
      expect(Theme.of(tester.element(screen)).brightness, Brightness.light);

      await tester.ensureVisible(dark);
      await tester.pumpAndSettle();
      await tester.tap(dark);
      await tester.pumpAndSettle();
      expect(storage.attempts, 1);
      expect(find.text('未能保存设置，请重试。'), findsOneWidget);
      await closeErrorDialog(tester);
      expect(settings.themeMode, ThemeMode.light);
      expect(tester.widget<AppPressable>(light).selected, isTrue);
      expect(tester.widget<AppPressable>(dark).selected, isFalse);
      expect(Theme.of(tester.element(screen)).brightness, Brightness.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.themeMode), 'light');

      await tester.ensureVisible(dark);
      await tester.tap(dark);
      await tester.pumpAndSettle();
      expect(storage.attempts, 2);
      expect(settings.themeMode, ThemeMode.dark);
      expect(tester.widget<AppPressable>(dark).selected, isTrue);
      expect(Theme.of(tester.element(screen)).brightness, Brightness.dark);
      expect(prefs.getString(StorageKeys.themeMode), 'dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'time preference opens a Cupertino wheel and persists the chosen time',
    (tester) async {
      final settings = await showSettings(tester);
      await settings.setNightModeEnabled(true);
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('night-start-time'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.mode, CupertinoDatePickerMode.time);
      picker.onDateTimeChanged(DateTime(2026, 9, 25, 21, 35));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(settings.nightStartTime, '21:35');
      expect(
        (await SharedPreferences.getInstance()).getString(
          StorageKeys.nightStartTime,
        ),
        '21:35',
      );
    },
  );

  testWidgets(
    'preview plays once, resets on completion, and can stop a second preview',
    (tester) async {
      final audio = _PreviewAudio();
      await showSettings(tester, previewAudio: audio);
      final preview = find.byKey(const ValueKey('sound-preview-button'));
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(audio.playCount, 1);
      expect(audio.lastLoop, isFalse);
      expect(find.text('停止试听'), findsOneWidget);
      audio.playing = false;
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('试听提醒音'), findsOneWidget);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(audio.playCount, 2);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
      expect(audio.stopCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(audio.disposed, isTrue);
    },
  );

  testWidgets(
    'leaving settings stops a preview even if playback is still starting',
    (tester) async {
      final gate = Completer<void>();
      final audio = _PreviewAudio()..playGate = gate;
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await showSettings(tester, previewAudio: audio, active: active);
      final preview = find.byKey(const ValueKey('sound-preview-button'));
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pump();
      active.value = false;
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
      expect(audio.stopCount, greaterThanOrEqualTo(1));
      active.value = true;
      await tester.pumpAndSettle();
      expect(find.text('试听提醒音'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(audio.disposed, isTrue);
    },
  );

  testWidgets('preview failure allows retry after closing the error dialog', (
    tester,
  ) async {
    final audio = _PreviewAudio()..failPlayback = true;
    await showSettings(tester, previewAudio: audio);
    final preview = find.byKey(const ValueKey('sound-preview-button'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('暂时无法播放提醒音，请重试。'), findsOneWidget);
    await closeErrorDialog(tester);
    expect(tester.widget<AppButton>(preview).onPressed, isNotNull);
    audio.failPlayback = false;
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(audio.playing, isTrue);
    expect(audio.playCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'all interval presets are reachable above the fold in landscape',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showSettings(tester);
      for (final minutes in [120, 150, 180, 210, 240]) {
        expect(
          find.byKey(ValueKey('interval-preset-$minutes')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
