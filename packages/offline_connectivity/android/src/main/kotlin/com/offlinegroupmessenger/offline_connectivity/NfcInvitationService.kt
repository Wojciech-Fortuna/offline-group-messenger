package com.offlinegroupmessenger.offline_connectivity

import android.app.KeyguardManager
import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock

/** Credentials are process-memory only and unavailable by default. */
internal object NfcInvitationStore {
    private data class Entry(val bytes: ByteArray, val expires: Long)
    @Volatile private var entry: Entry? = null
    fun enable(bytes: ByteArray) { entry = Entry(bytes, SystemClock.elapsedRealtime() + 60_000) }
    fun clear() { entry = null }
    fun payload(): ByteArray? = entry?.takeIf { SystemClock.elapsedRealtime() < it.expires }?.bytes
}

class NfcInvitationService : HostApduService() {
    private val protocol = InvitationApdu {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isInteractive || keyguard.isKeyguardLocked) null else NfcInvitationStore.payload()
    }

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray =
        protocol.respond(commandApdu ?: byteArrayOf())

    override fun onDeactivated(reason: Int) { protocol.reset() }
}
