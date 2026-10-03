import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Text roles shared by every screen and overlay.
abstract final class AppTypography {
  static const bodyBase = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );
  static const supportingBase = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );
  static const captionBase = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );
  static TextStyle pageTitle(BuildContext context, {bool compact = false}) =>
      TextStyle(
        fontSize: compact ? 28 : 34,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
        color: AppPalette.of(context).primary,
      );

  static TextStyle sectionTitle(BuildContext context) => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0,
    color: AppPalette.of(context).textPrimary,
  );

  static TextStyle dialogTitle(BuildContext context) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0,
    color: AppPalette.of(context).primary,
  );

  static TextStyle body(BuildContext context) =>
      bodyBase.copyWith(color: AppPalette.of(context).textPrimary);

  static TextStyle label(BuildContext context) =>
      body(context).copyWith(fontWeight: FontWeight.w500);

  static TextStyle supporting(BuildContext context) =>
      supportingBase.copyWith(color: AppPalette.of(context).textSecondary);

  static TextStyle caption(BuildContext context) =>
      captionBase.copyWith(color: AppPalette.of(context).textSecondary);

  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0,
  );
}
