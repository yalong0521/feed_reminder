import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_haptics.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';

/// A moving scale beneath a fixed pointer; its value stays in whole millilitres.
class MilkAmountRuler extends StatefulWidget {
  const MilkAmountRuler({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.label = '本次奶量',
  });

  final TextEditingController controller;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String label;

  int? get value {
    final text = controller.text;
    final amount = int.tryParse(text);
    return RegExp(r'^\d+$').hasMatch(text) &&
            amount != null &&
            amount >= 0 &&
            amount <= 2000
        ? amount
        : null;
  }

  @override
  State<MilkAmountRuler> createState() => _MilkAmountRulerState();
}

class _MilkAmountRulerState extends State<MilkAmountRuler> {
  static const _pixelsPerMl = 2.0;
  // Input and gestures share a stable range, independent of previous edits.
  static const _maximum = 2000;
  late int _position = _valid(widget.value) ? widget.value! : 0;
  late final _scroll = ScrollController(
    initialScrollOffset: _position * _pixelsPerMl,
    keepScrollOffset: false,
  );
  bool _syncing = false;
  bool _syncPending = false;
  bool _focused = false;
  bool _writingFromRuler = false;
  late String _observedText;
  int? _dragTick;

  static bool _valid(int? value) =>
      value != null && value >= 0 && value <= 2000;

  @override
  void initState() {
    super.initState();
    // Initialize before the first build so later input edits can be aligned.
    _scroll.addListener(_readScroll);
    _observedText = widget.controller.text;
    widget.controller.addListener(_inputChanged);
  }

  @override
  void didUpdateWidget(MilkAmountRuler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_inputChanged);
      widget.controller.addListener(_inputChanged);
      _observedText = widget.controller.text;
      if (_valid(widget.value)) {
        _position = widget.value!;
      }
      _alignToInput();
    } else if (oldWidget.enabled && !widget.enabled) {
      // Stop any ongoing fling when a surrounding save disables this field.
      _alignToInput();
    }
  }

  void _inputChanged() {
    if (widget.controller.text == _observedText) return;
    _observedText = widget.controller.text;
    if (_writingFromRuler) return;
    // Observe edits synchronously, before the next animation tick can overwrite
    // them. Waiting for didUpdateWidget loses a race with ballistic scrolling.
    _alignToInput();
    setState(() {
      if (_valid(widget.value)) {
        _position = widget.value!;
      }
    });
  }

  void _alignToInput() {
    if (_syncPending) return;
    _syncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncing = true;
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          (_position * _pixelsPerMl).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
      _syncPending = false;
      _syncing = false;
    });
  }

  void _readScroll() {
    if (_syncing || _syncPending || !widget.enabled || !_scroll.hasClients) {
      return;
    }
    final value = (_scroll.offset / _pixelsPerMl).round().clamp(0, _maximum);
    _position = value;
    if (value != widget.value) {
      _writingFromRuler = true;
      try {
        widget.onChanged(value);
      } finally {
        _writingFromRuler = false;
      }
    }
  }

  void _step(int delta) {
    if (!widget.enabled) return;
    final value = (_position + delta).clamp(0, _maximum);
    if (value != widget.value) {
      widget.onChanged(value);
      AppHaptics.selection();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !widget.enabled) return false;
    final tick =
        (notification.metrics.pixels / _pixelsPerMl).round().clamp(
          0,
          _maximum,
        ) ~/
        10;
    if (notification is ScrollStartNotification) {
      _dragTick = notification.dragDetails == null ? null : tick;
    } else if (notification is ScrollUpdateNotification) {
      // Finger-driven 10mL detents only. Text edits, alignment jumps and
      // ballistic scrolling after release must remain silent.
      if (notification.dragDetails != null &&
          _dragTick != null &&
          tick != _dragTick) {
        AppHaptics.selection();
      }
      _dragTick = notification.dragDetails == null ? null : tick;
    } else if (notification is ScrollEndNotification) {
      _dragTick = null;
    }
    return false;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_inputChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = AppTypography.caption(context).copyWith(
      fontSize: 12,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final height = 48.0 + scaler.scale(12) * 1.2 + 6;
    final increase = (_position + 10).clamp(0, _maximum);
    final decrease = (_position - 10).clamp(0, _maximum);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          slider: true,
          enabled: widget.enabled,
          label: '${widget.label}刻度',
          value: _valid(widget.value) ? '${widget.value} 毫升' : '未输入有效奶量',
          increasedValue: widget.enabled && increase != _position
              ? '$increase 毫升'
              : null,
          decreasedValue: widget.enabled && decrease != _position
              ? '$decrease 毫升'
              : null,
          onIncrease: widget.enabled && increase != _position
              ? () => _step(10)
              : null,
          onDecrease: widget.enabled && decrease != _position
              ? () => _step(-10)
              : null,
          child: FocusableActionDetector(
            enabled: widget.enabled,
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            mouseCursor: widget.enabled
                ? SystemMouseCursors.grab
                : SystemMouseCursors.basic,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowLeft): _StepMilk(-1),
              SingleActivator(LogicalKeyboardKey.arrowRight): _StepMilk(1),
              SingleActivator(LogicalKeyboardKey.arrowDown): _StepMilk(-10),
              SingleActivator(LogicalKeyboardKey.arrowUp): _StepMilk(10),
            },
            actions: {
              _StepMilk: CallbackAction<_StepMilk>(
                onInvoke: (intent) {
                  _step(intent.delta);
                  return null;
                },
              ),
            },
            child: ExcludeSemantics(
              child: Opacity(
                opacity: widget.enabled ? 1 : .46,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: _focused
                        ? Border.all(color: colors.primary, width: 2)
                        : null,
                  ),
                  child: SizedBox(
                    height: height,
                    // The numeric scale always increases left-to-right,
                    // independently of the surrounding text's reading direction.
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            NotificationListener<ScrollNotification>(
                              onNotification: _onScroll,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(
                                      scrollbars: false,
                                      overscroll: false,
                                      dragDevices: {
                                        ...PointerDeviceKind.values,
                                      },
                                    ),
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'milk-amount-ruler-scroll',
                                  ),
                                  controller: _scroll,
                                  scrollDirection: Axis.horizontal,
                                  physics: widget.enabled
                                      ? const ClampingScrollPhysics()
                                      : const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: constraints.maxWidth / 2,
                                  ),
                                  child: CustomPaint(
                                    size: Size(_maximum * _pixelsPerMl, height),
                                    painter: _RulerPainter(
                                      maximum: _maximum,
                                      pixelsPerMl: _pixelsPerMl,
                                      scroll: _scroll,
                                      viewportWidth: constraints.maxWidth,
                                      color: colors.textSecondary,
                                      labelStyle: labelStyle,
                                      textScaler: scaler,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: constraints.maxWidth / 2 - 1,
                              child: IgnorePointer(
                                child: Container(
                                  width: 2,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('左右拖动 · 精确到 1 mL', style: AppTypography.caption(context)),
            Text('0–$_maximum mL', style: AppTypography.caption(context)),
          ],
        ),
      ],
    );
  }
}

