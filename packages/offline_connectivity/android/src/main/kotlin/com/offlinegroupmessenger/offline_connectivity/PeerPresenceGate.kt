package com.offlinegroupmessenger.offline_connectivity

/** Revalidates a selected public host without stopping/flushing native discovery. */
internal class PeerPresenceGate(
    private val target: String,
    private val isCurrent: () -> Boolean,
    private val requestPeers: ((Collection<String>) -> Unit) -> Unit,
    private val discoverPeers: (() -> Unit, (Int) -> Unit) -> Unit,
    private val schedule: (Long, () -> Unit) -> Unit,
    private val onReady: () -> Unit,
    private val onFailure: (Int?) -> Unit
) {
    private var finished = false
    private var started = false
    private var refreshing = false
    private var queryRevision = 0

    private fun active() = !finished && isCurrent()

    fun start() {
        if (started || !active()) return
        started = true
        // Independent deadline also covers missing Android callbacks.
        schedule(8_000) { fail(null) }
        query()
    }

    private fun fail(reason: Int?) {
        if (!active()) return
        finished = true
        onFailure(reason)
    }

    private fun query() {
        if (!active()) return
        val revision = ++queryRevision
        requestPeers { addresses ->
            if (active() && revision == queryRevision) {
                queryRevision++ // Ignore duplicate/late responses to this query.
                if (addresses.any { it.equals(target, ignoreCase = true) }) {
                    finished = true
                    onReady()
                } else if (!refreshing) {
                    refreshing = true
                    discoverPeers({ if (active()) query() }, { fail(it) })
                } else {
                    schedule(500) { query() }
                }
            }
        }
    }
}
