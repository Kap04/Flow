import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'appName': appName,
    'category': category,
    'isBlocked': isBlocked,
  };

  factory BlockableApp.fromJson(Map<String, dynamic> json) => BlockableApp(
    packageName: json['packageName'],
    appName: json['appName'],
    category: json['category'],
    isBlocked: json['isBlocked'] ?? false,
  );
}

class AppBlockingService {
  static const MethodChannel _channel = MethodChannel('com.flow.app_blocking');
  static const String _blockedAppsKey = 'blocked_apps';

  // Get all blockable apps from the device
  static Future<List<BlockableApp>> getBlockableApps() async {
    try {
      final List<dynamic> apps = await _channel.invokeMethod('getBlockableApps');
      return apps.map((app) {
        return BlockableApp(
          packageName: app['packageName'],
          appName: app['appName'],
          category: app['category'],
          icon: app['icon'] != null ? Uint8List.fromList(List<int>.from(app['icon'])) : null,
        );
      }).toList();
    } catch (e) {
      print('Error getting blockable apps: $e');
      return [];
    }
  }

  // Block an app
  static Future<bool> blockApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod('blockApp', {'packageName': packageName});
      if (result) {
        await _saveBlockedApp(packageName);
        await _updateBlockingService();
      }
      return result;
    } catch (e) {
      print('Error blocking app: $e');
      return false;
    }
  }

  // Unblock an app
  static Future<bool> unblockApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod('unblockApp', {'packageName': packageName});
      if (result) {
        await _removeBlockedApp(packageName);
        await _updateBlockingService();
      }
      return result;
    } catch (e) {
      print('Error unblocking app: $e');
      return false;
    }
  }

  // Get list of currently blocked apps
  static Future<List<String>> getBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final blockedAppsJson = prefs.getStringList(_blockedAppsKey) ?? [];
    return blockedAppsJson;
  }

  // Check if app blocking service is running
  static Future<bool> isServiceRunning() async {
    try {
      return await _channel.invokeMethod('isServiceRunning');
    } catch (e) {
      print('Error checking service status: $e');
      return false;
    }
  }

  // Start the blocking service
  static Future<bool> startBlockingService() async {
    try {
      return await _channel.invokeMethod('startBlockingService');
    } catch (e) {
      print('Error starting blocking service: $e');
      return false;
    }
  }

  // Stop the blocking service
  static Future<bool> stopBlockingService() async {
    try {
      return await _channel.invokeMethod('stopBlockingService');
    } catch (e) {
      print('Error stopping blocking service: $e');
      return false;
    }
  }

  // Request necessary permissions
  static Future<bool> requestPermissions() async {
    try {
      return await _channel.invokeMethod('requestPermissions');
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }

  // Check if all permissions are granted
  static Future<bool> hasAllPermissions() async {
    try {
      return await _channel.invokeMethod('hasAllPermissions');
    } catch (e) {
      print('Error checking permissions: $e');
      return false;
    }
  }

  // Private helper methods
  static Future<void> _saveBlockedApp(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedApps = prefs.getStringList(_blockedAppsKey) ?? [];
    if (!blockedApps.contains(packageName)) {
      blockedApps.add(packageName);
      await prefs.setStringList(_blockedAppsKey, blockedApps);
    }
  }

  static Future<void> _removeBlockedApp(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final blockedApps = prefs.getStringList(_blockedAppsKey) ?? [];
    blockedApps.remove(packageName);
    await prefs.setStringList(_blockedAppsKey, blockedApps);
  }

  static Future<void> _updateBlockingService() async {
    final blockedApps = await getBlockedApps();
    try {
      await _channel.invokeMethod('updateBlockedApps', {'apps': blockedApps});
    } catch (e) {
      print('Error updating blocking service: $e');
    }
  }
}