package com.offlinegroupmessenger.offline_transport_lab

import android.app.Activity
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/** Observes a group owned by Messenger. Never creates, joins or removes it. */
internal class P2pObserver(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(WifiP2pManager::class.java)
    private var channel: WifiP2pManager.Channel? = null
    private var pending: MethodChannel.Result? = null
    private var revision = 0

    private fun fail(message: String) {
        revision++
        handler.removeCallbacksAndMessages(null)
        val result = pending; pending = null
        result?.error("p2p_unavailable", message, null)
    }

    fun read(result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "P2P query already running", null); return }
        pending = result
        val token = ++revision
        handler.postDelayed({ if (token == revision) fail("Android did not return the Wi-Fi Direct interface") }, 8_000)
        try {
            if (channel == null) channel = manager?.initialize(activity, Looper.getMainLooper()) {
                channel = null; fail("Wi-Fi Direct channel closed")
            }
            val ch = requireNotNull(channel)
            manager.requestConnectionInfo(ch) { info ->
                if (token != revision) return@requestConnectionInfo
                if (!info.groupFormed) { fail("Create/join a group in Messenger first, then open this lab"); return@requestConnectionInfo }
                try { manager.requestGroupInfo(ch) { group ->
                    if (token != revision) return@requestGroupInfo
                    try {
                        val iface = requireNotNull(group?.`interface`)
                        val address = NetworkInterface.getByName(iface)?.interfaceAddresses?.firstOrNull {
                            it.address is Inet4Address && !it.address.isLoopbackAddress && !it.address.isAnyLocalAddress
                        } ?: error("P2P IPv4 unavailable")
                        val local = requireNotNull(address.address.hostAddress)
                        val host = info.groupOwnerAddress?.hostAddress ?: if (info.isGroupOwner) local else error("Host IPv4 unavailable")
                        handler.removeCallbacksAndMessages(null)
                        revision++
                        val reply = pending; pending = null
                        reply?.success(mapOf("local" to local, "host" to host,
                            "prefix" to address.networkPrefixLength.toInt(), "isHost" to info.isGroupOwner))
                    } catch (_: Exception) { fail("Cannot read the actual Wi-Fi Direct interface; retry after the group connects") }
                } } catch (_: Exception) { fail("Cannot query group; check Nearby devices / Location permission") }
            }
        } catch (_: Exception) { fail("Cannot query Wi-Fi Direct; check permissions and radio state") }
    }

    fun close() {
        fail("Lab closed")
        if (Build.VERSION.SDK_INT >= 27) channel?.close()
        channel = null
    }
}
