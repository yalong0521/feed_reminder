import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

abstract final class AppPageLayout {
  static const maxContentWidth = 1120.0;
  static bool compact(BuildContext context) =>
      MediaQuery.sizeOf(context).height <= 500;

  static double horizontalPadding(double width) =>
      width < 600 ? 24 : (width < 1080 ? 28 : 48);

  static double contentPadding(double width) {
    final padding = horizontalPadding(width);
    final excess = (width - padding * 2 - maxContentWidth).clamp(
      0.0,
      double.infinity,
    );
    return padding + excess / 2;
  }

  static double topPadding(bool compact) => compact ? 18 : 36;
  static double headerGap(bool compact) => compact ? 20 : 32;
}

/// A single hierarchy and spacing contract for top-level page headings.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTypography.pageTitle(context, compact: compact),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(subtitle, style: AppTypography.supporting(context)),
        ],
      ],
    );
    if (trailing == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            constraints.maxWidth >= 560 &&
            MediaQuery.textScalerOf(context).scale(16) <= 22;
        if (inline) {
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 24),
              trailing!,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 16), trailing!],
        );
      },
    );
  }
}
