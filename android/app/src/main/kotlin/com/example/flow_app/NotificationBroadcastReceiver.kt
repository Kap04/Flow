package com.example.flow_app

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class NotificationBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "NotificationBroadcast"
        private const val CHANNEL_ID = "scheduled_sessions"
        private const val PREFS_NAME = "session_notifications"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Alarm fired! Intent: $intent")
        
        // Get notification data from intent extras
        val notificationId = intent.getIntExtra("notification_id", 0)
        val sessionId = intent.getStringExtra("session_id") ?: ""
        val title = intent.getStringExtra("title") ?: ""
        val body = intent.getStringExtra("body") ?: ""
        val offsetMinutes = intent.getIntExtra("offset_minutes", 0)
        
        Log.d(TAG, "Received: id=$notificationId sessionId=$sessionId title=$title body=$body offset=$offsetMinutes")
        
        if (title.isEmpty() || body.isEmpty()) {
            Log.e(TAG, "Missing notification data, skipping")
            return
        }
        
        // Create notification channel if needed
        createNotificationChannel(context)
        
        // Create intent to open app
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("sessionId", sessionId)
            putExtra("action", "reminder")
            putExtra("offsetMinutes", offsetMinutes)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            context, 
            notificationId, 
            openAppIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Create "Start Now" action - use MainActivity directly
        val startNowIntent = Intent(context, MainActivity::class.java).apply {
            action = "NOTIFICATION_START_NOW"
            putExtra("sessionId", sessionId)
            putExtra("action", "START_NOW")
            putExtra("fromNotification", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val startNowPendingIntent = PendingIntent.getActivity(
            context, 
            notificationId + 1000, 
            startNowIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Create "I'll start at XX:XX" action (snooze) - use MainActivity directly
        val snoozeIntent = Intent(context, MainActivity::class.java).apply {
            action = "NOTIFICATION_SNOOZE"
            putExtra("sessionId", sessionId)
            putExtra("action", "SNOOZE")
            putExtra("fromNotification", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val snoozePendingIntent = PendingIntent.getActivity(
            context, 
            notificationId + 2000, 
            snoozeIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Calculate actual session start time for snooze text
        val sessionStartTime = System.currentTimeMillis() + (offsetMinutes * 60 * 1000)
        val snoozeText = "I'll start at " + formatTime(sessionStartTime)
        
        // Build notification
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_play, "Start Now", startNowPendingIntent)
            .addAction(android.R.drawable.ic_menu_recent_history, snoozeText, snoozePendingIntent)
        
        // Show notification
        val notificationManager = NotificationManagerCompat.from(context)
        try {
            notificationManager.notify(notificationId, builder.build())
            Log.d(TAG, "✓ Notification shown successfully: id=$notificationId")
        } catch (e: SecurityException) {
            Log.e(TAG, "✗ SecurityException showing notification: ${e.message}")
        }
        
        // Clean up stored data
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove("notif_$notificationId").apply()
        Log.d(TAG, "✓ Cleaned up stored data for id=$notificationId")
    }
    
    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Scheduled Sessions"
            val description = "Notifications for scheduled focus sessions"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                this.description = description
                enableVibration(true)
                enableLights(true)
            }
            
            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "✓ Notification channel created")
        }
    }
    
    private fun formatTime(timeMillis: Long): String {
        val calendar = java.util.Calendar.getInstance()
        calendar.timeInMillis = timeMillis
        val hour = calendar.get(java.util.Calendar.HOUR)
        val minute = calendar.get(java.util.Calendar.MINUTE)
        val amPm = if (calendar.get(java.util.Calendar.AM_PM) == java.util.Calendar.AM) "AM" else "PM"
        val displayHour = if (hour == 0) 12 else hour
        val displayMinute = String.format("%02d", minute)
        return "$displayHour:$displayMinute $amPm"
    }
}