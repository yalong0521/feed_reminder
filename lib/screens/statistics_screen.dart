import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_record.dart';
import '../models/milk_statistics.dart';
import '../providers/feed_provider.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_date_range_picker.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_surface.dart';
import '../widgets/milk_volume_chart.dart';
import '../widgets/feed_load_failure.dart';

typedef _StatisticsSnapshot = ({
  List<FeedRecord> records,
  DateTime today,
  bool initialized,
  bool available,
  String? error,
});

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int _dayCount = 7;
  DateTimeRange? _customRange;
  DateTime? _selectedDate;

  Future<void> _chooseRange(MilkStatistics statistics) async {
    final provider = context.read<FeedProvider>();
    var earliest = DateTime(2020);
    for (final record in provider.feedHistory) {
      final date = calendarDate(record.time);
      if (date.isBefore(earliest)) earliest = date;
    }
    final range = await showAppDateRangePicker(
      context,
      now: provider.referenceTime,
      initial: DateTimeRange(
        start: statistics.days.first.date,
        end: statistics.days.last.date,
      ),
      title: '自选统计范围',
      maximumDays: MilkStatistics.maxCustomDays,
      earliestDate: earliest,
    );
    if (range != null && mounted) {
      setState(() {
        _customRange = range;
        if (_selectedDate == null ||
            _selectedDate!.isBefore(range.start) ||
            _selectedDate!.isAfter(range.end)) {
          _selectedDate = range.end;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Selector<FeedProvider, _StatisticsSnapshot>(
            selector: (context, provider) {
              final now = provider.referenceTime;
              return (
                // Do not rebuild on each countdown tick, but allow a future
                // record to enter the chart after a clock correction catches up.
                records: provider.feedHistory
                    .where((record) => !record.time.isAfter(now))
                    .toList(growable: false),
                today: DateTime(now.year, now.month, now.day),
                initialized: provider.isInitialized,
                available: provider.isAvailable,
                error: provider.error,
              );
            },
            shouldRebuild: (before, after) =>
                before.today != after.today ||
                before.initialized != after.initialized ||
                before.available != after.available ||
                before.error != after.error ||
                !listEquals(before.records, after.records),
            builder: (context, snapshot, child) {
              final colors = AppPalette.of(context);
              return LayoutBuilder(
                builder: (context, constraints) {
                  final padding = AppPageLayout.contentPadding(
                    constraints.maxWidth,
                  );
                  final compact = AppPageLayout.compact(context);
                  // A clock correction can move today before the chosen end.
                  // Keep the stored choice, while displaying only elapsed days.
                  final custom = _customRange;
                  final end =
                      custom != null && custom.end.isBefore(snapshot.today)
                      ? custom.end
                      : snapshot.today;
                  final start = custom != null && custom.start.isBefore(end)
                      ? custom.start
                      : end;
                  final statistics = MilkStatistics.aggregate(
                    snapshot.records,
                    now: context.read<FeedProvider>().referenceTime,
                    dayCount: custom == null ? _dayCount : null,
                    startDate: custom == null ? null : start,
                    endDate: custom == null ? null : end,
                  );
                  final selected = statistics.days.firstWhere(
                    (day) => day.date == _selectedDate,
                    orElse: () => statistics.days.last,
                  );
                  final selectedIndex = statistics.days.indexOf(selected);
                  // Anchor pages at the latest date: every day belongs to one
                  // non-overlapping page, with at most 30 keyboard targets.
                  final chartEnd =
                      statistics.days.length -
                      ((statistics.days.length - 1 - selectedIndex) ~/ 30) * 30;
                  final chartStart = (chartEnd - 30).clamp(0, chartEnd);
                  final chartDays = statistics.days.sublist(
                    chartStart,
                    chartEnd,
                  );
                  return SingleChildScrollView(
                    key: const PageStorageKey('milk-statistics-scroll'),
                    padding: EdgeInsets.fromLTRB(padding, 8, padding, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppButton(
                          key: const ValueKey('statistics-back'),
                          surface: false,
                          compact: true,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          onPressed: () {
                            if (ModalRoute.of(context)?.isCurrent == true) {
                              Navigator.of(context).pop();
                            }
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.back, size: 18),
                              SizedBox(width: 6),
                              Text('返回记录'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppPageHeader(
                          title: '奶量统计',
                          subtitle: '看见每一天的喂养节奏。',
                          compact: compact,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final count in [7, 30])
                              Semantics(
                                selected: custom == null && _dayCount == count,
                                child: AppButton(
                                  key: ValueKey('statistics-range-$count'),
                                  filled: custom == null && _dayCount == count,
                                  onPressed: () => setState(() {
                                    _dayCount = count;
                                    _customRange = null;
                                    final first = DateTime(
                                      snapshot.today.year,
                                      snapshot.today.month,
                                      snapshot.today.day - count + 1,
                                    );
                                    if (_selectedDate != null &&
                                        (_selectedDate!.isBefore(first) ||
                                            _selectedDate!.isAfter(
                                              snapshot.today,
                                            ))) {
                                      _selectedDate = snapshot.today;
                                    }
                                  }),
                                  child: Text('近 $count 天'),
                                ),
                              ),
                            Semantics(
                              selected: custom != null,
                              child: AppButton(
                                key: const ValueKey('statistics-range-custom'),
                                filled: custom != null,
                                onPressed: () => _chooseRange(statistics),
                                child: const Text('自选'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_date(statistics.days.first.date)} — ${_date(statistics.days.last.date)}'
                          '${statistics.days.last.date == snapshot.today ? ' · 含今天' : ''}',
                          style: AppTypography.caption(context),
                        ),
                        if (!snapshot.initialized)
                          const Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(child: CupertinoActivityIndicator()),
                          )
                        else if (!snapshot.available)
                          const FeedLoadFailure()
                        else ...[
                          if (snapshot.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                snapshot.error!,
                                style: AppTypography.body(
                                  context,
                                ).copyWith(color: colors.alert),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            '已记录总奶量',
                            style: AppTypography.supporting(context),
                          ),
                          const SizedBox(height: 4),
                          Semantics(
                            label: '已记录总奶量 ${statistics.totalMl} 毫升',
                            excludeSemantics: true,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text.rich(
                                TextSpan(
                                  text: '${statistics.totalMl}',
                                  style: TextStyle(
                                    fontSize: 48,
                                    height: 1.2,
                                    fontWeight: FontWeight.w500,
                                    color: colors.primary,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: ' mL',
                                      style: AppTypography.sectionTitle(
                                        context,
                                      ).copyWith(color: colors.primary),
                                    ),
                                  ],
                                ),
                                key: const ValueKey('statistics-total'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SummaryMetrics(statistics: statistics),
                          const SizedBox(height: 8),
                          Text(
                            '日均按 ${statistics.days.length} 个自然日计算，包含没有记录的日期。',
                            style: AppTypography.caption(context),
                          ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            color: colors.border,
                          ),
                          if (statistics.feedCount == 0)
                            const _EmptyStatistics(
                              title: '这段时间还没有喂奶记录',
                              message: '记录喂奶后，每日奶量会显示在这里。',
                            )
                          else if (statistics.recordedCount == 0)
                            const _EmptyStatistics(
                              title: '还没有记录奶量',
                              message: '已有喂奶记录的奶量均为 0 mL。\n可返回历史记录补充，图表会随之更新。',
                            ),
                          const SizedBox(height: 4),
                          Semantics(
                            header: true,
                            child: Text(
                              '每日奶量',
                              style: AppTypography.sectionTitle(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (statistics.days.length > 30) ...[
                            Text(
                              '${_date(chartDays.first.date)} — ${_date(chartDays.last.date)} · 图表 ${chartDays.length} 天',
                              key: const ValueKey('statistics-chart-range'),
                              style: AppTypography.caption(context),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                AppButton(
                                  key: const ValueKey(
                                    'statistics-chart-previous',
                                  ),
                                  compact: true,
                                  onPressed: chartStart == 0
                                      ? null
                                      : () => setState(() {
                                          _selectedDate = statistics
                                              .days[chartStart - 1]
                                              .date;
                                        }),
                                  child: const Text('前一页'),
                                ),
                                AppButton(
                                  key: const ValueKey('statistics-chart-next'),
                                  compact: true,
                                  onPressed: chartEnd == statistics.days.length
                                      ? null
                                      : () => setState(() {
                                          _selectedDate = statistics
                                              .days[(chartEnd + 29).clamp(
                                                0,
                                                statistics.days.length - 1,
                                              )]
                                              .date;
                                        }),
                                  child: const Text('后一页'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          MilkVolumeChart(
                            days: chartDays,
                            selectedDate: selected.date,
                            onSelectDay: (date) =>
                                setState(() => _selectedDate = date),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const ValueKey('statistics-day-detail'),
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.softGreen,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_date(selected.date)}${selected.date == snapshot.today ? ' · 今天' : ''}',
                                    style: AppTypography.caption(context),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${selected.totalMl} mL',
                                    style: AppTypography.sectionTitle(
                                      context,
                                    ).copyWith(color: colors.primary),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    selected.feedCount == 0
                                        ? '当天暂无喂奶记录'
                                        : '${selected.feedCount} 次喂奶 · ${selected.unrecordedCount} 次未记录奶量',
                                    style: AppTypography.supporting(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _SummaryMetrics(
                            statistics: statistics,
                            averagesOnly: true,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '0 mL 表示未记录奶量：计入喂奶次数，不增加总奶量。旧记录默认为 0 mL，可在历史记录中补充。',
                            style: AppTypography.caption(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '单餐平均仅计算奶量大于 0 的记录。平均间隔取范围内相邻两餐的实际时间差，含未记录奶量及同时间记录；不跨范围边界，不计未来记录，少于两餐时暂无。',
                            style: AppTypography.caption(context),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _date(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({required this.statistics, this.averagesOnly = false});

  final MilkStatistics statistics;
  final bool averagesOnly;

  @override
  Widget build(BuildContext context) {
    final metrics = averagesOnly
        ? [
            _Metric(
              label: '单餐平均',
              value: statistics.averageMealMl == null
                  ? '暂无'
                  : '${statistics.averageMealMl!.toStringAsFixed(1)} mL',
            ),
            _Metric(
              label: '平均间隔',
              value: _interval(statistics.averageInterval),
            ),
          ]
        : [
            _Metric(
              label: '日均奶量',
              value: '${statistics.dailyAverageMl.toStringAsFixed(1)} mL',
            ),
            _Metric(label: '喂奶次数', value: '${statistics.feedCount} 次'),
            _Metric(label: '未记录奶量', value: '${statistics.unrecordedCount} 次'),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = (constraints.maxWidth / (104 * scale)).floor().clamp(
          1,
          metrics.length,
        );
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ],
        );
      },
    );
  }

  String _interval(Duration? duration) {
    if (duration == null) return '暂无';
    if (duration == Duration.zero) return '0 分钟';
    if (duration.inMinutes < 1) return '不足 1 分钟';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return hours == 0
        ? '$minutes 分钟'
        : '$hours 小时${minutes == 0 ? '' : ' $minutes 分钟'}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: AppTypography.caption(context)),
      const SizedBox(height: 4),
      Text(value, style: AppTypography.sectionTitle(context)),
    ],
  );
}

class _EmptyStatistics extends StatelessWidget {
  const _EmptyStatistics({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.label(context)),
        const SizedBox(height: 8),
        Text(message, style: AppTypography.supporting(context)),
      ],
    ),
  );
}
