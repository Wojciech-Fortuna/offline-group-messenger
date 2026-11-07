package com.offlinegroupmessenger.offline_connectivity

/** Native action acceptance is not proof that a usable P2P group exists. */
internal class ConnectionSetup(
    private val isCurrent: () -> Boolean,
    private val schedule: (Long, () -> Unit) -> Unit,
    private val onAccepted: () -> Unit,
    private val onConnected: () -> Unit,
    private val onFailure: (String, Int?) -> Unit
) {
    private var started = false
    private var answered = false
    private var finished = false
    private fun active() = started && !finished && isCurrent()

    fun start() {
        if (started) return
        started = true
        schedule(15_000) {
            if (active() && !answered) fail("timeout")
        }
        // Independent of action callbacks and periodic connection-info queries.
        schedule(75_000) { if (active()) fail("connection_timeout") }
    }

    fun accepted() {
        if (!active() || answered) return
        answered = true
        onAccepted()
    }

    fun rejected(reason: Int) {
        if (!active() || answered) return
        answered = true
        fail("connection_failed", reason)
    }

    fun connected() {
        if (!active()) return
        finished = true
        onConnected()
    }

    private fun fail(code: String, reason: Int? = null) {
        if (!active()) return
        finished = true
        onFailure(code, reason)
    }
}
