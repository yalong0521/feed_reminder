import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_record.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import 'app_controls.dart';
import 'app_message_dialog.dart';
import 'app_surface.dart';
import 'milk_amount_field.dart';

class AddFeedRecordDialog extends StatefulWidget {
  const AddFeedRecordDialog({
    super.key,
    this.record,
    this.defaultMilkAmountMl = 0,
  });

  final FeedRecord? record;
  final int defaultMilkAmountMl;

  @override
  State<AddFeedRecordDialog> createState() => _AddFeedRecordDialogState();
}

class _AddFeedRecordDialogState extends State<AddFeedRecordDialog> {
  final _milkFieldKey = GlobalKey();
  late DateTime _selectedDate;
  late final TextEditingController _milkController;
  bool _saving = false;
  bool _picking = false;
  bool _closing = false;
  String? _error;
  String? _milkError;

  bool get _keepsRecordedTime =>
      widget.record?.time.isAtSameMomentAs(_selectedDate) ?? false;

  @override
  void initState() {
    super.initState();
    final now = context.read<FeedProvider>().referenceTime;
    // Retain the original seconds and milliseconds for an amount-only edit.
    _selectedDate =
        widget.record?.time ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _milkController = TextEditingController(
      text: '${widget.record?.milkAmountMl ?? widget.defaultMilkAmountMl}',
    );
  }

