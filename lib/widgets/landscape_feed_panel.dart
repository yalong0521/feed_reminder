import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../providers/feed_provider.dart';
import '../utils/constants.dart';
import '../theme/app_typography.dart';
import 'app_page_header.dart';
import '../utils/time_utils.dart';
import 'app_controls.dart';
import 'countdown_timeline.dart';
import 'countdown_text.dart';
import 'feed_button.dart';
import 'overdue_duration.dart';
import 'overdue_timeline.dart';

/// The slider keeps the same element path when the journal changes layout.
class LandscapeFeedPanel extends StatelessWidget {
  const LandscapeFeedPanel({
    super.key,
    required this.feed,
    required this.quiet,
    required this.onRecord,
    required this.onUndo,
    required this.onStopAlert,
    required this.onBackfill,
    this.onHistory,
    this.pulseEnabled = true,
    this.defaultMilkAmountMl = 0,
    this.recordingEnabled = true,
    this.isMilkAmountAdjusted = false,
    this.onAdjustMilk,
    this.onSnooze,
  });
  final FeedProvider feed;
  final bool quiet;
  final Future<void> Function() onRecord;
  final Future<void> Function() onUndo;
  final Future<void> Function() onStopAlert;
  final VoidCallback onBackfill;
  final VoidCallback? onHistory;
  final bool pulseEnabled;
  final int defaultMilkAmountMl;
  final bool recordingEnabled;
  final bool isMilkAmountAdjusted;
  final VoidCallback? onAdjustMilk;
  final VoidCallback? onSnooze;
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
    final shortLandscape = landscape && size.height <= 500;
    final landscapeTopPadding = size.height <= 300
        ? 8.0
        : shortLandscape
        ? 12.0
        : 26.0;
    final landscapeBottomPadding = size.height <= 300
        ? 12.0
        : shortLandscape
        ? 16.0
        : 32.0;
    final horizontalPadding = landscape
        ? (size.width >= 800 ? 32.0 : 24.0)
        : AppPageLayout.contentPadding(size.width);
    final p = AppPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: landscape ? 1280 : double.infinity,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            landscape
                ? landscapeTopPadding
                : AppPageLayout.topPadding(AppPageLayout.compact(context)),
            horizontalPadding,
            landscape ? landscapeBottomPadding : 20,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: SizedBox(
                height: math.max(constraints.maxHeight, landscape ? 200 : 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      key: ValueKey(
                        landscape ? 'landscape-home' : 'portrait-home',
                      ),
                      constraints: landscape
                          ? const BoxConstraints.tightFor(height: 0)
                          : const BoxConstraints(minHeight: 84),
                      child: landscape ? null : _heading(context),
                    ),
                    if (feed.error != null)
                      Text(
                        feed.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: p.alert),
                      ),
                    Expanded(
                      child: Center(child: _countdown(context, landscape)),
                    ),
                    SizedBox(
                      height: landscape
                          ? shortLandscape
                                ? 12
                                : 16
                          : 24,
                    ),
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
    final now = feed.referenceTime;
    return AppPageHeader(
      title: AppStrings.appName,
      subtitle: '${now.month}月${now.day}日  周${'一二三四五六日'[now.weekday - 1]}',
      compact: AppPageLayout.compact(context),
    );
  }

  Widget _countdown(BuildContext context, bool landscape) {
    if (_alert) return _overdueCountdown(context, landscape);
    final p = AppPalette.of(context);
    final color = _timeColor(p);
    final time = _hasRecord
        ? TimeUtils.formatDuration(feed.timeRemaining)
        : '--:--:--';
    return Padding(
      padding: EdgeInsets.only(top: landscape ? 8 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                key: const ValueKey('countdown-details-scroll'),
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Keep the full clock visible before scrolling to details.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FractionallySizedBox(
                                widthFactor: landscape ? .94 : 1,
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Row(
                                    children: [
                                      Text(
                                        feed.isReminderDeferred
                                            ? '已延后提醒'
                                            : _warning
                                            ? '快到喂奶时间'
                                            : !_hasRecord
                                            ? '等待第一条记录'
                                            : '距离下次喂奶',
                                        style: TextStyle(
                                          color: _warning
                                              ? color
                                              : p.textPrimary,
                                          fontSize: 18,
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
                              const SizedBox(height: 10),
                              FractionallySizedBox(
                                widthFactor: landscape ? .94 : 1,
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: CountdownText(
                                    time,
                                    semanticLabel: !_hasRecord
                                        ? '等待第一条记录'
                                        : '距离下次喂奶 $time',
                                    key: ValueKey(
                                      landscape
                                          ? 'landscape-countdown'
                                          : 'portrait-countdown',
                                    ),
                                    fontSize: CountdownText.timerFontSize(
                                      landscape,
                                    ),
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
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
                          child: CountdownTimeline(
                            lastFeedTime: feed.lastFeedTime,
                            nextFeedTime: feed.nextFeedTime,
                            now: feed.referenceTime,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 28, child: _countdownFooter(context)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overdueCountdown(BuildContext context, bool landscape) {
    final p = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: landscape ? 8 : 0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final relaxedPortrait =
                      !landscape &&
                      constraints.maxHeight >= 380 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.2;
                  final timelineHeight = OverdueTimeline.requiredHeight(
                    context,
                    deadline: feed.nextFeedTime!,
                    now: feed.referenceTime,
                    width: math.min(560, constraints.maxWidth * .9),
                  );
                  final normalBeforeGap = relaxedPortrait ? 16.0 : 24.0;
                  final normalAfterGap = relaxedPortrait ? 7.0 : 12.0;
                  // Choose density from the content's actual font metrics.
                  // A tighter layout can still keep the complete timeline.
                  final normalHeight =
                      _overdueHeroHeight(
                        context,
                        constraints.maxWidth,
                        fontSize: CountdownText.timerFontSize(landscape),
                        compact: false,
                      ) +
                      normalBeforeGap +
                      timelineHeight +
                      normalAfterGap;
                  final compact =
                      landscape && normalHeight + 2 > constraints.maxHeight;
                  final beforeGap = compact ? 12.0 : normalBeforeGap;
                  final afterGap = compact ? 8.0 : normalAfterGap;
                  // Reserve the timeline while the fitted digits can remain
                  // readable. This minimum is a fit threshold, not a smaller
                  // font assigned to the overdue state.
                  final showTimeline =
                      !compact ||
                      _overdueHeroHeight(
                                context,
                                constraints.maxWidth,
                                fontSize: math.min(
                                  CountdownText.timerFontSize(landscape),
                                  96,
                                ),
                                compact: true,
                              ) +
                              beforeGap +
                              timelineHeight +
                              afterGap +
                              2 <=
                          constraints.maxHeight;
                  final heroHeight = showTimeline && landscape
                      ? math.max(
                          0.0,
                          constraints.maxHeight -
                              beforeGap -
                              timelineHeight -
                              afterGap,
                        )
                      : constraints.maxHeight;
                  return SingleChildScrollView(
                    key: const ValueKey('countdown-details-scroll'),
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: heroHeight),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: _overdueHero(context, landscape, compact),
                            ),
                          ),
                        ),
                        if (showTimeline) ...[
                          SizedBox(height: beforeGap),
                          FractionallySizedBox(
                            widthFactor: .9,
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 560,
                                ),
                                child: OverdueTimeline(
                                  deadline: feed.nextFeedTime!,
                                  now: feed.referenceTime,
                                  color: p.alert,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: afterGap),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            // Keep stopping the sound reachable even when the details scroll.
            SizedBox(height: 48, child: _countdownFooter(context)),
          ],
        ),
      ),
    );
  }

  static const _overdueSubtitleStyle = TextStyle(fontSize: 18, height: 1.3);

  double _overdueHeroHeight(
    BuildContext context,
    double width, {
    required double fontSize,
    required bool compact,
  }) {
    final inherited = DefaultTextStyle.of(context);
    final subtitle = TextPainter(
      text: TextSpan(
        text: '该喂奶了',
        style: inherited.style.merge(_overdueSubtitleStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: inherited.textHeightBehavior,
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final subtitleHeight = math.max(quiet ? 16.0 : 0.0, subtitle.height);
    subtitle.dispose();
    final duration = OverdueDuration.measure(
      context,
      duration: feed.overdue,
      fontSize: fontSize,
      unitFontSize: compact ? 24 : 30,
    );
    final scale = math.min(1.0, width / duration.width);
    return subtitleHeight + (compact ? 8 : 12) + duration.height * scale;
  }

  Widget _overdueHero(BuildContext context, bool landscape, bool compact) {
    final p = AppPalette.of(context);
    final subtitle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '该喂奶了',
          style: _overdueSubtitleStyle.copyWith(color: p.textSecondary),
        ),
        if (quiet) ...[
          const SizedBox(width: 10),
          Tooltip(
            message: '夜间静默',
            child: Icon(CupertinoIcons.moon, size: 16, color: p.textSecondary),
          ),
        ],
      ],
    );
    final duration = FittedBox(
      fit: BoxFit.scaleDown,
      child: OverdueDuration(
        key: ValueKey(landscape ? 'landscape-countdown' : 'portrait-countdown'),
        duration: feed.overdue,
        color: p.alert,
        fontSize: CountdownText.timerFontSize(landscape),
        unitFontSize: compact ? 24 : 30,
        pulse: pulseEnabled,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        subtitle,
        SizedBox(height: compact ? 8 : 12),
        duration,
      ],
    );
  }

  Widget _countdownFooter(BuildContext context) {
    if (_alert) {
      final stopped = feed.isAlertAcknowledged;
      final stopping = feed.isStoppingAlert;
      final saved = feed.isAlertAcknowledgementPersisted;
      final stopLabel = stopping
          ? '正在停止提醒…'
          : stopped
          ? saved
                ? '本次提醒已停止'
                : '重试保存停止状态'
          : '停止本次提醒';
      final statusColor = stopped && saved
          ? AppPalette.of(context).textSecondary
          : AppPalette.of(context).alert;
      final stopContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.speaker_slash, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                stopLabel,
                style: stopped && saved
                    ? AppTypography.supporting(context)
                    : null,
              ),
            ),
          ),
        ],
      );
      return Align(
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: stopped && saved && !stopping
                  ? Semantics(
                      liveRegion: true,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: stopContent,
                        ),
                      ),
                    )
                  : AppButton(
                      onPressed: feed.isSaving || stopping ? null : onStopAlert,
                      surface: false,
                      destructive: !stopped || !saved,
                      padding: EdgeInsets.zero,
                      child: stopContent,
                    ),
            ),
            if (!stopped && onSnooze != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: AppButton(
                  key: const ValueKey('snooze-reminder'),
                  surface: false,
                  onPressed: feed.isSaving || stopping ? null : onSnooze,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('稍后提醒'),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        feed.isReminderDeferred
            ? '下次提醒 ${TimeUtils.formatTime(feed.nextFeedTime!)}'
            : _hasRecord
            ? '本轮间隔 ${TimeUtils.formatInterval(feed.feedIntervalMinutes)}'
            : '记录后，开始计时',
        style: AppTypography.supporting(context),
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
          Text(title, style: AppTypography.supporting(context)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 30,
              height: 1.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (detail != null)
            Text(detail, style: AppTypography.caption(context)),
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
              child: metric(
                '今天',
                '${feed.todayRecords.length} 次',
                detail:
                    '${feed.todayRecords.fold<int>(0, (sum, record) => sum + record.milkAmountMl)} mL 已记录',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dock(BuildContext context, bool landscape) {
    const actionSize = 60.0;
    const actionRadius = actionSize / 2;
    Widget action({
      required String key,
      required String label,
      required IconData icon,
      required String semanticLabel,
      required VoidCallback? onPressed,
    }) => SizedBox(
      width: actionSize,
      height: actionSize,
      child: AppButton(
        key: ValueKey(key),
        compact: true,
        radius: actionRadius,
        padding: const EdgeInsets.all(6),
        semanticLabel: semanticLabel,
        onPressed: onPressed,
        child: ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(height: 3),
                Text(label, style: AppTypography.caption(context)),
              ],
            ),
          ),
        ),
      ),
    );
    final dock = SizedBox(
      key: const ValueKey('feed-control-dock'),
      height: 64,
      child: Row(
        children: [
          Expanded(
            child: FeedButton(
              onPressed: onRecord,
              onUndo: onUndo,
              milkAmountMl: defaultMilkAmountMl,
              enabled: recordingEnabled && feed.isInitialized && !feed.isSaving,
            ),
          ),
          if (landscape && onAdjustMilk != null) ...[
            const SizedBox(width: 12),
            action(
              key: 'adjust-meal-amount',
              label: '奶量',
              icon: CupertinoIcons.pencil,
              semanticLabel:
                  '调整本次奶量，$defaultMilkAmountMl 毫升${isMilkAmountAdjusted ? '，已调整' : ''}',
              onPressed: recordingEnabled && !feed.isSaving
                  ? onAdjustMilk
                  : null,
            ),
          ],
          const SizedBox(width: 12),
          action(
            key: 'backfill-feed',
            label: '补记',
            icon: CupertinoIcons.add,
            semanticLabel: '补记',
            onPressed: feed.isSaving ? null : onBackfill,
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Landscape keeps its full countdown height by placing this independent
        // action beside the slider. The keyed dock preserves slider/undo state
        // when rotation inserts or removes the portrait adjustment row.
        if (!landscape && onAdjustMilk != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const ValueKey('adjust-meal-amount'),
              compact: true,
              surface: false,
              onPressed: recordingEnabled && !feed.isSaving
                  ? onAdjustMilk
                  : null,
              child: Text(
                '本次奶量 · $defaultMilkAmountMl mL${isMilkAmountAdjusted ? ' · 已调整' : ' · 调整'}',
                style: AppTypography.caption(context),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        dock,
      ],
    );
  }
}
