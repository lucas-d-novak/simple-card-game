import 'package:flutter/widgets.dart';

/// Screen-size classification used to adapt the UI between small touch devices
/// and wide desktop browsers.
enum ScreenClass { mobile, tablet, desktop }

/// Centralised responsive breakpoint strategy and sizing helpers.
///
/// Classification is based on the *available width* rather than the physical
/// device, so it works correctly inside a resizable desktop browser window as
/// well as on a phone.
class Responsive {
  Responsive._();

  /// Width below which we treat the layout as a narrow / touch phone.
  static const double mobileMaxWidth = 600;

  /// Width below which we treat the layout as a tablet (in between phone and
  /// full desktop).
  static const double tabletMaxWidth = 1000;

  /// The maximum content width on very wide screens, so the board does not
  /// stretch uncomfortably across an ultra-wide monitor.
  static const double maxContentWidth = 1400;

  /// Minimum comfortable touch-target size on mobile (Material guideline).
  static const double minTouchTarget = 48;

  static ScreenClass classify(double width) {
    if (width < mobileMaxWidth) return ScreenClass.mobile;
    if (width < tabletMaxWidth) return ScreenClass.tablet;
    return ScreenClass.desktop;
  }

  /// Classify using the ambient [MediaQuery] width.
  static ScreenClass of(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width);

  static bool isMobile(double width) => classify(width) == ScreenClass.mobile;
  static bool isDesktop(double width) => classify(width) == ScreenClass.desktop;

  /// Pick a value based on the screen class. [tablet] falls back to [mobile]
  /// when omitted; [desktop] falls back to [tablet].
  static T value<T>(
    double width, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    switch (classify(width)) {
      case ScreenClass.mobile:
        return mobile;
      case ScreenClass.tablet:
        return tablet ?? mobile;
      case ScreenClass.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }

  /// Card width used for cards in the hand / center row, scaled by screen size.
  static double handCardWidth(double availableWidth) => value(
        availableWidth,
        mobile: 84,
        tablet: 104,
        desktop: 118,
      );

  /// Card width for compact cards (champions / played-this-turn).
  static double compactCardWidth(double availableWidth) => value(
        availableWidth,
        mobile: 64,
        tablet: 74,
        desktop: 82,
      );
}
