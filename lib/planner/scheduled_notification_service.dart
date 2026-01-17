import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';
import 'planner_model.dart';

class ScheduledNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const MethodChannel _nativeChannel = MethodChannel('com.example.flow_app/native_alarm');

  static const String channelId = 'scheduled_sessions';
  static const String channelName = 'Scheduled Sessions';

  static Future<void> init({Function(NotificationResponse)? onNotificationResponse}) async {
    print('🔔 ScheduledNotificationService.init()');
    tz.initializeTimeZones();
    _configureTimezone();

    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: const DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );
    print('✓ Plugin initialized');

    // Create channel
    const androidChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: 'Notifications for scheduled focus sessions',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(androidChannel);
      print('✓ Channel created');
    }
  }
  
  static void _configureTimezone() {
    try {
      final now = DateTime.now();
      final offsetMinutes = now.timeZoneOffset.inMinutes;
      final map = {
        300: 'Asia/Karachi',
        330: 'Asia/Kolkata',
        480: 'Asia/Shanghai',
        -300: 'America/New_York',
        60: 'Europe/Paris',
        0: 'UTC',
      };
      final name = map[offsetMinutes] ?? 'UTC';
      final loc = tz.getLocation(name);
      tz.setLocalLocation(loc);
      print('✓ Timezone set: ${loc.name} offset=${now.timeZoneOffset}');
    } catch (e) {
      print('✗ Timezone config failed, fallback to UTC: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }
  

  
  /// Check and request exact alarm permission (Android 12+)
  static Future<bool> checkAndRequestPermissions() async {
    if (!Platform.isAndroid) return true;
    
    // Check notification permission first (Android 13+)
    final notificationStatus = await Permission.notification.status;
    print('Notification permission status: $notificationStatus');
    if (notificationStatus.isDenied) {
      final result = await Permission.notification.request();
      print('Notification permission request result: $result');
      if (result.isDenied) {
        print('⚠️ Notification permission denied!');
        return false;
      }
    }
    
    // Check exact alarm permission
    final alarmStatus = await Permission.scheduleExactAlarm.status;
    print('Exact alarm permission status: $alarmStatus');
    
    if (await Permission.scheduleExactAlarm.isGranted) {
      print('✓ Exact alarm permission granted');
      return true;
    }
    
    // Request permission - this will open Android settings automatically
    final status = await Permission.scheduleExactAlarm.request();
    print('Exact alarm permission request result: $status');
    return status.isGranted;
  }
  
  static Future<void> scheduleSessionNotifications(ScheduledSession session) async {
    print('\n=== Schedule Session Reminders ===');
    print('Session: ${session.id} title=${session.title} startAt=${session.startAt} offsets=${session.reminderOffsets} now=${DateTime.now()}');
    await cancelSessionNotifications(session.id);
    for (final offset in session.reminderOffsets) {
      final fireTime = session.startAt.subtract(Duration(minutes: offset));
      if (!fireTime.isAfter(DateTime.now())) {
        print('• Skip offset $offset (fireTime $fireTime in past)');
        continue;
      }
      await _scheduleReminderNotification(session, offset, fireTime);
    }
    final pending = await _plugin.pendingNotificationRequests();
    print('✓ Pending after scheduling: ${pending.map((e) => e.id).toList()}');
  }

  static Future<void> _scheduleReminderNotification(ScheduledSession session, int offsetMinutes, DateTime scheduledTime) async {
    final id = _generateNotificationId(session.id, offsetMinutes);
    print('→ Scheduling reminder id=$id offset=$offsetMinutes fireAt=$scheduledTime (now=${DateTime.now()})');
    final payload = jsonEncode({'sessionId': session.id, 'action': 'reminder', 'offsetMinutes': offsetMinutes});
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Session reminder',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('start_now', 'Start Now', showsUserInterface: true),
        AndroidNotificationAction('snooze', 'I\'ll start at ${_formatSnoozeTime(session.startAt)}', showsUserInterface: false),
      ],
    );
    final details = NotificationDetails(android: androidDetails);
    final tzTime = tz.TZDateTime(
      tz.local,
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
      scheduledTime.hour,
      scheduledTime.minute,
      scheduledTime.second,
    );
    try {
      await _plugin.zonedSchedule(
        id,
        'Time for ${session.title}',
        'Your session starts in $offsetMinutes minutes',
        tzTime,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      print('✓ zonedSchedule registered id=$id tzFireAt=$tzTime');
    } catch (e) {
      print('✗ zonedSchedule error id=$id: $e');
    }

    // Schedule native alarm as fallback for when app is terminated
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('scheduleNativeAlarm', {
          'notificationId': id,
          'sessionId': session.id,
          'title': 'Time for ${session.title}',
          'body': 'Your session starts in $offsetMinutes minutes',
          'offsetMinutes': offsetMinutes,
          'scheduledTime': scheduledTime.millisecondsSinceEpoch,
        });
        print('✓ Native alarm scheduled id=$id fireAt=$scheduledTime');
      } catch (e) {
        print('✗ Native alarm scheduling failed id=$id: $e');
      }
    }
    // Log pending right after
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final match = pending.any((p) => p.id == id);
      print('  Pending contains id=$id ? $match (all=${pending.map((e) => e.id).toList()})');
    } catch (e) {
      print('  ✗ Could not fetch pending: $e');
    }

    // Post-fire audit & fallback: after expected fire time +8s, inspect pending.
    final secondsUntil = scheduledTime.difference(DateTime.now()).inSeconds;
    if (secondsUntil > 0) {
      Future.delayed(Duration(seconds: secondsUntil + 8), () async {
        final now = DateTime.now();
        print('⏰ Audit for reminder id=$id at $now (expected fire $scheduledTime)');
        try {
          final pending = await _plugin.pendingNotificationRequests();
          final stillPending = pending.any((p) => p.id == id);
          print('  Audit: stillPending=$stillPending pendingIds=${pending.map((e) => e.id).toList()}');
          if (stillPending) {
            print('  ⚠ Detected reminder id=$id still pending AFTER fire time; issuing fallback .show()');
            try {
              await _plugin.show(
                id,
                'Time for ${session.title}',
                'Your session starts now',
                details,
                payload: payload,
              );
              print('  ✓ Fallback .show() posted for id=$id');
            } catch (e) {
              print('  ✗ Fallback show failed id=$id: $e');
            }
          }
        } catch (e) {
          print('  ✗ Audit fetch pending failed: $e');
        }
      });
    }
  }
  
  static Future<void> scheduleCountdownNotification({required ScheduledSession session, required DateTime startTime}) async {
    final id = _generateNotificationId(session.id, 0);
    final payload = jsonEncode({'sessionId': session.id, 'action': 'countdown_complete'});
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Countdown complete',
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('start', 'Start', showsUserInterface: true),
      ],
    );
    final details = NotificationDetails(android: androidDetails, iOS: const DarwinNotificationDetails());
    final tzTime = tz.TZDateTime(
      tz.local,
      startTime.year,
      startTime.month,
      startTime.day,
      startTime.hour,
      startTime.minute,
      startTime.second,
    );
    try {
      await _plugin.zonedSchedule(
        id,
        'Time to start ${session.title}!',
        'Your scheduled session is ready to begin',
        tzTime,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      print('✓ countdown scheduled id=$id tzFireAt=$tzTime');
    } catch (e) {
      print('✗ countdown scheduling failed: $e');
    }
  }
  
  /// Schedule a "time to start" notification for the exact session start time
  static Future<void> scheduleStartTimeNotification({required ScheduledSession session, required DateTime startTime}) async {
    final id = _generateNotificationId(session.id, -1); // Use -1 for start time notifications
    print('⏰ Scheduling start time notification: id=$id for ${session.title} at $startTime');
    
    // Cancel any existing countdown notification for this session
    final countdownId = _generateNotificationId(session.id, 0);
    await _plugin.cancel(countdownId);
    
    // Create notification for the exact start time
    final payload = jsonEncode({
      'sessionId': session.id,
      'action': 'time_to_start',
      'offsetMinutes': 0,
    });
    
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Time to start your scheduled session',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        actions: [
          AndroidNotificationAction(
            'start_session',
            'Start Session',
            showsUserInterface: true,
          ),
        ],
      ),
    );
    
    // Convert to timezone-aware datetime
    final tzTime = tz.TZDateTime(
      tz.local,
      startTime.year,
      startTime.month,
      startTime.day,
      startTime.hour,
      startTime.minute,
      startTime.second,
    );
    
    try {
      await _plugin.zonedSchedule(
        id,
        'It\'s time for ${session.title}!',
        'Your scheduled session is ready to begin',
        tzTime,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      
      // Also schedule native alarm for reliability when app is closed
      if (Platform.isAndroid) {
        try {
          await _nativeChannel.invokeMethod('scheduleNativeAlarm', {
            'notificationId': id,
            'sessionId': session.id,
            'title': 'It\'s time for ${session.title}!',
            'body': 'Your scheduled session is ready to begin',
            'offsetMinutes': 0,
            'scheduledTime': startTime.millisecondsSinceEpoch,
          });
          print('✓ Native start time alarm scheduled: id=$id');
        } catch (e) {
          print('✗ Native start time alarm failed: $e');
        }
      }
      
      print('✓ Start time notification scheduled id=$id tzFireAt=$tzTime');
    } catch (e) {
      print('✗ Start time notification scheduling failed: $e');
    }
  }
  
  static Future<void> cancelSessionNotifications(String sessionId) async {
    print('Cancelling notifications for $sessionId');
    for (final offset in [10, 30, 60]) {
      final id = _generateNotificationId(sessionId, offset);
      await _plugin.cancel(id);
      
      // Cancel native alarm too
      if (Platform.isAndroid) {
        try {
          await _nativeChannel.invokeMethod('cancelNativeAlarm', {
            'notificationId': id,
          });
          print('✓ Native alarm cancelled id=$id');
        } catch (e) {
          print('✗ Native alarm cancellation failed id=$id: $e');
        }
      }
    }
    final countdownId = _generateNotificationId(sessionId, 0);
    await _plugin.cancel(countdownId);
    
    if (Platform.isAndroid) {
      try {
        await _nativeChannel.invokeMethod('cancelNativeAlarm', {
          'notificationId': countdownId,
        });
        print('✓ Native countdown alarm cancelled id=$countdownId');
      } catch (e) {
        print('✗ Native countdown cancellation failed: $e');
      }
    }
  }
  
  static int _generateNotificationId(String sessionId, int offsetMinutes) {
    return ('$sessionId-$offsetMinutes').hashCode & 0x7fffffff;
  }

  static String _formatSnoozeTime(DateTime time) {
    final h = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final m = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}
