import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_glass.dart';

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
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            color: AppPalette.of(context).textPrimary,
          ),
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

  Future<void> _requestPermission(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _showError('无法打开权限设置，请在系统设置中检查应用权限。');
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
      child: SingleChildScrollView(
        key: const PageStorageKey('settings-scroll'),
        padding: EdgeInsets.fromLTRB(24, compact ? 12 : 24, 24, 36),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsHeader(compact: compact, saving: busy),
                if (settings.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '设置未能完整读取或保存，请重试；若仍失败，请重新打开应用。',
                    style: TextStyle(
                      color: colors.alert,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
                SizedBox(height: compact ? 18 : 32),
                _SettingsGrid(
                  children: [
                    _SettingsGroup(
                      icon: CupertinoIcons.clock,
                      title: '喂奶间隔',
                      description: '根据最近一条喂奶记录，计算下次提醒。',
                      footer: '支持 1–1440 分钟，也可以随时调整。',
                      children: [
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _intervalLabel(settings.feedIntervalMinutes),
                              key: const ValueKey('interval-value'),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.8,
                                color: colors.primary,
                                height: 1.2,
                              ),
                            ),
                            AppButton(
                              key: const ValueKey('custom-interval-button'),
                              compact: true,
                              onPressed: busy
                                  ? null
                                  : () => _pickInterval(settings),
                              child: const _ActionLabel(
                                icon: CupertinoIcons.pencil,
                                label: '自定义',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 9,
                          runSpacing: 10,
                          children: [
                            for (final minutes in [120, 150, 180, 210, 240])
                              _GlassOption(
                                controlKey: ValueKey(
                                  'interval-preset-$minutes',
                                ),
                                label: _presetLabel(minutes),
                                selected:
                                    settings.feedIntervalMinutes == minutes,
                                onPressed: busy
                                    ? null
                                    : () => _save(
                                        () => settings.setFeedInterval(minutes),
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    _SettingsGroup(
                      icon: CupertinoIcons.moon_stars,
                      title: '安静的夜晚',
                      description: '夜间时段只在应用内显示提醒，保持安静。',
                      footer: settings.nightStartTime == settings.nightEndTime
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
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final controls = [
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
                            ];
                            if (constraints.maxWidth < 350 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    20) {
                              return Column(
                                children: [
                                  controls.first,
                                  const SizedBox(height: 12),
                                  controls.last,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: controls.first),
                                const SizedBox(width: 12),
                                Expanded(child: controls.last),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    _SettingsGroup(
                      icon: CupertinoIcons.bell,
                      title: '提醒声音',
                      description: '选择适合当下环境的提醒方式。',
                      footer: '试听只播放一次，不受夜间静音时段限制。',
                      children: [
                        _ToggleRow(
                          controlKey: const ValueKey('sound-enabled-switch'),
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
                        const SizedBox(height: 22),
                        AppButton(
                          key: const ValueKey('sound-preview-button'),
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
                      title: '屏幕与显示',
                      description: '让床头的计时屏幕也保持舒适。',
                      footer: '有喂奶记录且停留在计时页时，屏幕会保持常亮。切换页面或退出应用后恢复系统设置。',
                      children: [
                        Text(
                          '外观主题',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
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
                              (ThemeMode.light, '浅色', CupertinoIcons.sun_max),
                              (ThemeMode.dark, '深色', CupertinoIcons.moon),
                            ])
                              _GlassOption(
                                controlKey: ValueKey(
                                  'theme-mode-${option.$1.name}',
                                ),
                                label: option.$2,
                                icon: option.$3,
                                selected: settings.themeMode == option.$1,
                                onPressed: busy
                                    ? null
                                    : () => _save(
                                        () => settings.setThemeMode(option.$1),
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
                          '外观选择不影响夜间静音；防烧屏待机仍使用暗色时钟。',
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
                        description: '允许系统通知，才能在离开应用后接收提醒。',
                        footer: defaultTargetPlatform == TargetPlatform.android
                            ? '未授权准时提醒时，系统可能延迟发送通知。'
                            : null,
                        children: [
                          _PermissionRow(
                            label: '系统通知权限',
                            icon: CupertinoIcons.bell,
                            onPressed: () => _requestPermission(
                              notifications.requestPermissions,
                            ),
                          ),
                          if (defaultTargetPlatform ==
                              TargetPlatform.android) ...[
                            const _GroupSeparator(),
                            _PermissionRow(
                              label: '准时提醒权限',
                              icon: CupertinoIcons.alarm,
                              onPressed: () => _requestPermission(
                                notifications.requestExactAlarmPermission,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _compactSettingsLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height &&
      size.height < 600 &&
      MediaQuery.textScalerOf(context).scale(14) <= 20;
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
          Icon(
            CupertinoIcons.checkmark_circle,
            size: 15,
            color: colors.primary,
          ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(saving ? '正在保存…' : '更改会自动保存', style: _hintStyle(context)),
        ),
      ],
    );
    final title = Text(
      '提醒偏好',
      style: TextStyle(
        fontSize: compact ? 26 : 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        color: colors.textPrimary,
        height: 1.25,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              status,
            ],
          )
        else
          title,
        SizedBox(height: compact ? 6 : 10),
        Text('按你和宝宝的节奏，安排每一次提醒。', style: _descriptionStyle(context)),
        if (!compact) ...[const SizedBox(height: 16), status],
      ],
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
        spacing: 20,
        runSpacing: compact ? 22 : 28,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(
              width: twoColumns && i > 0
                  ? (constraints.maxWidth - 20) / 2
                  : constraints.maxWidth,
              child: children[i],
            ),
        ],
      );
    },
  );
}

TextStyle _descriptionStyle(BuildContext context) => TextStyle(
  fontSize: 14,
  height: 1.6,
  color: AppPalette.of(context).textSecondary,
);
TextStyle _hintStyle(BuildContext context) => TextStyle(
  fontSize: 12,
  height: 1.6,
  color: AppPalette.of(context).textSecondary,
);

String _presetLabel(int minutes) =>
    '${minutes % 60 == 0 ? minutes ~/ 60 : minutes / 60} 小时';

String _intervalLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$remainder 分钟';
  if (remainder == 0) return '$hours 小时';
  return '$hours 小时 $remainder 分钟';
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final compact = _compactSettingsLayout(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, right: 6),
          child: Row(
            children: [
              Icon(icon, size: 19, color: colors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(description, style: _descriptionStyle(context)),
        ),
        SizedBox(height: compact ? 10 : 14),
        AppGlassSurface(
          radius: 28,
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(footer!, style: _hintStyle(context)),
          ),
        ],
      ],
    );
  }
}

class _GroupSeparator extends StatelessWidget {
  const _GroupSeparator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Container(height: .5, color: AppPalette.of(context).border),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
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

class _GlassOption extends StatelessWidget {
  const _GlassOption({
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
    final foreground = selected ? colors.onPrimary : colors.textPrimary;
    return AppPressable(
      key: controlKey,
      onPressed: onPressed,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      child: AppGlassSurface(
        radius: 20,
        tinted: selected,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
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
      child: AppGlassSurface(
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _hintStyle(context)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.5,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 17,
                    color: color,
                  ),
                ],
              ),
            ],
          ),
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
      Icon(icon, size: 17),
      const SizedBox(width: 8),
      Flexible(child: Text(label)),
    ],
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onPressed: onPressed,
      semanticLabel: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, color: colors.textPrimary),
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
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: AppGlassSurface(
                radius: 30,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自定义喂奶间隔',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '输入 1–1440 分钟。修改后，当前计时也会按新间隔重新计算。',
                      style: _descriptionStyle(context),
                    ),
                    const SizedBox(height: 22),
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
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      cursorColor: colors.primary,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.background.withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _error == null ? colors.border : colors.alert,
                          width: .5,
                        ),
                      ),
                      suffix: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text('分钟', style: _descriptionStyle(context)),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.alert,
                          height: 1.5,
                        ),
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
