import 'package:flutter/material.dart';

/// Growy's light and dark colours in one place.
///
/// Every screen reads its colours through [GrowyPalette] (directly, through
/// [AppColors], or through a screen's private `_GrowyColors` class), so the
/// whole app switches between light and dark by flipping [isDark].
///
/// [isDark] is set by `GrowyApp` (main.dart) from the theme the user picked
/// in Me → Appearance. Do not set it anywhere else.
class GrowyPalette {
  GrowyPalette._();

  static bool isDark = false;

  static Color _pick(Color light, Color dark) => isDark ? dark : light;

  // Brand
  static Color get primary =>
      _pick(const Color(0xFF6FA37B), const Color(0xFF7DB389));
  static Color get primaryTint =>
      _pick(const Color(0xFFE9F2EB), const Color(0xFF1F2D23));
  static Color get secondary => const Color(0xFFF0B8AE);
  static Color get secondaryTint =>
      _pick(const Color(0xFFFCEEEB), const Color(0xFF35262A));
  static Color get secondaryDeep =>
      _pick(const Color(0xFFD9887A), const Color(0xFFEBA497));

  // Surfaces
  /// Page and card background (white in light mode).
  static Color get surface =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF151816));

  /// Raised surface: cards on Home, input fills, photo placeholders.
  static Color get surfaceRaised =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF1D211E));

  /// Light grey placeholder (e.g. empty photo box).
  static Color get surfaceMuted =>
      _pick(const Color(0xFFF4F4F4), const Color(0xFF222723));

  /// Warm cream page background used on Home, Verify and the customizer.
  static Color get cream =>
      _pick(const Color(0xFFF8F1EC), const Color(0xFF121513));

  static Color get cardBorder =>
      _pick(const Color(0xFFEEEEEE), const Color(0xFF2A302C));
  static Color get inputBorder =>
      _pick(const Color(0xFFD8D8D8), const Color(0xFF3A413C));

  // Text
  static Color get textMain =>
      _pick(const Color(0xFF2E2E2E), const Color(0xFFECEFEC));
  static Color get textSecondary =>
      _pick(const Color(0xFF8A8A8A), const Color(0xFFA2A9A4));
  static Color get textDisabled =>
      _pick(const Color(0xFFC4C4C4), const Color(0xFF5B625D));
  static Color get placeholder =>
      _pick(const Color(0xFFB8B8B8), const Color(0xFF6E7570));

  // States
  static Color get error =>
      _pick(const Color(0xFFD9534F), const Color(0xFFE57A75));
  static Color get errorTint =>
      _pick(const Color(0x1FD9534F), const Color(0x33E57A75));
  static Color get success =>
      _pick(const Color(0xFF4CAF50), const Color(0xFF6CC070));

  /// Soft amber for "try again" states that aren't the user's fault
  /// (e.g. a photo the AI couldn't verify).
  static Color get warning =>
      _pick(const Color(0xFFD9932B), const Color(0xFFE8AE55));

  // Medals stay the same in both modes.
  static Color get gold => const Color(0xFFE0B84C);
  static Color get silver => const Color(0xFFA8A8A8);
  static Color get bronze => const Color(0xFFC68A5A);

  // Effects
  static Color get buttonShadow =>
      _pick(const Color(0x596FA37B), const Color(0x33000000));
  static Color get checkingOverlay =>
      _pick(const Color(0x99FFFFFF), const Color(0x99000000));
  static Color get cameraScrim => const Color(0x8C000000);

  /// A thin divider / unselected outline (was Colors.black12).
  static Color get hairline =>
      _pick(const Color(0x1F000000), const Color(0x29FFFFFF));
}

/// Older token names used by the auth screens, Home, Verify and the
/// customizer. They now follow the light/dark palette.
class AppColors {
  AppColors._();

  static Color get primary => GrowyPalette.primary;
  static Color get secondary => GrowyPalette.secondary;
  static Color get secondaryText => GrowyPalette.textSecondary;
  static Color get border => GrowyPalette.inputBorder;
  static Color get placeholder => GrowyPalette.placeholder;
  static Color get mainText => GrowyPalette.textMain;
  static Color get background => GrowyPalette.cream;
  static Color get textDark => GrowyPalette.textMain;
  static Color get textGray => GrowyPalette.textSecondary;
  static Color get hintGray => GrowyPalette.placeholder;
  static Color get inputFill => GrowyPalette.surfaceRaised;

  /// Plain page background (white in light mode). Login, Sign Up, Welcome.
  static Color get surface => GrowyPalette.surface;

  /// Card background (white in light mode).
  static Color get card => GrowyPalette.surfaceRaised;
}

/// Material themes, so built-in widgets (dialogs, snack bars, switches,
/// pickers) match Growy in both modes.
class GrowyThemes {
  GrowyThemes._();

  static const Color _seed = Color(0xFF6FA37B);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
      primary: _seed,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      primary: const Color(0xFF7DB389),
      surface: const Color(0xFF151816),
    ),
    scaffoldBackgroundColor: const Color(0xFF151816),
  );
}
