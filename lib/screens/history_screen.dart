import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_record.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_controls.dart';
import '../utils/time_utils.dart';
import '../widgets/add_feed_record_dialog.dart';

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
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('删除这条记录？'),
          content: Text(
            '${_fullDate(record.time)} ${TimeUtils.formatTime(record.time)} 的喂奶记录将被删除。此操作无法撤销。',
          ),
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('cancel-delete-record'),
              isDefaultAction: true,
              onPressed: () => close(dialogContext, false),
              child: const Text(AppStrings.cancel),
            ),
            CupertinoDialogAction(
              key: const ValueKey('confirm-delete-record'),
              isDestructiveAction: true,
              onPressed: () => close(dialogContext, true),
              child: const Text(AppStrings.delete),
            ),
          ],
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
      if (mounted) _showMessage('删除失败，请重试');
    } finally {
      _confirmingDelete = false;
    }
  }

  void _showMessage(String message) {
    showAppNotice(context, message);
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

            return LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth > constraints.maxHeight &&
                    constraints.maxHeight <= 500;
                final horizontalPadding = constraints.maxWidth > 1088
                    ? (constraints.maxWidth - 1040) / 2
                    : 24.0;

                return CustomScrollView(
                  key: const PageStorageKey('feed-history-scroll'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        compact ? 16 : 28,
                        horizontalPadding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (compact) ...[
                              _CompactHistoryHeader(
                                todayCount: todayCount,
                                totalCount: records.length,
                                saving: snapshot.saving,
                                onAdd: () => showAddFeedRecordDialog(context),
                              ),
                              const SizedBox(height: 12),
                            ] else ...[
                              Text(
                                '成长日常',
                                style: TextStyle(
                                  color: AppPalette.of(context).textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppStrings.history,
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.6,
                                  color: AppPalette.of(context).textPrimary,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '每一次用心照顾，都有迹可循。',
                                style: TextStyle(
                                  color: AppPalette.of(context).textSecondary,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _SummaryCard(
                                      label: '今日喂奶',
                                      count: todayCount,
                                      icon: CupertinoIcons.sun_max,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SummaryCard(
                                      label: '已存记录',
                                      count: records.length,
                                      icon: CupertinoIcons.doc_text,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '喂奶时间线',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppPalette.of(context).textPrimary,
                                    ),
                                  ),
                                  AppButton(
                                    key: const ValueKey(
                                      'history-backfill-button',
                                    ),
                                    onPressed: snapshot.saving
                                        ? null
                                        : () =>
                                              showAddFeedRecordDialog(context),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(CupertinoIcons.plus, size: 18),
                                        SizedBox(width: 7),
                                        Text('补记喂奶'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (snapshot.error != null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          20,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: AppGlassSurface(
                            padding: const EdgeInsets.all(20),
                            radius: 24,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  CupertinoIcons.info_circle,
                                  color: AppPalette.of(context).alert,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    snapshot.error!,
                                    style: TextStyle(
                                      color: AppPalette.of(context).textPrimary,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (records.isEmpty && snapshot.error == null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          24,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyHistory(
                            onAdd: () => showAddFeedRecordDialog(context),
                          ),
                        ),
                      )
                    else if (records.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        sliver: SliverList.builder(
                          itemCount: days.length,
                          itemBuilder: (context, index) {
                            final dayRecords = groups[days[index]]!;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: _DayGroup(
                                date: days[index],
                                referenceTime: snapshot.day,
                                records: dayRecords,
                                latestId: records.first.id,
                                saving: snapshot.saving,
                                compact: compact,
                                onDelete: _deleteRecord,
                              ),
                            );
                          },
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        4,
                        horizontalPadding,
                        28,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          '记录保存在这台设备上，最多保留最近 100 条。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppPalette.of(context).textSecondary,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      padding: const EdgeInsets.all(18),
      radius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppPalette.of(context).primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppPalette.of(context).textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$count',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.of(context).textPrimary,
                    height: 1.2,
                  ),
                ),
                TextSpan(
                  text: ' 次',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactHistoryHeader extends StatelessWidget {
  const _CompactHistoryHeader({
    required this.todayCount,
    required this.totalCount,
    required this.saving,
    required this.onAdd,
  });
  final int todayCount;
  final int totalCount;
  final bool saving;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.history,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.15,
                  letterSpacing: -.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _CountPill(label: '今日', count: todayCount),
                  _CountPill(label: '已存', count: totalCount),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '喂奶时间线',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            AppButton(
              key: const ValueKey('history-backfill-button'),
              compact: true,
              onPressed: saving ? null : onAdd,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.plus, size: 17),
                  SizedBox(width: 6),
                  Text('补记喂奶'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppGlassSurface(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            TextSpan(
              text: '$count',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.date,
    required this.referenceTime,
    required this.records,
    required this.latestId,
    required this.saving,
    required this.compact,
    required this.onDelete,
  });

  final DateTime date;
  final DateTime referenceTime;
  final List<FeedRecord> records;
  final String latestId;
  final bool saving;
  final bool compact;
  final ValueChanged<FeedRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final now = referenceTime;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final relative = _sameDay(date, now)
        ? '今天 · '
        : _sameDay(date, yesterday)
        ? '昨天 · '
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 2, compact ? 8 : 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$relative${_fullDate(date)}',
                  style: TextStyle(
                    color: AppPalette.of(context).textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${records.length} 次',
                style: TextStyle(
                  color: AppPalette.of(context).textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        AppGlassSurface(
          radius: 26,
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: compact ? 4 : 8,
          ),
          child: Column(
            children: [
              for (var index = 0; index < records.length; index++) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: Container(
                      height: .5,
                      color: AppPalette.of(context).border,
                    ),
                  ),
                _RecordRow(
                  record: records[index],
                  isLatest: records[index].id == latestId,
                  saving: saving,
                  compact: compact,
                  onDelete: () => onDelete(records[index]),
                ),
              ],
            ],
          ),
        ),
      ],
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 16),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isLatest
                  ? AppPalette.of(context).primary
                  : AppPalette.of(context).softGreen,
              shape: BoxShape.circle,
              border: Border.all(
                color: isLatest
                    ? AppPalette.of(context).primary
                    : AppPalette.of(context).accentLight,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      TimeUtils.formatTime(record.time),
                      style: TextStyle(
                        fontSize: compact ? 21 : 23,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).textPrimary,
                        height: 1.2,
                      ),
                    ),
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).softGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '最近一次',
                          style: TextStyle(
                            color: AppPalette.of(context).primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: compact ? 5 : 8),
                Text(
                  _intervalLabel(record.intervalFromPrevious),
                  style: TextStyle(
                    color: AppPalette.of(context).textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          AppButton(
            key: ValueKey('delete-record-${record.id}'),
            glass: false,
            destructive: true,
            padding: const EdgeInsets.all(14),
            semanticLabel: '删除 ${TimeUtils.formatTime(record.time)} 的记录',
            onPressed: saving ? null : onDelete,
            child: const Icon(CupertinoIcons.trash, size: 20),
          ),
        ],
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
  const _EmptyHistory({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      radius: 28,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppPalette.of(context).softGreen,
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.book,
              size: 34,
              color: AppPalette.of(context).primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '开始记录宝宝的日常',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '还没有喂奶记录\n回到首页记录，或补记之前的喂奶时间。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppPalette.of(context).textSecondary,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            key: const ValueKey('history-first-record'),
            filled: true,
            onPressed: onAdd,
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
