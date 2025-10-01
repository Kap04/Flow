import 'package:flutter/services.dart';

class DndHelper {
  static const MethodChannel _channel = MethodChannel('com.example.flow_app/dnd');

  static Future<bool> isAccessGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDndAccessGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    await _channel.invokeMethod('openDndSettings');
  }

  static Future<void> openAppSettings() async {
    await _channel.invokeMethod('openAppSettings');
  }

  static Future<void> enableDnd() async {
    await _channel.invokeMethod('enableDnd');
  }

  static Future<void> disableDnd() async {
    await _channel.invokeMethod('disableDnd');
  }
}
