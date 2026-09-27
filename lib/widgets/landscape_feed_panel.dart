import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';
import 'app_controls.dart';
import 'countdown_scale.dart';
import 'countdown_text.dart';
import 'feed_button.dart';

/// The slider keeps the same element path when the journal changes layout.
class LandscapeFeedPanel extends StatelessWidget {
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
  final FeedProvider feed;
  final SettingsProvider settings;
  final bool quiet;
  final Future<void> Function() onRecord;
  final Future<void> Function() onUndo;
  final Future<void> Function() onStopAlert;
  final VoidCallback onBackfill;
  final VoidCallback? onHistory;
  bool get _alert => feed.state == FeedState.alerting;
  bool get _warning => feed.state == FeedState.warning;
  bool get _hasRecord => feed.lastFeedTime != null;
  Color _timeColor(AppPalette p) => _alert
      ? p.alert
      : _warning
      ? p.warning
      : p.primary;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width >= 600 && size.width > size.height;
    final horizontalPadding = landscape && size.width >= 800 ? 32.0 : 24.0;
    final p = AppPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: landscape ? 1280 : 660),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            landscape ? 26 : 24,
            horizontalPadding,
            landscape ? 32 : 20,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: SizedBox(
                height: math.max(constraints.maxHeight, landscape ? 240 : 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      key: ValueKey(
                        landscape ? 'landscape-home' : 'portrait-home',
                      ),
                      height: landscape ? 0 : 84,
                      child: landscape ? null : _heading(context),
                    ),
                    if (feed.error != null)
                      Text(
                        feed.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.alert, fontSize: 12),
                      ),
                    Expanded(
                      child: Center(child: _countdown(context, landscape)),
                    ),
                    SizedBox(height: landscape ? 16 : 24),
                    SizedBox(
                      height: landscape ? 0 : 108,
                      child: landscape ? null : _facts(context),
                    ),
                    _dock(context, landscape),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final p = AppPalette.of(context);
    final now = feed.referenceTime;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '喂奶提醒',
            style: TextStyle(
              fontFamily: 'JournalChinese',
              color: p.primary,
              fontSize: 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${now.month}月${now.day}日  周${'一二三四五六日'[now.weekday - 1]}',
            style: TextStyle(
              fontFamily: 'JournalChinese',
              color: p.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdown(BuildContext context, bool landscape) {
    final p = AppPalette.of(context);
    final color = _timeColor(p);
    return Padding(
      padding: EdgeInsets.only(top: landscape ? 8 : 0),
      child: Column(
        // Keep the clock, scale and reminder together at every screen height.
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: FractionallySizedBox(
              widthFactor: landscape ? .94 : 1,
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  children: [
                    Text(
                      _alert
                          ? '该喂奶了，已超过'
                          : _warning
                          ? '快到喂奶时间'
                          : !_hasRecord
                          ? '等待第一条记录'
                          : '距离下次喂奶',
                      style: TextStyle(
                        fontFamily: 'JournalChinese',
                        color: _alert || _warning ? color : p.textPrimary,
                        fontSize: landscape ? 19 : 17,
                      ),
                    ),
                    if (quiet) ...[
                      const SizedBox(width: 10),
                      Tooltip(
                        message: '夜间静默',
                        child: Icon(
                          CupertinoIcons.moon,
                          size: 16,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            flex: 5,
            child: FractionallySizedBox(
              widthFactor: landscape ? .94 : 1,
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: CountdownText(
                  _hasRecord
                      ? TimeUtils.formatDuration(
                          _alert ? feed.overdue : feed.timeRemaining,
                        )
                      : '--:--:--',
                  key: ValueKey(
                    landscape ? 'landscape-countdown' : 'portrait-countdown',
                  ),
                  fontSize: landscape ? 180 : 108,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          FractionallySizedBox(
            widthFactor: .86,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: CountdownScale(
                  remaining: _hasRecord ? feed.timeRemaining : Duration.zero,
                  interval: Duration(minutes: feed.feedIntervalMinutes),
                  color: color,
                ),
              ),
            ),
          ),
          SizedBox(height: 48, child: _nextReminder(context)),
        ],
      ),
    );
  }

  Widget _nextReminder(BuildContext context) {
    final p = AppPalette.of(context);
    if (_alert) {
      return Align(
        alignment: Alignment.center,
        child: AppButton(
          onPressed: onStopAlert,
          surface: false,
          destructive: true,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.speaker_slash, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(feed.isAlertAcknowledged ? '本次提醒已停止' : '停止本次提醒'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final next = feed.nextFeedTime;
    final dateChanged =
        next != null && !DateUtils.isSameDay(feed.referenceTime, next);
    return Tooltip(
      message: '提醒间隔 ${feed.feedIntervalMinutes} 分钟',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: !_hasRecord ? '记录后，开始计时' : '下一次  ',
                style: TextStyle(
                  fontFamily: 'JournalChinese',
                  fontSize: 17,
                  color: p.textSecondary,
                ),
              ),
              if (_hasRecord)
                TextSpan(
                  text:
                      '${dateChanged ? '${next.month}/${next.day} ' : ''}${TimeUtils.formatTime(next!)}',
                  style: TextStyle(
                    fontFamily: 'JournalSerif',
                    fontSize: 25,
                    color: p.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _facts(BuildContext context) {
    final p = AppPalette.of(context);
    Widget metric(String title, String value, {String? detail}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'JournalChinese',
              color: p.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'JournalSerif',
              fontFamilyFallback: const ['JournalChinese'],
              color: p.textPrimary,
              fontSize: 30,
              height: 1.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (detail != null)
            Text(
              detail,
              style: TextStyle(color: p.textSecondary, fontSize: 11),
            ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: metric(
              '上次',
              _hasRecord ? TimeUtils.formatTime(feed.lastFeedTime!) : '— —',
              detail: _hasRecord
                  ? '已间隔 ${TimeUtils.formatDuration(feed.timeElapsed)}'
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: AppPressable(
              semanticLabel: '查看今日喂奶记录',
              onPressed: onHistory,
              child: metric('今天', '${feed.todayRecords.length} 次'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dock(BuildContext context, bool landscape) {
    final p = AppPalette.of(context);
    return SizedBox(
      key: const ValueKey('feed-control-dock'),
      height: 64,
      child: Row(
        children: [
          Expanded(
            child: FeedButton(
              onPressed: onRecord,
              onUndo: onUndo,
              enabled: feed.isInitialized && !feed.isSaving,
              orientation: landscape
                  ? Orientation.landscape
                  : Orientation.portrait,
            ),
          ),
          SizedBox(width: landscape ? 22 : 12),
          AppPressable(
            key: const ValueKey('backfill-feed'),
            semanticLabel: '补记',
            excludeSemantics: true,
            onPressed: feed.isSaving ? null : onBackfill,
            child: Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.primary, width: .8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '补记',
                    style: TextStyle(
                      fontFamily: 'JournalChinese',
                      color: p.primary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
