import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/character_config.dart';
import 'auth_service.dart';

/// Talks to the backend's avatar endpoints:
///   GET /users/me/avatar  -> returns the saved colors (or defaults if none saved)
///   PUT /users/me/avatar  -> saves _config.toJson() (skin, hair, shirt, pants, shoes)
class AvatarService {
  static const Duration _timeout = Duration(seconds: 10);

  String get _avatarUrl => '${AuthService.backendUrl}/users/me/avatar';

  /// Same auth header as every other request: Bearer <Firebase ID token>.
  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not logged in');
    }
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Loads the user's saved avatar. The response has the same keys as
  /// CharacterConfig.toJson(), so it goes straight into fromJson().
  Future<CharacterConfig> getMyAvatar() async {
    final response = await http
        .get(Uri.parse(_avatarUrl), headers: await _headers())
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load avatar (${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CharacterConfig.fromJson(json);
  }

  /// Saves the user's avatar colors exactly as CharacterConfig.toJson() gives them.
  Future<void> saveMyAvatar(CharacterConfig config) async {
    final response = await http
        .put(
          Uri.parse(_avatarUrl),
          headers: await _headers(),
          body: jsonEncode(config.toJson()),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to save avatar (${response.statusCode}): ${response.body}',
      );
    }
  }
}