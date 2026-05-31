import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/feed_record.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import '../widgets/add_feed_record_dialog.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.history,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
      ),
      body: Consumer<FeedProvider>(
        builder: (context, feedProvider, child) {
          final records = feedProvider.feedHistory;

          if (records.isEmpty) {
            return const Center(
              child: Text(
                '还没有喂奶记录',
                style: TextStyle(fontSize: 16, color: AppColors.textLight),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: records.length,
            itemBuilder: (context, index) {
              return _buildDismissibleItem(
                context,
                feedProvider,
                records,
                index,
              );
            },
          );
        },
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(28),
          elevation: 4,
          shadowColor: AppColors.accent.withValues(alpha: 0.4),
          child: InkWell(
            onTap: () => showAddFeedRecordDialog(context),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    '添加记录',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDismissibleItem(
    BuildContext context,
    FeedProvider feedProvider,
    List<FeedRecord> records,
    int index,
  ) {
    final record = records[index];
    return Dismissible(
      key: Key(record.time.millisecondsSinceEpoch.toString()),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.5},
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认删除'),
              content: const Text('确定要删除这条喂奶记录吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        feedProvider.deleteFeedRecord(index);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('记录已删除'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: _buildRecordItem(record),
    );
  }

  Widget _buildRecordItem(FeedRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                TimeUtils.formatTime(record.time),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  fontFamily: 'Menlo',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                TimeUtils.getDateGroup(record.time),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
          if (record.intervalFromPrevious != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                TimeUtils.formatInterval(record.intervalFromPrevious!),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
