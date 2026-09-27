import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import 'app_glass.dart';
import 'app_controls.dart';
import 'feed_button.dart';
import 'glass_countdown_text.dart';

/// A distant-readable timer above a single, reachable glass control dock.
class LandscapeFeedPanel extends StatelessWidget {
  final FeedProvider feed;
  final SettingsProvider settings;
  final bool quiet;
  final Future<void> Function() onRecord;
  final Future<void> Function() onUndo;
  final Future<void> Function() onStopAlert;
  final VoidCallback onBackfill;
  final VoidCallback? onHistory;

  const LandscapeFeedPanel({
    super.key,
    required this.feed,
    required this.settings,
    required this.quiet,
    required this.onRecord,
    required this.onUndo,
    required this.onStopAlert,
    required this.onBackfill,
    this.onHistory,
  });

  bool get _alert => feed.state == FeedState.alerting;
  bool get _warning => feed.state == FeedState.warning;
  bool get _hasRecord => feed.lastFeedTime != null;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width >= 600 && size.width > size.height;
    final shortLandscape = landscape && size.height < 360;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: landscape ? 1440 : 640),
        child: Padding(
          key: ValueKey(landscape ? 'landscape-home' : 'portrait-home'),
          padding: EdgeInsets.fromLTRB(
            size.width >= 740 ? 32 : 16,
            4,
            size.width >= 740 ? 32 : 16,
            shortLandscape
                ? 12
                : landscape
                ? 24
                : 16,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (landscape) {
                // A short keyboard viewport scrolls; normal phone landscapes keep
                // the clock and the complete dock on screen, including large text.
                final height = math.max(
                  feed.error == null ? 220.0 : 250.0,
                  constraints.maxHeight,
                );
                return SingleChildScrollView(
                  child: SizedBox(
                    height: height,
                    child: Column(
                      children: [
                        if (feed.error != null) _error(context),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _metric(
                                  context,
                                  '上次喂奶',
                                  _hasRecord
                                      ? TimeUtils.formatTime(feed.lastFeedTime!)
                                      : '— —',
                                  alignment: Alignment.centerLeft,
                                ),
                              ),
                              Expanded(
                                flex: 8,
                                child: _countdown(context, landscape: true),
                              ),
                              Expanded(
                                flex: 2,
                                child: _metric(
                                  context,
                                  '今日',
                                  '${feed.todayRecords.length} 次',
                                  onTap: onHistory,
                                  alignment: Alignment.centerRight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _progress(context),
                        _dock(context, landscape: true),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, content) {
                        return SingleChildScrollView(
                          child: SizedBox(
                            height: math.max(content.maxHeight, 285),
                            child: Column(
                              children: [
                                if (feed.error != null) _error(context),
                                Expanded(
                                  child: _countdown(context, landscape: false),
                                ),
                                SizedBox(
                                  height: 76,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _metric(
                                          context,
                                          '上次喂奶',
                                          _hasRecord
                                              ? TimeUtils.formatTime(
                                                  feed.lastFeedTime!,
                                                )
                                              : '— —',
                                        ),
                                      ),
                                      Expanded(
                                        child: _metric(
                                          context,
                                          '今日',
                                          '${feed.todayRecords.length} 次',
                                          onTap: onHistory,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _progress(context),
                  _dock(context, landscape: false),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _error(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      feed.error!,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: AppPalette.of(context).alert, fontSize: 13),
    ),
  );

  Widget _countdown(BuildContext context, {required bool landscape}) {
    final colors = AppPalette.of(context);
    final label = !_hasRecord
        ? '等待第一条记录'
        : _alert
        ? '已到喂奶时间 · 已超过'
        : _warning
        ? '快到喂奶时间'
        : '距离下次喂奶';
    final color = _alert
        ? colors.alert
        : _warning
        ? colors.warning
        : Theme.of(context).brightness == Brightness.dark
        ? colors.textPrimary
        : colors.primary;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: landscape ? 8 : 0, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: landscape ? 18 : 20,
                    fontWeight: FontWeight.w500,
                    color: _alert || _warning ? color : colors.textSecondary,
                  ),
                ),
                if (quiet) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '夜间静默',
                    child: Icon(
                      CupertinoIcons.moon,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: GlassCountdownText(
                _hasRecord
                    ? TimeUtils.formatDuration(
                        _alert ? feed.overdue : feed.timeRemaining,
                      )
                    : '--:--:--',
                key: ValueKey(
                  landscape ? 'landscape-countdown' : 'portrait-countdown',
                ),
                fontSize: landscape ? 160 : 108,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _nextReminder(context),
        ],
      ),
    );
  }

  Widget _nextReminder(BuildContext context) {
    final colors = AppPalette.of(context);
    final next = feed.nextFeedTime;
    if (_alert) {
      return AppButton(
        onPressed: onStopAlert,
        glass: false,
        destructive: true,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.speaker_slash, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(feed.isAlertAcknowledged ? '本次提醒已停止' : '停止本次提醒'),
              ),
            ),
          ],
        ),
      );
    }

    final dateChanged =
        next != null && !DateUtils.isSameDay(feed.referenceTime, next);
    final hours = feed.feedIntervalMinutes ~/ 60;
    final minutes = feed.feedIntervalMinutes % 60;
    final interval =
        '${hours > 0 ? '$hours 小时' : ''}${hours > 0 && minutes > 0 ? ' ' : ''}${minutes > 0 ? '$minutes 分钟' : ''}';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            !_hasRecord
                ? '记录后，开始计时'
                : '下次 ${dateChanged ? '${next.month}/${next.day} ' : ''}${TimeUtils.formatTime(next!)}',
            style: TextStyle(
              fontSize: 18,
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_hasRecord) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Icon(
                CupertinoIcons.circle_fill,
                size: 6,
                color: colors.accentLight,
              ),
            ),
            Text(
              '间隔 $interval',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final colors = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.width >= 600 && size.width > size.height && size.height < 360;
    final progress = _hasRecord
        ? (feed.timeElapsed.inSeconds / (feed.feedIntervalMinutes * 60)).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, compact ? 6 : 10, 24, compact ? 10 : 16),
      child: ExcludeSemantics(
        child: AppProgressTrack(
          value: progress,
          height: compact ? 4 : 6,
          backgroundColor: colors.border.withValues(alpha: .7),
          color: _alert
              ? colors.alert
              : _warning
              ? colors.warning
              : colors.accentLight,
        ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String title,
    String value, {
    VoidCallback? onTap,
    Alignment alignment = Alignment.center,
  }) {
    final content = Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: alignment == Alignment.centerLeft
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppPalette.of(context).textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    return onTap == null
        ? content
        : AppPressable(
            semanticLabel: '查看今日喂奶记录',
            onPressed: onTap,
            child: content,
          );
  }

  Widget _dock(BuildContext context, {required bool landscape}) {
    final colors = AppPalette.of(context);
    final record = FeedButton(
      onPressed: onRecord,
      onUndo: onUndo,
      enabled: feed.isInitialized && !feed.isSaving,
      orientation: landscape ? Orientation.landscape : Orientation.portrait,
    );
    final backfill = AppButton(
      key: const ValueKey('backfill-feed'),
      onPressed: feed.isSaving ? null : onBackfill,
      glass: false,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.clock, size: 24),
          SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '补记',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
    final elapsed = _hasRecord
        ? TimeUtils.formatDuration(feed.timeElapsed)
        : '— —';
    return AppGlassSurface(
      key: const ValueKey('feed-control-dock'),
      radius: landscape ? 44 : 32,
      padding: EdgeInsets.symmetric(
        horizontal: landscape ? 24 : 14,
        vertical: landscape && MediaQuery.sizeOf(context).height < 360 ? 8 : 14,
      ),
      child: landscape
          ? SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    flex: 27,
                    child: _metric(
                      context,
                      '已间隔',
                      elapsed,
                      alignment: Alignment.center,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(flex: 49, child: record),
                  const SizedBox(width: 16),
                  Expanded(flex: 24, child: backfill),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '已间隔',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          elapsed,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: record),
                    const SizedBox(width: 8),
                    SizedBox(width: 92, child: backfill),
                  ],
                ),
              ],
            ),
    );
  }
}
