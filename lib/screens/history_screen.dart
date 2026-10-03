import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_record.dart';
import '../providers/feed_provider.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import '../widgets/add_feed_record_dialog.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_message_dialog.dart';
import '../widgets/app_page_header.dart';

typedef _HistorySnapshot = ({
  List<FeedRecord> records,
  bool initialized,
  bool saving,
  String? error,
  DateTime day,
});

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _confirmingDelete = false;

  Future<void> _deleteRecord(FeedRecord record) async {
    if (_confirmingDelete) return;
    final provider = context.read<FeedProvider>();
    if (provider.isSaving) return;
    _confirmingDelete = true;
    var closing = false;
    void close(BuildContext dialogContext, bool confirmed) {
      if (closing || ModalRoute.of(dialogContext)?.isCurrent != true) return;
      closing = true;
      Navigator.of(dialogContext).pop(confirmed);
    }

    try {
      final confirmed = await Navigator.of(context, rootNavigator: true)
          .push<bool>(
            createAppMessageDialogRoute<bool>(
              context,
              builder: (dialogContext) => AppMessageDialog(
                title: '删除这条记录？',
                icon: CupertinoIcons.trash,
                detail: _DeleteRecordDetail(record: record),
                content: const Text('删除后无法恢复，请确认这是要移除的一餐。'),
                actions: [
                  AppButton(
                    key: const ValueKey('cancel-delete-record'),
                    onPressed: () => close(dialogContext, false),
                    child: const Text(AppStrings.cancel),
                  ),
                  AppButton(
                    key: const ValueKey('confirm-delete-record'),
                    filled: true,
                    onPressed: () => close(dialogContext, true),
                    child: const Text('确认删除'),
                  ),
                ],
              ),
            ),
          );
      if (confirmed != true || !mounted) return;

      // A record's position can change while its confirmation is open.
      final index = provider.feedHistory.indexWhere(
        (item) => item.id == record.id,
      );
      if (index < 0) return;
      await provider.deleteFeedRecord(index);
    } catch (_) {
      if (mounted) showAppNotice(context, '删除失败，请重试');
    } finally {
      _confirmingDelete = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Selector<FeedProvider, _HistorySnapshot>(
          selector: (context, provider) {
            final now = provider.referenceTime;
            return (
              records: provider.feedHistory,
              initialized: provider.isInitialized,
              saving: provider.isSaving,
              error: provider.error,
              day: DateTime(now.year, now.month, now.day),
            );
          },
          builder: (context, snapshot, child) {
            if (!snapshot.initialized) {
              return const Center(child: CupertinoActivityIndicator());
            }

            final records = snapshot.records;
            final todayCount = context.read<FeedProvider>().todayRecords.length;
            final groups = <DateTime, List<FeedRecord>>{};
            for (final record in records) {
              final day = DateTime(
                record.time.year,
                record.time.month,
                record.time.day,
              );
              groups.putIfAbsent(day, () => []).add(record);
            }
            final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
            // Only lightweight data is flattened here. Each date header and
            // record gets its own sliver child, even for a large single day.
            final entries = <_HistoryEntry>[
              for (final day in days) ...[
                _HistoryEntry.header(day, groups[day]!.length),
                for (final record in groups[day]!) _HistoryEntry.item(record),
              ],
            ];

            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = AppPageLayout.compact(context);
                final largeText =
                    MediaQuery.textScalerOf(context).scale(16) > 22;
                // The landscape app shell already carries the daily summary.
                // Only a broad page gets a second column within the journal.
                final sidebar = !largeText && constraints.maxWidth >= 1080;
                final horizontalPadding = AppPageLayout.contentPadding(
                  constraints.maxWidth,
                );
                final topPadding = AppPageLayout.topPadding(compact);
                final colors = AppPalette.of(context);

                final journal = CustomScrollView(
                  key: const PageStorageKey('feed-history-scroll'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: AppPageLayout.headerGap(compact),
                        ),
                        child: _HistoryHeader(
                          compact: compact,
                          saving: snapshot.saving,
                          onAdd: () => showAddFeedRecordDialog(context),
                        ),
                      ),
                    ),
                    if (!sidebar)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: compact ? 18 : 32),
                          child: _HistorySummary(
                            todayCount: todayCount,
                            totalCount: records.length,
                            vertical: false,
                            compact: compact,
                          ),
                        ),
                      ),
                    if (snapshot.error != null)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.alert.withValues(alpha: .07),
                            border: Border(
                              left: BorderSide(color: colors.alert, width: 3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                CupertinoIcons.info_circle,
                                color: colors.alert,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  snapshot.error!,
                                  style: AppTypography.body(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (records.isEmpty && snapshot.error == null)
                      SliverToBoxAdapter(
                        child: _EmptyHistory(
                          saving: snapshot.saving,
                          onAdd: () => showAddFeedRecordDialog(context),
                        ),
                      )
                    else if (records.isNotEmpty)
                      SliverList.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final record = entry.record;
                          if (record == null) {
                            return _DayHeader(
                              date: entry.day!,
                              referenceTime: snapshot.day,
                              count: entry.count,
                              compact: compact,
                            );
                          }
                          final lastInDay =
                              index + 1 == entries.length ||
                              entries[index + 1].record == null;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: lastInDay ? (compact ? 24 : 36) : 0,
                            ),
                            child: _RecordRow(
                              record: record,
                              isLatest: record.id == records.first.id,
                              saving: snapshot.saving,
                              compact: compact,
                              onDelete: () => _deleteRecord(record),
                            ),
                          );
                        },
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 28),
                        child: Text(
                          '记录保存在这台设备上，历史记录会持续保留。',
                          style: AppTypography.caption(context),
                        ),
                      ),
                    ),
                  ],
                );

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding,
                    horizontalPadding,
                    0,
                  ),
                  child: sidebar
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: journal),
                            Container(
                              width: 1,
                              margin: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                              color: colors.border,
                            ),
                            SizedBox(
                              width: compact ? 156 : 216,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 28),
                                child: _HistorySummary(
                                  todayCount: todayCount,
                                  totalCount: records.length,
                                  vertical: true,
                                  compact: compact,
                                ),
                              ),
                            ),
                          ],
                        )
                      : journal,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.compact,
    required this.saving,
    required this.onAdd,
  });

  final bool compact;
  final bool saving;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final add = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary),
      ),
      child: AppButton(
        key: const ValueKey('history-backfill-button'),
        compact: true,
        surface: false,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onPressed: saving ? null : onAdd,
        child: Text(
          '补记喂奶',
          style: AppTypography.button.copyWith(color: colors.primary),
        ),
      ),
    );
    return AppPageHeader(
      title: AppStrings.history,
      subtitle: '把每一次照顾，留在时间里。',
      compact: compact,
      trailing: add,
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({
    required this.todayCount,
    required this.totalCount,
    required this.vertical,
    required this.compact,
  });

  final int todayCount;
  final int totalCount;
  final bool vertical;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final today = _CountSummary(
      label: '今日喂奶',
      count: todayCount,
      compact: compact && !vertical,
    );
    final total = _CountSummary(
      label: '已存记录',
      count: totalCount,
      compact: compact && !vertical,
    );
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: compact ? 10 : 18),
          today,
          Container(
            height: 1,
            color: colors.border,
            margin: EdgeInsets.symmetric(vertical: compact ? 22 : 36),
          ),
          total,
          Container(
            height: 1,
            color: colors.border,
            margin: EdgeInsets.symmetric(vertical: compact ? 22 : 36),
          ),
          Text('按自己的节奏，\n慢慢长大。', style: AppTypography.supporting(context)),
        ],
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: today),
          const SizedBox(width: 24),
          Expanded(child: total),
        ],
      ),
    );
  }
}

