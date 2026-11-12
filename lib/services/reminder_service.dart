// Growy — daily habit reminder (local notifications, no backend).
//
// How it works:
// - The user turns the reminder on and picks a time (Me page).
// - The app schedules one notification per day for the next 14 days.
// - Every time Home loads, it tells this service how many habits are left
//   today. If none are left, tonight's reminder is skipped; otherwise
//   tonight's message says how many are left.
// - Opening the app reschedules the next 14 days, so reminders keep coming
//   as long as the app is opened at least once every two weeks.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The user's reminder choice, saved on this phone.
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour; // 0–23
  final int minute; // 0–59

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }
}

class ReminderService {
  ReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Notification ids 1000–1013 are the next 14 days; 999 is the test.
  static const int _firstId = 1000;
  static const int _daysAhead = 14;
  static const int _testId = 999;

  // Saved on the phone (shared_preferences).
  static const String _kEnabled = 'reminder_enabled';
  static const String _kHour = 'reminder_hour';
  static const String _kMinute = 'reminder_minute';
  static const String _kCountDate = 'reminder_count_date';
  static const String _kRemaining = 'reminder_remaining';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'growy_daily_reminder',
      'Daily habit reminder',
      channelDescription: 'Reminds you to verify your habits each day',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // Permission is asked only when the user turns the reminder on.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Default: off, 8:00 PM.
  static Future<ReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ReminderSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      hour: prefs.getInt(_kHour) ?? 20,
      minute: prefs.getInt(_kMinute) ?? 0,
    );
  }

  /// Asks the phone for permission to show notifications.
  /// Returns false if the user said no.
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await _ensureInit();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // null on Android 12 and older, where no permission is needed.
      return await android?.requestNotificationsPermission() ?? true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  /// Saves the user's choice and reschedules (or cancels) the reminders.
  static Future<void> saveSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, settings.enabled);
    await prefs.setInt(_kHour, settings.hour);
    await prefs.setInt(_kMinute, settings.minute);
    await _reschedule();
  }

  /// Called by Home after it loads: how many of today's habits are not done.
  static Future<void> updateTodayProgress({required int remaining}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCountDate, _todayKey());
    await prefs.setInt(_kRemaining, remaining);
    await _reschedule();
  }

  /// For testing: shows a reminder about one minute from now.
  static Future<void> sendTestReminder() async {
    if (kIsWeb) return;
    await _ensureInit();
    final when = DateTime.now().add(const Duration(minutes: 1));
    await _schedule(
      _testId,
      '🌱 Test reminder',
      'Reminders are working. You can close the app now.',
      when,
    );
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  static Future<void> _reschedule() async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      for (var i = 0; i < _daysAhead; i++) {
        await _plugin.cancel(_firstId + i);
      }

      final settings = await loadSettings();
      if (!settings.enabled) return;

      final prefs = await SharedPreferences.getInstance();
      final knowsToday = prefs.getString(_kCountDate) == _todayKey();
      final remainingToday = knowsToday ? prefs.getInt(_kRemaining) : null;

      final now = DateTime.now();
      for (var i = 0; i < _daysAhead; i++) {
        final when = DateTime(
          now.year,
          now.month,
          now.day + i,
          settings.hour,
          settings.minute,
        );
        if (!when.isAfter(now)) continue; // today's time already passed

        var title = '🌱 Time for your habits';
        var body = "Verify today's habits to keep your streak going.";

        if (i == 0 && remainingToday != null) {
          if (remainingToday <= 0) continue; // all done today: no reminder
          final one = remainingToday == 1;
          title = '🌱 $remainingToday ${one ? 'habit' : 'habits'} left today';
          body = 'Snap a photo to verify ${one ? 'it' : 'them'} '
              'and help your avatar grow.';
        }

        await _schedule(_firstId + i, title, body, when);
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  /// [when] is a normal phone-local time; it's converted to an exact
  /// moment in UTC, so no time-zone package for the phone is needed.
  static Future<void> _schedule(
    int id,
    String title,
    String body,
    DateTime when,
  ) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.UTC),
      _details,
      // Inexact: may arrive a few minutes late, but needs no extra
      // "exact alarm" permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}