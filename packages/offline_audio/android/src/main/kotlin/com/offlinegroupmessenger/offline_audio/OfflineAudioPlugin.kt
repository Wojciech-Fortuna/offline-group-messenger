package com.offlinegroupmessenger.offline_audio

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import org.webrtc.NetworkMonitorAutoDetect

/** Observes the existing network; never owns or tears down the Messenger group. */
class OfflineAudioPlugin : FlutterPlugin {
    private var methods: MethodChannel? = null
    private var observer: P2pObserver? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NetworkMonitorAutoDetect.setIncludeWifiDirect(true)
        observer = P2pObserver(binding.applicationContext)
        methods = MethodChannel(binding.binaryMessenger, "com.offlinegroupmessenger/audio").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "p2pNetwork") observer!!.read(result) else result.notImplemented()
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null); methods = null
        observer?.close(); observer = null
    }
}
