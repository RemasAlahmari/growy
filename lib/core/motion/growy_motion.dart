import 'package:flutter/material.dart';

/// Growy's motion tokens. Every animation in the app takes its duration and
/// curve from here, so motion feels the same on every screen.
///
/// Rule of thumb: calm by default, celebrate only on milestones.
class GrowyMotion {
  GrowyMotion._();

  // Durations
  static const Duration pressDown = Duration(milliseconds: 120);
  static const Duration pressUp = Duration(milliseconds: 180);
  static const Duration micro = Duration(milliseconds: 150);
  static const Duration enter = Duration(milliseconds: 400);
  static const Duration stagger = Duration(milliseconds: 350);
  static const Duration staggerStep = Duration(milliseconds: 60);
  static const Duration highlight = Duration(milliseconds: 600);
  static const Duration success = Duration(milliseconds: 700);
  static const Duration count = Duration(milliseconds: 600);
  static const Duration levelUp = Duration(milliseconds: 1600);
  static const Duration reducedFade = Duration(milliseconds: 150);

  /// Lists stop staggering after this many items; the rest arrive together.
  static const int maxStaggered = 6;

  /// How far content rises while it fades in.
  static const double enterOffset = 16;

  // Curves
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve pressCurve = Curves.easeOut;
  static const Curve popCurve = Curves.easeOutBack;
  static const Curve ambientCurve = Curves.easeInOutSine;

  /// True when the user turned on "Remove animations" (Android) or
  /// "Reduce Motion" (iOS). Animations then become short fades or nothing.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Delay for the [index]th item of a staggered list.
  static Duration staggerDelay(int index) {
    final step = index < maxStaggered ? index : maxStaggered - 1;
    return staggerStep * (step < 0 ? 0 : step);
  }
}
