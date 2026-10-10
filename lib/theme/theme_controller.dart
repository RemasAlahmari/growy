import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's appearance choice (System / Light / Dark) and saves it
/// on the phone, so it survives restarts.
///
/// Use the single shared instance: `themeController`.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static const String _key = 'growy_theme_mode';

  /// Reads the saved choice. Call once in main() before runApp.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_key)) {
        case 'light':
          value = ThemeMode.light;
        case 'dark':
          value = ThemeMode.dark;
        default:
          value = ThemeMode.system;
      }
    } catch (e) {
      debugPrint('Could not load theme setting: $e');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (e) {
      debugPrint('Could not save theme setting: $e');
    }
  }
}

final ThemeController themeController = ThemeController();
