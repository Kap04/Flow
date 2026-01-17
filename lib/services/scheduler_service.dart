import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../planner/planner_model.dart';

class SchedulerService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  SchedulerService() {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> scheduleSessionNotification(ScheduledSession session) async {
    for (final offset in session.reminderOffsets) {
      final scheduledTime = session.startAt.subtract(Duration(minutes: offset));
      await _notificationsPlugin.zonedSchedule(
        session.id.hashCode + offset,
        'Session Reminder',
        '${session.title} starts in $offset minutes.',
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'session_reminders',
            'Session Reminders',
            channelDescription: 'Reminders for scheduled sessions.',
            largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }

    // Schedule the session start notification
    await _notificationsPlugin.zonedSchedule(
      session.id.hashCode,
      'Session Start',
      '${session.title} is starting now.',
      tz.TZDateTime.from(session.startAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'session_starts',
          'Session Starts',
          channelDescription: 'Notifications for session start times.',
          largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelSessionNotifications(String sessionId) async {
    await _notificationsPlugin.cancel(sessionId.hashCode);
  }
}