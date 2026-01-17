package com.example.flow_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.view.View
import android.graphics.Color

class BlockingOverlayActivity : Activity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Make this activity full screen and always on top
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
        )
        
        val appName = intent.getStringExtra("app_name") ?: "This app"
        val packageName = intent.getStringExtra("package_name") ?: ""
        
        createBlockingView(appName, packageName)
    }
    
    private fun createBlockingView(appName: String, packageName: String) {
        // Create a simple blocking layout programmatically
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1a1a1a"))
            gravity = android.view.Gravity.CENTER
            setPadding(60, 60, 60, 60)
        }
        
        // App blocked icon
        val iconView = android.widget.ImageView(this).apply {
            setImageResource(android.R.drawable.ic_delete) // Using built-in icon
            layoutParams = android.widget.LinearLayout.LayoutParams(200, 200).apply {
                gravity = android.view.Gravity.CENTER
                bottomMargin = 40
            }
            setColorFilter(Color.parseColor("#ef4444"))
        }
        layout.addView(iconView)
        
        // Title
        val titleText = TextView(this).apply {
            text = "App Blocked"
            textSize = 28f
            setTextColor(Color.WHITE)
            gravity = android.view.Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = 20
            }
        }
        layout.addView(titleText)
        
        // Message
        val messageText = TextView(this).apply {
            text = "$appName is blocked to help you stay focused"
            textSize = 16f
            setTextColor(Color.parseColor("#a1a1aa"))
            gravity = android.view.Gravity.CENTER
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = 40
            }
        }
        layout.addView(messageText)
        
        // Buttons container
        val buttonContainer = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER
        }
        
        // Go Back button
        val backButton = Button(this).apply {
            text = "Go Back"
            textSize = 16f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#374151"))
            setPadding(40, 20, 40, 20)
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                rightMargin = 20
            }
            
            setOnClickListener {
                returnToHome()
                finish()
            }
        }
        buttonContainer.addView(backButton)
        
        // Manage Blocks button
        val manageButton = Button(this).apply {
            text = "Manage Blocks"
            textSize = 16f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#2563eb"))
            setPadding(40, 20, 40, 20)
            
            setOnClickListener {
                openAppBlockingScreen()
                finish()
            }
        }
        buttonContainer.addView(manageButton)
        
        layout.addView(buttonContainer)
        
        setContentView(layout)
    }
    
    private fun returnToHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
    }
    
    private fun openAppBlockingScreen() {
        // Open the main app with a specific intent to show app blocking screen
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_app_blocking", true)
        }
        
        if (intent != null) {
            startActivity(intent)
        }
    }
    
    override fun onBackPressed() {
        // Prevent back button from closing this overlay
        returnToHome()
        finish()
    }
}