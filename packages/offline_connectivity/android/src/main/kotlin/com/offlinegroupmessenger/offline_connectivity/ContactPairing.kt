package com.offlinegroupmessenger.offline_connectivity

import com.nimbusds.jose.util.JSONObjectUtils

/** One bounded enrollment. Trust needs both possession proofs and both user approvals. */
internal class ContactPairing(private val book: ContactBook, name: String, val reader: Boolean) {
    private val local = mapOf("key" to book.crypto.key, "name" to ContactBook.name(name), "nonce" to ContactCrypto.nonce())
    private var remote: Map<String, String>? = null
    private var transcript: String? = null
    private var proven = false
    private var approved = false
    private var receivedApproval = false
    private var receipt: String? = null
    private var stopped = false
    private var complete = false
    private var problem: String? = null
    @Synchronized fun status(): Map<String, Any?> = mapOf(
        "state" to when { complete -> "verified"; stopped -> "stopped"; proven -> "confirm"; else -> "waiting" },
        "name" to remote?.get("name"), "code" to transcript?.take(32)?.chunked(4)?.joinToString(" "),
        "approved" to approved, "error" to problem)
    @Synchronized fun stop(reason: String? = null) { stopped = true; problem = reason }
    private fun active() { check(!stopped) { "Pairing stopped" } }
    private fun setRemote(raw: Any?) {
        require(raw is Map<*, *> && raw.keys == setOf("key", "name", "nonce"))
        val peer = raw.map { (key, value) -> (key as String) to (value as String) }.toMap()
        require(ContactCrypto.decode(peer.getValue("nonce")).size == 32)
        require(ContactBook.name(peer.getValue("name")) == peer["name"])
        val id = ContactCrypto.fingerprint(peer.getValue("key"))
        require(id != book.crypto.id && book.entry(id)?.get("state") != "blocked")
        require(remote == null || remote == peer) { "Peer changed during pairing" }
        remote = peer
        // Fixed array order avoids a JSON object canonicalization dependency.
        val r = if (reader) local else peer
        val h = if (reader) peer else local
        val fields = listOf("ogm-nfc-contact-v1", r.getValue("key"), r.getValue("name"), r.getValue("nonce"),
            h.getValue("key"), h.getValue("name"), h.getValue("nonce"))
        transcript = ContactCrypto.hash(JSONObjectUtils.toJSONString(mapOf("fields" to fields)).toByteArray(Charsets.UTF_8))
    }
    private fun sign(kind: String): String = book.crypto.sign(mapOf(
        "kind" to kind, "transcript" to requireNotNull(transcript), "role" to if (reader) "reader" else "host"))
    private fun verify(token: Any?, kind: String) {
        val payload = ContactCrypto.verify(token as String, remote!!.getValue("key"))
        require(payload == mapOf("kind" to kind, "transcript" to transcript, "role" to if (reader) "host" else "reader"))
    }
    private fun markProven() {
        book.pending(remote!!.getValue("key"), remote!!.getValue("name"), transcript!!)
        proven = true
    }
    @Synchronized fun hello(): Map<String, Any?> { active(); check(reader); return mapOf("type" to "hello", "identity" to local) }
    @Synchronized fun receiveHello(message: Map<String, Any?>): Map<String, Any?> {
        active(); check(!reader); require(message["type"] == "hello")
        setRemote(message["identity"])
        return mapOf("type" to "proof", "identity" to local, "proof" to sign("proof"))
    }
    @Synchronized fun receiveHostProof(message: Map<String, Any?>): Map<String, Any?> {
        active(); check(reader); require(message["type"] == "proof")
        setRemote(message["identity"]); verify(message["proof"], "proof"); markProven()
        return mapOf("type" to "proof", "proof" to sign("proof"))
    }
    @Synchronized fun receiveReaderProof(message: Map<String, Any?>): Map<String, Any?> {
        active(); check(!reader && remote != null); require(message["type"] == "proof")
        verify(message["proof"], "proof"); if (!proven) markProven()
        return mapOf("type" to "ready")
    }
    @Synchronized fun approve() {
        active(); check(proven)
        book.approve(ContactCrypto.fingerprint(remote!!.getValue("key")), transcript!!)
        receipt = sign("confirm"); approved = true
        finish()
    }
    private fun finish() {
        if (approved && receivedApproval) {
            book.verified(ContactCrypto.fingerprint(remote!!.getValue("key")), transcript!!)
            complete = true
        }
    }
    @Synchronized fun poll(): Map<String, Any?> { active(); check(proven); return mapOf("type" to "confirm", "receipt" to receipt) }
    @Synchronized fun receiveConfirmation(message: Map<String, Any?>): Map<String, Any?> {
        active(); check(proven); require(message["type"] == "confirm")
        message["receipt"]?.let { verify(it, "confirm"); receivedApproval = true }
        finish()
        return poll()
    }
    @Synchronized fun handle(message: Map<String, Any?>): Map<String, Any?> = when (message["type"]) {
        "hello" -> receiveHello(message)
        "proof" -> receiveReaderProof(message)
        "confirm" -> receiveConfirmation(message)
        else -> error("Unsupported contact exchange")
    }
}
