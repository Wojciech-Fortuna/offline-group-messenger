package com.offlinegroupmessenger.offline_connectivity

import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Connection setup only. Shared chat logic and TCP messaging belong in Dart. */
class OfflineConnectivityPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.offlinegroupmessenger/connectivity"
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> {
                val appContext = context
                if (appContext == null) {
                    result.error("unavailable", "Plugin is detached.", null)
                    return
                }
                val supported = appContext.packageManager.hasSystemFeature(
                    PackageManager.FEATURE_WIFI_DIRECT
                )
                result.success(
                    mapOf(
                        "platform" to "android",
                        "wifiDirectSupported" to supported,
                        "implementationReady" to false,
                        "description" to if (supported) {
                            "Wi-Fi Direct hardware detected. Group connections are not implemented yet."
                        } else {
                            "This device does not report Wi-Fi Direct support."
                        }
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }
}
