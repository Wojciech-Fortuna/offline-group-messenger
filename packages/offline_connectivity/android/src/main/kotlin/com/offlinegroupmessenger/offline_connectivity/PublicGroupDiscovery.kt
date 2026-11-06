package com.offlinegroupmessenger.offline_connectivity

import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Handler
import android.os.SystemClock

/** DNS-SD advertises public groups only. Never publishes network/admission credentials. */
internal class PublicGroupDiscovery(
    private val manager: WifiP2pManager,
    private val handler: Handler,
    private val onPeers: (List<Map<String, Any>>) -> Unit,
    private val onAdvertiseError: () -> Unit
) {
    private var channel: WifiP2pManager.Channel? = null
    private var service: WifiP2pDnsSdServiceInfo? = null
    private var request: WifiP2pDnsSdServiceRequest? = null
    private var advertised = false
    private var advertisementRevision = 0
    private var scanRevision = 0
    private var scanning = false
    private val peers = linkedMapOf<String, Pair<Map<String, Any>, Long>>()

    fun attach(value: WifiP2pManager.Channel) {
        if (channel === value) return
        close()
        channel = value
        manager.setDnsSdResponseListeners(value, { _, _, _ -> }, { domain, record, device ->
            if (channel === value && scanning && PublicGroupRecord.accepts(domain, record)) {
                peers[device.deviceAddress] = Pair(mapOf(
                    "id" to device.deviceAddress,
                    "name" to (device.deviceName?.takeIf { it.isNotBlank() } ?: "Public group"),
                    "isGroupOwner" to true
                ), SystemClock.elapsedRealtime())
                publishPeers()
            }
        })
    }

    fun advertise(enabled: Boolean) {
        val ch = channel ?: return
        if (enabled == advertised) return
        advertised = enabled
        val revision = ++advertisementRevision
        service?.let { try { manager.removeLocalService(ch, it, null) } catch (_: RuntimeException) {} }
        service = null
        if (!enabled) return
        val info = WifiP2pDnsSdServiceInfo.newInstance(
            PublicGroupRecord.INSTANCE, PublicGroupRecord.TYPE,
            PublicGroupRecord.fields() + ("advertisement" to revision.toString())
        )
        service = info
        try {
            manager.addLocalService(ch, info, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    if (channel !== ch || revision != advertisementRevision || !advertised) {
                        try { manager.removeLocalService(ch, info, null) } catch (_: RuntimeException) {}
                    }
                }
                override fun onFailure(reason: Int) {
                    if (channel === ch && revision == advertisementRevision) onAdvertiseError()
                }
            })
        } catch (_: RuntimeException) { onAdvertiseError() }
    }

    fun search(listener: WifiP2pManager.ActionListener) {
        val ch = channel ?: run { listener.onFailure(WifiP2pManager.ERROR); return }
        stopSearch()
        scanning = true
        val revision = scanRevision
        val req = WifiP2pDnsSdServiceRequest.newInstance(PublicGroupRecord.TYPE)
        request = req
        fun valid() = channel === ch && scanning && revision == scanRevision
        val failure = { reason: Int -> if (valid()) { stopSearch(); listener.onFailure(reason) } }
        try {
            manager.clearServiceRequests(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    if (!valid()) return
                    try { manager.addServiceRequest(ch, req, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            if (!valid()) return
                            try { manager.discoverServices(ch, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() { if (valid()) listener.onSuccess() }
                                override fun onFailure(reason: Int) { failure(reason) }
                            }) } catch (_: RuntimeException) { failure(WifiP2pManager.ERROR) }
                        }
                        override fun onFailure(reason: Int) { failure(reason) }
                    }) } catch (_: RuntimeException) { failure(WifiP2pManager.ERROR) }
                }
                override fun onFailure(reason: Int) { failure(reason) }
            })
        } catch (_: RuntimeException) { failure(WifiP2pManager.ERROR) }
        fun expire() {
            if (!valid()) return
            val cutoff = SystemClock.elapsedRealtime() - 60_000
            if (peers.entries.removeAll { it.value.second < cutoff }) publishPeers()
            handler.postDelayed({ expire() }, 5_000)
        }
        handler.postDelayed({ expire() }, 5_000)
    }

    private fun publishPeers() = onPeers(peers.values.map { it.first }.sortedBy { it["name"].toString() })

    fun stopSearch() {
        scanning = false
        scanRevision++
        val ch = channel
        val req = request
        request = null
        if (ch != null && req != null) {
            try { manager.removeServiceRequest(ch, req, null) } catch (_: RuntimeException) {}
        }
        peers.clear()
        onPeers(emptyList())
    }

    fun close() {
        advertise(false)
        stopSearch()
        channel = null
    }
}
