import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'widgets/app_surface.dart';
import 'widgets/app_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/settings_screen.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'services/privacy_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/constants.dart';
import 'utils/privacy_policy.dart';
import 'utils/time_utils.dart';
import 'widgets/app_message_dialog.dart';

/// Uses platform-managed consent on HarmonyOS and a local notice elsewhere.
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

class _FeedReminderAppState extends State<FeedReminderApp> {
  late final StorageService _storage;
  bool _checkingConsent = true;
  bool _accepted = false;
  bool _savingConsent = false;
  bool _consentReadFailed = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? StorageService();
    // AppGallery's hosted declaration is presented by HarmonyOS at launch.
    // A second, app-owned notice would conflict with the hosted consent flow.
    if (PrivacyService.usesHostedPolicy) {
      _accepted = true;
      _checkingConsent = false;
    } else {
      unawaited(_readConsent());
    }
  }

  Future<void> _readConsent() async {
    setState(() {
      _checkingConsent = true;
      _consentReadFailed = false;
      _notice = null;
    });
    try {
      final version = await _storage.getAcceptedPrivacyPolicyVersion();
      if (!mounted) return;
      setState(() {
        _accepted = version == PrivacyPolicy.version;
        _checkingConsent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingConsent = false;
        _consentReadFailed = true;
        _notice = '无法读取隐私确认状态，请重试。';
      });
    }
  }

  Future<void> _acceptPrivacyPolicy() async {
    setState(() {
      _savingConsent = true;
      _notice = null;
    });
    try {
      await _storage.setAcceptedPrivacyPolicyVersion(PrivacyPolicy.version);
      if (!mounted) return;
      // Persist first: failed saves must not start providers, restore reminders,
      // or trigger a system permission prompt, including after an upgrade.
      setState(() => _accepted = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingConsent = false;
        _notice = '隐私确认保存失败，请重试。同意成功前不会启动记录与提醒功能。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) {
      return _ConsentedFeedReminderApp(
        storage: _storage,
        audioService: widget.audioService,
        notificationService: widget.notificationService,
        feedProvider: widget.feedProvider,
        settingsProvider: widget.settingsProvider,
        enablePlatformEffects: widget.enablePlatformEffects,
      );
    }
    return MaterialApp(
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
      home: Builder(
        builder: (context) => PopScope(
          canPop: false,
          child: Scaffold(
            body: AppBackdrop(
              child: _checkingConsent
                  ? const Center(child: CircularProgressIndicator())
                  : AppMessageDialog(
                      key: const ValueKey('privacy-consent-dialog'),
                      title: '欢迎使用奶点记',
                      icon: CupertinoIcons.hand_raised,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(PrivacyPolicy.notice),
                          const SizedBox(height: 12),
                          AppButton(
                            key: const ValueKey('privacy-policy-read'),
                            onPressed: _savingConsent
                                ? null
                                : () => showPrivacyPolicy(context),
                            child: Text(
                              '阅读《隐私政策》',
                              style: TextStyle(
                                color: AppPalette.of(context).primary,
                              ),
                            ),
                          ),
                          if (_notice != null) ...[
                            const SizedBox(height: 12),
                            Semantics(liveRegion: true, child: Text(_notice!)),
                          ],
                        ],
                      ),
                      actions: [
                        AppButton(
                          key: const ValueKey('privacy-consent-decline'),
                          onPressed: _savingConsent
                              ? null
                              : () => setState(() {
                                  _notice = '您暂未同意，可继续阅读隐私政策，再决定是否使用奶点记。';
                                }),
                          child: const Text('暂不同意'),
                        ),
                        if (_consentReadFailed)
                          AppButton(
                            key: const ValueKey('privacy-consent-retry'),
                            filled: true,
                            onPressed: _readConsent,
                            child: const Text('重试'),
                          )
                        else
                          AppButton(
                            key: const ValueKey('privacy-consent-accept'),
                            filled: true,
                            onPressed: _savingConsent
                                ? null
                                : _acceptPrivacyPolicy,
                            child: Text(_savingConsent ? '正在保存…' : '同意并继续'),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns service lifetimes only after the current privacy policy is accepted.
class _ConsentedFeedReminderApp extends StatefulWidget {
  const _ConsentedFeedReminderApp({
    required this.storage,
    this.audioService,
    this.notificationService,
    this.feedProvider,
    this.settingsProvider,
    required this.enablePlatformEffects,
  });

  final StorageService storage;
  final AudioService? audioService;
  final NotificationService? notificationService;
  final FeedProvider? feedProvider;
  final SettingsProvider? settingsProvider;
  final bool enablePlatformEffects;

  @override
  State<_ConsentedFeedReminderApp> createState() =>
      _ConsentedFeedReminderAppState();
}

class _ConsentedFeedReminderAppState extends State<_ConsentedFeedReminderApp>
    with WidgetsBindingObserver {
  static const _systemUiChannel = MethodChannel('feed_reminder/system_ui');
  late final StorageService _storage;
  late final AudioService _audio;
  late final NotificationService _notifications;
  late final SettingsProvider _settings;
  late final FeedProvider _feed;
  int _index = 0;
  late bool _foreground;
  bool _initializingNotifications = false;
  bool _notificationPermissionsRequested = false;
  bool _wakelock = false;
  bool _displayDimmed = false;
  bool? _systemBarsHidden;
  Future<void> _systemUiUpdates = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A consent read/write may finish after the app has already backgrounded.
    // Inherit that state instead of treating this newly mounted shell as active.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _storage = widget.storage;
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
    _feed.setForeground(_foreground);
    _settings.addListener(_syncSettings);
    _feed.addListener(_syncWakelock);
    Future.wait([_settings.ready, _feed.ready]).then((_) {
      if (!mounted) return;
      _syncSettings();
      _syncWakelock();
    });
    if (widget.enablePlatformEffects) {
      _syncSystemUi();
      unawaited(_initializeNotifications());
    }
  }

  void _syncSystemUi({bool restore = false, bool force = false}) {
    if (!widget.enablePlatformEffects ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            !_notifications.isHarmonyOS)) {
      return;
    }
    final hidden = !restore && _foreground && _index == 0 && _displayDimmed;
    if (!force && _systemBarsHidden == hidden) return;
    _systemBarsHidden = hidden;
    // Serialize native changes so a delayed hide cannot override wake/dispose.
    _systemUiUpdates = _systemUiUpdates.then((_) async {
      try {
        if (!_notifications.isHarmonyOS &&
            defaultTargetPlatform == TargetPlatform.android) {
          if (!hidden) {
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          }
          // Android 16 enforces edge-to-edge layout. Hide only the insets,
          // without switching Flutter to a mode that changes that layout.
          await _systemUiChannel.invokeMethod<void>(
            'setSystemBarsHidden',
            hidden,
          );
        } else {
          // Flutter-OH's mode call lacks a success reply; the manual overlays
          // path both controls the status bar and completes its Future.
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: hidden ? const [] : SystemUiOverlay.values,
          );
        }
      } catch (error) {
        if (_systemBarsHidden == hidden) _systemBarsHidden = null;
        debugPrint('System bar configuration unavailable: $error');
      }
    });
  }

  Future<void> _initializeNotifications() async {
    if (_initializingNotifications ||
        _notificationPermissionsRequested ||
        !_foreground) {
      return;
    }
    _initializingNotifications = true;
    try {
      await _notifications.init();
      if (!mounted || !_foreground) return;
      _notificationPermissionsRequested = true;
      await _notifications.requestPermissions();
      if (mounted && _notifications.isSupported) {
        // Restoring records can attempt scheduling before the permission
        // dialog finishes. Retry once the user has allowed notifications.
        await _feed.refresh();
      }
    } catch (error) {
      // Notification permissions must never prevent access to saved records.
      debugPrint('Notification initialization unavailable: $error');
    } finally {
      _initializingNotifications = false;
    }
  }

  void _syncSettings() {
    if (!mounted || !_settings.isAvailable || !_feed.isInitialized) return;
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
    // Home reports leaving standby after it rebuilds as inactive. A brief
    // focus change without a frame must keep its existing standby state.
    setState(() => _foreground = foreground);
    _feed.setForeground(foreground);
    _syncWakelock();
    _syncSystemUi(force: foreground);
    if (foreground && widget.enablePlatformEffects) {
      unawaited(_initializeNotifications());
    }
  }

  void _selectPage(int index) {
    setState(() {
      _index = index;
      if (index != 0) _displayDimmed = false;
    });
    _syncWakelock();
    _syncSystemUi();
  }

  void _onDisplayDimmedChanged(bool dimmed) {
    // Home may notify during its own update/build. Keep the shell update out
    // of that frame and preserve Home's element when navigation disappears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final active = dimmed && _foreground && _index == 0;
      if (_displayDimmed != active) {
        setState(() => _displayDimmed = active);
        _syncSystemUi();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSystemUi(restore: true);
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
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarDividerColor: Colors.transparent,
                      systemNavigationBarIconBrightness: dark
                          ? Brightness.light
                          : Brightness.dark,
                      systemNavigationBarContrastEnforced: false,
                      systemStatusBarContrastEnforced: false,
                    ),
            child: child!,
          );
        },
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: _index == 0 && _displayDimmed
                ? AppPalette.dark.background
                : AppPalette.of(context).background,
            body: AppBackdrop(
              dimmed: _index == 0 && _displayDimmed,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = MediaQuery.sizeOf(context);
                    final rail = size.width >= 600 && size.width > size.height;
                    return Flex(
                      direction: rail ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      verticalDirection: rail
                          ? VerticalDirection.down
                          : VerticalDirection.up,
                      children: [
                        Visibility(
                          visible: !(_index == 0 && _displayDimmed),
                          child: _AppNavigation(
                            index: _index,
                            onSelect: _selectPage,
                            rail: rail,
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
                                  onDisplayDimmedChanged:
                                      _onDisplayDimmedChanged,
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
                    );
                  },
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
  const _AppNavigation({
    required this.index,
    required this.onSelect,
    required this.rail,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final width = (MediaQuery.sizeOf(context).width * .257).clamp(180.0, 260.0);
    Widget destination(int page, String label, String key) {
      final active = index == page;
      return Expanded(
        child: AppPressable(
          key: ValueKey(key),
          onPressed: () => onSelect(page),
          semanticLabel: label,
          excludeSemantics: true,
          selected: active,
          child: SizedBox(
            height: rail ? 48 : 54,
            child: Column(
              crossAxisAlignment: rail
                  ? (page == 0
                        ? CrossAxisAlignment.start
                        : page == 2
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.center)
                  : CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: rail ? 17 : 16,
                        color: active ? p.primary : p.textSecondary,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: 32,
                  height: 2,
                  color: active ? p.primary : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final navigation = Row(
      children: [
        destination(0, '计时', 'nav-home'),
        destination(1, '记录', 'nav-history'),
        destination(2, '设置', 'nav-settings'),
      ],
    );
    return Container(
      key: const ValueKey('app-navigation'),
      width: rail ? width : double.infinity,
      padding: EdgeInsets.fromLTRB(
        rail ? (width >= 210 ? 27 : 16) : 24,
        rail ? 24 : 3,
        rail ? (width >= 210 ? 18 : 16) : 24,
        rail ? 16 : 3,
      ),
      decoration: BoxDecoration(
        color: p.background,
        border: rail
            ? Border(right: BorderSide(color: p.border, width: .7))
            : Border(top: BorderSide(color: p.border, width: .7)),
      ),
      child: !rail
          ? navigation
          : SingleChildScrollView(
              child:
                  Selector<
                    FeedProvider,
                    ({DateTime day, DateTime? last, int count})
                  >(
                    selector: (_, feed) => (
                      day: DateUtils.dateOnly(feed.referenceTime),
                      last: feed.lastFeedTime,
                      count: feed.todayRecords.length,
                    ),
                    builder: (context, data, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            AppStrings.appName,
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 28,
                              fontWeight: FontWeight.w400,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${data.day.month}月${data.day.day}日  周${'一二三四五六日'[data.day.weekday - 1]}',
                            style: TextStyle(
                              fontSize: 14,
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Container(width: 35, height: 1, color: p.primary),
                        const SizedBox(height: 18),
                        navigation,
                        const SizedBox(height: 12),
                        Divider(color: p.border, height: 1),
                        const SizedBox(height: 17),
                        Text(
                          '上次',
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            data.last == null
                                ? '— —'
                                : TimeUtils.formatTime(data.last!),
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.2,
                              color: p.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (data.last != null)
                          Selector<FeedProvider, Duration>(
                            selector: (_, feed) => feed.timeElapsed,
                            builder: (context, elapsed, _) => Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '已间隔 ${TimeUtils.formatDuration(elapsed)}',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Divider(color: p.border, height: 1),
                        const SizedBox(height: 13),
                        AppPressable(
                          onPressed: () => onSelect(1),
                          semanticLabel: '查看今日喂奶记录',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '今天',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${data.count}',
                                        style: const TextStyle(fontSize: 34),
                                      ),
                                      const TextSpan(
                                        text: ' 次',
                                        style: TextStyle(fontSize: 20),
                                      ),
                                    ],
                                  ),
                                  style: TextStyle(
                                    height: 1.2,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
    );
  }
}
