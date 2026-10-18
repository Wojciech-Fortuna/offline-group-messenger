package com.offlinegroupmessenger.offline_connectivity

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Foreground, explicitly enabled sharing/reading. No Android Beam or persisted secrets. */
internal class NfcInvitationController(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val reading = AtomicBoolean(false)
    private val adapter get() = NfcAdapter.getDefaultAdapter(context)
    private var activity: Activity? = null
    private var resumed = false
    @Volatile private var generation = 0
    private var scan: MethodChannel.Result? = null
    private var expiry: Runnable? = null
    @Volatile private var tagConnection: IsoDep? = null
    var sharing = false
        private set

    val canShare get() = context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
    val canRead get() = context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC)

    fun attach(value: Activity) { activity = value; resumed = value.hasWindowFocus() }
    fun resume() { resumed = true }
    fun pause() { resumed = false; cancel() }
    fun detach() { pause(); activity = null }

    private fun ready(result: MethodChannel.Result, host: Boolean): Activity? {
        val current = activity
        when {
            current == null || !resumed -> result.error("nfc_inactive", "Keep the app open and both phones unlocked.", null)
            !canRead || (host && !canShare) -> result.error("nfc_unsupported", "This phone does not support this NFC mode. Use QR instead.", null)
            adapter?.isEnabled != true -> result.error("nfc_disabled", "Enable NFC in system settings, return here and retry.", null)
            else -> return current
        }
        return null
    }

    fun share(result: MethodChannel.Result, invitation: (MethodChannel.Result) -> Unit) {
        val current = ready(result, true) ?: return
        cancel()
        val token = generation
        invitation(object : MethodChannel.Result {
            override fun success(value: Any?) {
                if (token != generation || !resumed || current !== activity) {
                    result.error("nfc_cancelled", "NFC sharing was cancelled.", null)
                    return
                }
                if (ready(result, true) == null) return
                try {
                    val bytes = JSONObject(value as Map<*, *>).toString().toByteArray(Charsets.UTF_8)
                    require(bytes.size in 1..InvitationApdu.MAX_BYTES)
                    val preferred = CardEmulation.getInstance(adapter!!).setPreferredService(
                        current, ComponentName(context, NfcInvitationService::class.java))
                    check(preferred)
                    NfcInvitationStore.enable(bytes)
                    sharing = true
                    expiry = Runnable { stopSharing() }.also { handler.postDelayed(it, 60_000) }
                    result.success(null)
                } catch (_: RuntimeException) {
                    stopSharing()
                    result.error("nfc_unavailable", "Could not enable NFC sharing. Use QR or retry.", null)
                }
            }
            override fun error(code: String, message: String?, details: Any?) = result.error(code, message, null)
            override fun notImplemented() = result.notImplemented()
        })
    }

    fun read(result: MethodChannel.Result) {
        val current = ready(result, false) ?: return
        cancel()
        scan = result
        val token = generation
        try {
            adapter!!.enableReaderMode(current, { tag ->
                if (token != generation) return@enableReaderMode
                if (!reading.compareAndSet(false, true)) return@enableReaderMode
                try { executor.execute {
                    var connection: IsoDep? = null
                    try {
                        if (token != generation) return@execute
                        connection = IsoDep.get(tag) ?: throw IllegalArgumentException()
                        tagConnection = connection
                        check(token == generation)
                        connection.connect()
                        connection.timeout = 2_000
                        val bytes = InvitationApdu.read { command ->
                            check(token == generation)
                            connection.transceive(command)
                        }
                        val raw = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                            .decode(ByteBuffer.wrap(bytes)).toString()
                        handler.post { if (token == generation) completeRead(raw) }
                    } catch (_: Exception) {
                        handler.post {
                            if (token == generation) finishReadError("nfc_read_failed",
                                "Could not read this invitation. Keep the phones together, enable sharing on the host and retry.")
                        }
                    } finally {
                        try { connection?.close() } catch (_: Exception) { }
                        if (tagConnection === connection) tagConnection = null
                        reading.set(false)
                    }
                } } catch (_: java.util.concurrent.RejectedExecutionException) { reading.set(false) }
            }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
            expiry = Runnable {
                if (token == generation) finishReadError("nfc_timeout", "No invitation received. Retry or use QR.")
            }.also { handler.postDelayed(it, 30_000) }
        } catch (_: RuntimeException) {
            finishReadError("nfc_unavailable", "Could not start NFC reader. Retry or use QR.")
        }
    }

    private fun completeRead(raw: String) {
        val result = scan
        scan = null
        cancel()
        result?.success(raw)
    }

    private fun finishReadError(code: String, message: String) {
        val result = scan
        scan = null
        cancel()
        result?.error(code, message, null)
    }

    fun stopSharing() {
        NfcInvitationStore.clear()
        if (sharing) {
            sharing = false
            expiry?.let(handler::removeCallbacks)
            expiry = null
            try { activity?.let { CardEmulation.getInstance(adapter!!).unsetPreferredService(it) } }
            catch (_: RuntimeException) { }
        }
    }

    fun cancel() {
        generation++
        stopSharing()
        expiry?.let(handler::removeCallbacks)
        expiry = null
        try { activity?.let { adapter?.disableReaderMode(it) } } catch (_: RuntimeException) { }
        try { tagConnection?.close() } catch (_: Exception) { }
        tagConnection = null
        val result = scan
        scan = null
        result?.error("nfc_cancelled", "NFC session stopped. Retry when ready.", null)
    }

    fun dispose() { detach(); executor.shutdownNow() }
}