  @override
  void dispose() {
    _milkController.dispose();
    super.dispose();
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
    final milkError = MilkAmountField.validate(_milkController.text);
    if (milkError != null) {
      setState(() => _milkError = milkError);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closing || _milkError == null) return;
        final fieldContext = _milkFieldKey.currentContext;
        if (fieldContext == null) return;
        Scrollable.ensureVisible(
          fieldContext,
          alignment: 1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      });
      return;
    }
    if (!_keepsRecordedTime && _selectedDate.isAfter(provider.referenceTime)) {
      // The clock can move between the enabled button's build and its tap.
      // Future-time errors are derived below so they expire with validity.
      setState(() => _error = null);
      return;
    }
    if (!_keepsRecordedTime && _selectedDate.isBefore(DateTime(2020))) {
      setState(() => _error = '请选择 2020 年以后的日期');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amount = int.parse(_milkController.text);
      if (widget.record case final record?) {
        await provider.updateFeedRecord(
          record.id,
          time: _selectedDate,
          milkAmountMl: amount,
        );
      } else {
        await provider.addFeedRecordWithTime(
          _selectedDate,
          milkAmountMl: amount,
        );
      }
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
    final validity = context.select<FeedProvider, ({bool saving, bool future})>(
      (provider) => (
        saving: provider.isSaving,
        future:
            !_keepsRecordedTime &&
            _selectedDate.isAfter(provider.referenceTime),
      ),
    );
    final isFuture = validity.future;
    final error = isFuture ? AppStrings.futureTimeError : _error;
    final disabled = _saving || _picking || validity.saving;
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
      emphasizeValue: true,
      compact: compact,
      onTap: disabled ? null : () => _pick(date: false),
    );
    final dateTimeFields = IntrinsicHeight(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: dateField),
          SizedBox(height: compact ? 12 : 16),
          Expanded(child: timeField),
        ],
      ),
    );
    final milkField = MilkAmountField(
      key: _milkFieldKey,
      controller: _milkController,
      enabled: !disabled,
      errorText: _milkError,
      onSubmitted: _save,
      onChanged: () {
        if (_milkError != null) setState(() => _milkError = null);
      },
    );
    final sideBySide =
        compact &&
        size.width >= 700 &&
        MediaQuery.textScalerOf(context).scale(16) <= 22;
    final actions = LayoutBuilder(
      builder: (context, constraints) {
        final cancel = AppButton(
          key: const ValueKey('add-feed-cancel'),
          onPressed: _saving ? null : () => _close(false),
          child: const Text(AppStrings.cancel),
        );
        final save = Semantics(
          liveRegion: true,
          child: AppButton(
            key: const ValueKey('add-feed-save'),
            filled: true,
            semanticLabel: _saving
                ? widget.record == null
                      ? '正在保存记录'
                      : '正在保存修改'
                : null,
            onPressed: disabled || isFuture ? null : _save,
            child: _saving
                ? CupertinoActivityIndicator(color: colors.onPrimary)
                : Text(widget.record == null ? '保存记录' : '保存修改'),
          ),
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
    );

    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.all(compact ? 20 : 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: sideBySide ? 740 : 460),
          child: AppSurface(
            key: const ValueKey('add-feed-record-surface'),
            radius: 24,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 16 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          namesRoute: true,
                          child: Text(
                            widget.record == null
                                ? AppStrings.addFeedTitle
                                : '修改喂奶记录',
                            style: AppTypography.dialogTitle(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.record == null ? '补上实际喂奶的时间与奶量。' : '按实际情况调整时间或奶量。',
                      style: AppTypography.supporting(context),
                    ),
                  ],
                  SizedBox(height: compact ? 16 : 24),
                  if (sideBySide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              dateTimeFields,
                              const SizedBox(height: 12),
                              // Short landscape uses the space beside the ruler
                              // so its height cannot push Save below the screen.
                              actions,
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: milkField),
                      ],
                    )
                  else ...[
                    dateTimeFields,
                    const SizedBox(height: 24),
                    milkField,
                  ],
                  SizedBox(height: compact ? 12 : 16),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_circle,
                              color: colors.alert,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error,
                                style: AppTypography.supporting(
                                  context,
                                ).copyWith(color: colors.alert),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!compact)
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
                            widget.record == null
                                ? '补记会按时间排序，倒计时以最新一次喂奶为准。'
                                : '只修改奶量不会改变计时；修改时间后会重新排序。',
                            style: AppTypography.caption(context),
                          ),
                        ),
                      ],
                    ),
                  if (!sideBySide) ...[
                    SizedBox(height: compact ? 12 : 24),
                    actions,
                  ],
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
    this.emphasizeValue = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;
  final bool emphasizeValue;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onPressed: onTap,
      semanticLabel: '$label，$value',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 15, color: colors.textSecondary),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTypography.caption(context),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 4 : 10),
                  Text(
                    value,
                    style: emphasizeValue
                        ? TextStyle(
                            color: colors.primary,
                            fontSize: compact ? 29 : 36,
                            height: 1,
                            fontWeight: FontWeight.w400,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )
                        : AppTypography.label(context),
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

Future<bool?> showAddFeedRecordDialog(
  BuildContext navigatorContext, {
  FeedRecord? record,
}) async {
  final navigator = Navigator.of(navigatorContext, rootNavigator: true);
  final active = _activeBackfillDialogs[navigator];
  if (active != null) return active;
  final provider = navigatorContext.read<FeedProvider>();
  final settings = navigatorContext.read<SettingsProvider?>();
  final pending = _openFeedRecordDialog(
    navigatorContext,
    provider,
    settings,
    record,
  );
  // The lock also covers asynchronous preference loading before the dialog.
  _activeBackfillDialogs[navigator] = pending;
  try {
    return await pending;
  } finally {
    if (identical(_activeBackfillDialogs[navigator], pending)) {
      _activeBackfillDialogs[navigator] = null;
    }
  }
}

Future<bool?> _openFeedRecordDialog(
  BuildContext navigatorContext,
  FeedProvider provider,
  SettingsProvider? settings,
  FeedRecord? record,
) async {
  if (record == null && settings != null) {
    await settings.ready;
    if (!navigatorContext.mounted) return null;
    if (!settings.isAvailable) {
      showAppNotice(navigatorContext, '默认奶量设置未能读取，请重新打开应用后重试。');
      return false;
    }
  }
  if (!navigatorContext.mounted) return null;
  final defaultAmount = settings?.defaultMilkAmountMl ?? 0;
  return Navigator.of(navigatorContext, rootNavigator: true).push<bool>(
    createAppMessageDialogRoute<bool>(
      navigatorContext,
      barrierLabel: record == null ? '关闭补记' : '关闭修改',
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: provider,
        child: AddFeedRecordDialog(
          record: record,
          defaultMilkAmountMl: defaultAmount,
        ),
      ),
    ),
  );
}
