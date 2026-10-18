package com.offlinegroupmessenger.offline_connectivity

import org.junit.Assert.*
import org.junit.Test

class InvitationApduTest {
    @Test fun roundTripUsesBoundedChunksIncludingUnicode() {
        val data = ("Group żółw 👋 " + "x".repeat(500)).toByteArray(Charsets.UTF_8)
        val host = InvitationApdu { data }
        var reads = 0
        val result = InvitationApdu.read { command ->
            if (command[1] == 0xB0.toByte()) {
                assertTrue((command[4].toInt() and 255) <= 200)
                reads++
            }
            host.respond(command)
        }
        assertArrayEquals(data, result)
        assertTrue(reads >= 3)
    }

    @Test fun disabledOrRevokedSharingNeverReturnsCredentials() {
        var data: ByteArray? = null
        val host = InvitationApdu { data }
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), host.respond(InvitationApdu.SELECT))
        data = "secret".toByteArray()
        host.respond(InvitationApdu.SELECT)
        data = null // Expiry/background/disconnect use the same missing-payload gate.
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), host.respond(byteArrayOf(0, 0xB0.toByte(), 0, 0, 6)))
    }

    @Test fun newSessionAndDeactivationRequireSelectionAgain() {
        var data = "first".toByteArray()
        val host = InvitationApdu { data }
        host.respond(InvitationApdu.SELECT)
        data = "other".toByteArray()
        val read = byteArrayOf(0, 0xB0.toByte(), 0, 0, 5)
        assertEquals(0x69, host.respond(read)[0].toInt())
        host.respond(InvitationApdu.SELECT)
        assertArrayEquals(data + byteArrayOf(0x90.toByte(), 0), host.respond(read))
        host.reset()
        assertEquals(0x69, host.respond(read)[0].toInt())
    }

    @Test fun invalidCommandsAndOutOfBoundsReadsAreRejected() {
        val data = "secret".toByteArray()
        val host = InvitationApdu { data }
        host.respond(InvitationApdu.SELECT)
        assertArrayEquals(byteArrayOf(0x6D, 0), host.respond(byteArrayOf(0)))
        for (read in listOf(
            byteArrayOf(0, 0xB0.toByte(), 0, 0, 0),
            byteArrayOf(0, 0xB0.toByte(), 0, 5, 2),
            byteArrayOf(0, 0xB0.toByte(), 0, 0, 201.toByte()))) {
            assertArrayEquals(byteArrayOf(0x6B, 0), host.respond(read))
        }
    }

    @Test fun readerRejectsUnsupportedTruncatedAndOversizedResponses() {
        for (reply in listOf(byteArrayOf(), byteArrayOf(0x6A, 0x82.toByte()),
            byteArrayOf(0x08, 0x01, 0x90.toByte(), 0), byteArrayOf(0, 0, 0x90.toByte(), 0))) {
            assertThrows(IllegalArgumentException::class.java) { InvitationApdu.read { reply } }
        }
        assertThrows(IllegalArgumentException::class.java) {
            InvitationApdu.read { command ->
                if (command.contentEquals(InvitationApdu.SELECT)) byteArrayOf(0, 5, 0x90.toByte(), 0)
                else byteArrayOf(1, 0x90.toByte(), 0)
            }
        }
    }

    @Test fun revocationBetweenChunksAbortsRead() {
        var data: ByteArray? = ByteArray(600) { 65 }
        val host = InvitationApdu { data }
        var calls = 0
        assertThrows(IllegalArgumentException::class.java) {
            InvitationApdu.read { command ->
                calls++
                if (calls == 3) data = null
                host.respond(command)
            }
        }
    }
}
