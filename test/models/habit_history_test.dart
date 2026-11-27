// UT-FR7.2-01: HabitLog.fromJson converts the backend's UTC time to local time.
// UT-FR7.2-02: MonthHistory gives the right numbers for the Habits page.
import 'package:flutter_test/flutter_test.dart';
import 'package:growy/models/habit_history.dart';

HabitLog log(String id, DateTime at, {int points = 10}) => HabitLog(
      id: id,
      habitId: '1',
      habitName: 'Reading',
      category: 'Study',
      completedAt: at,
      pointsEarned: points,
      imageUrl: '',
    );

void main() {
  group('UT-FR7.2-01 HabitLog.fromJson', () {
    test('UTC time from the backend becomes local time', () {
      final l = HabitLog.fromJson({
        'id': 12,
        'habit_id': 3,
        'habit_name': 'Walking',
        'category': 'Health',
        'completed_at': '2026-11-27T21:30:00Z', // 00:30 next day in Riyadh
        'points_earned': 10,
        'image_url': '/photos/abc.jpg',
      });

      final expected = DateTime.utc(2026, 11, 27, 21, 30).toLocal();
      expect(l.completedAt.isUtc, isFalse);
      expect(l.completedAt, expected);
      expect(l.completedAt.day, expected.day); // the calendar uses the local day
    });

    test('on a UTC+3 phone (Saudi), 21:30Z is shown on the next day', () {
      final l = HabitLog.fromJson({
        'id': 1,
        'habit_id': 1,
        'completed_at': '2026-11-27T21:30:00Z',
      });
      if (DateTime.now().timeZoneOffset == const Duration(hours: 3)) {
        expect(l.completedAt.day, 28);
        expect(l.completedAt.hour, 0);
        expect(l.completedAt.minute, 30);
      } else {
        markTestSkipped('This machine is not on UTC+3');
      }
    });

    test('ids become strings, photo path gets the server address', () {
      final l = HabitLog.fromJson({
        'id': 12,
        'habit_id': 3,
        'habit_name': 'Walking',
        'category': 'Health',
        'completed_at': '2026-11-27T09:00:00Z',
        'points_earned': 10,
        'image_url': '/photos/abc.jpg',
      });

      expect(l.id, '12');
      expect(l.habitId, '3');
      expect(l.habitName, 'Walking');
      expect(l.category, 'Health');
      expect(l.pointsEarned, 10);
      expect(l.imageUrl, startsWith('http'));
      expect(l.imageUrl, endsWith('/photos/abc.jpg'));
    });

    test('missing name, category, points and photo get safe defaults', () {
      final l = HabitLog.fromJson({
        'id': 1,
        'habit_id': 1,
        'completed_at': '2026-11-27T09:00:00Z',
      });

      expect(l.habitName, '');
      expect(l.category, '');
      expect(l.pointsEarned, 0);
      expect(l.imageUrl, ''); // older logs have no photo
    });
  });

  group('UT-FR7.2-02 MonthHistory', () {
    // November 2026: two habits on the 3rd, one on the 10th, one on the 25th.
    final history = MonthHistory(
      month: DateTime(2026, 11, 17, 15, 45), // any day/time in the month
      logs: [
        log('a', DateTime(2026, 11, 3, 8, 0), points: 10),
        log('b', DateTime(2026, 11, 25, 20, 0), points: 5),
        log('c', DateTime(2026, 11, 3, 21, 0), points: 15),
        log('d', DateTime(2026, 11, 10, 7, 30), points: 10),
      ],
    );

    test('month is the first day of the month', () {
      expect(history.month, DateTime(2026, 11, 1));
    });

    test('logs are sorted newest first', () {
      expect(history.logs.map((l) => l.id).toList(), ['b', 'd', 'c', 'a']);
    });

    test('dayCounts: habits per day of the month', () {
      expect(history.dayCounts, {3: 2, 10: 1, 25: 1});
    });

    test('habitsCompleted, xpEarned and daysActive', () {
      expect(history.habitsCompleted, 4);
      expect(history.xpEarned, 40);
      expect(history.daysActive, 3);
    });

    test('logsOn returns one day only, newest first', () {
      expect(history.logsOn(DateTime(2026, 11, 3)).map((l) => l.id).toList(),
          ['c', 'a']);
      expect(history.logsOn(DateTime(2026, 11, 10)).single.id, 'd');
      expect(history.logsOn(DateTime(2026, 11, 4)), isEmpty);
    });

    test('logsOn ignores the same day in another month', () {
      expect(history.logsOn(DateTime(2026, 10, 3)), isEmpty);
    });

    test('an empty month gives zeros', () {
      final empty = MonthHistory(month: DateTime(2026, 12), logs: const []);
      expect(empty.dayCounts, isEmpty);
      expect(empty.habitsCompleted, 0);
      expect(empty.xpEarned, 0);
      expect(empty.daysActive, 0);
    });

    test('the list of logs cannot be changed from outside', () {
      expect(() => history.logs.add(log('x', DateTime(2026, 11, 1))),
          throwsUnsupportedError);
    });
  });
}