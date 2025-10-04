package com.example.flow_app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.example.flow_app/dnd"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
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
	}
}
