// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

package com.nightcode.luci

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup

class MainActivity : FlutterFragmentActivity() {
    private val PERMISSION_CHANNEL = "com.nightcode.luci/local_network_permission"
    private val LIFECYCLE_CHANNEL = "com.nightcode.luci/app_lifecycle"
    private val LOCAL_NETWORK_PERMISSION_CODE = 1001
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Modern edge-to-edge layout & display cutout handling without deprecated APIs
        setupEdgeToEdge()

        // Unlock high refresh rate (90Hz/120Hz/144Hz) for ultra-smooth 120fps scrolling
        unlockHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIFECYCLE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "exitApp" -> {
                    try {
                        moveTaskToBack(true)
                        finish()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EXIT_ERROR", e.message, null)
                    }
                }
                "moveTaskToBack" -> {
                    try {
                        val moved = moveTaskToBack(true)
                        result.success(moved)
                    } catch (e: Exception) {
                        result.error("MOVE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLocalNetworkPermission" -> {
                    val status = checkLocalNetworkPermissionStatus()
                    result.success(status)
                }
                "requestLocalNetworkPermission" -> {
                    if (Build.VERSION.SDK_INT >= 37) { // Android 17+ / API 37+
                        val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                        if (ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(this, arrayOf(permission), LOCAL_NETWORK_PERMISSION_CODE)
                        }
                    } else {
                        // Automatically granted on Android 16 and lower
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkLocalNetworkPermissionStatus(): Boolean {
        return if (Build.VERSION.SDK_INT >= 37) {
            ContextCompat.checkSelfPermission(this, "android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCAL_NETWORK_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onPostCreate(savedInstanceState: Bundle?) {
        super.onPostCreate(savedInstanceState)
        setupScrollCaptureSupport()
    }

    override fun onResume() {
        super.onResume()
        unlockHighRefreshRate()
        setupScrollCaptureSupport()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            unlockHighRefreshRate()
            setupScrollCaptureSupport()
        }
    }

    /**
     * Enables native long screenshot / scroll capture support across OEM engines
     * (Xiaomi HyperOS/MIUI, Samsung OneUI, Oppo/OnePlus ColorOS/OxygenOS, Vivo FuntouchOS,
     * and Android 12+ AOSP ScrollCapture API).
     */
    private fun setupScrollCaptureSupport() {
        try {
            window.decorView.isScrollContainer = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                window.decorView.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
            }

            val contentView = findViewById<View>(android.R.id.content)
            contentView?.let { root ->
                root.isScrollContainer = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    root.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
                }
                if (root is ViewGroup) {
                    enableScrollCaptureRecursively(root)
                }
            }
        } catch (_: Exception) {
            // Defensive fallback ensuring zero startup crashes on non-standard device hardware/ROMs
        }
    }

    private fun enableScrollCaptureRecursively(viewGroup: ViewGroup) {
        for (i in 0 until viewGroup.childCount) {
            val child = viewGroup.getChildAt(i)
            child.isScrollContainer = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                child.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
            }
            if (child is ViewGroup) {
                enableScrollCaptureRecursively(child)
            }
        }
    }

    private fun unlockHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val display = this.display
                val supportedModes = display?.supportedModes
                val maxMode = supportedModes?.maxByOrNull { it.refreshRate }
                if (maxMode != null) {
                    val lp = window.attributes
                    lp.preferredDisplayModeId = maxMode.modeId
                    window.attributes = lp
                }
            } catch (_: Exception) {
                // High refresh rate API unsupported or managed by OS
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                @Suppress("DEPRECATION")
                val display = windowManager.defaultDisplay
                val supportedModes = display?.supportedModes
                val maxMode = supportedModes?.maxByOrNull { it.refreshRate }
                if (maxMode != null) {
                    val lp = window.attributes
                    lp.preferredDisplayModeId = maxMode.modeId
                    window.attributes = lp
                }
            } catch (_: Exception) {
                // High refresh rate API unsupported or managed by OS
            }
        }
    }
    
    private fun setupEdgeToEdge() {
        try {
            // Modern edge-to-edge window setup without using deprecated WindowManager cutout flags
            WindowCompat.setDecorFitsSystemWindows(window, false)

            // Configure modern display cutout mode for Android 15+ (API 35+)
            if (Build.VERSION.SDK_INT >= 35) {
                val lp = window.attributes
                lp.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                window.attributes = lp
            }
        } catch (_: Exception) {
            // Defensive fallback ensuring zero startup crashes on non-standard device hardware/ROMs
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW || level == android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            flutterEngine?.systemChannel?.sendMemoryPressureWarning()
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        flutterEngine?.systemChannel?.sendMemoryPressureWarning()
    }
}
