import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import 'app_surface.dart';
import 'app_controls.dart';
import '../theme/app_typography.dart';

/// Pointer input must start on the handle and reach the end before release.
/// Assistive slider adjustments and deliberate keyboard steps are equivalent.
class FeedButton extends StatefulWidget {
  final Future<void> Function() onPressed;
  final Future<void> Function()? onUndo;
  final bool enabled;
  final int? milkAmountMl;
  const FeedButton({
    super.key,
    required this.onPressed,
    this.onUndo,
    this.enabled = true,
    this.milkAmountMl,
  });
  @override
  State<FeedButton> createState() => _FeedButtonState();
}

class _FeedButtonState extends State<FeedButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'Feed confirmation slider');
  Timer? _confirmationTimer;
  bool _busy = false;
  bool _saved = false;
  bool _failed = false;
  bool _undoFailed = false;
  bool _undoing = false;
  bool _dragging = false;
  bool _showFocusHighlight = false;
  bool _pointerInput = false;
  int? _pressedPointer;
  double? _layoutWidth;
  double? _gestureWidth;

  bool get _interactive => widget.enabled && !_busy && !_saved;

  @override
  void didUpdateWidget(FeedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && !_busy && !_saved) _reset();
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    _focus.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _reset() {
    if (!mounted) return;
    _releasePress();
    _dragging = false;
    _gestureWidth = null;
    if (MediaQuery.disableAnimationsOf(context)) {
      _progress.value = 0;
    } else {
      _progress.animateTo(0, curve: Curves.easeOutCubic);
    }
  }

  void _releasePress() {
    if (_pressedPointer != null) setState(() => _pressedPointer = null);
  }

  Future<void> _record() async {
    if (!_interactive) return;
    _confirmationTimer?.cancel();
    setState(() {
      _busy = true;
      _failed = false;
      _dragging = false;
      _pressedPointer = null;
      _showFocusHighlight = false;
    });
    _progress.value = 1;
    try {
      await widget.onPressed();
      if (!mounted) return;
      unawaited(HapticFeedback.lightImpact());
      setState(() {
        _saved = true;
        _busy = false;
        _undoFailed = false;
      });
      _scheduleReset();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
      _reset();
    }
  }

  void _scheduleReset() {
    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        _saved = false;
        _undoFailed = false;
      });
      _progress.value = 0;
    });
  }

  Future<void> _undo() async {
    if (_busy || !widget.enabled || widget.onUndo == null) return;
    _confirmationTimer?.cancel();
    setState(() {
      _busy = true;
      _undoing = true;
    });
    try {
      await widget.onUndo!();
      if (!mounted) return;
      setState(() {
        _saved = false;
        _busy = false;
        _undoing = false;
        _undoFailed = false;
      });
      _progress.value = 0;
    } catch (_) {
      if (!mounted) return;
      // Leave time to retry without permanently blocking the next recording.
      setState(() {
        _busy = false;
        _undoing = false;
        _undoFailed = true;
      });
      _scheduleReset();
    }
  }

  void _advance({required bool assistive}) {
    if (!_interactive) return;
    _beginAdjustment();
    _progress.value = (_progress.value + .25).clamp(0, 1);
    if (assistive && _progress.value >= 1) _record();
  }

  void _beginAdjustment() {
    // The return animation is decorative. A new attempt must never inherit
    // the cancelled attempt's remaining visual progress.
    if (_progress.isAnimating) _progress.value = 0;
  }

  void _decrease() {
    if (!_interactive) return;
    _beginAdjustment();
    _progress.value = (_progress.value - .25).clamp(0, 1);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final showFocus =
          widget.enabled &&
          _focus.hasFocus &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
      if (_pointerInput || _showFocusHighlight != showFocus) {
        setState(() {
          _pointerInput = false;
          _showFocusHighlight = showFocus;
        });
      }
    }
    if (!_interactive) return KeyEventResult.ignored;
    final controlKey = const [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.escape,
    ].contains(event.logicalKey);
    if (controlKey && event is! KeyDownEvent) {
      // Held keys must neither advance confirmation nor move focus away.
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _advance(assistive: false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _decrease();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _reset();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if ((event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          !_progress.isAnimating &&
          _progress.value >= 1) {
        _record();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final previousWidth = _layoutWidth;
      _layoutWidth = width;
      if (previousWidth != null &&
          previousWidth != width &&
          !_busy &&
          !_saved &&
          (_progress.value > 0 || _pressedPointer != null)) {
        _gestureWidth = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_busy && !_saved) _reset();
        });
      }
      final colors = AppPalette.of(context);
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      const inset = 6.0;
      const handle = 52.0;
      final travel = (width - inset * 2 - handle).clamp(1.0, double.infinity);
      return Listener(
        // Desktop pointer events can leave Flutter in keyboard highlight mode.
        // Hide that ring until keyboard input resumes, without dropping focus.
        onPointerDown: (_) {
          if (!_pointerInput) setState(() => _pointerInput = true);
        },
        child: SizedBox(
          key: const ValueKey('feed-slide-track'),
          height: 64,
          width: double.infinity,
          child: _saved || _busy
              ? AppSurface(
                  tinted: true,
                  radius: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (_busy)
                        CupertinoActivityIndicator(color: colors.onPrimary)
                      else
                        Icon(
                          _undoFailed
                              ? CupertinoIcons.exclamationmark_circle
                              : CupertinoIcons.check_mark_circled_solid,
                          color: colors.onPrimary,
                          size: 25,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          label: _undoFailed ? '撤销失败，记录仍然保留，可以重试撤销' : null,
                          excludeSemantics: _undoFailed,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _undoing
                                  ? '正在撤销…'
                                  : _busy
                                  ? '正在保存…'
                                  : _undoFailed
                                  ? '撤销失败'
                                  : '已记录',
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_saved && widget.onUndo != null)
                        AppButton(
                          key: const ValueKey('feed-slide-undo'),
                          surface: false,
                          compact: true,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          onPressed: _busy || !widget.enabled ? null : _undo,
                          child: Text(
                            '撤销',
                            style: AppTypography.button.copyWith(
                              color: colors.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : Semantics(
                  key: const ValueKey('feed-slide-save-status'),
                  container: true,
                  explicitChildNodes: true,
                  // Keep the live message separate from animated progress,
                  // so returning the thumb does not reannounce each frame.
                  liveRegion: _failed,
                  label: _failed ? '记录未保存，请向右滑动重试' : null,
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onKey,
                    child: FocusableActionDetector(
                      focusNode: _focus,
                      enabled: widget.enabled,
                      // Pointer drags keep focus for later keyboard adjustments,
                      // but only keyboard navigation needs a visible focus ring.
                      onShowFocusHighlight: (value) {
                        if (_showFocusHighlight != value) {
                          setState(() => _showFocusHighlight = value);
                        }
                      },
                      onFocusChange: (value) {
                        if (!value) {
                          if (_pointerInput) {
                            setState(() => _pointerInput = false);
                          }
                          if (!_dragging) _reset();
                        }
                      },
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) => Semantics(
                          slider: true,
                          enabled: _interactive,
                          excludeSemantics: true,
                          label: _failed ? '记录未保存，向右滑动重试' : '滑动记录这次喂奶',
                          hint:
                              '${widget.milkAmountMl == null
                                  ? ''
                                  : widget.milkAmountMl == 0
                                  ? '本次暂不记录奶量。'
                                  : '本次记录 ${widget.milkAmountMl} 毫升。'}向右滑到底并松开确认。键盘按右方向键逐步推进，再按回车确认。',
                          value:
                              '${_failed ? '未保存，' : ''}${(_progress.value * 100).round()}%',
                          increasedValue:
                              '${((_progress.value + .25).clamp(0, 1) * 100).round()}%',
                          decreasedValue:
                              '${((_progress.value - .25).clamp(0, 1) * 100).round()}%',
                          onIncrease: _interactive
                              ? () => _advance(assistive: true)
                              : null,
                          onDecrease: _interactive ? _decrease : null,
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              border: _showFocusHighlight && !_pointerInput
                                  ? Border.all(color: colors.primary, width: 2)
                                  : null,
                            ),
                            child: AppSurface(
                              color: colors.softGreen,
                              outlined: false,
                              radius: 32,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width:
                                        inset * 2 +
                                        handle +
                                        travel * _progress.value,
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: Curves.easeOut.transform(
                                          _progress.value,
                                        ),
                                        child: DecoratedBox(
                                          key: const ValueKey(
                                            'feed-slide-fill',
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              32,
                                            ),
                                            gradient: LinearGradient(
                                              colors: [
                                                Color.lerp(
                                                  colors.softGreen,
                                                  colors.primary,
                                                  .08 + .1 * _progress.value,
                                                )!,
                                                Color.lerp(
                                                  colors.softGreen,
                                                  colors.primary,
                                                  .2 + .16 * _progress.value,
                                                )!,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 66,
                                        right: 16,
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity: (1 - _progress.value * 1.7)
                                              .clamp(0, 1),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _failed
                                                      ? '未保存，右滑重试'
                                                      : '滑动记录喂奶',
                                                  style: AppTypography.button
                                                      .copyWith(
                                                        color: colors
                                                            .textSecondary
                                                            .withValues(
                                                              alpha:
                                                                  widget.enabled
                                                                  ? 1
                                                                  : .5,
                                                            ),
                                                      ),
                                                ),
                                                if (widget.milkAmountMl !=
                                                        null &&
                                                    !_failed)
                                                  Text(
                                                    widget.milkAmountMl == 0
                                                        ? '奶量未设置 · 可在设置中配置'
                                                        : '本次 ${widget.milkAmountMl} mL',
                                                    key: const ValueKey(
                                                      'feed-default-milk-amount',
                                                    ),
                                                    style:
                                                        AppTypography.caption(
                                                          context,
                                                        ).copyWith(
                                                          fontSize: 12,
                                                          color: colors
                                                              .textSecondary
                                                              .withValues(
                                                                alpha:
                                                                    widget
                                                                        .enabled
                                                                    ? 1
                                                                    : .5,
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
                                  if (_progress.value > .65)
                                    Positioned.fill(
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 60,
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              _progress.value >= .92
                                                  ? '松开确认'
                                                  : '继续向右滑',
                                              style: AppTypography.button
                                                  .copyWith(
                                                    color: colors.textPrimary,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    key: const ValueKey(
                                      'feed-slide-handle-position',
                                    ),
                                    left: inset + travel * _progress.value,
                                    top: inset,
                                    width: handle,
                                    height: handle,
                                    child: MouseRegion(
                                      cursor: _interactive
                                          ? (_pressedPointer != null
                                                ? SystemMouseCursors.grabbing
                                                : SystemMouseCursors.grab)
                                          : SystemMouseCursors.basic,
                                      child: Listener(
                                        onPointerDown: !_interactive
                                            ? null
                                            : (event) {
                                                if (_pressedPointer == null &&
                                                    event.buttons ==
                                                        kPrimaryButton) {
                                                  setState(
                                                    () => _pressedPointer =
                                                        event.pointer,
                                                  );
                                                }
                                              },
                                        onPointerUp: (event) {
                                          if (_pressedPointer ==
                                              event.pointer) {
                                            _releasePress();
                                          }
                                        },
                                        // Flutter ends an accepted drag on pointer
                                        // cancellation too. Invalidate it first.
                                        onPointerCancel: (_) => _reset(),
                                        child: GestureDetector(
                                          key: const ValueKey(
                                            'feed-slide-thumb',
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          dragStartBehavior:
                                              DragStartBehavior.down,
                                          excludeFromSemantics: true,
                                          onHorizontalDragStart: !_interactive
                                              ? null
                                              : (_) {
                                                  _beginAdjustment();
                                                  _progress.stop();
                                                  _dragging = true;
                                                  _gestureWidth = width;
                                                  _focus.requestFocus();
                                                },
                                          onHorizontalDragUpdate: !_interactive
                                              ? null
                                              : (details) {
                                                  if (!_dragging ||
                                                      _gestureWidth !=
                                                          _layoutWidth) {
                                                    return;
                                                  }
                                                  _progress.value =
                                                      (_progress.value +
                                                              details.delta.dx /
                                                                  travel)
                                                          .clamp(0, 1);
                                                },
                                          onHorizontalDragEnd: !_interactive
                                              ? null
                                              : (_) {
                                                  final confirmed =
                                                      _dragging &&
                                                      _gestureWidth ==
                                                          _layoutWidth &&
                                                      _progress.value >= .92;
                                                  _dragging = false;
                                                  if (confirmed) {
                                                    _record();
                                                  } else {
                                                    _reset();
                                                  }
                                                },
                                          onHorizontalDragCancel: _reset,
                                          // Scale only the artwork; the original
                                          // 52px gesture target stays stable.
                                          child: AnimatedScale(
                                            scale:
                                                _pressedPointer != null &&
                                                    _interactive &&
                                                    !reduceMotion
                                                ? .94
                                                : 1,
                                            duration: Duration(
                                              milliseconds: reduceMotion
                                                  ? 0
                                                  : 140,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            child: DecoratedBox(
                                              key: const ValueKey(
                                                'feed-slide-thumb-visual',
                                              ),
                                              decoration: BoxDecoration(
                                                color: colors.primary
                                                    .withValues(
                                                      alpha: widget.enabled
                                                          ? 1
                                                          : .45,
                                                    ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                CupertinoIcons.arrow_right,
                                                color: colors.onPrimary,
                                                size: 25,
                                              ),
                                            ),
                                          ),
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
      );
    },
  );
}
