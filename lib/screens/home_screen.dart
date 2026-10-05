import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_haptics.dart';
import '../utils/constants.dart';
import '../theme/app_typography.dart';
import '../utils/time_utils.dart';
import '../widgets/add_feed_record_dialog.dart';
import '../widgets/app_controls.dart';
import '../widgets/meal_amount_dialog.dart';
import '../widgets/snooze_reminder_dialog.dart';
import '../widgets/feed_load_failure.dart';

import '../widgets/landscape_feed_panel.dart';
import '../widgets/countdown_text.dart';
import '../widgets/overdue_duration.dart';

class HomeScreen extends StatefulWidget {
  final bool isActive;
  final int wakeRevision;
  final VoidCallback? onHistoryRequested;
  final ValueChanged<bool>? onDisplayDimmedChanged;
  const HomeScreen({
    super.key,
    this.isActive = true,
    this.wakeRevision = 0,
    this.onHistoryRequested,
    this.onDisplayDimmedChanged,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _idleTimer;
  Duration _idleFor = Duration.zero;
  bool _dimmed = false;
  int _offset = 0;
  String? _lastRecordedId;
  int? _mealAmountOverride;
  bool _adjustingMeal = false;
  bool _choosingSnooze = false;
  bool _stoppingAlert = false;
  final FocusNode _standbyFocus = FocusNode(debugLabel: 'Standby wake control');
  FocusNode? _focusBeforeStandby;
  LogicalKeyboardKey? _wakeKey;
  FeedProvider? _feed;
  SettingsProvider? _settings;
  DateTime? _alertDeadline;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final feed = context.read<FeedProvider>();
    final settings = context.read<SettingsProvider>();
    if (_feed != feed) {
      _feed?.removeListener(_checkStandbyConditions);
      _feed = feed..addListener(_checkStandbyConditions);
      _alertDeadline = feed.state == FeedState.alerting
          ? feed.nextFeedTime
          : null;
    }
    if (_settings != settings) {
      _settings?.removeListener(_checkStandbyConditions);
      _settings = settings..addListener(_checkStandbyConditions);
    }
  }

  void _checkStandbyConditions() {
    final alertDeadline = _feed!.state == FeedState.alerting
        ? _feed!.nextFeedTime
        : null;
    final newAlert = alertDeadline != null && alertDeadline != _alertDeadline;
    _alertDeadline = alertDeadline;
    // Wake once when a feeding becomes due, then allow idle protection again.
    // Per-second updates and acknowledging that same alert must not wake it.
    // The overlay, navigation and keyboard focus must wake together. Waiting
    // for the five-second idle timer left the visible controls unfocusable.
    if (newAlert ||
        (_dimmed &&
            (!_settings!.burnInProtectionEnabled ||
                _feed!.lastFeedTime == null))) {
      _wake();
    }
  }

  @override
  void initState() {
    super.initState();
    _idleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !widget.isActive) return;
      final settings = context.read<SettingsProvider>();
      final feed = context.read<FeedProvider>();
      _idleFor += const Duration(seconds: 5);
      final shouldDim =
          settings.burnInProtectionEnabled &&
          feed.lastFeedTime != null &&
          _idleFor >= const Duration(seconds: 30) &&
          (ModalRoute.of(context)?.isCurrent ?? true);
      if (shouldDim || _dimmed) {
        final changed = _dimmed != shouldDim;
        setState(() {
          _dimmed = shouldDim;
          _offset++;
        });
        if (changed) {
          if (shouldDim) {
            _focusBeforeStandby = FocusManager.instance.primaryFocus;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _dimmed && widget.isActive) {
                _standbyFocus.requestFocus();
              }
            });
          } else {
            _restoreFocusAfterWake();
          }
          widget.onDisplayDimmedChanged?.call(shouldDim);
        }
      }
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wakeRevision != oldWidget.wakeRevision) _wake();
    if (widget.isActive != oldWidget.isActive) {
      if (_dimmed) widget.onDisplayDimmedChanged?.call(false);
      _dimmed = false;
      _idleFor = Duration.zero;
      _wakeKey = null;
      _focusBeforeStandby = null;
      if (_standbyFocus.hasPrimaryFocus) _standbyFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _feed?.removeListener(_checkStandbyConditions);
    _settings?.removeListener(_checkStandbyConditions);
    _standbyFocus.dispose();
    super.dispose();
  }

  void _wake() {
    _idleFor = Duration.zero;
    if (_dimmed) {
      setState(() => _dimmed = false);
      widget.onDisplayDimmedChanged?.call(false);
      if (_wakeKey == null) _restoreFocusAfterWake();
    }
  }

  void _restoreFocusAfterWake() {
    final previous = _focusBeforeStandby;
    _focusBeforeStandby = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dimmed || !widget.isActive || _wakeKey != null) return;
      if (previous != null &&
          previous.context?.mounted == true &&
          previous.canRequestFocus) {
        previous.requestFocus();
      } else if (_standbyFocus.hasPrimaryFocus) {
        _standbyFocus.unfocus();
      }
    });
  }

  KeyEventResult _handleStandbyKey(FocusNode node, KeyEvent event) {
    if (_wakeKey != null) {
      // Keep the wake key (including repeats) away from the newly visible
      // controls until release. A held Enter must never record a feeding.
      if (event is KeyUpEvent && event.logicalKey == _wakeKey) {
        setState(() => _wakeKey = null);
        _restoreFocusAfterWake();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      _idleFor = Duration.zero;
      if (_dimmed) {
        _wakeKey = event.logicalKey;
        _wake();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _stopAlert() async {
    final feed = context.read<FeedProvider>();
    if (_stoppingAlert || feed.isStoppingAlert) return;
    _stoppingAlert = true;
    _wake();
    try {
      await feed.stopAlert();
      if (mounted && widget.isActive) AppHaptics.success();
    } catch (_) {
      if (mounted && widget.isActive) {
        AppHaptics.warning();
        showAppNotice(context, '停止提醒未完成，请重试');
      }
    } finally {
      _stoppingAlert = false;
    }
  }

  Future<void> _recordFeed() async {
    _wake();
    final feed = context.read<FeedProvider>();
    final settings = context.read<SettingsProvider>();
    await settings.ready;
    if (!mounted) return;
    if (!settings.isAvailable) throw StateError('默认奶量尚未读取，请稍后重试');
    final previousIds = {for (final record in feed.feedHistory) record.id};
    final amount = _mealAmountOverride ?? settings.defaultMilkAmountMl;
    await feed.recordFeed(milkAmountMl: amount);
    if (!mounted) return;
    // A corrected system clock can put this feeding before a saved record.
    // Undo follows the inserted identity, independently of chronological order.
    _lastRecordedId = feed.feedHistory
        .where((record) => !previousIds.contains(record.id))
        .firstOrNull
        ?.id;
    setState(() => _mealAmountOverride = null);
  }

  Future<void> _adjustMealAmount() async {
    final settings = context.read<SettingsProvider>();
    final feed = context.read<FeedProvider>();
    if (_adjustingMeal || feed.isSaving || !settings.isAvailable) return;
    _wake();
    setState(() => _adjustingMeal = true);
    try {
      final choice = await showMealAmountDialog(
        context,
        currentAmount: _mealAmountOverride ?? settings.defaultMilkAmountMl,
        defaultAmount: settings.defaultMilkAmountMl,
      );
      if (mounted && choice != null) {
        final before = _mealAmountOverride ?? settings.defaultMilkAmountMl;
        final after = choice.amount ?? settings.defaultMilkAmountMl;
        setState(() => _mealAmountOverride = choice.amount);
        if (widget.isActive && before != after) AppHaptics.selection();
      }
    } finally {
      if (mounted) setState(() => _adjustingMeal = false);
    }
  }

  Future<void> _snoozeAlert() async {
    final feed = context.read<FeedProvider>();
    if (_choosingSnooze || feed.isSaving || feed.isAlertAcknowledged) return;
    _wake();
    setState(() => _choosingSnooze = true);
    try {
      final minutes = await showSnoozeReminderDialog(context);
      if (!mounted || minutes == null) return;
      await feed.snoozeAlert(minutes);
      if (mounted && widget.isActive) AppHaptics.success();
    } catch (_) {
      if (mounted && widget.isActive) {
        AppHaptics.warning();
        showAppNotice(context, '未能延后提醒，请确认当前提醒状态后重试。');
      }
    } finally {
      if (mounted) setState(() => _choosingSnooze = false);
    }
  }

  Future<void> _undoFeed() async {
    _wake();
    final feed = context.read<FeedProvider>();
    final id = _lastRecordedId;
    final index = feed.feedHistory.indexWhere((record) => record.id == id);
    if (index >= 0) await feed.deleteFeedRecord(index);
    if (_lastRecordedId == id) _lastRecordedId = null;
  }

  @override
  Widget build(
    BuildContext context,
  ) => Consumer2<FeedProvider, SettingsProvider>(
    builder: (context, feed, settings, _) {
      if (feed.isInitialized && !feed.isAvailable) {
        return const FeedLoadFailure();
      }
      final size = MediaQuery.sizeOf(context);
      final landscape = size.width >= 600 && size.width > size.height;
      final overdue = feed.state == FeedState.alerting;
      final standbyLabel = overdue ? '超时' : '距离下次喂奶';
      final standbyTime = TimeUtils.formatDuration(
        overdue ? feed.overdue : feed.timeRemaining,
      );
      final quiet =
          settings.nightModeEnabled &&
          TimeUtils.isInNightMode(
            settings.nightStartTime,
            settings.nightEndTime,
            now: feed.referenceTime,
          );
      return Listener(
        onPointerDown: (_) => _wake(),
        child: Focus(
          focusNode: _standbyFocus,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: _handleStandbyKey,
          child: Stack(
            children: [
              ExcludeFocus(
                excluding: _dimmed || _wakeKey != null,
                child: LandscapeFeedPanel(
                  feed: feed,
                  isActive: widget.isActive,
                  defaultMilkAmountMl:
                      _mealAmountOverride ?? settings.defaultMilkAmountMl,
                  recordingEnabled:
                      feed.isAvailable &&
                      settings.isAvailable &&
                      !_adjustingMeal,
                  isMilkAmountAdjusted: _mealAmountOverride != null,
                  onAdjustMilk: _adjustMealAmount,
                  quiet: quiet,
                  pulseEnabled: widget.isActive && !_dimmed,
                  onRecord: _recordFeed,
                  onUndo: _undoFeed,
                  onStopAlert: _stopAlert,
                  onSnooze: _choosingSnooze ? null : _snoozeAlert,
                  onHistory: widget.onHistoryRequested,
                  onBackfill: () {
                    _wake();
                    showAddFeedRecordDialog(context);
                  },
                ),
              ),
              if (_dimmed &&
                  widget.isActive &&
                  settings.burnInProtectionEnabled &&
                  feed.lastFeedTime != null)
                Positioned.fill(
                  child: BlockSemantics(
                    child: Semantics(
                      key: const ValueKey('standby-screen'),
                      excludeSemantics: true,
                      button: true,
                      label: '$standbyLabel $standbyTime，轻触唤醒屏幕',
                      onTap: _wake,
                      child: GestureDetector(
                        onTap: _wake,
                        behavior: HitTestBehavior.opaque,
                        child: ColoredBox(
                          color: AppPalette.dark.background,
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(
                                math.sin(_offset.toDouble()) * 14,
                                math.cos(_offset.toDouble()) * 14,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: overdue
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OverdueDuration(
                                              duration: feed.overdue,
                                              color: AppPalette.dark.alert,
                                              fontSize:
                                                  CountdownText.timerFontSize(
                                                    landscape,
                                                  ),
                                              unitFontSize: 24,
                                              pulse: true,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              '轻触唤醒',
                                              style:
                                                  AppTypography.supporting(
                                                    context,
                                                  ).copyWith(
                                                    color: AppPalette
                                                        .dark
                                                        .textSecondary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              standbyLabel,
                                              style: TextStyle(
                                                color: AppPalette
                                                    .dark
                                                    .textSecondary,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: CountdownText(
                                                standbyTime,
                                                fontSize:
                                                    CountdownText.timerFontSize(
                                                      landscape,
                                                    ),
                                                color: AppPalette.dark.primary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '下次 ${TimeUtils.formatTime(feed.nextFeedTime!)} · 轻触唤醒',
                                            style:
                                                AppTypography.supporting(
                                                  context,
                                                ).copyWith(
                                                  color: AppPalette
                                                      .dark
                                                      .textSecondary,
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
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
