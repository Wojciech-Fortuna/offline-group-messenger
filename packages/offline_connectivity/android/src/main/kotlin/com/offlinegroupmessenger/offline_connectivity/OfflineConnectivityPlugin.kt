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
import android.util.Log
import java.net.Inet4Address
import java.net.NetworkInterface
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
    private lateinit var contacts: ContactsBridge
    private var attached = false
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var discovery: PublicGroupDiscovery? = null
    // Fail closed for a system group surviving an app-process restart.
    private var privateGroup = true
    private var admissionToken: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var afterPermission: (() -> Unit)? = null
    private var operationTimeout: Runnable? = null
    private var connectionSetup: ConnectionSetup? = null
    private var revision = 0
    private var connectionReadRevision = 0
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
                        discovery?.stopSearch()
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
                    if (!discovering && status == "discovering" && discovery?.isSearching() != true) { status = "idle"; emit() }
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
        contacts = ContactsBridge(context, binding.binaryMessenger)
        attached = true
        methods = MethodChannel(binding.binaryMessenger, "com.offlinegroupmessenger/connectivity")
            .also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "com.offlinegroupmessenger/connectivity/events")
            .also { it.setStreamHandler(this) }
        manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        discovery = manager?.let { mgr -> PublicGroupDiscovery(mgr, handler,
            onPeers = { values -> peers = values; if (attached) sink?.success(snapshot()) },
            onAdvertiseError = {
                errorCode = "discovery_unavailable"
                errorMessage = "Public discovery is unavailable. Recreate the group or share its QR/NFC invitation."
                if (attached) sink?.success(snapshot())
            },
            onSearchFinished = {
                if (attached && status == "discovering") { status = "idle"; emit() }
            }
        ) }
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
                    discovery?.close()
                    channel = null
                    revision++
                    clearConnection("unavailable")
                    fail("channel_lost", "Wi-Fi Direct service disconnected. Try again.")
                }
            }
            channel?.let { discovery?.attach(it) }
        }
        return channel
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "status" to status, "wifiEnabled" to wifiEnabled, "permissionGranted" to permitted(),
        "isHost" to isHost, "privateGroup" to privateGroup, "hostAddress" to hostAddress, "peers" to peers,
        "errorCode" to errorCode, "errorMessage" to errorMessage
    )
    private fun emit() {
        if (status != "connected" || !isHost) nfc.stopSharing()
        discovery?.advertise(status == "connected" && isHost && !privateGroup && wifiEnabled && permitted())
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
        revision++ // Failed operations must not accept late native callbacks.
        connectionSetup = null
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
        // Generic Wi-Fi peers are intentionally excluded. DNS-SD supplies public groups.
    }
    private fun readConnection() {
        if (!attached || !permitted() || status == "disconnecting") return
        val ch = channel ?: return
        val token = revision
        val readToken = ++connectionReadRevision
        guarded {
            manager?.requestConnectionInfo(ch) { info ->
                if (!attached || token != revision || readToken != connectionReadRevision || status == "disconnecting") return@requestConnectionInfo
                val previousStatus = status
                if (info.groupFormed) {
                    isHost = info.isGroupOwner
                    // Android supplies the real address; never assume a P2P subnet.
                    hostAddress = info.groupOwnerAddress?.hostAddress
                    status = if (hostAddress != null) "connected" else "connecting"
                    clearError()
                    if (status == "connected") connectionSetup?.connected()
                    if (isHost && hostAddress == null) {
                        readHostInterface(ch, token, readToken)
                    }
                } else if (status == "connected") {
                    clearConnection("idle")
                }
                if (status != previousStatus) Log.d("OfflineConnection", "P2P state=$status owner=$isHost addressReady=${hostAddress != null}")
                emit()
            }
        }
    }

    private fun readHostInterface(ch: WifiP2pManager.Channel, token: Int, readToken: Int) {
        guarded {
            manager?.requestGroupInfo(ch) { group ->
                if (!attached || token != revision || readToken != connectionReadRevision ||
                    status != "connecting" || !isHost || group?.isGroupOwner != true) return@requestGroupInfo
                // Only the actual P2P interface can supply a missing GO address.
                // Never use infrastructure Wi-Fi, mobile data, DNS or a guessed subnet.
                val interfaceName = group.`interface` ?: return@requestGroupInfo
                val address = try {
                    NetworkInterface.getByName(interfaceName)?.inetAddresses?.toList()
                        ?.filterIsInstance<Inet4Address>()
                        ?.firstOrNull { !it.isLoopbackAddress && !it.isAnyLocalAddress }
                        ?.hostAddress
                } catch (_: Exception) { null }
                if (address != null) {
                    hostAddress = address
                    status = "connected"
                    clearError()
                    connectionSetup?.connected()
                    Log.d("OfflineConnection", "Host address obtained from P2P interface")
                    emit()
                }
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
            "rotatePrivateAdmission" -> {
                val args = call.arguments as? Map<*, *>
                val previous = args?.get("previous") as? String
                val next = args?.get("next") as? String
                if (pending != null || status != "connected" || !isHost || !privateGroup ||
                    previous == null || previous != admissionToken || next == null ||
                    next == previous || !next.matches(Regex("[0-9a-f]{64}"))) {
                    result.error("membership_changed", "Private group changed. Retry from the participant list.", null)
                } else {
                    nfc.stopSharing()
                    admissionToken = next
                    result.success(null)
                }
            }
            "startNfcSharing" -> nfc.share(result) { getInvitation(it, viaNfc = true) }
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
                val args = call.arguments as? Map<*, *>
                if (call.method == "createGroup") {
                    val isPrivate = args?.get("privateGroup") == true
                    val secret = args?.get("admissionToken") as? String
                    if (args?.get("privateGroup") !is Boolean ||
                        (isPrivate && (secret == null || !secret.matches(Regex("[0-9a-f]{64}")) || !nfc.canShare)) ||
                        (!isPrivate && secret != null)) {
                        result.error("invalid_group", "Private groups require NFC sharing support and valid admission credentials.", null); return
                    }
                    privateGroup = isPrivate
                    admissionToken = secret
                }
                if (call.method == "joinGroup" && peers.none { it["id"] == peerId }) {
                    result.error("invalid_peer", "Discover devices again and select a nearby device.", null); return
                }
                var invitationConfig: WifiP2pConfig? = null
                if (call.method == "joinInvitation") {
                    if (Build.VERSION.SDK_INT < 29) {
                        result.error("unsupported", "QR joining requires Android 10+. Use nearby-device discovery.", null); return
                    }
                    val name = args?.get("networkName") as? String
                    val password = args?.get("passphrase") as? String
                    val isPrivate = args?.get("privateGroup") == true
                    val secret = args?.get("admissionToken") as? String
                    if (args?.get("app") != "offline-group-messenger" || args["version"] != (if (isPrivate) 2 else 1) ||
                        (args["privateGroup"] != null && args["privateGroup"] !is Boolean) ||
                        (isPrivate && (args["version"] != 2 || secret == null || !secret.matches(Regex("[0-9a-f]{64}")))) ||
                        (!isPrivate && secret != null) ||
                        args["transport"] != "wifi-direct" || name == null || password == null ||
                        !name.matches(Regex("DIRECT-[a-zA-Z0-9]{2}.*")) ||
                        name.toByteArray(Charsets.UTF_8).size > 32 || name.any { it.code < 32 || it.code == 127 } ||
                        password.length !in 8..63 || password.any { it.code !in 32..126 }) {
                        result.error("invalid_invitation", "This is not a supported group invitation.", null); return
                    }
                    try {
                        invitationConfig = WifiP2pConfig.Builder()
                            .setNetworkName(name).setPassphrase(password).build()
                        privateGroup = isPrivate
                        admissionToken = null // Joining credentials stay in the Dart session, not broadcasts.
                    } catch (_: IllegalArgumentException) {
                        result.error("invalid_invitation", "Invalid group credentials.", null); return
                    }
                }
                if (call.method == "joinGroup") { privateGroup = false; admissionToken = null }
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
        if (method != "disconnect") {
            val location = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val enabled = if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled
                else location.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            if (!enabled) { fail("location_disabled", "Enable Location in system settings for Wi-Fi Direct. Internet and a GPS fix are not required."); return }
        }
        val token = ++revision
        val setup = if (method in listOf("createGroup", "joinGroup", "joinInvitation")) {
            ConnectionSetup(
                isCurrent = { attached && token == revision },
                schedule = { delay, task -> handler.postDelayed({ task() }, delay) },
                onAccepted = {
                    Log.d("OfflineConnection", "$method accepted; waiting for authoritative group state")
                    finish()
                    readConnection()
                    emit()
                },
                onConnected = { finish() },
                onFailure = { code, reason ->
                    try { mgr.cancelConnect(ch, null) } catch (_: RuntimeException) {}
                    Log.d("OfflineConnection", "$method setup failed: $code reason=$reason")
                    fail(
                        if (reason != null) reasonCode(reason) else code,
                        if (reason != null) reasonMessage(reason)
                        else if (code == "connection_timeout") "No group formed. Check the other phone and try again."
                        else "Android did not answer. Disconnect and try again."
                    )
                }
            )
        } else null
        connectionSetup = setup
        setup?.start()
        if (setup == null) operationTimeout = Runnable {
            if (token == revision && pending != null) {
                revision++ // Ignore late callbacks belonging to this timed-out request.
                if (method == "discoverPeers") discovery?.stopSearch()
                else try { mgr.cancelConnect(ch, null) } catch (_: RuntimeException) {}
                Log.d("OfflineConnection", "$method action timed out")
                clearConnection("idle")
                fail("timeout", "Android did not answer. Disconnect and try again.")
            }
        }.also { handler.postDelayed(it, if (method == "discoverPeers") 55_000 else 15_000) }
        val listener = object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                if (!attached || token != revision) return
                if (setup != null) { setup.accepted(); return }
                Log.d("OfflineConnection", "$method accepted; waiting for authoritative group state")
                finish()
                if (method == "discoverPeers") readPeers() else readConnection()
                emit()
            }
            override fun onFailure(reason: Int) {
                if (attached && token == revision) {
                    if (setup != null) { setup.rejected(reason); return }
                    Log.d("OfflineConnection", "$method failed: $reason")
                    fail(reasonCode(reason), reasonMessage(reason))
                }
            }
        }
        fun issueAction() {
          if (!attached || token != revision) return
          guarded { when (method) {
            "createGroup" -> {
                clearConnection("connecting"); emit()
                if (Build.VERSION.SDK_INT >= 29) {
                    val credentials = OfflineGroupCredentials.create()
                    val config = WifiP2pConfig.Builder()
                        .setNetworkName(credentials.networkName)
                        .setPassphrase(credentials.passphrase)
                        .setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_2GHZ)
                        .enablePersistentMode(false)
                        .build()
                    Log.d("OfflineConnection", "Creating local 2.4 GHz group")
                    mgr.createGroup(ch, config, listener)
                } else {
                    Log.d("OfflineConnection", "Creating local group with legacy Android API")
                    mgr.createGroup(ch, listener)
                }
                watchConnection(token)
            }
            "discoverPeers" -> {
                peers = emptyList(); status = "discovering"; emit()
                discovery?.search(listener) ?: listener.onFailure(WifiP2pManager.ERROR)
            }
            "joinGroup" -> {
                clearConnection("connecting"); emit()
                PeerPresenceGate(
                    target = requireNotNull(peerId),
                    isCurrent = { attached && token == revision && pending != null && status == "connecting" },
                    requestPeers = { reply -> guarded {
                        mgr.requestPeers(ch) { devices -> reply(devices.deviceList.map { it.deviceAddress }) }
                    } },
                    discoverPeers = { ready, failed -> guarded {
                        Log.d("OfflineConnection", "Refreshing selected public host presence")
                        mgr.discoverPeers(ch, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() = ready()
                            override fun onFailure(reason: Int) = failed(reason)
                        })
                    } },
                    schedule = { delay, task -> handler.postDelayed({ task() }, delay) },
                    onReady = { guarded {
                        Log.d("OfflineConnection", "Selected public host present; connecting without flushing discovery")
                        mgr.connect(ch, WifiP2pConfig().apply {
                            deviceAddress = peerId
                            wps.setup = WpsInfo.PBC
                            groupOwnerIntent = 0
                        }, listener)
                        watchConnection(token)
                    } },
                    onFailure = { reason ->
                        try { mgr.stopPeerDiscovery(ch, null) } catch (_: RuntimeException) {}
                        if (reason == null) {
                            fail("peer_unavailable", "The selected host is no longer visible to Android. Find nearby groups again and retry.")
                        } else listener.onFailure(reason)
                    }
                ).start()
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
                cancel()
            }
          } }
        }
        if (method == "discoverPeers") issueAction()
        else if (method == "joinGroup") {
            discovery?.stopSearch(stopNativeDiscovery = false)
            issueAction()
        }
        else discovery?.stopSearch { issueAction() } ?: issueAction()
    }

    private fun getInvitation(result: MethodChannel.Result, viaNfc: Boolean = false) {
        if (pending != null) { result.error("busy", "Another request is in progress.", null); return }
        if (privateGroup && (!viaNfc || admissionToken == null)) {
            result.error("private_group", "Private groups use NFC invitations only. Recreate the group if its credentials were lost.", null); return
        }
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
                    val payload = mutableMapOf<String, Any>(
                        "app" to "offline-group-messenger", "version" to if (privateGroup) 2 else 1,
                        "transport" to "wifi-direct",
                        "networkName" to group.networkName, "passphrase" to group.passphrase
                    )
                    if (privateGroup) {
                        payload["privateGroup"] = true
                        payload["admissionToken"] = requireNotNull(admissionToken)
                    }
                    finish(payload)
                }
            }
        }
    }

    // Some devices omit connection broadcasts. Poll authoritative info; the
    // independent ConnectionSetup deadline also covers missing query callbacks.
    private fun watchConnection(token: Int) {
        handler.postDelayed({
            if (!attached || token != revision || status != "connecting") return@postDelayed
            readConnection()
            watchConnection(token)
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
        discovery?.close()
        nfc.dispose()
        contacts.close()
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
