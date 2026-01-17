package com.example.flow_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONException
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "session_notifications"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in listOf(
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_PACKAGE_REPLACED
            )) {
            
            Log.d(TAG, "Boot completed or package replaced, rescheduling alarms")
            
            // Get stored notification data
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val allEntries = prefs.all
            
            for ((key, value) in allEntries) {
                if (key.startsWith("notif_")) {
                    try {
                        val jsonData = value as String
                        val data = JSONObject(jsonData)
                        
                        // Use NativeAlarmHelper to reschedule
                        val scheduledTime = data.getLong("scheduled_time")
                        if (scheduledTime > System.currentTimeMillis()) {
                            val notificationId = data.getInt("notification_id")
                            val sessionId = data.getString("session_id")
                            val title = data.getString("title")
                            val body = data.getString("body")
                            val offsetMinutes = data.getInt("offset_minutes")
                            
                            NativeAlarmHelper.scheduleAlarm(context, notificationId, sessionId, 
                                title, body, offsetMinutes, scheduledTime)
                            Log.d(TAG, "✓ Rescheduled alarm: id=$notificationId time=$scheduledTime")
                        } else {
                            // Clean up old entries
                            prefs.edit().remove(key).apply()
                            Log.d(TAG, "✓ Cleaned up expired entry: $key")
                        }
                    } catch (e: JSONException) {
                        Log.e(TAG, "Error parsing stored notification data: ${e.message}")
                        // Remove corrupted entry
                        prefs.edit().remove(key).apply()
                    }
                }
            }
        }
    }
}