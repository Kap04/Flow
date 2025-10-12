import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const int timerNotificationId = 1001;
  static const String androidChannelId = 'timer_channel';
  static const String androidChannelName = 'Timer updates';

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      // On Android 13+ we need to request runtime POST_NOTIFICATIONS permission
      try {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      } catch (_) {
        // permission_handler might not be available on some platforms during tests
      }

      final channel = AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: 'Updates for running timers',
        // Use default importance so the notification is visible to users by default
        importance: Importance.defaultImportance,
        playSound: false,
        showBadge: false,
      );
      await _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    }
  }

  static Future<void> showTimerNotification({
    required String title,
    required String body,
    required int secondsLeft,
    bool ongoing = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      channelDescription: 'Updates for running timers',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
      ongoing: ongoing,
      styleInformation: const DefaultStyleInformation(true, true),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
      presentBadge: false,
    );

    final notificationBody = '$body — ${_formatDuration(secondsLeft)} remaining';
    await _plugin.show(
      timerNotificationId,
      title,
      notificationBody,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  static Future<void> cancelTimerNotification() async {
    await _plugin.cancel(timerNotificationId);
  }

  static String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
