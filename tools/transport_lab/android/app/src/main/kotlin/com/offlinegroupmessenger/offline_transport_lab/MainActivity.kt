package com.offlinegroupmessenger.offline_transport_lab

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.offlinegroupmessenger.offline_audio.P2pObserver

class MainActivity : FlutterActivity() {
    private lateinit var ble: BleLab
    private lateinit var network: P2pObserver
    private var permissionResult: MethodChannel.Result? = null
    private var afterPermission: (() -> Unit)? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        ble = BleLab(this)
        network = P2pObserver(this)
        MethodChannel(engine.dartExecutor.binaryMessenger, "offline_transport_lab").setMethodCallHandler { call, result ->
            fun run(block: () -> Unit) {
                try { block() } catch (e: Exception) {
                    ble.stop()
                    result.error("radio_error", e.message ?: "Radio operation failed", null)
                }
            }
            when (call.method) {
                "p2pNetwork" -> {
                    val permissions = if (Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
                        else arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
                    val action = { network.read(result) }
                    if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) action()
                    else if (permissionResult != null) result.error("busy", "Permission request already open", null)
                    else {
                        permissionResult = result; afterPermission = action
                        requestPermissions(permissions, 8120)
                    }
                }
                "bleState" -> result.success(ble.snapshot())
                "bleStop" -> { ble.stop(); result.success(null) }
                "bleAdvertise", "bleScan", "bleProbe" -> {
                    val action = { run {
                        when (call.method) {
                            "bleAdvertise" -> ble.advertise()
                            "bleScan" -> ble.scan()
                            else -> ble.probe(requireNotNull(call.argument<String>("id")))
                        }
                        result.success(null)
                    } }
                    val permissions = if (Build.VERSION.SDK_INT >= 31) arrayOf(
                        Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT,
                        Manifest.permission.BLUETOOTH_ADVERTISE
                    ) else arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
                    if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) action()
                    else if (permissionResult != null) result.error("busy", "Permission request already open", null)
                    else {
                        permissionResult = result; afterPermission = action
                        requestPermissions(permissions, 8120)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code != 8120) return
        val result = permissionResult
        val action = afterPermission
        permissionResult = null; afterPermission = null
        if (grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED }) action?.invoke()
        else result?.error("permission_denied", "Allow nearby devices / Location for the lab", null)
    }

    override fun onPause() { if (::ble.isInitialized) ble.stop(); super.onPause() }
    override fun onDestroy() {
        if (::ble.isInitialized) ble.stop()
        if (::network.isInitialized) network.close()
        afterPermission = null
        permissionResult?.error("closed", "Lab closed", null); permissionResult = null
        super.onDestroy()
    }
}
