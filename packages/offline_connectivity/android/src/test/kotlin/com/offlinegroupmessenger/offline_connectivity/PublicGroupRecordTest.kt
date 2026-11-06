package com.offlinegroupmessenger.offline_connectivity

import org.junit.Assert.*
import org.junit.Test

class PublicGroupRecordTest {
    @Test fun onlyPublicMessengerRecordsAreAccepted() {
        val domain = "OfflineMessenger._ogm._tcp.local."
        assertTrue(PublicGroupRecord.accepts(domain, PublicGroupRecord.fields()))
        assertFalse(PublicGroupRecord.accepts(domain, PublicGroupRecord.fields() + ("mode" to "private")))
        assertFalse(PublicGroupRecord.accepts(domain, PublicGroupRecord.fields() + ("v" to "1")))
        assertFalse(PublicGroupRecord.accepts(domain, mapOf("mode" to "public")))
        assertFalse(PublicGroupRecord.accepts("Other._ogm._tcp.local.", PublicGroupRecord.fields()))
    }

    @Test fun advertisementContainsNoCredentialsOrPersonalName() {
        assertEquals(setOf("app", "v", "mode"), PublicGroupRecord.fields().keys)
    }
}
