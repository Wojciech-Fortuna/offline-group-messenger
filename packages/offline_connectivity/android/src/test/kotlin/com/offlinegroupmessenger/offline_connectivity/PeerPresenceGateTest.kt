package com.offlinegroupmessenger.offline_connectivity

import org.junit.Assert.*
import org.junit.Test

class PeerPresenceGateTest {
    private class Radio {
        var current = true
        var peers = listOf<String>()
        var queries = 0
        var discoveries = 0
        var connections = 0
        var holdQuery = false
        var holdDiscovery = false
        var discoveryError: Int? = null
        var queryReply: ((Collection<String>) -> Unit)? = null
        var discoveryReply: (() -> Unit)? = null
        val failures = mutableListOf<Int?>()
        private var now = 0L
        private val tasks = mutableListOf<Pair<Long, () -> Unit>>()
        val gate = PeerPresenceGate(
            target = "aa:bb:cc:dd:ee:ff",
            isCurrent = { current },
            requestPeers = { reply ->
                queries++
                queryReply = reply
                if (!holdQuery) reply(peers)
            },
            discoverPeers = { ready, failed ->
                discoveries++
                discoveryReply = ready
                val error = discoveryError
                if (error != null) failed(error) else if (!holdDiscovery) ready()
            },
            schedule = { delay, task -> tasks.add(Pair(now + delay, task)); Unit },
            onReady = { connections++ },
            onFailure = { failures.add(it) }
        )

        fun advance(until: Long) {
            while (true) {
                val next = tasks.minByOrNull { it.first } ?: break
                if (next.first > until) break
                tasks.remove(next)
                now = next.first
                next.second()
            }
            now = until
        }
    }

    @Test fun presentHostConnectsOnceWithoutRestartingDiscovery() {
        val radio = Radio().apply { peers = listOf("AA:BB:CC:DD:EE:FF") }
        radio.gate.start()
        radio.gate.start()
        radio.queryReply!!(radio.peers)
        radio.advance(10_000)
        assertEquals(1, radio.connections)
        assertEquals(0, radio.discoveries)
        assertTrue(radio.failures.isEmpty())
    }

    @Test fun flushedHostIsRediscoveredBeforeConnecting() {
        val radio = Radio()
        radio.gate.start()
        assertEquals(0, radio.connections)
        assertEquals(1, radio.discoveries)
        radio.peers = listOf("aa:bb:cc:dd:ee:ff")
        radio.advance(500)
        radio.advance(10_000)
        assertEquals(1, radio.connections)
        assertEquals(1, radio.discoveries)
        assertTrue(radio.failures.isEmpty())
    }

    @Test fun unrelatedDevicesNeverReplaceTheSelectedPublicHost() {
        val radio = Radio().apply { peers = listOf("11:22:33:44:55:66") }
        radio.gate.start()
        radio.advance(8_000)
        assertEquals(0, radio.connections)
        assertEquals(listOf<Int?>(null), radio.failures)
        val queriesAtDeadline = radio.queries
        radio.peers = listOf("aa:bb:cc:dd:ee:ff")
        radio.advance(20_000)
        assertEquals(queriesAtDeadline, radio.queries)
        assertEquals(0, radio.connections)
    }

    @Test fun missingPeerCallbackTimesOutAndLateReplyCannotConnect() {
        val radio = Radio().apply { holdQuery = true }
        radio.gate.start()
        radio.advance(8_000)
        radio.queryReply!!(listOf("aa:bb:cc:dd:ee:ff"))
        assertEquals(listOf<Int?>(null), radio.failures)
        assertEquals(0, radio.connections)
    }

    @Test fun missingDiscoveryCallbackAlsoHasADeadline() {
        val radio = Radio().apply { holdDiscovery = true }
        radio.gate.start()
        radio.advance(8_000)
        radio.discoveryReply!!()
        assertEquals(listOf<Int?>(null), radio.failures)
        assertEquals(1, radio.queries)
    }

    @Test fun obsoleteOperationIgnoresPeerCallbacksAndDeadline() {
        val radio = Radio().apply { holdQuery = true }
        radio.gate.start()
        radio.current = false
        radio.queryReply!!(listOf("aa:bb:cc:dd:ee:ff"))
        radio.advance(10_000)
        assertEquals(0, radio.connections)
        assertTrue(radio.failures.isEmpty())
    }

    @Test fun obsoleteOperationDoesNotContinueRediscovery() {
        val radio = Radio().apply { holdDiscovery = true }
        radio.gate.start()
        radio.current = false
        radio.discoveryReply!!()
        radio.advance(10_000)
        assertEquals(1, radio.queries)
        assertEquals(0, radio.connections)
        assertTrue(radio.failures.isEmpty())
    }

    @Test fun nativeDiscoveryFailureIsReportedOnceWithoutBlindRetry() {
        val radio = Radio().apply { discoveryError = 2 }
        radio.gate.start()
        radio.advance(10_000)
        assertEquals(listOf<Int?>(2), radio.failures)
        assertEquals(1, radio.discoveries)
        assertEquals(0, radio.connections)
    }
}
