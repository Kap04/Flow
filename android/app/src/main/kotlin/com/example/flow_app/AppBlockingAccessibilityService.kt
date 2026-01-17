package com.example.flow_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.content.pm.PackageManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

class AppBlockingAccessibilityService : AccessibilityService() {
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
        }
        
        serviceInfo = info
        Log.d("AppBlockingService", "Accessibility service connected")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return
            
            // Skip our own app and system apps
            if (packageName == "com.example.flow_app" || 
                packageName.startsWith("com.android") || 
                packageName.startsWith("android")) {
                return
            }
            
            // Check if this app is blocked
            val blockedApps = getBlockedApps()
            if (blockedApps.contains(packageName)) {
                Log.d("AppBlockingService", "Blocking access to: $packageName")
                showBlockingOverlay(packageName)
                
                // Return user to home screen after a brief delay
                Handler(Looper.getMainLooper()).postDelayed({
                    returnToHome()
                }, 100)
            }
        }
    }
    
    override fun onInterrupt() {
        Log.d("AppBlockingService", "Accessibility service interrupted")
    }
    
    private fun getBlockedApps(): Set<String> {
        val sharedPref = getSharedPreferences("app_blocking", Context.MODE_PRIVATE)
        return sharedPref.getStringSet("blocked_apps", emptySet()) ?: emptySet()
    }
    
    private fun showBlockingOverlay(packageName: String) {
        val appName = getAppName(packageName)
        
        val intent = Intent(this, BlockingOverlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("app_name", appName)
            putExtra("package_name", packageName)
        }
        
        startActivity(intent)
    }
    
    private fun returnToHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
    }
    
    private fun getAppName(packageName: String): String {
        return try {
            val packageManager = packageManager
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            packageName
        }
    }
    
    companion object {
        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            val enabledServices = android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            
            val serviceName = "${context.packageName}/${AppBlockingAccessibilityService::class.java.name}"
            return enabledServices?.contains(serviceName) == true
        }
    }
}