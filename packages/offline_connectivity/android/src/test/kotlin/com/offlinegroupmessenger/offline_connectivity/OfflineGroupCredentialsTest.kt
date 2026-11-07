package com.offlinegroupmessenger.offline_connectivity

import org.junit.Assert.*
import org.junit.Test

class OfflineGroupCredentialsTest {
    @Test fun localCredentialsFitAndroidAndInvitationConstraints() {
        repeat(20) {
            val credentials = OfflineGroupCredentials.create()
            assertTrue(credentials.networkName.matches(Regex("DIRECT-[a-zA-Z0-9]{2}.*")))
            assertTrue(credentials.networkName.toByteArray(Charsets.UTF_8).size <= 32)
            assertTrue(credentials.passphrase.length in 8..63)
            assertTrue(credentials.passphrase.all { it.code in 32..126 })
            assertFalse(credentials.toString().contains(credentials.passphrase))
        }
    }

    @Test fun newGroupsDoNotReuseNetworkCredentials() {
        val first = OfflineGroupCredentials.create()
        val second = OfflineGroupCredentials.create()
        assertNotEquals(first.networkName, second.networkName)
        assertNotEquals(first.passphrase, second.passphrase)
    }
}
