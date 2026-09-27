import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/feed_provider.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import 'app_controls.dart';
import 'app_glass.dart';

class AddFeedRecordDialog extends StatefulWidget {
  const AddFeedRecordDialog({super.key});

  @override
  State<AddFeedRecordDialog> createState() => _AddFeedRecordDialogState();
}

class _AddFeedRecordDialogState extends State<AddFeedRecordDialog> {
  late DateTime _selectedDate;
  bool _saving = false;
  bool _picking = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = context.read<FeedProvider>().referenceTime;
    _selectedDate = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
  }

  Future<void> _pick({required bool date}) async {
    if (_picking || _saving || _closing) return;
    setState(() => _picking = true);
    final now = context.read<FeedProvider>().referenceTime;
    final day = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    try {
      final selection = await showAppDateTimePicker(
        context,
        initial: _selectedDate,
        minimum: date ? DateTime(2020) : day,
        maximum: date || DateUtils.isSameDay(day, now)
            ? now
            : DateTime(day.year, day.month, day.day, 23, 59, 59),
        mode: date
            ? CupertinoDatePickerMode.date
            : CupertinoDatePickerMode.time,
        title: date ? '选择喂奶日期' : '选择喂奶时间',
      );
      if (!mounted || selection == null) return;
      setState(() {
        _selectedDate = date
            ? DateTime(
                selection.year,
                selection.month,
                selection.day,
                _selectedDate.hour,
                _selectedDate.minute,
              )
            : DateTime(
                day.year,
                day.month,
                day.day,
                selection.hour,
                selection.minute,
              );
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final provider = context.read<FeedProvider>();
    if (_saving || _picking || _closing || provider.isSaving) return;
    if (_selectedDate.isAfter(provider.referenceTime)) {
      setState(() => _error = AppStrings.futureTimeError);
      return;
    }
    if (_selectedDate.isBefore(DateTime(2020))) {
      setState(() => _error = '请选择 2020 年以后的日期');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await provider.addFeedRecordWithTime(_selectedDate);
      if (!mounted) return;
      setState(() => _saving = false);
      _close(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请重试';
      });
    }
  }

  void _close(bool saved) {
    if (_closing || _saving || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _closing = true;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width > size.height && size.height <= 500;
    final isFuture = _selectedDate.isAfter(
      context.read<FeedProvider>().referenceTime,
    );
    final error = isFuture ? AppStrings.futureTimeError : _error;
    final providerSaving = context.select<FeedProvider, bool>(
      (provider) => provider.isSaving,
    );
    final disabled = _saving || _picking || providerSaving;
    final dateField = _PickerField(
      key: const ValueKey('add-feed-date-field'),
      label: '喂奶日期',
      value:
          '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
      icon: CupertinoIcons.calendar,
      compact: compact,
      onTap: disabled ? null : () => _pick(date: true),
    );
    final timeField = _PickerField(
      key: const ValueKey('add-feed-time-field'),
      label: '喂奶时间',
      value: TimeUtils.formatTime(_selectedDate),
      icon: CupertinoIcons.clock,
      compact: compact,
      onTap: disabled ? null : () => _pick(date: false),
    );

    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 600 : 440),
          child: AppGlassSurface(
            key: const ValueKey('add-feed-record-surface'),
            radius: 32,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 20 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) ...[
                    AppGlassSurface(
                      radius: 18,
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        CupertinoIcons.calendar_badge_plus,
                        color: colors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    AppStrings.addFeedTitle,
                    style: TextStyle(
                      fontSize: compact ? 24 : 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 8),
                    Text(
                      '选择实际喂奶时间，补全宝宝的日常记录。',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],
                  SizedBox(height: compact ? 14 : 24),
                  if (compact)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: dateField),
                        const SizedBox(width: 12),
                        Expanded(child: timeField),
                      ],
                    )
                  else ...[
                    dateField,
                    const SizedBox(height: 12),
                    timeField,
                  ],
                  SizedBox(height: compact ? 12 : 16),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error,
                          style: TextStyle(
                            color: colors.alert,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        color: colors.textSecondary,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '补记会按时间排序，倒计时以最新一次喂奶为准。',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cancel = AppButton(
                        key: const ValueKey('add-feed-cancel'),
                        glass: false,
                        onPressed: _saving ? null : () => _close(false),
                        child: const Text(AppStrings.cancel),
                      );
                      final save = AppButton(
                        key: const ValueKey('add-feed-save'),
                        filled: true,
                        onPressed: disabled || isFuture ? null : _save,
                        child: _saving
                            ? CupertinoActivityIndicator(
                                color: colors.onPrimary,
                              )
                            : const Text('保存记录'),
                      );
                      if (constraints.maxWidth < 300 &&
                          MediaQuery.textScalerOf(context).scale(16) > 20) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [save, const SizedBox(height: 8), cancel],
                        );
                      }
                      return Row(
                        children: [
                          cancel,
                          const SizedBox(width: 12),
                          Expanded(child: save),
                        ],
                      );
                    },
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

class _PickerField extends StatelessWidget {
  const _PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    required this.compact,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onPressed: onTap,
      semanticLabel: '$label，$value',
      excludeSemantics: true,
      child: AppGlassSurface(
        radius: 20,
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Row(
          children: [
            if (!compact) ...[
              Icon(icon, size: 22, color: colors.primary),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: compact ? 16 : 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              color: colors.textTertiary,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }
}

final _activeBackfillDialogs = Expando<Future<bool?>>('Active backfill dialog');

Future<bool?> showAddFeedRecordDialog(BuildContext navigatorContext) async {
  final navigator = Navigator.of(navigatorContext, rootNavigator: true);
  final active = _activeBackfillDialogs[navigator];
  if (active != null) return active;
  final provider = navigatorContext.read<FeedProvider>();
  final pending = showGeneralDialog<bool>(
    context: navigatorContext,
    barrierDismissible: false,
    barrierLabel: '关闭补记',
    barrierColor: Colors.black.withValues(alpha: .3),
    transitionDuration: Duration(
      milliseconds: MediaQuery.disableAnimationsOf(navigatorContext) ? 0 : 220,
    ),
    transitionBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .96, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
    pageBuilder: (dialogContext, animation, secondary) =>
        ChangeNotifierProvider.value(
          value: provider,
          child: const AddFeedRecordDialog(),
        ),
  );
  _activeBackfillDialogs[navigator] = pending;
  try {
    return await pending;
  } finally {
    if (identical(_activeBackfillDialogs[navigator], pending)) {
      _activeBackfillDialogs[navigator] = null;
    }
  }
}
