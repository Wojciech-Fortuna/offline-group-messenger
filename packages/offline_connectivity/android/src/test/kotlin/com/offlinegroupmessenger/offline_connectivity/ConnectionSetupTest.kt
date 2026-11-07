package com.offlinegroupmessenger.offline_connectivity

import org.junit.Assert.*
import org.junit.Test

class ConnectionSetupTest {
    private class Harness {
        var current = true
        var accepted = 0
        var connected = 0
        val failures = mutableListOf<Pair<String, Int?>>()
        private var now = 0L
        private val tasks = mutableListOf<Pair<Long, () -> Unit>>()
        val setup = ConnectionSetup(
            isCurrent = { current },
            schedule = { delay, task -> tasks.add(now + delay to task); Unit },
            onAccepted = { accepted++ },
            onConnected = { connected++ },
            onFailure = { code, reason -> failures.add(code to reason) }
        ).also { it.start() }
        fun advance(until: Long) {
            while (true) {
                val task = tasks.minByOrNull { it.first } ?: break
                if (task.first > until) break
                tasks.remove(task)
                now = task.first
                task.second()
            }
            now = until
        }
    }

    @Test fun acceptanceDoesNotMeanConnectedAndStillHasFormationDeadline() {
        val h = Harness()
        h.setup.accepted()
        h.advance(15_000)
        assertEquals(1, h.accepted)
        assertEquals(0, h.connected)
        assertTrue(h.failures.isEmpty())
        h.advance(75_000)
        assertEquals(listOf("connection_timeout" to null), h.failures)
        h.setup.connected()
        assertEquals(0, h.connected)
    }

    @Test fun authoritativeGroupCompletesEvenWhenActionCallbackIsMissing() {
        val h = Harness()
        h.setup.connected()
        h.advance(90_000)
        h.setup.rejected(0)
        h.setup.accepted()
        assertEquals(1, h.connected)
        assertEquals(0, h.accepted)
        assertTrue(h.failures.isEmpty())
    }

    @Test fun connectedGroupSurvivesDuplicateAndContradictoryCallbacks() {
        val h = Harness()
        h.setup.accepted()
        h.setup.connected()
        h.setup.connected()
        h.setup.rejected(2)
        h.setup.accepted()
        h.advance(90_000)
        assertEquals(1, h.accepted)
        assertEquals(1, h.connected)
        assertTrue(h.failures.isEmpty())
    }

    @Test fun missingCallbackExpiresAndLateCallbacksCannotReviveAttempt() {
        val h = Harness()
        h.advance(15_000)
        h.setup.accepted()
        h.setup.connected()
        h.setup.rejected(0)
        h.advance(90_000)
        assertEquals(listOf("timeout" to null), h.failures)
        assertEquals(0, h.accepted)
        assertEquals(0, h.connected)
    }

    @Test fun rejectionIsTerminalAndPreservesNativeReason() {
        val h = Harness()
        h.setup.rejected(2)
        h.setup.accepted()
        h.setup.connected()
        h.advance(90_000)
        assertEquals(listOf("connection_failed" to 2), h.failures)
        assertEquals(0, h.accepted)
        assertEquals(0, h.connected)
    }

    @Test fun duplicateAcceptanceCannotExtendDeadlineOrFailAnAcceptedAction() {
        val h = Harness()
        h.setup.accepted()
        h.advance(70_000)
        h.setup.start()
        h.setup.accepted()
        h.setup.rejected(0)
        h.advance(75_000)
        assertEquals(1, h.accepted)
        assertEquals(listOf("connection_timeout" to null), h.failures)
    }

    @Test fun cancellationOrReplacementSuppressesEveryOldCallbackAndDeadline() {
        val old = Harness()
        old.current = false
        val retry = Harness()
        old.setup.accepted()
        old.setup.connected()
        old.setup.rejected(0)
        old.advance(90_000)
        retry.setup.accepted()
        retry.setup.connected()
        retry.advance(90_000)
        assertEquals(0, old.accepted)
        assertEquals(0, old.connected)
        assertTrue(old.failures.isEmpty())
        assertEquals(1, retry.connected)
        assertTrue(retry.failures.isEmpty())
    }
}
