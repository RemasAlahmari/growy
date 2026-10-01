import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/habit_summary.dart';
import 'auth_service.dart';

/// What GET /users/me returns, used by the Home header and stats.
class UserProfile {
  const UserProfile({
    required this.username,
    required this.totalPoints,
    required this.currentLevel,
    required this.streakDays,
    required this.todayPoints,
  });

  final String username;
  final int totalPoints;
  final int currentLevel;
  final int streakDays;
  final int todayPoints;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: json['username'] as String? ?? '',
      totalPoints: (json['total_points'] as num? ?? 0).toInt(),
      currentLevel: (json['current_level'] as num? ?? 0).toInt(),
      streakDays: (json['streak_days'] as num? ?? 0).toInt(),
      todayPoints: (json['today_points'] as num? ?? 0).toInt(),
    );
  }
}

/// Loads everything the Home screen shows from the backend.
class HomeService {
  static const Duration _timeout = Duration(seconds: 10);

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not logged in');
    }
    final token = await user.getIdToken();
    return {'Authorization': 'Bearer $token'};
  }

  /// GET /users/me -> username, total_points, streak_days, today_points
  Future<UserProfile> getMe() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.backendUrl}/users/me'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load profile (${response.statusCode}): ${response.body}',
      );
    }
    return UserProfile.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// GET /habits/today -> each habit with completed_today and streak for this user
  Future<List<HabitSummary>> getTodayHabits() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.backendUrl}/habits/today'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load habits (${response.statusCode}): ${response.body}',
      );
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) {
      final json = item as Map<String, dynamic>;
      return HabitSummary(
        id: json['id'].toString(),
        name: json['name'] as String,
        // The CLIP label the photo will be checked against
        category: json['ai_label'] as String? ?? '',
        xpValue: (json['points'] as num).toInt(),
        completedToday: json['completed_today'] as bool? ?? false,
        streak: (json['streak'] as num? ?? 0).toInt(),
      );
    }).toList();
  }
}