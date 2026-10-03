import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/privacy_service.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_message_dialog.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_surface.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.isActive = true,
    this.previewAudioFactory,
  });

  /// IndexedStack keeps this page mounted after the user changes tabs.
  final bool isActive;

  /// Each screen owns its preview player independently of the real reminder.
  final AudioService Function()? previewAudioFactory;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  AudioService? _previewAudio;
  Timer? _previewTimer;
  bool _previewing = false;
  bool _audioBusy = false;
  bool _permissionBusy = false;
  bool _saving = false;
  bool _editing = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) unawaited(_stopPreview());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stopPreview());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewGeneration++;
    _previewTimer?.cancel();
    final audio = _previewAudio;
    if (audio != null) {
      unawaited(
        audio.dispose().catchError((Object error) {
          debugPrint('Unable to dispose sound preview: $error');
        }),
      );
    }
    super.dispose();
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      _showError('未能保存设置，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (mounted && widget.isActive) showAppNotice(context, message);
  }

  Future<void> _stopPreview() async {
    _previewGeneration++;
    _previewTimer?.cancel();
    try {
      await _previewAudio?.stopReminder();
    } catch (_) {
      _showError('未能停止试听，请重试。');
    } finally {
      if (mounted) {
        setState(() {
          _previewing = _previewAudio?.isPlaying ?? false;
          _audioBusy = false;
        });
      }
    }
  }

  Future<void> _togglePreview() async {
    if (_audioBusy) return;
    if (_previewing) {
      setState(() => _audioBusy = true);
      await _stopPreview();
      return;
    }
    setState(() => _audioBusy = true);
    final generation = ++_previewGeneration;
    try {
      final audio = _previewAudio ??=
          widget.previewAudioFactory?.call() ?? AudioService();
      await audio.playReminder(loop: false);
      if (!mounted || !widget.isActive || generation != _previewGeneration) {
        await audio.stopReminder();
        return;
      }
      setState(() => _previewing = audio.isPlaying);
      _previewTimer?.cancel();
      _previewTimer = Timer.periodic(const Duration(milliseconds: 250), (
        timer,
      ) {
        if (!audio.isPlaying) {
          timer.cancel();
          if (mounted) setState(() => _previewing = false);
        }
      });
    } catch (_) {
      _showError('暂时无法播放提醒音，请重试。');
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _pickInterval(SettingsProvider settings) async {
    if (_editing || _saving || settings.isSaving) return;
    _editing = true;
    try {
      final minutes = await showCupertinoModalPopup<int>(
        context: context,
        builder: (context) => DefaultTextStyle(
          style: AppTypography.body(context),
          child: _IntervalEditor(initialValue: settings.feedIntervalMinutes),
        ),
      );
      if (minutes != null && mounted) {
        await _save(() => settings.setFeedInterval(minutes));
      }
    } finally {
      _editing = false;
    }
  }

  Future<void> _pickTime(
    String title,
    String value,
    Future<void> Function(String) save,
  ) async {
    if (_editing || _saving) return;
    _editing = true;
    try {
      final parts = value.split(':');
      final hour = parts.isNotEmpty ? int.tryParse(parts.first) : null;
      final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
      final today = DateTime.now();
      final time = await showAppDateTimePicker(
        context,
        title: title,
        mode: CupertinoDatePickerMode.time,
        initial: DateTime(
          today.year,
          today.month,
          today.day,
          (hour ?? 22).clamp(0, 23),
          (minute ?? 0).clamp(0, 59),
        ),
      );
      if (time != null && mounted) {
        final formatted =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        await _save(() => save(formatted));
      }
    } finally {
      _editing = false;
    }
  }

  Future<void> _openNotificationSettings() async {
    final result = await context
        .read<NotificationService>()
        .openNotificationSettings();
    if (!mounted ||
        !widget.isActive ||
        result != NotificationSettingsResult.needsConfirmation) {
      return;
    }
    // Older HarmonyOS returns while its native sheet is still open. Keep a
    // completion action underneath it so permission changes can resync reminders.
    await Navigator.of(context, rootNavigator: true).push<void>(
      createAppMessageDialogRoute<void>(
        context,
        builder: (dialogContext) => AppMessageDialog(
          title: '系统通知设置',
          icon: CupertinoIcons.bell,
          content: const Text('设置通知后，返回此处点击“完成”，让当前提醒按新的权限设置生效。'),
          actions: [
            AppButton(
              key: const ValueKey('notification-settings-complete'),
              filled: true,
              onPressed: () {
                if (ModalRoute.of(dialogContext)?.isCurrent == true) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPermissionSettings(Future<void> Function() action) async {
    if (_permissionBusy) return;
    setState(() => _permissionBusy = true);
    try {
      await action();
      if (mounted && context.read<NotificationService>().isHarmonyOS) {
        await context.read<FeedProvider>().refresh();
      }
    } catch (_) {
      _showError('无法打开权限设置，请在系统设置中检查应用权限。');
    } finally {
      if (mounted) setState(() => _permissionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final notifications = context.read<NotificationService>();
    final colors = AppPalette.of(context);
    final busy = _saving || settings.isSaving;
    final compact = _compactSettingsLayout(context);
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = AppPageLayout.contentPadding(
            constraints.maxWidth,
          );
          return SingleChildScrollView(
            key: const PageStorageKey('settings-scroll'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppPageLayout.topPadding(compact),
              horizontalPadding,
              40,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppPageLayout.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsHeader(compact: compact, saving: busy),
                    if (settings.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '设置未能完整读取或保存，请重试；若仍失败，请重新打开应用。',
                        style: AppTypography.supporting(
                          context,
                        ).copyWith(color: colors.alert),
                      ),
                    ],
                    SizedBox(height: AppPageLayout.headerGap(compact)),
                    _SettingsGrid(
                      children: [
                        _SettingsGroup(
                          icon: CupertinoIcons.clock,
                          separated: false,
                          title: '喂奶间隔',
                          description: '下一次提醒，从最近一次喂奶开始计算。',
                          children: [
                            _IntervalPreference(
                              minutes: settings.feedIntervalMinutes,
                              busy: busy,
                              onCustom: () => _pickInterval(settings),
                              onSelect: (minutes) => _save(
                                () => settings.setFeedInterval(minutes),
                              ),
                            ),
                          ],
                        ),
                        _SettingsGroup(
                          icon: CupertinoIcons.moon_stars,
                          title: '夜间时段',
                          description: '保留屏幕提醒，把安静留给夜晚。',
                          footer:
                              settings.nightStartTime == settings.nightEndTime
                              ? '开始与结束时间相同，当前不会进入夜间静音。'
                              : '支持跨越午夜，例如 22:00 至次日 06:00。',
                          children: [
                            _ToggleRow(
                              controlKey: const ValueKey('night-mode-switch'),
                              title: '夜间静音',
                              subtitle: '关闭声音和系统通知',
                              value: settings.nightModeEnabled,
                              onChanged: busy
                                  ? null
                                  : (value) => _save(
                                      () => settings.setNightModeEnabled(value),
                                    ),
                            ),
                            const _GroupSeparator(),
                            _TimeControl(
                              controlKey: const ValueKey('night-start-time'),
                              label: '开始时间',
                              value: settings.nightStartTime,
                              onTap: busy || !settings.nightModeEnabled
                                  ? null
                                  : () => _pickTime(
                                      '开始时间',
                                      settings.nightStartTime,
                                      settings.setNightStartTime,
                                    ),
                            ),
                            const _GroupSeparator(),
                            _TimeControl(
                              controlKey: const ValueKey('night-end-time'),
                              label: '结束时间',
                              value: settings.nightEndTime,
                              onTap: busy || !settings.nightModeEnabled
                                  ? null
                                  : () => _pickTime(
                                      '结束时间',
                                      settings.nightEndTime,
                                      settings.setNightEndTime,
                                    ),
                            ),
                          ],
                        ),
                        _SettingsGroup(
                          icon: CupertinoIcons.bell,
                          title: '提醒声音',
                          description: '用声音提醒，或只看一眼计时。',
                          footer: '试听仅播放一次；夜间静音不影响试听。',
                          children: [
                            _ToggleRow(
                              controlKey: const ValueKey(
                                'sound-enabled-switch',
                              ),
                              title: '声音提醒',
                              subtitle: '到达设定时间时播放提醒音',
                              value: settings.soundEnabled,
                              onChanged: busy
                                  ? null
                                  : (value) async {
                                      if (!value) await _stopPreview();
                                      if (mounted) {
                                        await _save(
                                          () => settings.setSoundEnabled(value),
                                        );
                                      }
                                    },
                            ),
                            const _GroupSeparator(),
                            _ToggleRow(
                              controlKey: const ValueKey('sound-loop-switch'),
                              title: '循环播放',
                              subtitle: settings.soundEnabled
                                  ? '应用运行时，持续播放至停止或记录喂奶'
                                  : '开启声音提醒后可设置',
                              value: settings.soundLoopEnabled,
                              onChanged: busy || !settings.soundEnabled
                                  ? null
                                  : (value) => _save(
                                      () => settings.setSoundLoopEnabled(value),
                                    ),
                            ),
                            const _GroupSeparator(),
                            AppButton(
                              key: const ValueKey('sound-preview-button'),
                              compact: true,
                              onPressed: _audioBusy || !settings.soundEnabled
                                  ? null
                                  : _togglePreview,
                              child: _ActionLabel(
                                icon: _previewing
                                    ? CupertinoIcons.stop_fill
                                    : CupertinoIcons.play_fill,
                                label: _previewing ? '停止试听' : '试听提醒音',
                              ),
                            ),
                          ],
                        ),
                        _SettingsGroup(
                          icon: CupertinoIcons.device_phone_portrait,
                          title: '屏幕与外观',
                          description: '白天清晰，入夜柔和。',
                          footer: '有喂奶记录且停留在计时页时，屏幕会保持常亮。切换页面或退出应用后恢复系统设置。',
                          children: [
                            Text('外观主题', style: AppTypography.label(context)),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final option in const [
                                  (
                                    ThemeMode.system,
                                    '跟随系统',
                                    CupertinoIcons.circle_lefthalf_fill,
                                  ),
                                  (
                                    ThemeMode.light,
                                    '浅色',
                                    CupertinoIcons.sun_max,
                                  ),
                                  (ThemeMode.dark, '深色', CupertinoIcons.moon),
                                ])
                                  _PreferenceOption(
                                    controlKey: ValueKey(
                                      'theme-mode-${option.$1.name}',
                                    ),
                                    label: option.$2,
                                    icon: option.$3,
                                    selected: settings.themeMode == option.$1,
                                    onPressed: busy
                                        ? null
                                        : () => _save(
                                            () => settings.setThemeMode(
                                              option.$1,
                                            ),
                                          ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '默认跟随系统；选择浅色或深色后，将保持所选外观。',
                              style: _hintStyle(context),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '外观与夜间静音独立；待机时使用暗色时钟。',
                              style: _hintStyle(context),
                            ),
                            const _GroupSeparator(),
                            _ToggleRow(
                              controlKey: const ValueKey('burn-in-switch'),
                              title: '防烧屏保护',
                              subtitle: '轻微移动计时内容，减少固定像素长亮',
                              value: settings.burnInProtectionEnabled,
                              onChanged: busy
                                  ? null
                                  : (value) => _save(
                                      () => settings.setBurnInProtectionEnabled(
                                        value,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        if (notifications.isSupported) ...[
                          _SettingsGroup(
                            icon: CupertinoIcons.checkmark_shield,
                            title: '系统提醒权限',
                            description: '离开应用后，也能收到下一次提醒。',
                            footer:
                                defaultTargetPlatform == TargetPlatform.android
                                ? '未授权准时提醒时，系统可能延迟发送通知。'
                                : notifications.isHarmonyOS
                                ? '鸿蒙静音提醒默认仅显示在通知中心，后台声音以系统通知设置为准。'
                                : null,
                            children: [
                              _PermissionRow(
                                label: '系统通知权限',
                                subtitle: '前往系统通知设置',
                                icon: CupertinoIcons.bell,
                                onPressed: _permissionBusy
                                    ? null
                                    : () => _openPermissionSettings(
                                        _openNotificationSettings,
                                      ),
                              ),
                              if (defaultTargetPlatform ==
                                  TargetPlatform.android) ...[
                                const _GroupSeparator(),
                                _PermissionRow(
                                  label: '准时提醒权限',
                                  icon: CupertinoIcons.alarm,
                                  onPressed: _permissionBusy
                                      ? null
                                      : () => _openPermissionSettings(
                                          notifications
                                              .requestExactAlarmPermission,
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        _SettingsGroup(
                          icon: CupertinoIcons.doc_text,
                          title: '隐私政策',
                          description: '了解记录如何保存，以及如何管理和删除数据。',
                          children: [
                            _PermissionRow(
                              label: '阅读隐私政策',
                              subtitle: PrivacyService.usesHostedPolicy
                                  ? '查看华为托管的隐私声明'
                                  : '无需联网，随时查看完整内容',
                              icon: CupertinoIcons.doc_text,
                              onPressed: () => showPrivacyPolicy(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

bool _compactSettingsLayout(BuildContext context) {
  return AppPageLayout.compact(context);
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.compact, required this.saving});
  final bool compact;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (saving)
          CupertinoActivityIndicator(radius: 7, color: colors.primary)
        else
          Icon(CupertinoIcons.checkmark, size: 13, color: colors.textSecondary),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            saving ? '正在保存…' : '更改会自动保存',
            style: AppTypography.supporting(context),
          ),
        ),
      ],
    );
    return AppPageHeader(
      title: '偏好设置',
      subtitle: '提醒与显示，按你的习惯。',
      compact: compact,
      trailing: status,
    );
  }
}

class _SettingsGrid extends StatelessWidget {
  const _SettingsGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = _compactSettingsLayout(context);
      final twoColumns =
          constraints.maxWidth >= 680 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      return Wrap(
        spacing: 48,
        runSpacing: compact ? 30 : 40,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(
              width: twoColumns && i > 0
                  ? (constraints.maxWidth - 48) / 2
                  : constraints.maxWidth,
              child: children[i],
            ),
        ],
      );
    },
  );
}

TextStyle _descriptionStyle(BuildContext context) =>
    AppTypography.supporting(context);
TextStyle _hintStyle(BuildContext context) => AppTypography.caption(context);

String _presetLabel(int minutes) =>
    '${minutes % 60 == 0 ? minutes ~/ 60 : minutes / 60} 小时';

class _IntervalPreference extends StatelessWidget {
  const _IntervalPreference({
    required this.minutes,
    required this.busy,
    required this.onCustom,
    required this.onSelect,
  });

  final int minutes;
  final bool busy;
  final VoidCallback onCustom;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final value = Wrap(
      spacing: 16,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          TimeUtils.formatInterval(minutes),
          key: const ValueKey('interval-value'),
          style: TextStyle(
            fontSize: 36,
            height: 1.25,
            fontWeight: FontWeight.w400,
            letterSpacing: -.4,
            color: colors.primary,
          ),
        ),
        AppButton(
          key: const ValueKey('custom-interval-button'),
          compact: true,
          onPressed: busy ? null : onCustom,
          child: const _ActionLabel(
            icon: CupertinoIcons.slider_horizontal_3,
            label: '自定义',
          ),
        ),
      ],
    );
    final presets = Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        for (final preset in [120, 150, 180, 210, 240])
          _PreferenceOption(
            controlKey: ValueKey('interval-preset-$preset'),
            label: _presetLabel(preset),
            selected: minutes == preset,
            onPressed: busy ? null : () => onSelect(preset),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= 960 &&
            MediaQuery.textScalerOf(context).scale(14) <= 18;
        if (horizontal) {
          return Row(
            children: [
              Expanded(child: value),
              const SizedBox(width: 32),
              Flexible(child: presets),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [value, const SizedBox(height: 16), presets],
        );
      },
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
    this.footer,
    this.separated = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;
  final String? footer;
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final compact = _compactSettingsLayout(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (separated) Container(height: 1, color: colors.border),
        SizedBox(height: compact ? 16 : 20),
        Row(
          children: [
            Expanded(
              child: Text(title, style: AppTypography.sectionTitle(context)),
            ),
            const SizedBox(width: 16),
            Icon(icon, size: 21, color: colors.textSecondary),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(description, style: _descriptionStyle(context)),
        SizedBox(height: compact ? 16 : 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
        if (footer != null) ...[
          const SizedBox(height: 16),
          Text(footer!, style: _hintStyle(context)),
        ],
      ],
    );
  }
}

class _GroupSeparator extends StatelessWidget {
  const _GroupSeparator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(
      height: 1,
      color: AppPalette.of(context).border.withValues(alpha: .7),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.controlKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key controlKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.label(context)),
                const SizedBox(height: 5),
                Text(subtitle, style: _hintStyle(context)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            key: controlKey,
            value: value,
            onChanged: onChanged,
            activeTrackColor: colors.primary,
          ),
        ],
      ),
    );
  }
}

class _PreferenceOption extends StatelessWidget {
  const _PreferenceOption({
    required this.controlKey,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
  });

  final Key controlKey;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final foreground = selected ? colors.primary : colors.textSecondary;
    return AppPressable(
      key: controlKey,
      onPressed: onPressed,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: .07)
              : colors.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: .7)
                : colors.border,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                style: AppTypography.button.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeControl extends StatelessWidget {
  const _TimeControl({
    required this.controlKey,
    required this.label,
    required this.value,
    this.onTap,
  });

  final Key controlKey;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final color = onTap == null ? colors.textSecondary : colors.primary;
    return AppPressable(
      key: controlKey,
      onPressed: onTap,
      semanticLabel: '$label $value',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final time = ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -.3,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(CupertinoIcons.chevron_forward, size: 13, color: color),
                ],
              ),
            );
            final labelText = Text(label, style: AppTypography.label(context));
            if (MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 10), time],
              );
            }
            return Row(
              children: [
                Expanded(child: labelText),
                const SizedBox(width: 16),
                time,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 8),
      Flexible(child: Text(label)),
    ],
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    this.subtitle = '前往系统授权',
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onPressed: onPressed,
      semanticLabel: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.label(context)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: _hintStyle(context)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalEditor extends StatefulWidget {
  const _IntervalEditor({required this.initialValue});
  final int initialValue;

  @override
  State<_IntervalEditor> createState() => _IntervalEditorState();
}

class _IntervalEditorState extends State<_IntervalEditor> {
  late final TextEditingController _controller;
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_closing) return;
    final value = int.tryParse(_controller.text);
    if (value == null || value < 1 || value > 1440) {
      setState(() => _error = '请输入 1–1440 之间的整数');
      return;
    }
    _close(value);
  }

  void _close([int? value]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: AppSurface(
                radius: 24,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('自定义喂奶间隔', style: AppTypography.dialogTitle(context)),
                    const SizedBox(height: 12),
                    Text(
                      '选择适合宝宝的节奏。保存后，当前计时会按新间隔重新计算。',
                      style: _descriptionStyle(context),
                    ),
                    const SizedBox(height: 28),
                    Text('间隔时长', style: _hintStyle(context)),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      key: const ValueKey('custom-interval-field'),
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w400,
                        color: colors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      cursorColor: colors.primary,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _error == null ? colors.border : colors.alert,
                          width: 1,
                        ),
                      ),
                      suffix: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text('分钟', style: _descriptionStyle(context)),
                      ),
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text('可设置 1–1440 分钟', style: _hintStyle(context)),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: AppTypography.supporting(
                          context,
                        ).copyWith(color: colors.alert),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        AppButton(onPressed: _close, child: const Text('取消')),
                        AppButton(
                          filled: true,
                          onPressed: _submit,
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
