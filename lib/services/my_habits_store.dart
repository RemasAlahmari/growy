import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which habits (from the backend's habit list) the user added to their
/// personal list.
///
/// Saved on this phone only, per Firebase user, because the backend has no
/// endpoint for it. `null` means the user has never chosen, and the app
/// then treats every habit as added (so existing users don't see an empty
/// Home).
class MyHabitsStore {
  MyHabitsStore._();

  static String _key() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return 'my_habit_ids_$uid';
  }

  /// The saved habit ids, or null if the user never picked any.
  static Future<Set<String>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key())?.toSet();
  }

  static Future<void> save(Set<String> habitIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(), habitIds.toList());
  }
}