package com.offlinegroupmessenger.offline_connectivity

import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

internal fun testCrypto(): ContactCrypto {
    val pair = KeyPairGenerator.getInstance("EC").apply {
        initialize(ECGenParameterSpec("secp256r1"))
    }.generateKeyPair()
    return ContactCrypto(pair.public as ECPublicKey, pair.private)
}

class ContactBookTest {
    @Test fun callSignaturesRequirePinnedMutualTrustAndCorrectRecipient() {
        val a = testCrypto(); val b = testCrypto(); val c = testCrypto()
        val ab = ContactBook(a, null) {}; val bb = ContactBook(b, null) {}
        assertThrows(Exception::class.java) { ab.signCall(mapOf("to" to b.id)) }
        ab.pending(b.key, "Bob", "a".repeat(64)); ab.approve(b.id, "a".repeat(64)); ab.verified(b.id, "a".repeat(64))
        bb.pending(a.key, "Alice", "b".repeat(64)); bb.approve(a.id, "b".repeat(64)); bb.verified(a.id, "b".repeat(64))
        val token = ab.signCall(mapOf("to" to b.id, "kind" to "invite", "from" to c.id))
        assertEquals(a.id, bb.verifyCall(token)["from"])
        assertThrows(Exception::class.java) { bb.verifyCall(c.sign(mapOf("from" to a.id, "to" to b.id, "scope" to "ogm-call-v1"))) }
        assertThrows(Exception::class.java) { bb.verifyCall(a.sign(mapOf("from" to a.id, "to" to c.id, "scope" to "ogm-call-v1"))) }
        bb.block(a.id)
        assertThrows(Exception::class.java) { bb.verifyCall(token) }
    }
    @Test fun signaturesRejectSubstitutionTamperingAndAlgorithms() {
        val a = testCrypto(); val b = testCrypto()
        val signed = a.sign(mapOf("message" to "test"))
        assertEquals("test", ContactCrypto.verify(signed, a.key)["message"])
        assertThrows(Exception::class.java) { ContactCrypto.verify(signed, b.key) }
        val parts = signed.split('.').toMutableList()
        parts[1] = ContactCrypto.encode("{\"message\":\"changed\"}".toByteArray())
        assertThrows(Exception::class.java) { ContactCrypto.verify(parts.joinToString("."), a.key) }
        parts[0] = ContactCrypto.encode("{\"alg\":\"none\",\"typ\":\"ogm-contact-v1\"}".toByteArray())
        assertThrows(Exception::class.java) { ContactCrypto.verify(parts.joinToString("."), a.key) }
    }
    @Test fun pendingAndApprovalSurviveRestartButRequireMatchingTranscript() {
        val a = testCrypto(); val b = testCrypto(); var saved: String? = null
        var book = ContactBook(a, null) { saved = it }
        val transcript = "a".repeat(64)
        book.pending(b.key, "Bob", transcript)
        assertThrows(Exception::class.java) { book.verified(b.id, transcript) }
        book.approve(b.id, transcript)
        book = ContactBook(a, saved) { saved = it }
        assertThrows(Exception::class.java) { book.verified(b.id, "b".repeat(64)) }
        book.verified(b.id, transcript)
        book.pending(b.key, "Impostor name", "c".repeat(64))
        assertEquals("Bob", book.entry(b.id)!!["name"])
        assertEquals("verified", book.entry(b.id)!!["state"])
        assertThrows(Exception::class.java) { ContactBook(testCrypto(), saved) {} }
    }
    @Test fun blockingAndDeletingDoNotSilentlyRestoreTrust() {
        val a = testCrypto(); val b = testCrypto(); val book = ContactBook(a, null) {}
        book.pending(b.key, "Bob", "a".repeat(64)); book.block(b.id)
        assertThrows(Exception::class.java) { book.pending(b.key, "Bob", "b".repeat(64)) }
        book.delete(b.id)
        book.pending(b.key, "Bob", "b".repeat(64))
        assertEquals("pending", book.entry(b.id)!!["state"])
        assertThrows(Exception::class.java) { book.pending(a.key, "Self", "a".repeat(64)) }
    }
    @Test fun failedDurableWriteDoesNotPublishTrust() {
        val a = testCrypto(); val b = testCrypto(); var fail = false
        val book = ContactBook(a, null) { if (fail) error("disk full") }
        book.pending(b.key, "Bob", "a".repeat(64)); book.approve(b.id, "a".repeat(64))
        fail = true
        assertThrows(Exception::class.java) { book.verified(b.id, "a".repeat(64)) }
        assertEquals("pending", book.entry(b.id)!!["state"])
    }
}
