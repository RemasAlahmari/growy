import '../models/character_config.dart';
import '../utils/avatar_stage.dart';
import 'api_client.dart';

/// Talks to the backend's avatar endpoints:
///   GET /users/me/avatar  -> returns the saved colors (or defaults if none saved)
///   PUT /users/me/avatar  -> saves _config.toJson() (skin, hair, shirt, pants, shoes)
///   PUT /users/me         -> saves boy/girl ({"gender": "boy"|"girl"})
/// Errors are thrown as [ApiException].
class AvatarService {
  static const String _path = '/users/me/avatar';

  /// Loads the user's saved avatar. The response has the same keys as
  /// CharacterConfig.toJson(), so it goes straight into fromJson().
  Future<CharacterConfig> getMyAvatar() async {
    final json = await ApiClient.getJson(_path);
    return CharacterConfig.fromJson(json as Map<String, dynamic>);
  }

  /// Saves the user's avatar colors exactly as CharacterConfig.toJson() gives them.
  Future<void> saveMyAvatar(CharacterConfig config) async {
    await ApiClient.putJson(_path, config.toJson());
  }

  /// Saves boy/girl on the backend too, so the same character shows after
  /// logging in on another phone. (The backend stores it as male/female.)
  Future<void> saveGender(AvatarGender gender) async {
    await ApiClient.putJson('/users/me', {'gender': gender.name});
  }
}
