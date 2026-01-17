package com.example.flow_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.Build
import androidx.core.app.NotificationCompat
import android.content.pm.PackageManager
import android.graphics.BitmapFactory

class AppBlockingForegroundService : Service() {
    
    private val CHANNEL_ID = "APP_BLOCKING_CHANNEL"
    private val NOTIFICATION_ID = 1001
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val blockedApps = getBlockedApps()
        
        if (blockedApps.isNotEmpty()) {
            startForeground(NOTIFICATION_ID, createPersistentNotification(blockedApps.size))
        } else {
            stopSelf()
        }
        
        return START_STICKY // Restart if killed
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App Blocking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when apps are being blocked"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createPersistentNotification(blockedCount: Int): Notification {
        // Intent to open app blocking screen when notification is tapped
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_app_blocking", true)
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 
            0, 
            intent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚫 $blockedCount apps blocked")
            .setContentText("Tap to manage blocked apps")
            .setSmallIcon(android.R.drawable.ic_menu_close_clear_cancel)
            .setContentIntent(pendingIntent)
            .setOngoing(true) // Makes it non-swipeable
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(false)
            .build()
    }
    
    private fun getBlockedApps(): Set<String> {
        val sharedPref = getSharedPreferences("app_blocking", Context.MODE_PRIVATE)
        return sharedPref.getStringSet("blocked_apps", emptySet()) ?: emptySet()
    }
    
    fun updateNotification() {
        val blockedApps = getBlockedApps()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (blockedApps.isNotEmpty()) {
            notificationManager.notify(NOTIFICATION_ID, createPersistentNotification(blockedApps.size))
        } else {
            notificationManager.cancel(NOTIFICATION_ID)
            stopSelf()
        }
    }
}