package com.example.flow_app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import android.util.Log
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.app.usage.UsageStatsManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityManager
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.AdaptiveIconDrawable
import android.util.Base64
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.example.flow_app/dnd"
	private val ALARM_CHANNEL = "com.example.flow_app/native_alarm"
	private val NOTIFICATION_CHANNEL = "com.example.flow_app/notification_action"
	private val APP_BLOCKING_CHANNEL = "com.example.flow_app/app_blocking"
	private var notificationMethodChannel: MethodChannel? = null
	
	// Store pending notification action when Flutter isn't ready yet
	private var pendingSessionId: String? = null
	private var pendingAction: String? = null

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		Log.d("MainActivity", "onCreate called with intent: ${intent?.action} extras: ${intent?.extras}")
		Log.d("MainActivity", "Intent details: sessionId=${intent?.getStringExtra("sessionId")} action=${intent?.getStringExtra("action")} fromNotification=${intent?.getBooleanExtra("fromNotification", false)}")
		handleNotificationIntent(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleNotificationIntent(intent)
	}

	override fun onResume() {
		super.onResume()
		// Handle notification intent in case it was missed in onCreate/onNewIntent
		handleNotificationIntent(intent)
	}

	private fun handleNotificationIntent(intent: Intent?) {
		if (intent == null) return
		
		val sessionId = intent.getStringExtra("sessionId")
		val action = intent.getStringExtra("action")
		val fromNotification = intent.getBooleanExtra("fromNotification", false)
		val intentAction = intent.action
		
		Log.d("MainActivity", "Handling notification intent: sessionId=$sessionId action=$action fromNotification=$fromNotification intentAction=$intentAction")
		
		if (sessionId != null && action != null && fromNotification) {
			// Clear the intent extras to prevent re-processing
			intent.removeExtra("sessionId")
			intent.removeExtra("action")
			intent.removeExtra("fromNotification")
			intent.action = null
			
			// Store the action for when Flutter becomes ready
			pendingSessionId = sessionId
			pendingAction = action
			
			// Try to send immediately if method channel is available
			if (notificationMethodChannel != null) {
				Log.d("MainActivity", "Method channel available, sending immediately")
				sendNotificationActionToFlutter(sessionId, action)
				pendingSessionId = null
				pendingAction = null
			} else {
				Log.d("MainActivity", "Flutter not ready yet, storing pending action: $action for $sessionId")
			}
		} else if (sessionId != null || action != null) {
			Log.d("MainActivity", "Notification intent detected but incomplete: sessionId=$sessionId action=$action fromNotification=$fromNotification")
		}
	}
	
	private fun sendNotificationActionToFlutter(sessionId: String, action: String) {
		notificationMethodChannel?.invokeMethod("onNotificationAction", mapOf(
			"sessionId" to sessionId,
			"action" to action
		))
		Log.d("MainActivity", "✓ Sent notification action to Flutter: $action for $sessionId")
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		
		// DND Channel
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			try {
				val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
				when (call.method) {
					"isDndAccessGranted" -> {
						val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) nm.isNotificationPolicyAccessGranted else false
						result.success(granted)
					}
					"openDndSettings" -> {
						val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					}
						"openAppSettings" -> {
							val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
							val uri = Uri.parse("package:" + this.packageName)
							intent.data = uri
							intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(intent)
							result.success(true)
						}
					"enableDnd" -> {
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
							if (!nm.isNotificationPolicyAccessGranted) {
								result.error("NO_ACCESS", "Do Not Disturb access not granted", null)
							} else {
								// Use PRIORITY filter so DND is enabled but the device isn't forced fully silent
								nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
								result.success(true)
							}
						} else {
							result.error("UNSUPPORTED", "Requires Android M+", null)
						}
					}
					"disableDnd" -> {
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
							if (!nm.isNotificationPolicyAccessGranted) {
								result.error("NO_ACCESS", "Do Not Disturb access not granted", null)
							} else {
								nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
								result.success(true)
							}
						} else {
							result.error("UNSUPPORTED", "Requires Android M+", null)
						}
					}
					else -> result.notImplemented()
				}
			} catch (e: Exception) {
				result.error("ERROR", e.message, null)
			}
		}
		
		// Native Alarm Channel
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"scheduleNativeAlarm" -> {
					try {
						val notificationId = call.argument<Int>("notificationId") ?: 0
						val sessionId = call.argument<String>("sessionId") ?: ""
						val title = call.argument<String>("title") ?: ""
						val body = call.argument<String>("body") ?: ""
						val offsetMinutes = call.argument<Int>("offsetMinutes") ?: 0
						val scheduledTime = call.argument<Long>("scheduledTime") ?: 0L
						
						NativeAlarmHelper.scheduleAlarm(this, notificationId, sessionId, title, body, offsetMinutes, scheduledTime)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"cancelNativeAlarm" -> {
					try {
						val notificationId = call.argument<Int>("notificationId") ?: 0
						NativeAlarmHelper.cancelAlarm(this, notificationId)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
		
		// Notification action channel
		notificationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
		
		// Send any pending notification action now that Flutter is ready
		if (pendingSessionId != null && pendingAction != null) {
			Log.d("MainActivity", "Flutter ready! Sending pending action: $pendingAction for $pendingSessionId")
			// Wait a bit for Flutter to fully initialize
			android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
				sendNotificationActionToFlutter(pendingSessionId!!, pendingAction!!)
				pendingSessionId = null
				pendingAction = null
			}, 1500) // Wait longer for full Flutter initialization
		}
		
		// Handle notification action if app was launched by notification
		handleNotificationIntent(intent)
		
		// App Blocking Channel
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_BLOCKING_CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"getBlockableApps" -> {
					try {
						val apps = getBlockableApps()
						result.success(apps)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"blockApp" -> {
					try {
						val packageName = call.argument<String>("packageName") ?: ""
						blockApp(packageName)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"unblockApp" -> {
					try {
						val packageName = call.argument<String>("packageName") ?: ""
						unblockApp(packageName)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"hasUsageStatsPermission" -> {
					try {
						val granted = hasUsageStatsPermission()
						result.success(granted)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"hasSystemAlertPermission" -> {
					try {
						val granted = hasSystemAlertPermission()
						result.success(granted)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"hasAccessibilityPermission" -> {
					try {
						val granted = hasAccessibilityPermission()
						result.success(granted)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"openUsageStatsSettings" -> {
					try {
						val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"openSystemAlertSettings" -> {
					try {
						val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
						intent.data = Uri.parse("package:$packageName")
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"openAccessibilitySettings" -> {
					try {
						val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"startAppBlockingService" -> {
					try {
						startAppBlockingService()
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				"stopAppBlockingService" -> {
					try {
						stopAppBlockingService()
						result.success(true)
					} catch (e: Exception) {
						result.error("ERROR", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}
	
	private fun getBlockableApps(): List<Map<String, Any>> {
		val packageManager = applicationContext.packageManager
		val installedApps = packageManager.getInstalledApplications(0)
		val blockableApps = mutableListOf<Map<String, Any>>()
		
		// Get current blocked apps
		val sharedPref = getSharedPreferences("app_blocking", Context.MODE_PRIVATE)
		val blockedApps = sharedPref.getStringSet("blocked_apps", emptySet()) ?: emptySet()
		
		// Debug: Log what apps we can actually see
		Log.d("AppBlocking", "Total installed apps visible: ${installedApps.size}")
		
		for (app in installedApps) {
			// Include all apps except system framework apps and our own app
			if (app.packageName != packageName && 
				!app.packageName.startsWith("com.android.") &&
				!app.packageName.startsWith("android.") &&
				app.packageName != "com.google.android.packageinstaller" &&
				app.packageName != "com.android.vending") {
				
					try {
						val appName = packageManager.getApplicationLabel(app).toString()
						// Check if app has a launcher intent (is launchable)
						val launchIntent = packageManager.getLaunchIntentForPackage(app.packageName)
						if (launchIntent != null) {
							val iconBase64 = getAppIconAsBase64(app.packageName)
							val isBlocked = blockedApps.contains(app.packageName)
							val category = categorizeApp(app.packageName, appName)
							
							Log.d("AppBlocking", "Found launchable app: ${app.packageName} ($appName) blocked=$isBlocked category=$category")
							blockableApps.add(mapOf(
								"packageName" to app.packageName,
								"appName" to appName,
								"category" to category,
								"iconBase64" to iconBase64,
								"isBlocked" to isBlocked
							))
						} else {
							Log.d("AppBlocking", "Skipping non-launchable app: ${app.packageName} ($appName)")
						}
				} catch (e: Exception) {
					Log.d("AppBlocking", "Error processing app ${app.packageName}: ${e.message}")
				}
			}
		}
		
		Log.d("AppBlocking", "Total blockable apps found: ${blockableApps.size}")
		return blockableApps.sortedBy { it["appName"] as String }
	}
	
	private fun getAppIconAsBase64(packageName: String): String {
		return try {
			val packageManager = applicationContext.packageManager
			val drawable = packageManager.getApplicationIcon(packageName)
			val bitmap = drawableToBitmap(drawable)
			
			// Resize to 48dp for efficiency
			val density = resources.displayMetrics.density
			val size = (48 * density).toInt()
			val resizedBitmap = Bitmap.createScaledBitmap(bitmap, size, size, true)
			
			// Convert to Base64
			val byteArrayOutputStream = ByteArrayOutputStream()
			resizedBitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
			val byteArray = byteArrayOutputStream.toByteArray()
			Base64.encodeToString(byteArray, Base64.NO_WRAP)
		} catch (e: Exception) {
			Log.e("AppBlocking", "Failed to get icon for $packageName: ${e.message}")
			"" // Return empty string if icon can't be loaded
		}
	}
	
	private fun drawableToBitmap(drawable: Drawable): Bitmap {
		if (drawable is BitmapDrawable) {
			return drawable.bitmap
		}
		
		val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && drawable is AdaptiveIconDrawable) {
			// Handle adaptive icons
			val size = 108 // Adaptive icon size
			Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
		} else {
			val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 1
			val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 1
			Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
		}
		
		val canvas = Canvas(bitmap)
		drawable.setBounds(0, 0, canvas.width, canvas.height)
		drawable.draw(canvas)
		return bitmap
	}
	
	private fun categorizeApp(packageName: String, appName: String): String {
		val lowerPackage = packageName.lowercase()
		val lowerName = appName.lowercase()
		
		return when {
			// Social Media Apps
			lowerPackage.contains("instagram") || 
			lowerPackage.contains("facebook") || 
			lowerPackage.contains("twitter") || 
			lowerPackage.contains("tiktok") || 
			lowerPackage.contains("snapchat") || 
			lowerPackage.contains("linkedin") || 
			lowerPackage.contains("reddit") ||
			lowerPackage.contains("pinterest") ||
			lowerName.contains("instagram") || 
			lowerName.contains("facebook") || 
			lowerName.contains("twitter") || 
			lowerName.contains("tiktok") || 
			lowerName.contains("snapchat") || 
			lowerName.contains("linkedin") || 
			lowerName.contains("reddit") ||
			lowerName.contains("pinterest") -> "social"
			
			// Video & Streaming Apps
			lowerPackage.contains("youtube") || 
			lowerPackage.contains("netflix") || 
			lowerPackage.contains("twitch") || 
			lowerPackage.contains("hulu") ||
			lowerPackage.contains("disney") ||
			lowerPackage.contains("video") ||
			lowerPackage.contains("primevideo") ||
			lowerPackage.contains("hbo") ||
			lowerName.contains("youtube") || 
			lowerName.contains("netflix") || 
			lowerName.contains("twitch") || 
			lowerName.contains("hulu") ||
			lowerName.contains("disney") ||
			lowerName.contains("video") ||
			lowerName.contains("prime video") ||
			lowerName.contains("hbo") -> "video"
			
			// Games
			lowerPackage.contains("game") ||
			lowerPackage.contains("supercell") ||
			lowerPackage.contains("king.") ||
			lowerPackage.contains("ubisoft") ||
			lowerPackage.contains("ea.") ||
			lowerPackage.contains("roblox") ||
			lowerPackage.contains("minecraft") ||
			lowerName.contains("game") ||
			lowerName.contains("clash") ||
			lowerName.contains("candy crush") ||
			lowerName.contains("brawl") ||
			lowerName.contains("roblox") ||
			lowerName.contains("minecraft") -> "games"
			
			else -> "other"
		}
	}
	

	
	private fun blockApp(packageName: String) {
		val sharedPref = getSharedPreferences("app_blocking", Context.MODE_PRIVATE)
		// Create a new mutable copy to avoid SharedPreferences mutation issues
		val existingApps = sharedPref.getStringSet("blocked_apps", emptySet()) ?: emptySet()
		val blockedApps = existingApps.toMutableSet()
		blockedApps.add(packageName)
		
		// Use commit() instead of apply() to ensure immediate persistence
		sharedPref.edit().putStringSet("blocked_apps", blockedApps).commit()
		
		Log.d("MainActivity", "Blocked app: $packageName. Total blocked: ${blockedApps.size}")
		
		// Update accessibility service
		updateAccessibilityServiceBlockedApps()
		
		// Start or update foreground service
		startAppBlockingService()
	}
	
	private fun unblockApp(packageName: String) {
		val sharedPref = getSharedPreferences("app_blocking", Context.MODE_PRIVATE)
		// Create a new mutable copy to avoid SharedPreferences mutation issues
		val existingApps = sharedPref.getStringSet("blocked_apps", emptySet()) ?: emptySet()
		val blockedApps = existingApps.toMutableSet()
		blockedApps.remove(packageName)
		
		// Use commit() instead of apply() to ensure immediate persistence
		sharedPref.edit().putStringSet("blocked_apps", blockedApps).commit()
		
		Log.d("MainActivity", "Unblocked app: $packageName. Total blocked: ${blockedApps.size}")
		
		// Update accessibility service
		updateAccessibilityServiceBlockedApps()
		
		// Update or stop foreground service
		if (blockedApps.isEmpty()) {
			stopAppBlockingService()
		} else {
			startAppBlockingService()
		}
	}
	
	private fun updateAccessibilityServiceBlockedApps() {
		// The accessibility service will read from SharedPreferences
		// No direct communication needed as it polls the preferences
	}
	
	private fun hasUsageStatsPermission(): Boolean {
		val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
		val time = System.currentTimeMillis()
		val stats = usageStatsManager.queryUsageStats(
			UsageStatsManager.INTERVAL_DAILY, 
			time - 1000 * 60 * 60 * 24, 
			time
		)
		return stats != null && stats.isNotEmpty()
	}
	
	private fun hasSystemAlertPermission(): Boolean {
		return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			Settings.canDrawOverlays(this)
		} else {
			true
		}
	}
	
	private fun hasAccessibilityPermission(): Boolean {
		val accessibilityManager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
		val enabledServices = accessibilityManager.getEnabledAccessibilityServiceList(
			AccessibilityServiceInfo.FEEDBACK_ALL_MASK
		)
		
		for (service in enabledServices) {
			if (service.resolveInfo.serviceInfo.name == AppBlockingAccessibilityService::class.java.name) {
				return true
			}
		}
		return false
	}
	
	private fun startAppBlockingService() {
		val intent = Intent(this, AppBlockingForegroundService::class.java)
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			startForegroundService(intent)
		} else {
			startService(intent)
		}
	}
	
	private fun stopAppBlockingService() {
		val intent = Intent(this, AppBlockingForegroundService::class.java)
		stopService(intent)
	}
}
