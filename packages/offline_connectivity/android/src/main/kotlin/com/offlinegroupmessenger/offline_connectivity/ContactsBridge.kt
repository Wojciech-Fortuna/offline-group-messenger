package com.offlinegroupmessenger.offline_connectivity

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class ContactsBridge(private val context: Context, messenger: BinaryMessenger, private val stopInvitation: () -> Unit) {
    val nfc = NfcContactsController(context)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "com.offlinegroupmessenger/contacts")
    @Volatile private var closed = false
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "pairingStart") {
                stopInvitation()
                nfc.start(call.argument<String>("name") ?: "", call.argument<Boolean>("reader") == true, result)
                return@setMethodCallHandler
            }
            if (call.method == "pairingStop") { nfc.cancel(); result.success(null); return@setMethodCallHandler }
            if (call.method == "pairingStatus") { result.success(nfc.pairing?.status()); return@setMethodCallHandler }
            if (call.method in listOf("reset", "block", "delete")) nfc.cancel()
            worker.execute {
                try {
                    check(!closed)
                    val value: Any? = when (call.method) {
                        "snapshot" -> ContactVault.open(context).snapshot()
                        "pairingApprove" -> requireNotNull(nfc.pairing).approve()
                        "rename" -> ContactVault.open(context).rename(
                            requireNotNull(call.argument<String>("id")), requireNotNull(call.argument<String>("name")))
                        "block" -> ContactVault.open(context).block(requireNotNull(call.argument<String>("id")))
                        "delete" -> ContactVault.open(context).delete(requireNotNull(call.argument<String>("id")))
                        "reset" -> ContactVault.reset(context)
                        else -> { main.post { result.notImplemented() }; return@execute }
                    }
                    main.post { result.success(if (value is Unit) null else value) }
                } catch (_: Exception) {
                    main.post { result.error("contacts_unavailable",
                        "Contacts could not be accessed. Retry; if keys or storage were lost, reset contacts and pair again.", null) }
                }
            }
        }
    }
    fun close() { closed = true; nfc.close(); channel.setMethodCallHandler(null); worker.shutdown() }
}
