package com.example.flow_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONException
import org.json.JSONObject

object NativeAlarmHelper {
    private const val TAG = "NativeAlarmHelper"
    private const val PREFS_NAME = "session_notifications"
    
    fun scheduleAlarm(context: Context, notificationId: Int, sessionId: String, 
                     title: String, body: String, offsetMinutes: Int, scheduledTime: Long) {
        
        Log.d(TAG, "Scheduling native alarm: id=$notificationId sessionId=$sessionId title=$title scheduledTime=$scheduledTime now=${System.currentTimeMillis()}")
        
        // Store notification data for persistence across reboots
        try {
            val data = JSONObject().apply {
                put("notification_id", notificationId)
                put("session_id", sessionId)
                put("title", title)
                put("body", body)
                put("offset_minutes", offsetMinutes)
                put("scheduled_time", scheduledTime)
            }
            
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString("notif_$notificationId", data.toString()).apply()
            Log.d(TAG, "✓ Stored notification data for id=$notificationId")
        } catch (e: JSONException) {
            Log.e(TAG, "Error storing notification data: ${e.message}")
        }
        
        // Create intent for BroadcastReceiver
        val intent = Intent(context, NotificationBroadcastReceiver::class.java).apply {
            putExtra("notification_id", notificationId)
            putExtra("session_id", sessionId)
            putExtra("title", title)
            putExtra("body", body)
            putExtra("offset_minutes", offsetMinutes)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context, 
            notificationId, 
            intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Schedule with AlarmManager
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager != null) {
            try {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, scheduledTime, pendingIntent)
                        Log.d(TAG, "✓ setExactAndAllowWhileIdle scheduled")
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT -> {
                        alarmManager.setExact(AlarmManager.RTC_WAKEUP, scheduledTime, pendingIntent)
                        Log.d(TAG, "✓ setExact scheduled")
                    }
                    else -> {
                        alarmManager.set(AlarmManager.RTC_WAKEUP, scheduledTime, pendingIntent)
                        Log.d(TAG, "✓ set scheduled")
                    }
                }
                Log.d(TAG, "✓ Native alarm scheduled: id=$notificationId fireAt=$scheduledTime")
            } catch (e: SecurityException) {
                Log.e(TAG, "✗ SecurityException scheduling alarm: ${e.message}")
            }
        } else {
            Log.e(TAG, "✗ AlarmManager is null")
        }
    }
    
    fun cancelAlarm(context: Context, notificationId: Int) {
        Log.d(TAG, "Canceling native alarm: id=$notificationId")
        
        // Cancel alarm
        val intent = Intent(context, NotificationBroadcastReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context, 
            notificationId, 
            intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        alarmManager?.cancel(pendingIntent)
        
        // Remove stored data
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove("notif_$notificationId").apply()
        
        Log.d(TAG, "✓ Canceled alarm and cleaned data for id=$notificationId")
    }
}