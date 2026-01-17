package com.example.flow_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class NotificationActionReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "NotificationAction"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val sessionId = intent.getStringExtra("sessionId") ?: ""
        
        Log.d(TAG, "Action received: $action for session: $sessionId")
        
        if ("START_NOW" == action) {
            // Open app immediately
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("sessionId", sessionId)
                putExtra("action", "START_NOW")
                putExtra("fromNotification", true)
                setAction("NOTIFICATION_START_NOW")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(openAppIntent)
            Log.d(TAG, "✓ Starting app for session: $sessionId")
        } else if ("SNOOZE" == action) {
            // Open app with snooze action  
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("sessionId", sessionId)
                putExtra("action", "SNOOZE")
                putExtra("fromNotification", true)
                setAction("NOTIFICATION_SNOOZE")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(openAppIntent)
            Log.d(TAG, "✓ Starting app with snooze for session: $sessionId")
        }
    }
}