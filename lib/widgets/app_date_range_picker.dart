import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../utils/constants.dart';
import 'app_controls.dart';
import 'app_message_dialog.dart';

DateTime calendarDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

int calendarDayCount(DateTime start, DateTime end) =>
    DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
    1;

String calendarDateLabel(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

String calendarRangeLabel(DateTimeRange range) => range.start == range.end
    ? calendarDateLabel(range.start)
    : '${calendarDateLabel(range.start)} — ${calendarDateLabel(range.end)}';

final _activeDateRangePickers = Expando<Future<DateTimeRange?>>(
  'Active date range picker',
);

Future<DateTimeRange?> showAppDateRangePicker(
  BuildContext context, {
  required DateTime now,
  required DateTimeRange initial,
  required String title,
  bool allowSingleDay = false,
  int? maximumDays,
  DateTime? earliestDate,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final active = _activeDateRangePickers[navigator];
  if (active != null) return active;
  final result = navigator.push<DateTimeRange>(
    createAppMessageDialogRoute<DateTimeRange>(
      context,
      builder: (_) => AppDateRangePicker(
        now: now,
        initial: initial,
        title: title,
        allowSingleDay: allowSingleDay,
        maximumDays: maximumDays,
        earliestDate: earliestDate,
      ),
    ),
  );
  _activeDateRangePickers[navigator] = result;
  try {
    return await result;
  } finally {
    _activeDateRangePickers[navigator] = null;
  }
}

/// Date-only search: changes stay local until Apply, including nested wheels.
class AppDateRangePicker extends StatefulWidget {
  const AppDateRangePicker({
    super.key,
    required this.now,
    required this.initial,
    required this.title,
    this.allowSingleDay = false,
    this.maximumDays,
    this.earliestDate,
  });

  final DateTime now;
  final DateTimeRange initial;
  final String title;
  final bool allowSingleDay;
  final int? maximumDays;
  final DateTime? earliestDate;

  @override
  State<AppDateRangePicker> createState() => _AppDateRangePickerState();
}

class _AppDateRangePickerState extends State<AppDateRangePicker> {
  late DateTime _start;
  late DateTime _end;
  late bool _singleDay;
  bool _picking = false;
  bool _closing = false;

  DateTime get _today => calendarDate(widget.now);
  DateTime get _minimum {
    final supplied = calendarDate(widget.earliestDate ?? DateTime(2020));
    return supplied.isAfter(_today) ? _today : supplied;
  }

  @override
  void initState() {
    super.initState();
    _start = _clamp(calendarDate(widget.initial.start));
    _end = _clamp(calendarDate(widget.initial.end));
    _singleDay = widget.allowSingleDay && _start == _end;
  }

  DateTime _clamp(DateTime date) => date.isBefore(_minimum)
      ? _minimum
      : date.isAfter(_today)
      ? _today
      : date;

  void _close([DateTimeRange? result]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _pick({required bool start}) async {
    if (_picking) return;
    setState(() => _picking = true);
    final value = await Navigator.of(context, rootNavigator: true)
        .push<DateTime>(
          createAppMessageDialogRoute<DateTime>(
            context,
            builder: (_) => _CalendarDayPicker(
              title: _singleDay
                  ? '选择日期'
                  : start
                  ? '开始日期'
                  : '结束日期',
              initial: start ? _start : _end,
              minimum: _minimum,
              maximum: _today,
            ),
          ),
        );
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (value != null) {
        if (start) {
          _start = _clamp(calendarDate(value));
        } else {
          _end = _clamp(calendarDate(value));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final end = _singleDay ? _start : _end;
    final count = calendarDayCount(_start, end);
    final error = count < 1
        ? '开始日期不能晚于结束日期'
        : widget.maximumDays != null && count > widget.maximumDays!
        ? '最多选择 ${widget.maximumDays} 个自然日，请缩短日期范围'
        : null;
    Widget field({required bool start}) => AppButton(
      key: ValueKey(start ? 'date-range-start' : 'date-range-end'),
      radius: 14,
      onPressed: _picking ? null : () => _pick(start: start),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _singleDay
                  ? '查看日期'
                  : start
                  ? '开始日期'
                  : '结束日期',
              style: AppTypography.caption(context),
            ),
            const SizedBox(height: 4),
            Text(calendarDateLabel(start ? _start : _end)),
          ],
        ),
      ),
    );
    return AppMessageDialog(
      title: widget.title,
      icon: CupertinoIcons.calendar,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.allowSingleDay) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final single in [true, false])
                  Semantics(
                    selected: _singleDay == single,
                    child: AppButton(
                      key: ValueKey(
                        single ? 'date-range-single' : 'date-range-period',
                      ),
                      compact: true,
                      filled: _singleDay == single,
                      onPressed: () => setState(() => _singleDay = single),
                      child: Text(single ? '某一天' : '日期范围'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          field(start: true),
          if (!_singleDay) ...[const SizedBox(height: 12), field(start: false)],
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              error ?? '共 $count 个自然日，包含起止日期。',
              style: AppTypography.caption(context).copyWith(
                color: error == null ? null : AppPalette.of(context).alert,
              ),
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          key: const ValueKey('date-range-cancel'),
          onPressed: () => _close(),
          child: const Text('取消'),
        ),
        AppButton(
          key: const ValueKey('date-range-apply'),
          filled: true,
          onPressed: error != null || _picking
              ? null
              : () => _close(DateTimeRange(start: _start, end: end)),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _CalendarDayPicker extends StatefulWidget {
  const _CalendarDayPicker({
    required this.title,
    required this.initial,
    required this.minimum,
    required this.maximum,
  });
  final String title;
  final DateTime initial;
  final DateTime minimum;
  final DateTime maximum;

  @override
  State<_CalendarDayPicker> createState() => _CalendarDayPickerState();
}

class _CalendarDayPickerState extends State<_CalendarDayPicker> {
  late DateTime _selected = widget.initial;
  bool _closing = false;

  void _close([DateTime? value]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AppMessageDialog(
    title: widget.title,
    content: SizedBox(
      height: MediaQuery.sizeOf(context).height < 440 ? 140 : 200,
      child: CupertinoDatePicker(
        key: const ValueKey('query-calendar-picker'),
        mode: CupertinoDatePickerMode.date,
        initialDateTime: _selected,
        minimumDate: widget.minimum,
        maximumDate: widget.maximum,
        onDateTimeChanged: (date) => _selected = date,
      ),
    ),
    actions: [
      AppButton(onPressed: () => _close(), child: const Text('取消')),
      AppButton(
        key: const ValueKey('query-calendar-done'),
        filled: true,
        onPressed: () => _close(_selected),
        child: const Text('完成'),
      ),
    ],
  );
}
