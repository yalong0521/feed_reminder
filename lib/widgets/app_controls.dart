import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import 'app_surface.dart';

/// One interaction language: a quiet press, with keyboard and reader support.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.selected,
    this.excludeSemantics = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool? selected;
  final bool excludeSemantics;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  void didUpdateWidget(AppPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabling removes onTapUp, so an in-flight press may never release here.
    if (widget.onPressed == null) _pressed = false;
  }

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reduceMotion ? 0 : 140);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      excludeSemantics: widget.excludeSemantics,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
              ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
              ActivateIntent(),
          SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            includeRepeats: false,
          ): ActivateIntent(),
          // Consume repeats here so the app's default shortcuts cannot
          // reactivate a control while a dialog is opening or closing.
          SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
          SingleActivator(LogicalKeyboardKey.space): DoNothingIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): DoNothingIntent(),
        },
        actions: {
          DoNothingIntent: DoNothingAction(),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          onTapDown: enabled ? (_) => _press(true) : null,
          onTapUp: enabled ? (_) => _press(false) : null,
          onTapCancel: () => _press(false),
          child: AnimatedScale(
            scale: _pressed && enabled && !reduceMotion ? .97 : 1,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: !enabled ? .46 : (_pressed ? .72 : (_hovered ? .9 : 1)),
              duration: duration,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: _focused
                      ? Border.all(
                          color: AppPalette.of(context).primary,
                          width: 2,
                        )
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.child,
    this.onPressed,
    this.filled = false,
    this.destructive = false,
    this.surface = true,
    this.compact = false,
    this.padding,
    this.semanticLabel,
    this.radius = 16,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool filled;
  final bool destructive;
  final bool surface;
  final bool compact;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;
  final double radius;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final foreground = destructive
        ? colors.alert
        : filled
        ? colors.onPrimary
        : colors.textPrimary;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 44 : 48, minWidth: 44),
      child: Padding(
        padding:
            padding ??
            EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: 10),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: IconTheme(
            data: IconThemeData(color: foreground, size: 20),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    return AppPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      selected: selected,
      child: surface
          ? AppSurface(radius: radius, tinted: filled, child: content)
          : content,
    );
  }
}

final _appNotices = Expando<_AppNoticeController>('Active app error dialog');

/// Shows one explicit error dialog per navigator, replacing its content when
/// another error arrives. [duration] is retained for call-site compatibility;
/// dialogs stay open until the user closes them or chooses an action.
void showAppNotice(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  if (!context.mounted) {
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final request = _AppNoticeRequest(context, message, actionLabel, onAction);
  final active = _appNotices[navigator];
  if (active != null && active.isOpen) {
    active.replace(request);
    return;
  }

  final controller = _AppNoticeController(navigator, request);
  final route = CupertinoDialogRoute<void>(
    context: context,
    barrierDismissible: false,
    settings: const RouteSettings(name: 'app-error-dialog'),
    builder: (dialogContext) => PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          controller.markClosing();
        }
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final request = controller.request;
          final colors = AppPalette.of(context);
          return CupertinoAlertDialog(
            key: const ValueKey('app-notice-dialog'),
            title: Column(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_circle,
                  color: colors.alert,
                  size: 30,
                ),
                const SizedBox(height: 12),
                Text(
                  '操作未完成',
                  style: TextStyle(color: colors.textPrimary, fontSize: 20),
                ),
              ],
            ),
            content: Semantics(
              liveRegion: true,
              child: Text(
                request.message,
                key: const ValueKey('app-notice-message'),
                style: TextStyle(
                  color: colors.textSecondary,
                  height: 1.6,
                  fontSize: 15,
                ),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                key: const ValueKey('app-notice-close'),
                isDefaultAction: !request.hasAction,
                onPressed: controller.dismiss,
                child: const Text('关闭'),
              ),
              if (request.hasAction)
                CupertinoDialogAction(
                  key: const ValueKey('app-notice-action'),
                  isDefaultAction: true,
                  onPressed: controller.activate,
                  child: Text(request.actionLabel!),
                ),
            ],
          );
        },
      ),
    ),
  );
  controller.route = route;
  _appNotices[navigator] = controller;
  unawaited(navigator.push<void>(route));
  unawaited(
    route.completed.then((_) {
      // A new error may already have opened while the old dialog faded out.
      if (identical(_appNotices[navigator], controller)) {
        _appNotices[navigator] = null;
      }
      controller.dispose();
    }),
  );
}

class _AppNoticeRequest {
  const _AppNoticeRequest(
    this.sourceContext,
    this.message,
    this.actionLabel,
    this.onAction,
  );

  final BuildContext sourceContext;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  bool get hasAction =>
      actionLabel != null && actionLabel!.trim().isNotEmpty && onAction != null;
}

class _AppNoticeController extends ChangeNotifier {
  _AppNoticeController(this.navigator, this.request);

  final NavigatorState navigator;
  late final CupertinoDialogRoute<void> route;
  _AppNoticeRequest request;
  bool _closing = false;

  bool get isOpen => !_closing && route.isActive;

  void replace(_AppNoticeRequest next) {
    if (_closing) {
      return;
    }
    request = next;
    notifyListeners();
  }

  void markClosing() => _closing = true;

  void dismiss() {
    if (_closing || !navigator.mounted) {
      return;
    }
    _closing = true;
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      // Never pop an unrelated route that appeared above this dialog.
      navigator.removeRoute(route);
    }
  }

  void activate() {
    if (_closing) {
      return;
    }
    final current = request;
    dismiss();
    if (current.sourceContext.mounted) {
      current.onAction?.call();
    }
  }
}

Future<DateTime?> showAppDateTimePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
  CupertinoDatePickerMode mode = CupertinoDatePickerMode.dateAndTime,
  String title = '选择时间',
}) {
  var selected = initial;
  var closing = false;
  void close(BuildContext dialogContext, [DateTime? result]) {
    if (closing || ModalRoute.of(dialogContext)?.isCurrent != true) return;
    closing = true;
    Navigator.of(dialogContext).pop(result);
  }

  if (minimum != null && selected.isBefore(minimum)) selected = minimum;
  if (maximum != null && selected.isAfter(maximum)) selected = maximum;
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭时间选择',
    barrierColor: Colors.black.withValues(alpha: .3),
    transitionDuration: Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 220,
    ),
    transitionBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .96, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
    pageBuilder: (context, animation, secondary) => SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppSurface(
              radius: 24,
              padding: const EdgeInsets.all(20),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppPalette.of(context).textPrimary,
                  fontSize: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        AppButton(
                          surface: false,
                          compact: true,
                          onPressed: () => close(context),
                          child: const Text('取消'),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        AppButton(
                          compact: true,
                          filled: true,
                          onPressed: () => close(context, selected),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Divider(
                        color: AppPalette.of(context).border,
                        height: 1,
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height < 400
                          ? 170
                          : 216,
                      child: CupertinoDatePicker(
                        key: const ValueKey('app-date-time-picker'),
                        mode: mode,
                        initialDateTime: selected,
                        minimumDate: minimum,
                        maximumDate: maximum,
                        use24hFormat: true,
                        onDateTimeChanged: (value) => selected = value,
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
  );
}
