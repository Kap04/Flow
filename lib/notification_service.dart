import 'dart:io';
import 'package:flutter/material.dart';
// removed unused foundation import
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
      // tint the notification with the app blue so the time visually pops on supported devices
      color: const Color.fromRGBO(10, 172, 223, 1),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: const DefaultStyleInformation(true, true),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
      presentBadge: false,
    );

    // Put the time back into the body and separate with a middle dot so the digits stand out
    final notificationBody = '$body · ${_formatDuration(secondsLeft)}';
    await _plugin.show(
      timerNotificationId,
      title,
      notificationBody,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // Show/update a count-up (elapsed) notification. This displays elapsed time instead
  // of remaining time and is intended for the 'infinite' count-up timer.
  static Future<void> showCountupNotification({
    required String title,
    required String body,
    required int elapsedSeconds,
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
      color: const Color.fromRGBO(10, 172, 223, 1),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: const DefaultStyleInformation(true, true),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: false,
      presentBadge: false,
    );

    final notificationBody = '$body · ${_formatElapsed(elapsedSeconds)}';
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

  static String _formatElapsed(int seconds) {
    final d = Duration(seconds: seconds);
    final hh = d.inHours.toString();
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }
}