class _CountSummary extends StatelessWidget {
  const _CountSummary({
    required this.label,
    required this.count,
    required this.compact,
  });

  final String label;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final caption = Text(label, style: AppTypography.supporting(context));
    final value = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: compact ? 30 : 48,
              fontWeight: FontWeight.w400,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(text: ' 次', style: AppTypography.supporting(context)),
        ],
      ),
      style: const TextStyle(height: 1.1),
    );
    if (compact) {
      return Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [caption, value],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [caption, const SizedBox(height: 12), value],
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry.header(this.day, this.count) : record = null;
  const _HistoryEntry.item(this.record) : day = null, count = 0;

  final DateTime? day;
  final int count;
  final FeedRecord? record;
}

class _DeleteRecordDetail extends StatelessWidget {
  const _DeleteRecordDetail({required this.record});

  final FeedRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(
            _fullDate(record.time),
            style: AppTypography.supporting(context),
          ),
          Text(
            TimeUtils.formatTime(record.time),
            style: TextStyle(
              fontSize: 36,
              height: 1.2,
              color: colors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.referenceTime,
    required this.count,
    required this.compact,
  });

  final DateTime date;
  final DateTime referenceTime;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final yesterday = DateTime(
      referenceTime.year,
      referenceTime.month,
      referenceTime.day - 1,
    );
    final relative = _sameDay(date, referenceTime)
        ? '今天 · '
        : _sameDay(date, yesterday)
        ? '昨天 · '
        : '';

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$relative${_fullDate(date)}',
              style: AppTypography.sectionTitle(context),
            ),
          ),
          const SizedBox(width: 12),
          Text('$count 条', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.isLatest,
    required this.saving,
    required this.compact,
    required this.onDelete,
  });

  final FeedRecord record;
  final bool isLatest;
  final bool saving;
  final bool compact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: EdgeInsets.symmetric(vertical: compact ? 10 : 19),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        TimeUtils.formatTime(record.time),
                        style: TextStyle(
                          fontSize: compact ? 32 : 38,
                          fontWeight: FontWeight.w400,
                          color: isLatest ? colors.primary : colors.textPrimary,
                          height: 1,
                          letterSpacing: -.4,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (isLatest)
                        Text(
                          '最近一次',
                          style: AppTypography.caption(context).copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _intervalLabel(record.intervalFromPrevious),
                    style: AppTypography.caption(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              key: ValueKey('delete-record-${record.id}'),
              surface: false,
              destructive: true,
              padding: const EdgeInsets.all(12),
              semanticLabel: '删除 ${TimeUtils.formatTime(record.time)} 的记录',
              onPressed: saving ? null : onDelete,
              child: const Icon(CupertinoIcons.trash, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  String _intervalLabel(Duration? interval) {
    if (interval == null) return '最早一条记录';
    if (interval.inMinutes <= 0) return '与上次间隔不足 1 分钟';
    final hours = interval.inHours;
    final minutes = interval.inMinutes % 60;
    final duration = hours > 0
        ? '$hours 小时${minutes > 0 ? ' $minutes 分钟' : ''}'
        : '$minutes 分钟';
    return '距上次 $duration';
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.saving, required this.onAdd});

  final bool saving;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.doc_text, size: 40, color: colors.primary),
          const SizedBox(height: 24),
          Text('第一条记录，从这里开始。', style: AppTypography.sectionTitle(context)),
          const SizedBox(height: 12),
          Text(
            '还没有喂奶记录\n回到计时页滑动记录，或补记之前的喂奶时间。',
            style: AppTypography.supporting(context),
          ),
          const SizedBox(height: 24),
          AppButton(
            key: const ValueKey('history-first-record'),
            filled: true,
            onPressed: saving ? null : onAdd,
            child: const Text('添加第一条记录'),
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _fullDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';
