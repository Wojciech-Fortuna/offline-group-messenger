package com.offlinegroupmessenger.offline_connectivity

import android.app.KeyguardManager
import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import com.nimbusds.jose.util.JSONObjectUtils
import java.util.concurrent.Executors

internal object NfcContactSession {
    @Volatile var host: ContactPairing? = null
    @Volatile var expires: Long = 0
    fun active(): ContactPairing? = host?.takeIf { SystemClock.elapsedRealtime() < expires }
}

class NfcContactService : HostApduService() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var generation = 0
    private val protocol = ContactApdu { bytes ->
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        check(power.isInteractive && !keyguard.isKeyguardLocked)
        val pairing = requireNotNull(NfcContactSession.active())
        val request = JSONObjectUtils.parse(bytes.toString(Charsets.UTF_8))
        JSONObjectUtils.toJSONString(pairing.handle(request)).toByteArray(Charsets.UTF_8)
    }
    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray? {
        val token = generation
        worker.execute {
            val response = if (NfcContactSession.active() == null) byteArrayOf(0x69, 0x85.toByte())
                else protocol.respond(commandApdu ?: byteArrayOf())
            if (generation == token) sendResponseApdu(response)
        }
        return null
    }
    override fun onDeactivated(reason: Int) { generation++; worker.execute { protocol.reset() } }
    override fun onDestroy() { generation++; worker.shutdown(); super.onDestroy() }
}
