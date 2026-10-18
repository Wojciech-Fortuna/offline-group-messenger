package com.offlinegroupmessenger.offline_connectivity

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.*
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.*
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*

/** Engine-scoped connection setup. Chat messages and sockets belong in Dart. */
class OfflineConnectivityPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private lateinit var nfc: NfcInvitationController
    private var attached = false
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var afterPermission: (() -> Unit)? = null
    private var operationTimeout: Runnable? = null
    private var revision = 0
    private var status = "idle"
    private var wifiEnabled = false
    private var isHost = false
    private var hostAddress: String? = null
    private var errorCode: String? = null
    private var errorMessage: String? = null
    private var peers = listOf<Map<String, Any>>()

    private val supported get() = context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
    private val permission get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES
        else Manifest.permission.ACCESS_FINE_LOCATION
    private fun permitted() = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!attached) return
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    wifiEnabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) ==
                        WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    if (!wifiEnabled) {
                        revision++
                        peers = emptyList()
                        clearConnection("unavailable")
                        fail("wifi_disabled", "Enable Wi-Fi and try again.")
                    } else {
                        if (status == "unavailable") status = "idle"
                        clearError()
                        refresh()
                    }
                    emit()
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> readPeers()
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> readConnection()
                WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION -> {
                    val discovering = intent.getIntExtra(WifiP2pManager.EXTRA_DISCOVERY_STATE, -1) ==
                        WifiP2pManager.WIFI_P2P_DISCOVERY_STARTED
                    if (!discovering && status == "discovering") { status = "idle"; emit() }
                }
            }
        }
    }
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity === activityBinding?.activity) { nfc.resume(); refresh() }
        }
        override fun onActivityCreated(activity: Activity, state: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityPaused(activity: Activity) {
            if (activity === activityBinding?.activity) nfc.pause()
        }
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        nfc = NfcInvitationController(context)
        attached = true
        methods = MethodChannel(binding.binaryMessenger, "com.offlinegroupmessenger/connectivity")
            .also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "com.offlinegroupmessenger/connectivity/events")
            .also { it.setStreamHandler(this) }
        manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        (context.applicationContext as Application).registerActivityLifecycleCallbacks(lifecycle)
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION)
        }
        // Protected system actions; Wi-Fi can emit from a privileged UID.
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else context.registerReceiver(receiver, filter)
        refresh()
    }

    private fun ensureChannel(): WifiP2pManager.Channel? {
        if (channel == null && supported) {
            channel = manager?.initialize(context, Looper.getMainLooper()) {
                if (attached) {
                    channel = null
                    revision++
                    clearConnection("unavailable")
                    fail("channel_lost", "Wi-Fi Direct service disconnected. Try again.")
                }
            }
        }
        return channel
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "status" to status, "wifiEnabled" to wifiEnabled, "permissionGranted" to permitted(),
        "isHost" to isHost, "hostAddress" to hostAddress, "peers" to peers,
        "errorCode" to errorCode, "errorMessage" to errorMessage
    )
    private fun emit() {
        if (status != "connected" || !isHost) nfc.stopSharing()
        if (attached) sink?.success(snapshot())
    }
    private fun clearError() { errorCode = null; errorMessage = null }
    private fun clearConnection(next: String) { status = next; isHost = false; hostAddress = null }
    private fun finish(value: Any? = null) {
        operationTimeout?.let(handler::removeCallbacks)
        operationTimeout = null
        afterPermission = null
        val result = pending
        pending = null
        result?.success(value)
    }
    private fun fail(code: String, message: String) {
        operationTimeout?.let(handler::removeCallbacks)
        operationTimeout = null
        afterPermission = null
        errorCode = code
        errorMessage = message
        if (status != "connected" && status != "unavailable") clearConnection("idle")
        val result = pending
        pending = null
        emit()
        result?.error(code, message, null)
    }
    private fun guarded(block: () -> Unit) {
        try { block() }
        catch (_: SecurityException) {
            fail("permission_denied", "Allow Nearby devices (or precise Location on older Android) in app settings.")
        }
        catch (_: RuntimeException) {
            fail("unavailable", "Wi-Fi Direct is unavailable. Enable Wi-Fi and try again.")
        }
    }

    private fun refresh() {
        if (!attached) return
        guarded {
            wifiEnabled = (context.getSystemService(Context.WIFI_SERVICE) as WifiManager).isWifiEnabled
            val ch = ensureChannel()
            if (ch != null && Build.VERSION.SDK_INT >= 29) {
                manager?.requestP2pState(ch) { state ->
                    if (attached) {
                        wifiEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        emit()
                    }
                }
            }
            if (permitted()) readConnection()
            emit()
        }
    }
    private fun readPeers() {
        if (!permitted() || !attached) return
        val ch = channel ?: return
        val token = revision
        guarded {
            manager?.requestPeers(ch) { list ->
                if (attached && token == revision) {
                    peers = list.deviceList.map {
                        mapOf("id" to it.deviceAddress, "name" to (it.deviceName ?: "Nearby device"),
                            "isGroupOwner" to it.isGroupOwner)
                    }.sortedBy { it["name"].toString() }
                    emit()
                }
            }
        }
    }
    private fun readConnection() {
        if (!attached || !permitted() || status == "disconnecting") return
        val ch = channel ?: return
        val token = revision
        guarded {
            manager?.requestConnectionInfo(ch) { info ->
                if (!attached || token != revision || status == "disconnecting") return@requestConnectionInfo
                if (info.groupFormed) {
                    isHost = info.isGroupOwner
                    // Android supplies the real address; never assume a P2P subnet.
                    hostAddress = info.groupOwnerAddress?.hostAddress
                    status = if (hostAddress != null) "connected" else "connecting"
                    clearError()
                } else if (status == "connected") {
                    clearConnection("idle")
                }
                emit()
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(mapOf(
                "platform" to "android", "wifiDirectSupported" to supported,
                "implementationReady" to true,
                "canJoinQr" to (supported && Build.VERSION.SDK_INT >= 29),
                "canShareNfc" to (supported && nfc.canShare),
                "canJoinNfc" to (supported && nfc.canRead && Build.VERSION.SDK_INT >= 29),
                "description" to if (supported) "Wi-Fi Direct is available on this device."
                    else "This device does not support Wi-Fi Direct."
            ))
            "getState" -> { refresh(); result.success(snapshot()) }
            "getInvitation" -> getInvitation(result)
            "startNfcSharing" -> nfc.share(result, ::getInvitation)
            "stopNfc" -> { nfc.cancel(); result.success(null) }
            "readNfcInvitation" -> {
                if (!supported || Build.VERSION.SDK_INT < 29) {
                    result.error("unsupported", "NFC joining requires Android 10+ and Wi-Fi Direct.", null)
                } else if (status in listOf("connecting", "connected", "disconnecting")) {
                    result.error("busy", "Disconnect from the current group before reading an invitation.", null)
                } else nfc.read(result)
            }
            "createGroup", "discoverPeers", "joinGroup", "joinInvitation", "disconnect" -> {
                if (pending != null) {
                    result.error("busy", "Another request is in progress.", null); return
                }
                if (!supported || manager == null) {
                    result.error("unsupported", "Wi-Fi Direct is not supported on this device.", null); return
                }
                if (call.method != "disconnect" && status in listOf("connecting", "connected", "disconnecting")) {
                    result.error("busy", "Disconnect from the current group first.", null); return
                }
                val peerId = (call.arguments as? Map<*, *>)?.get("peerId") as? String
                if (call.method == "joinGroup" && peers.none { it["id"] == peerId }) {
                    result.error("invalid_peer", "Discover devices again and select a nearby device.", null); return
                }
                var invitationConfig: WifiP2pConfig? = null
                if (call.method == "joinInvitation") {
                    if (Build.VERSION.SDK_INT < 29) {
                        result.error("unsupported", "QR joining requires Android 10+. Use nearby-device discovery.", null); return
                    }
                    val args = call.arguments as? Map<*, *>
                    val name = args?.get("networkName") as? String
                    val password = args?.get("passphrase") as? String
                    if (args?.get("app") != "offline-group-messenger" || args["version"] != 1 ||
                        args["transport"] != "wifi-direct" || name == null || password == null ||
                        !name.matches(Regex("DIRECT-[a-zA-Z0-9]{2}.*")) ||
                        name.toByteArray(Charsets.UTF_8).size > 32 || name.any { it.code < 32 || it.code == 127 } ||
                        password.length !in 8..63 || password.any { it.code !in 32..126 }) {
                        result.error("invalid_invitation", "This is not a supported group invitation.", null); return
                    }
                    try {
                        invitationConfig = WifiP2pConfig.Builder()
                            .setNetworkName(name).setPassphrase(password).build()
                    } catch (_: IllegalArgumentException) {
                        result.error("invalid_invitation", "Invalid group credentials.", null); return
                    }
                }
                pending = result
                clearError()
                val run = { execute(call.method, peerId, invitationConfig) }
                if (permitted()) guarded(run) else {
                    val activity = activityBinding?.activity
                    if (activity == null) {
                        fail("no_activity", "Open the app to grant connection permissions.")
                    } else {
                        afterPermission = run
                        // Android 12 requires coarse and fine location requested together.
                        val permissions = if (Build.VERSION.SDK_INT >= 33) arrayOf(permission)
                            else arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, permission)
                        guarded { activity.requestPermissions(permissions, PERMISSION_REQUEST) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun execute(method: String, peerId: String?, invitation: WifiP2pConfig? = null) {
        val ch = ensureChannel()
        val mgr = manager
        if (ch == null || mgr == null) { fail("unavailable", "Wi-Fi Direct service is unavailable."); return }
        wifiEnabled = (context.getSystemService(Context.WIFI_SERVICE) as WifiManager).isWifiEnabled
        if (!wifiEnabled && method != "disconnect") { fail("wifi_disabled", "Enable Wi-Fi and try again."); return }
        if (method == "discoverPeers") {
            val location = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val enabled = if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled
                else location.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            if (!enabled) { fail("location_disabled", "Enable Location in system settings for nearby-device discovery."); return }
        }
        val token = ++revision
        operationTimeout = Runnable {
            if (token == revision && pending != null) {
                revision++ // Ignore late callbacks belonging to this timed-out request.
                val previous = status
                fail("timeout", "Android did not answer. Disconnect and try again.")
                if (previous in listOf("connecting", "disconnecting")) { status = previous; emit() }
            }
        }.also { handler.postDelayed(it, 15_000) }
        val listener = object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                if (!attached || token != revision) return
                finish()
                if (method == "discoverPeers") readPeers() else readConnection()
                emit()
            }
            override fun onFailure(reason: Int) {
                if (attached && token == revision) fail(reasonCode(reason), reasonMessage(reason))
            }
        }
        when (method) {
            "createGroup" -> {
                clearConnection("connecting"); emit()
                mgr.createGroup(ch, listener)
                watchConnection(token)
            }
            "discoverPeers" -> {
                peers = emptyList(); status = "discovering"; emit()
                mgr.discoverPeers(ch, listener)
            }
            "joinGroup" -> {
                clearConnection("connecting"); emit()
                mgr.connect(ch, WifiP2pConfig().apply {
                    deviceAddress = peerId
                    wps.setup = WpsInfo.PBC
                    groupOwnerIntent = 0
                }, listener)
                watchConnection(token)
            }
            "joinInvitation" -> {
                clearConnection("connecting"); emit()
                mgr.connect(ch, requireNotNull(invitation), listener)
                watchConnection(token)
            }
            "disconnect" -> {
                nfc.cancel()
                status = "disconnecting"; emit()
                fun removeExistingGroup() {
                    if (!attached || token != revision) return
                    guarded {
                        mgr.requestGroupInfo(ch) { group ->
                            if (!attached || token != revision) return@requestGroupInfo
                            if (group == null) {
                                peers = emptyList(); clearConnection("idle"); finish(); emit()
                            } else guarded {
                                mgr.removeGroup(ch, object : WifiP2pManager.ActionListener {
                                    override fun onSuccess() {
                                        if (attached && token == revision) {
                                            peers = emptyList(); clearConnection("idle"); finish(); emit()
                                        }
                                    }
                                    override fun onFailure(reason: Int) {
                                        if (attached && token == revision) {
                                            fail(reasonCode(reason), reasonMessage(reason))
                                            readConnection()
                                        }
                                    }
                                })
                            }
                        }
                    }
                }
                val cancel = {
                    if (attached && token == revision) guarded {
                        mgr.cancelConnect(ch, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() = removeExistingGroup()
                            override fun onFailure(reason: Int) = removeExistingGroup()
                        })
                    }
                }
                mgr.stopPeerDiscovery(ch, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { cancel() }
                    override fun onFailure(reason: Int) { cancel() }
                })
            }
        }
    }

    private fun getInvitation(result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "Another request is in progress.", null); return }
        if (status != "connected" || !isHost || !permitted()) {
            result.error("not_host", "Create a group before sharing its invitation.", null); return
        }
        val ch = channel
        val mgr = manager
        if (ch == null || mgr == null) {
            result.error("unavailable", "Wi-Fi Direct service is unavailable.", null); return
        }
        pending = result
        val token = ++revision
        operationTimeout = Runnable {
            if (token == revision && pending != null) {
                revision++
                fail("timeout", "Could not read group invitation. Please retry.")
            }
        }.also { handler.postDelayed(it, 10_000) }
        guarded {
            mgr.requestGroupInfo(ch) { group ->
                if (!attached || token != revision) return@requestGroupInfo
                if (status != "connected" || !isHost || group == null || !group.isGroupOwner ||
                    group.networkName.isNullOrEmpty() || group.passphrase.isNullOrEmpty()) {
                    fail("not_host", "The host group is no longer available. Create a group and retry.")
                } else {
                    // Credentials are returned only on explicit request, never in state events or logs.
                    finish(mapOf(
                        "app" to "offline-group-messenger", "version" to 1,
                        "transport" to "wifi-direct",
                        "networkName" to group.networkName, "passphrase" to group.passphrase
                    ))
                }
            }
        }
    }

    // Some devices omit a broadcast after an invitation is rejected. Re-query the
    // authoritative info while connecting and keep a finite cancellation window.
    private fun watchConnection(token: Int, remaining: Int = 60) {
        handler.postDelayed({
            if (!attached || token != revision || status != "connecting") return@postDelayed
            if (remaining == 0) {
                revision++
                guarded { channel?.let { manager?.cancelConnect(it, null) } }
                fail("connection_timeout", "No group formed. Check the other phone and try again.")
                readConnection()
            } else {
                readConnection()
                watchConnection(token, remaining - 1)
            }
        }, 1_000)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != PERMISSION_REQUEST) return false
        val run = afterPermission
        afterPermission = null
        if (run != null) {
            if (permitted()) guarded(run)
            else fail("permission_denied", "Permission denied. Allow Nearby devices or precise Location in app settings, then retry.")
        }
        emit()
        return true
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink; emit(); refresh()
    }
    override fun onCancel(arguments: Any?) { sink = null }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        nfc.attach(binding.activity)
        binding.addRequestPermissionsResultListener(this)
        refresh()
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onDetachedFromActivity() = detachActivity()
    private fun detachActivity() {
        nfc.detach()
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        if (afterPermission != null) fail("activity_detached", "Permission request interrupted. Please retry.")
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        revision++
        detachActivity()
        fail("detached", "Connection adapter closed.")
        attached = false
        nfc.dispose()
        handler.removeCallbacksAndMessages(null)
        // Best effort cleanup; explicit disconnect is the reliable user-visible path.
        channel?.let { ch ->
            try {
                manager?.stopPeerDiscovery(ch, null)
                manager?.cancelConnect(ch, null)
                manager?.removeGroup(ch, null)
            } catch (_: RuntimeException) { }
            if (Build.VERSION.SDK_INT >= 27) ch.close()
        }
        channel = null
        context.unregisterReceiver(receiver)
        (context.applicationContext as Application).unregisterActivityLifecycleCallbacks(lifecycle)
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        sink = null
        manager = null
    }
    private fun reasonCode(reason: Int) = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "unsupported"
        WifiP2pManager.BUSY -> "busy"
        else -> "connection_failed"
    }
    private fun reasonMessage(reason: Int) = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct is not supported."
        WifiP2pManager.BUSY -> "Android Wi-Fi Direct is busy. Wait a moment and try again."
        else -> "Wi-Fi Direct request failed (Android code $reason). Check Wi-Fi and retry."
    }
    companion object { private const val PERMISSION_REQUEST = 7412 }
}
