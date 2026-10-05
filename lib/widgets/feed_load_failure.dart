import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/feed_provider.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import 'app_controls.dart';

/// Unread history is unknown, never an empty diary or a zero-volume statistic.
class FeedLoadFailure extends StatelessWidget {
  const FeedLoadFailure({super.key});

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle,
                color: AppPalette.of(context).alert,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text('记录暂时无法读取', style: AppTypography.sectionTitle(context)),
              const SizedBox(height: 8),
              Text(
                '原有记录已保留。读取成功前暂停记录和提醒调整，请重试。',
                style: AppTypography.supporting(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: AppButton(
                  key: const ValueKey('retry-feed-loading'),
                  filled: true,
                  onPressed: feed.isRetryingLoading ? null : feed.retryLoading,
                  child: Text(feed.isRetryingLoading ? '正在重试…' : '重新读取记录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
