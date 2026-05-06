import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/feed_record.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

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
