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
    required this.gender, 
  });

  final String username;
  final int totalPoints;
  final int currentLevel;
  final int streakDays;
  final int todayPoints;
  final String? gender;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: json['username'] as String? ?? '',
      totalPoints: (json['total_points'] as num? ?? 0).toInt(),
      currentLevel: (json['current_level'] as num? ?? 0).toInt(),
      streakDays: (json['streak_days'] as num? ?? 0).toInt(),
      todayPoints: (json['today_points'] as num? ?? 0).toInt(),
      gender: json['gender'] as String?, 
    );
  }
}
/// A habit from GET /habits/today, plus its category ("Study" or "Health").
class HabitEntry {
  const HabitEntry({required this.habit, required this.category});

  final HabitSummary habit;
  final String category;
}

/// A group the user has joined (from GET /groups/mine).
class JoinedGroup {
  const JoinedGroup({
    required this.id,
    required this.name,
    required this.category,
    this.iconKey = '',
  });

  final String id;
  final String name;

  /// "Study" or "Health".
  final String category;

  /// The group's type from the backend: "run", "book", "water", "mind".
  final String iconKey;

  /// Words a habit's name must contain to belong to each group type.
  static const Map<String, List<String>> _habitWordsByType = {
    'run': ['walk', 'run', 'step', 'jog'],
    'book': ['read', 'study', 'book', 'notes', 'homework'],
    'water': ['water', 'drink', 'hydrat'],
    'mind': ['meditat', 'stretch', 'yoga', 'breath', 'breakfast'],
  };

  /// The group's type: its icon_key, or guessed from its name.
  String get _type {
    if (_habitWordsByType.containsKey(iconKey)) return iconKey;
    final n = name.toLowerCase();
    if (n.contains('step') || n.contains('run') || n.contains('walk')) {
      return 'run';
    }
    if (n.contains('read') || n.contains('book') ||
        n.contains('study') || n.contains('exam')) {
      return 'book';
    }
    if (n.contains('water') || n.contains('hydrat')) return 'water';
    if (n.contains('mind') || n.contains('meditat')) return 'mind';
    return '';
  }

  /// True if members of this group need to do [entry] each day.
  /// A walking group needs walking, not every Health habit.
  bool needs(HabitEntry entry) {
    final words = _habitWordsByType[_type];
    // Unknown group type: fall back to matching the category.
    if (words == null) return entry.category == category;
    final habitName = entry.habit.name.toLowerCase();
    return words.any(habitName.contains);
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
    /// GET /habits/today -> each habit with completed_today and streak.
  Future<List<HabitSummary>> getTodayHabits() async {
    final entries = await getHabitCatalog();
    return entries.map((e) => e.habit).toList();
  }

  /// Same request as [getTodayHabits], but keeps each habit's category so
  /// Home can match habits to the user's groups.
  Future<List<HabitEntry>> getHabitCatalog() async {
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
      return HabitEntry(
        category: _habitCategory(json),
        habit: HabitSummary(
          id: json['id'].toString(),
          name: json['name'] as String,
          // The photo instruction shown on the verify screen
          category: json['ai_label'] as String? ?? '',
          xpValue: (json['points'] as num).toInt(),
          completedToday: json['completed_today'] as bool? ?? false,
          streak: (json['streak'] as num? ?? 0).toInt(),
        ),
      );
    }).toList();
  }

  /// GET /groups/mine -> the groups this user has joined.
  Future<List<JoinedGroup>> getMyGroups() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.backendUrl}/groups/mine'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load groups (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['groups'] as List<dynamic>? ?? const [])
        : decoded as List<dynamic>;
    return list.map((item) {
      final json = item as Map<String, dynamic>;
      return JoinedGroup(
        id: json['id'].toString(),
        name: (json['room_name'] ?? json['name'] ?? '') as String,
        category: normalizeCategory(json['category']) ?? 'Health',
        iconKey: (json['icon_key'] ?? '').toString(),
      );
    }).toList();
  }

  /// "study"/"Study" -> "Study", "health"/"Health" -> "Health", else null.
  static String? normalizeCategory(Object? value) {
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text == 'study') return 'Study';
    if (text == 'health') return 'Health';
    return null;
  }

  /// Uses the backend's "category" field. If the backend doesn't send one,
  /// guesses from the habit's name and photo label.
  static String _habitCategory(Map<String, dynamic> json) {
    final fromBackend =
        normalizeCategory(json['category'] ?? json['habit_category']);
    if (fromBackend != null) return fromBackend;

    final text = '${json['name'] ?? ''} ${json['ai_label'] ?? ''}'.toLowerCase();
    const studyWords = [
      'study', 'read', 'book', 'notes', 'homework', 'learn', 'revis', 'desk',
    ];
    return studyWords.any(text.contains) ? 'Study' : 'Health';
  }
}