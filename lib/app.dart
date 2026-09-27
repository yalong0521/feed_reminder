import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'widgets/app_glass.dart';
import 'widgets/app_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/constants.dart';

/// Owns service lifetimes and synchronizes settings independently of the views.
class FeedReminderApp extends StatefulWidget {
  final StorageService? storage;
  final AudioService? audioService;
  final NotificationService? notificationService;
  final FeedProvider? feedProvider;
  final SettingsProvider? settingsProvider;
  final bool enablePlatformEffects;
  const FeedReminderApp({
    super.key,
    this.storage,
    this.audioService,
    this.notificationService,
    this.feedProvider,
    this.settingsProvider,
    this.enablePlatformEffects = true,
  });
  @override
  State<FeedReminderApp> createState() => _FeedReminderAppState();
}

class _FeedReminderAppState extends State<FeedReminderApp>
    with WidgetsBindingObserver {
  late final StorageService _storage;
  late final AudioService _audio;
  late final NotificationService _notifications;
  late final SettingsProvider _settings;
  late final FeedProvider _feed;
  int _index = 0;
  bool _foreground = true;
  bool _wakelock = false;
  bool _displayDimmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storage = widget.storage ?? StorageService();
    _audio = widget.audioService ?? AudioService();
    _notifications = widget.notificationService ?? NotificationService();
    _settings = widget.settingsProvider ?? SettingsProvider(storage: _storage);
    _feed =
        widget.feedProvider ??
        FeedProvider(
          storage: _storage,
          audioService: _audio,
          notificationService: _notifications,
        );
    _settings.addListener(_syncSettings);
    _feed.addListener(_syncWakelock);
    Future.wait([_settings.ready, _feed.ready]).then((_) {
      if (!mounted) return;
      _syncSettings();
      _syncWakelock();
    });
    if (widget.enablePlatformEffects) unawaited(_initializeNotifications());
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notifications.init();
      await _notifications.requestPermissions();
    } catch (error) {
      // Notification permissions must never prevent access to saved records.
      debugPrint('Notification initialization unavailable: $error');
    }
  }

  void _syncSettings() {
    if (!mounted || !_settings.isInitialized || !_feed.isInitialized) return;
    _feed.updateSettings(
      feedIntervalMinutes: _settings.feedIntervalMinutes,
      nightModeEnabled: _settings.nightModeEnabled,
      nightStartTime: _settings.nightStartTime,
      nightEndTime: _settings.nightEndTime,
      soundEnabled: _settings.soundEnabled,
      soundLoopEnabled: _settings.soundLoopEnabled,
    );
  }

  void _syncWakelock() {
    if (!widget.enablePlatformEffects || !mounted) return;
    final enabled = _foreground && _index == 0 && _feed.lastFeedTime != null;
    if (_wakelock == enabled) return;
    _wakelock = enabled;
    unawaited(
      WakelockPlus.toggle(enable: enabled).catchError((Object error) {
        debugPrint('Wakelock unavailable: $error');
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() => _foreground = foreground);
    _feed.setForeground(foreground);
    _syncWakelock();
  }

  void _selectPage(int index) {
    setState(() => _index = index);
    _syncWakelock();
  }

  void _onDisplayDimmedChanged(bool dimmed) {
    // Home may notify during its own update/build. Keep the shell update out
    // of that frame and preserve Home's element when navigation disappears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _displayDimmed != dimmed) {
        setState(() => _displayDimmed = dimmed);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_syncSettings);
    _feed.removeListener(_syncWakelock);
    if (widget.feedProvider == null) _feed.dispose();
    if (widget.settingsProvider == null) _settings.dispose();
    if (widget.audioService == null) {
      unawaited(
        _audio.dispose().catchError((Object error) {
          debugPrint('Audio cleanup unavailable: $error');
        }),
      );
    }
    if (widget.enablePlatformEffects && _wakelock) {
      unawaited(WakelockPlus.disable().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      Provider<StorageService>.value(value: _storage),
      Provider<AudioService>.value(value: _audio),
      Provider<NotificationService>.value(value: _notifications),
      ChangeNotifierProvider<SettingsProvider>.value(value: _settings),
      ChangeNotifierProvider<FeedProvider>.value(value: _feed),
    ],
    child: Selector<SettingsProvider, ThemeMode>(
      selector: (_, settings) => settings.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        scrollBehavior: const CupertinoScrollBehavior(),
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        builder: (context, child) {
          final dark =
              Theme.of(context).brightness == Brightness.dark ||
              (_index == 0 && _displayDimmed);
          return AppGlass.wrap(
            AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (dark
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: dark
                            ? AppPalette.dark.background
                            : AppPalette.light.background,
                      ),
              child: child!,
            ),
          );
        },
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: _index == 0 && _displayDimmed
                ? AppPalette.dark.background
                : AppPalette.of(context).background,
            body: AppGlassBackdrop(
              dimmed: _index == 0 && _displayDimmed,
              child: SafeArea(
                child: Column(
                  children: [
                    Visibility(
                      visible: !(_index == 0 && _displayDimmed),
                      child: _AppNavigation(
                        index: _index,
                        onSelect: _selectPage,
                      ),
                    ),
                    // Stable element path preserves page state through rotation,
                    // theme changes and standby.
                    Expanded(
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        body: IndexedStack(
                          index: _index,
                          children: [
                            HomeScreen(
                              isActive: _index == 0 && _foreground,
                              onHistoryRequested: () => _selectPage(1),
                              onDisplayDimmedChanged: _onDisplayDimmedChanged,
                            ),
                            const HistoryScreen(),
                            SettingsScreen(
                              isActive: _index == 2 && _foreground,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AppNavigation extends StatelessWidget {
  const _AppNavigation({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        Widget destination(int page, String label, IconData icon, String key) {
          return AppButton(
            key: ValueKey(key),
            onPressed: () => onSelect(page),
            glass: page != 0,
            filled: page == index && page != 0,
            selected: page == index,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 16,
              vertical: 10,
            ),
            child: Semantics(
              selected: page == index,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: compact ? 20 : 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: page == 0
                              ? (compact ? 16 : 20)
                              : (compact ? 14 : 17),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Padding(
              key: const ValueKey('app-navigation'),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 20,
                vertical: MediaQuery.sizeOf(context).height < 360 ? 4 : 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: destination(
                        0,
                        '喂奶提醒',
                        CupertinoIcons.heart_circle,
                        'nav-home',
                      ),
                    ),
                  ),
                  destination(1, '记录', CupertinoIcons.book, 'nav-history'),
                  const SizedBox(width: 8),
                  destination(2, '设置', CupertinoIcons.gear, 'nav-settings'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
