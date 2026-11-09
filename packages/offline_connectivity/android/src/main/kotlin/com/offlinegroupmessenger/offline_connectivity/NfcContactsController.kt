package com.offlinegroupmessenger.offline_connectivity

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.nimbusds.jose.util.JSONObjectUtils
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class NfcContactsController(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val reading = AtomicBoolean(false)
    private var activity: Activity? = null
    private var resumed = false
    @Volatile private var generation = 0
    @Volatile private var connection: IsoDep? = null
    @Volatile var pairing: ContactPairing? = null
        private set
    private var expiry: Runnable? = null
    private val adapter get() = NfcAdapter.getDefaultAdapter(context)
    fun attach(value: Activity) { activity = value; resumed = value.hasWindowFocus() }
    fun resume() { resumed = true }
    fun pause() { resumed = false; cancel() }
    fun detach() { pause(); activity = null }
    fun start(name: String, reader: Boolean, result: MethodChannel.Result) {
        cancel()
        pairing = null
        val current = activity
        if (current == null || !resumed || adapter?.isEnabled != true) {
            result.error("nfc_unavailable", "Enable NFC and keep both apps open and phones unlocked.", null); return
        }
        val token = generation
        worker.execute {
            try {
                val created = ContactPairing(ContactVault.open(context), name, reader)
                main.post {
                    if (token != generation || !resumed) { result.error("cancelled", "Pairing cancelled", null); return@post }
                    try {
                        pairing = created
                        val deadline = SystemClock.elapsedRealtime() + 60_000
                        if (reader) {
                            adapter!!.enableReaderMode(current, { tag ->
                                if (generation != token || !reading.compareAndSet(false, true)) return@enableReaderMode
                                worker.execute {
                                    var link: IsoDep? = null
                                    try {
                                        check(generation == token)
                                        link = requireNotNull(IsoDep.get(tag)); connection = link
                                        link.connect(); link.timeout = 3000
                                        fun transceive(command: ByteArray): ByteArray {
                                            check(generation == token && SystemClock.elapsedRealtime() < deadline)
                                            return link.transceive(command)
                                        }
                                        val selected = transceive(ContactApdu.SELECT)
                                        require(selected.contentEquals(byteArrayOf(0x90.toByte(), 0)))
                                        fun exchange(message: Map<String, Any?>): Map<String, Any?> = JSONObjectUtils.parse(
                                            ContactApdu.request(JSONObjectUtils.toJSONString(message).toByteArray(Charsets.UTF_8), ::transceive)
                                                .toString(Charsets.UTF_8))
                                        val proof = created.receiveHostProof(exchange(created.hello()))
                                        require(exchange(proof)["type"] == "ready")
                                        while (generation == token && SystemClock.elapsedRealtime() < deadline) {
                                            created.receiveConfirmation(exchange(created.poll()))
                                            if (created.status()["state"] == "verified") break
                                            Thread.sleep(300)
                                        }
                                    } catch (_: Exception) {
                                        if (generation == token) created.stop("Tap interrupted or verification failed. Start again on both phones.")
                                    } finally {
                                        try { link?.close() } catch (_: Exception) {}
                                        if (connection === link) connection = null
                                        reading.set(false)
                                    }
                                }
                            }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
                        } else {
                            check(CardEmulation.getInstance(adapter!!).setPreferredService(current,
                                ComponentName(context, NfcContactService::class.java)))
                            NfcContactSession.expires = deadline
                            NfcContactSession.host = created
                        }
                        expiry = Runnable { if (generation == token) cancel("Pairing expired. Start again on both phones.") }
                            .also { main.postDelayed(it, 60_000) }
                        result.success(null)
                    } catch (_: Exception) { cancel(); result.error("nfc_unavailable", "This NFC mode is unavailable. Try reversing the phone roles.", null) }
                }
            } catch (_: Exception) {
                main.post { result.error("contacts_unavailable", "Cannot open contact identity. Check the name or reset lost contact storage.", null) }
            }
        }
    }
    fun cancel(reason: String? = null) {
        generation++
        expiry?.let(main::removeCallbacks); expiry = null
        NfcContactSession.host = null; NfcContactSession.expires = 0
        pairing?.stop(reason)
        try { connection?.close() } catch (_: Exception) {}; connection = null
        try { activity?.let { adapter?.disableReaderMode(it) } } catch (_: Exception) {}
        try { activity?.let { adapter?.let { a -> CardEmulation.getInstance(a).unsetPreferredService(it) } } } catch (_: Exception) {}
    }
    fun close() { detach(); worker.shutdownNow() }
}
