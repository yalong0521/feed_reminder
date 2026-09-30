import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import 'app_surface.dart';

/// The journal's confirmation/error surface, with actions outside the scroll
/// area in normal layouts; very short keyboard layouts scroll the whole sheet.
class AppMessageDialog extends StatelessWidget {
  const AppMessageDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.detail,
    this.icon,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final Widget? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final compact = MediaQuery.sizeOf(context).height < 440;
    final inset = compact ? 16.0 : 24.0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: Listener(
                // Paper is painted by an IgnorePointer surface; absorb its
                // inner padding so only taps outside the sheet dismiss it.
                behavior: HitTestBehavior.opaque,
                child: AppSurface(
                  radius: 24,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final body = Padding(
                        padding: EdgeInsets.all(inset),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              namesRoute: true,
                              header: true,
                              child: Row(
                                children: [
                                  if (icon != null) ...[
                                    ExcludeSemantics(
                                      child: Icon(
                                        icon,
                                        size: 22,
                                        color: colors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 24,
                                        height: 1.4,
                                        fontWeight: FontWeight.w500,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (detail != null) ...[
                              const SizedBox(height: 16),
                              detail!,
                            ],
                            const SizedBox(height: 12),
                            DefaultTextStyle.merge(
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 15,
                                height: 1.6,
                              ),
                              child: content,
                            ),
                          ],
                        ),
                      );
                      final actionBar = Padding(
                        padding: EdgeInsets.all(inset),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final stackActions =
                                actions.length > 1 &&
                                (constraints.maxWidth < 280 ||
                                    (constraints.maxWidth < 360 &&
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(16) >
                                            24));
                            if (stackActions) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < actions.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 8),
                                    actions[i],
                                  ],
                                ],
                              );
                            }
                            return Row(
                              children: [
                                for (var i = 0; i < actions.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 12),
                                  Expanded(child: actions[i]),
                                ],
                              ],
                            );
                          },
                        ),
                      );
                      // A keyboard can leave less height than a single action.
                      // In that case both content and actions must be scrollable.
                      final scrollAll = constraints.maxHeight < 240;
                      final sheet = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (scrollAll)
                            body
                          else
                            Flexible(child: SingleChildScrollView(child: body)),
                          Divider(height: 1, color: colors.border),
                          actionBar,
                        ],
                      );
                      return scrollAll
                          ? SingleChildScrollView(child: sheet)
                          : sheet;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

RawDialogRoute<T> createAppMessageDialogRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) => RawDialogRoute<T>(
  settings: settings,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: .3),
  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  transitionDuration: Duration(
    milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
  ),
  pageBuilder: (context, animation, secondaryAnimation) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          Navigator.of(context).maybePop();
        }
      },
    },
    child: Focus(autofocus: true, child: builder(context)),
  ),
  transitionBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation.drive(
            Tween(
              begin: .97,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
);
