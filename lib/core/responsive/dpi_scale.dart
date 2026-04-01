import 'package:flutter/material.dart';

/// Responsive scaling utility based on device screen density.
///
/// Uses a reference width of 375 logical pixels (iPhone SE / standard mobile).
/// All dimension helpers return values proportional to the actual screen width,
/// so the layout stays consistent across different DPIs and screen sizes.
class DpiScale {
  DpiScale._(this._factor);

  factory DpiScale.of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return DpiScale._(width / _referenceWidth);
  }

  static const double _referenceWidth = 375;

  final double _factor;

  /// Scale a dimension value proportionally to screen width.
  double scale(double value) => value * _factor;

  /// Scale for font sizes — clamped to avoid extremes on very large/small screens.
  double font(double value) => value * _factor.clamp(0.85, 1.3);

  /// Scale for padding / spacing.
  double space(double value) => value * _factor.clamp(0.8, 1.4);

  /// Scale for icon sizes.
  double icon(double value) => value * _factor.clamp(0.85, 1.3);

  /// Scale for border radius.
  double radius(double value) => value * _factor.clamp(0.9, 1.2);
}
