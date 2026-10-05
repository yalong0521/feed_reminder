import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/milk_statistics.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import 'app_controls.dart';

/// A keyboard- and screen-reader-accessible daily bar chart. Each day keeps a
/// full touch target, with horizontal scrolling instead of squeezing 30 bars.
class MilkVolumeChart extends StatefulWidget {
  const MilkVolumeChart({
    super.key,
    required this.days,
    required this.selectedDate,
    required this.onSelectDay,
  });

  final List<MilkDayStatistics> days;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDay;

  @override
  State<MilkVolumeChart> createState() => _MilkVolumeChartState();
}

class _MilkVolumeChartState extends State<MilkVolumeChart> {
  // The chart must not restore its offset from the surrounding vertical page.
  final _controller = ScrollController(keepScrollOffset: false);
  double _dayWidth = 44;
  double _visibleWidth = 0;

  @override
  void didUpdateWidget(MilkVolumeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedPage =
        oldWidget.days.first.date != widget.days.first.date ||
        oldWidget.days.last.date != widget.days.last.date;
    if (changedPage) {
      // Preserve a retained keyboard focus when today advances; otherwise
      // reveal the selected date after changing a same-length custom window.
      final focusedKey = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<_ChartDayFocus>()
          ?.key;
      final focusedDate = focusedKey is ValueKey<DateTime>
          ? focusedKey.value
          : null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final date = widget.days.any((day) => day.date == focusedDate)
            ? focusedDate
            : widget.selectedDate;
        final index = widget.days.indexWhere((day) => day.date == date);
        if (index < 0) return;
        final offset =
            (widget.days.length - index - .5) * _dayWidth - _visibleWidth / 2;
        _controller.jumpTo(
          offset.clamp(0.0, _controller.position.maxScrollExtent),
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final selectedDate = widget.selectedDate;
    final colors = AppPalette.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final caption = AppTypography.caption(context);
    Size measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: caption),
        textScaler: textScaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final maximum = days.fold(0, (value, day) => math.max(value, day.totalMl));
    final ceiling = math.max(100, (maximum / 100).ceil() * 100);
    final axisSize = measure('$ceiling');
    final plotHeight = math.max(160.0, axisSize.height * 3 + 24);
    final labelHeight = axisSize.height + 20;
    final dateWidth = days.fold(
      0.0,
      (width, day) =>
          math.max(width, measure('${day.date.month}/${day.date.day}').width),
    );
    final minimumDayWidth = math.max(44.0, dateWidth + 16);
    final axisWidth = math.max(42.0, axisSize.width + 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每日总奶量 · mL', style: AppTypography.caption(context)),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final visibleWidth = math.max(
              0.0,
              constraints.maxWidth - axisWidth,
            );
            final plotWidth = math.max(
              visibleWidth,
              days.length * minimumDayWidth,
            );
            final dayWidth = plotWidth / days.length;
            _dayWidth = dayWidth;
            _visibleWidth = visibleWidth;
            final plot = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: axisWidth,
                    height: plotHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final amount in [ceiling, ceiling ~/ 2, 0])
                          Text(
                            '$amount',
                            style: AppTypography.caption(context),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        ...ScrollConfiguration.of(context).dragDevices,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: SingleChildScrollView(
                      key: ValueKey('milk-chart-scroll-${days.length}'),
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      // Start with the most recent days in view, including the
                      // default selection, while dates remain chronological.
                      reverse: true,
                      child: SizedBox(
                        width: plotWidth,
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: plotHeight,
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var line = 0; line < 3; line++)
                                    Container(height: 1, color: colors.border),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                for (final day in days)
                                  _ChartDayFocus(
                                    key: ValueKey(day.date),
                                    child: AppPressable(
                                      key: ValueKey(
                                        'milk-chart-day-${day.date.toIso8601String()}',
                                      ),
                                      selected: day.date == selectedDate,
                                      semanticLabel:
                                          '${day.date.month}月${day.date.day}日，'
                                          '${day.totalMl}毫升，${day.feedCount}次喂奶，'
                                          '${day.unrecordedCount}次未记录奶量',
                                      excludeSemantics: true,
                                      onPressed: () =>
                                          widget.onSelectDay(day.date),
                                      child: SizedBox(
                                        width: dayWidth,
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              height: plotHeight,
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: Container(
                                                  width: math.min(
                                                    24,
                                                    dayWidth * .5,
                                                  ),
                                                  height: day.totalMl == 0
                                                      ? 2
                                                      : math.max(
                                                          2,
                                                          plotHeight *
                                                              day.totalMl /
                                                              ceiling,
                                                        ),
                                                  decoration: BoxDecoration(
                                                    color: day.totalMl == 0
                                                        ? colors.textTertiary
                                                        : colors.primary.withValues(
                                                            alpha:
                                                                day.date ==
                                                                    selectedDate
                                                                ? 1
                                                                : .48,
                                                          ),
                                                    borderRadius:
                                                        const BorderRadius.vertical(
                                                          top: Radius.circular(
                                                            5,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: labelHeight,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    '${day.date.month}/${day.date.day}',
                                                    style:
                                                        AppTypography.caption(
                                                          context,
                                                        ).copyWith(
                                                          color:
                                                              day.date ==
                                                                  selectedDate
                                                              ? colors.primary
                                                              : colors
                                                                    .textSecondary,
                                                          fontWeight:
                                                              day.date ==
                                                                  selectedDate
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Container(
                                                    width: 4,
                                                    height: 4,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color:
                                                          day.date ==
                                                              selectedDate
                                                          ? colors.primary
                                                          : Colors.transparent,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                plot,
                const SizedBox(height: 6),
                Text(
                  plotWidth > visibleWidth ? '左右滑动查看日期，点按柱形查看明细。' : '点按柱形查看明细。',
                  style: AppTypography.caption(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Observe the existing button's focus without adding another Tab stop.
class _ChartDayFocus extends StatelessWidget {
  const _ChartDayFocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused) {
          // This context belongs to one date, so both forward and backward
          // traversal reveal its full target in the reversed horizontal plot.
          Scrollable.ensureVisible(
            context,
            alignment: .5,
            duration: Duration(milliseconds: reduceMotion ? 0 : 180),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: child,
    );
  }
}