class _StepMilk extends Intent {
  const _StepMilk(this.delta);
  final int delta;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.maximum,
    required this.pixelsPerMl,
    required this.scroll,
    required this.viewportWidth,
    required this.color,
    required this.labelStyle,
    required this.textScaler,
  }) : super(repaint: scroll);

  final int maximum;
  final double pixelsPerMl;
  final ScrollController scroll;
  final double viewportWidth;
  final Color color;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients
        ? scroll.offset
        : scroll.initialScrollOffset;
    final visibleStart = offset - viewportWidth / 2 + 4;
    final visibleEnd = offset + viewportWidth / 2 - 4;
    final paint = Paint()
      ..color = color.withValues(alpha: .6)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var value = 0; value <= maximum; value += 10) {
      final major = value % 60 == 0 || value == maximum;
      final middle = value % 30 == 0;
      final x = value * pixelsPerMl;
      canvas.drawLine(
        Offset(
          x,
          major
              ? 16
              : middle
              ? 24
              : 30,
        ),
        Offset(x, 40),
        paint,
      );
      if (major && (value == maximum || maximum - value >= 30)) {
        final label = TextPainter(
          text: TextSpan(
            text: '$value',
            style: labelStyle.copyWith(color: color),
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();
        // Hide labels that would be cut into stray digits at the viewport edge.
        // The scale lines still extend naturally beyond the visible window.
        if (x - label.width / 2 >= visibleStart &&
            x + label.width / 2 <= visibleEnd) {
          label.paint(canvas, Offset(x - label.width / 2, 48));
        }
        label.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      oldDelegate.maximum != maximum ||
      oldDelegate.pixelsPerMl != pixelsPerMl ||
      oldDelegate.scroll != scroll ||
      oldDelegate.viewportWidth != viewportWidth ||
      oldDelegate.color != color ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.textScaler != textScaler;
}
