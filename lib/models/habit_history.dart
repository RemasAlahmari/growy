// Habits history models: one verified completion (HabitLog) and one month of
// them (MonthHistory). Moved out of habits_screen.dart so they can be tested.
import '../services/api_client.dart';

/// One photo-verified habit completion, as shown in the Habits history.
class HabitLog {
  final String id;
  final String habitId;
  final String habitName;

  /// "Study" or "Health".
  final String category;
  final DateTime completedAt;
  final int pointsEarned;

  /// Where the verification photo lives. A URL (http/https) once the backend
  /// stores it, or a local file path for photos taken in this session.
  /// These photos were always captured with the in-app camera; nothing is uploaded from the gallery.
  final String imageUrl;

  const HabitLog({
    required this.id,
    required this.habitId,
    required this.habitName,
    required this.category,
    required this.completedAt,
    required this.pointsEarned,
    required this.imageUrl,
  });

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    return HabitLog(
      id: json['id'].toString(),
      habitId: json['habit_id'].toString(),
      habitName: (json['habit_name'] ?? '') as String,
      category: (json['category'] ?? '') as String,
      completedAt: DateTime.parse(json['completed_at'] as String).toLocal(),
      pointsEarned: (json['points_earned'] ?? 0) as int,
      // The backend sends "/photos/<token>.jpg" (or "" for older logs).
      imageUrl: ApiClient.absoluteUrl((json['image_url'] ?? '') as String) ?? '',
    );
  }
}

/// All verified logs in one calendar month, plus the numbers the Habits page shows.
class MonthHistory {
  /// First day of the month (time ignored).
  final DateTime month;
  final List<HabitLog> logs;

  MonthHistory({required DateTime month, required List<HabitLog> logs})
    : month = DateTime(month.year, month.month),
      logs = List.unmodifiable(
        [...logs]..sort((a, b) => b.completedAt.compareTo(a.completedAt)),
      );

  /// Day of month (1–31) → number of habits completed that day.
  Map<int, int> get dayCounts {
    final counts = <int, int>{};
    for (final log in logs) {
      final day = log.completedAt.day;
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  int get habitsCompleted => logs.length;

  int get xpEarned => logs.fold(0, (sum, log) => sum + log.pointsEarned);

  int get daysActive => dayCounts.length;

  /// Logs for one day, newest first.
  List<HabitLog> logsOn(DateTime date) => logs
      .where(
        (log) =>
            log.completedAt.year == date.year &&
            log.completedAt.month == date.month &&
            log.completedAt.day == date.day,
      )
      .toList();
}