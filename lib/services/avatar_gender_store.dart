import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/avatar_stage.dart';

/// Remembers if the user's avatar is a boy or a girl, on this phone.
///
/// Saved locally, separately for each logged-in account, so the right
/// character shows instantly. The backend keeps a copy too (GET /users/me
/// returns "gender"), which is used on a phone that has nothing saved yet.
class AvatarGenderStore {
  static String get _key {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return 'avatar_gender_$uid';
  }

  /// Saves the choice for the logged-in account.
  static Future<void> save(AvatarGender gender) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, gender.name); // 'girl' or 'boy'
  }

  /// The saved choice, or null if nothing was saved on this phone yet.
  static Future<AvatarGender?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return avatarGenderFrom(prefs.getString(_key));
  }

  /// Which character to show:
  /// 1. the choice saved on this phone (the most recent one),
  /// 2. otherwise the gender from the backend (chosen on Sign Up),
  /// 3. otherwise girl.
  static Future<AvatarGender> resolve({String? backendValue}) async {
    return await load() ??
        avatarGenderFrom(backendValue) ??
        AvatarGender.girl;
  }
}

/// Turns a saved or backend value into an AvatarGender.
/// Accepts 'girl'/'boy' (saved on the phone) and 'female'/'male' (backend).
AvatarGender? avatarGenderFrom(String? value) => switch (value) {
  'girl' || 'female' => AvatarGender.girl,
  'boy' || 'male' => AvatarGender.boy,
  _ => null,
};