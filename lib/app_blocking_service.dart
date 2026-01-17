import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:convert';

class BlockableApp {
  final String packageName;
  final String appName;
  final String category;
  final Uint8List? icon;
  bool isBlocked;

  BlockableApp({
    required this.packageName,
    required this.appName,
    required this.category,
    this.icon,
    this.isBlocked = false,
  });

  factory BlockableApp.fromMap(Map<String, dynamic> map) {
    Uint8List? iconBytes;
    final iconBase64 = map['iconBase64'] as String?;
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        iconBytes = base64Decode(iconBase64);
      } catch (e) {
        print('Failed to decode icon for ${map['packageName']}: $e');
      }
    }
    
    return BlockableApp(
      packageName: map['packageName'] ?? '',
      appName: map['appName'] ?? '',
      category: map['category'] ?? 'other',
      icon: iconBytes,
      isBlocked: map['isBlocked'] ?? false,
    );
  }
}

class AppBlockingService {
  static const MethodChannel _channel = MethodChannel('com.example.flow_app/app_blocking');

  Future<List<BlockableApp>> getBlockableApps() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('getBlockableApps');
      return result.map((app) => BlockableApp.fromMap(Map<String, dynamic>.from(app))).toList();
    } catch (e) {
      throw Exception('Failed to get blockable apps: $e');
    }
  }

  Future<void> blockApp(String packageName) async {
    try {
      await _channel.invokeMethod('blockApp', {'packageName': packageName});
      await _channel.invokeMethod('startAppBlockingService');
    } catch (e) {
      throw Exception('Failed to block app: $e');
    }
  }

  Future<void> unblockApp(String packageName) async {
    try {
      await _channel.invokeMethod('unblockApp', {'packageName': packageName});
    } catch (e) {
      throw Exception('Failed to unblock app: $e');
    }
  }

  Future<bool> hasUsageStatsPermission() async {
    try {
      return await _channel.invokeMethod('hasUsageStatsPermission');
    } catch (e) {
      return false;
    }
  }

  Future<bool> hasSystemAlertPermission() async {
    try {
      return await _channel.invokeMethod('hasSystemAlertPermission');
    } catch (e) {
      return false;
    }
  }

  Future<bool> hasAccessibilityPermission() async {
    try {
      return await _channel.invokeMethod('hasAccessibilityPermission');
    } catch (e) {
      return false;
    }
  }

  Future<void> requestUsageStatsPermission() async {
    try {
      await _channel.invokeMethod('openUsageStatsSettings');
    } catch (e) {
      throw Exception('Failed to request usage stats permission: $e');
    }
  }

  Future<void> requestSystemAlertPermission() async {
    try {
      await _channel.invokeMethod('openSystemAlertSettings');
    } catch (e) {
      throw Exception('Failed to request system alert permission: $e');
    }
  }

  Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      throw Exception('Failed to request accessibility permission: $e');
    }
  }

  Future<void> startAppBlockingService() async {
    try {
      await _channel.invokeMethod('startAppBlockingService');
    } catch (e) {
      throw Exception('Failed to start app blocking service: $e');
    }
  }

  Future<void> stopAppBlockingService() async {
    try {
      await _channel.invokeMethod('stopAppBlockingService');
    } catch (e) {
      throw Exception('Failed to stop app blocking service: $e');
    }
  }
}