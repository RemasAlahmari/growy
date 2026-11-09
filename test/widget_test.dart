// Checks that the app reads the backend's JSON the way the FastAPI endpoints
// send it (field names and types). Runs without Firebase or a backend:
//   flutter test
//
// (This replaces the default Flutter counter test, which referred to a
// `MyApp` class that does not exist in Growy.)

import 'package:flutter_test/flutter_test.dart';

import 'package:growy/config/api_config.dart';
import 'package:growy/services/home_service.dart';
import 'package:growy/services/verification_service.dart';

void main() {
  test('UserProfile reads GET /users/me', () {
    final profile = UserProfile.fromJson({
      'id': 1,
      'username': 'sara',
      'display_name': 'Sara',
      'email': 'sara@example.com',
      'gender': 'female',
      'total_points': 120,
      'current_level': 1,
      'xp_into_level': 20,
      'xp_for_next_level': 400,
      'streak_days': 3,
      'longest_streak': 5,
      'today_points': 10,
      'habits_completed': 12,
      'photos_verified': 12,
    });
    expect(profile.username, 'sara');
    expect(profile.gender, 'female');
    expect(profile.totalPoints, 120);
    expect(profile.currentLevel, 1);
    expect(profile.streakDays, 3);
    expect(profile.todayPoints, 10);
  });

  test('UserProfile tolerates missing fields (older backend)', () {
    final profile = UserProfile.fromJson({'username': 'old'});
    expect(profile.gender, isNull);
    expect(profile.totalPoints, 0);
    expect(profile.currentLevel, 0);
  });

  test('VerificationResult reads POST /habits/{id}/complete/ai', () {
    final result = VerificationResult.fromJson({
      'verification_status': 'verified',
      'expected_activity': 'walking',
      'predicted_label': 'walking',
      'confidence': null,
      'confidence_level': 'high',
      'evidence': 'activity_in_progress',
      'reason': 'Feet walking on a sidewalk.',
      'points_earned': 10,
      'attempts_remaining': 3,
      'habit_log_id': 7,
      'total_points': 110,
      'current_level': 1,
      'leveled_up': true,
    });
    expect(result.isVerified, isTrue);
    expect(result.confidence, isNull);
    expect(result.confidenceLevel, 'high');
    expect(result.reason, 'Feet walking on a sidewalk.');
    expect(result.pointsEarned, 10);
    expect(result.attemptsRemaining, 3);
    expect(result.currentLevel, 1);
    expect(result.leveledUp, isTrue);
  });

  test('A rejected photo keeps its attempts count', () {
    final result = VerificationResult.fromJson({
      'verification_status': 'rejected',
      'points_earned': 0,
      'attempts_remaining': 0,
      'leveled_up': false,
    });
    expect(result.isVerified, isFalse);
    expect(result.attemptsRemaining, 0);
  });

  test('Habit and group categories are read the same way', () {
    // GET /habits/today and GET /groups/mine both send "Study" or "Health";
    // a group needs every habit with the same category.
    expect(HomeService.normalizeCategory('Study'), 'Study');
    expect(HomeService.normalizeCategory(' study '), 'Study');
    expect(HomeService.normalizeCategory('HEALTH'), 'Health');
    expect(HomeService.normalizeCategory(null), isNull);
    expect(HomeService.normalizeCategory('Sports'), isNull);
  });

  test('ApiConfig has a backend address', () {
    expect(ApiConfig.baseUrl, startsWith('http'));
    expect(ApiConfig.baseUrl.endsWith('/'), isFalse);
  });
}
