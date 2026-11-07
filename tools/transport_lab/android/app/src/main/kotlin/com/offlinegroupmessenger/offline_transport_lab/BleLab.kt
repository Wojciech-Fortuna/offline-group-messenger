package com.offlinegroupmessenger.offline_transport_lab

import android.app.Activity
import android.bluetooth.*
import android.bluetooth.le.*
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.security.SecureRandom
import java.util.UUID

/** Foreground-only transport probe. Carries random test bytes, never contacts. */
@Suppress("DEPRECATION", "MissingPermission")
internal class BleLab(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val manager get() = activity.getSystemService(BluetoothManager::class.java)
    private val adapter get() = manager?.adapter
    private var generation = 0
    private var state = "Stopped"
    private var successes = 0
    private var elapsedMs: Long? = null
    private var scanCallback: ScanCallback? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var server: BluetoothGattServer? = null
    private var client: BluetoothGatt? = null
    private val peers = linkedMapOf<String, BluetoothDevice>()
    private val echoes = linkedMapOf<String, ByteArray>()

    fun snapshot(): Map<String, Any?> = mapOf(
        "state" to state, "successes" to successes, "elapsedMs" to elapsedMs,
        "peers" to peers.keys.toList(),
        "bleSupported" to activity.packageManager.hasSystemFeature("android.hardware.bluetooth_le")
    )

    fun stop(message: String = "Stopped") {
        generation++
        handler.removeCallbacksAndMessages(null)
        try { scanCallback?.let { adapter?.bluetoothLeScanner?.stopScan(it) } } catch (_: Exception) {}
        try { advertiseCallback?.let { adapter?.bluetoothLeAdvertiser?.stopAdvertising(it) } } catch (_: Exception) {}
        try { client?.disconnect(); client?.close() } catch (_: Exception) {}
        try { server?.close() } catch (_: Exception) {}
        client = null; server = null; scanCallback = null; advertiseCallback = null
        peers.clear(); echoes.clear(); state = message
    }

    private fun ready() { check(adapter?.isEnabled == true) { "Enable Bluetooth first" } }
    private fun expires(token: Int, milliseconds: Long) {
        handler.postDelayed({ if (token == generation) stop("Timed out; retry when both labs are open") }, milliseconds)
    }

    fun advertise() {
        stop(); ready()
        val advertiser = requireNotNull(adapter?.bluetoothLeAdvertiser) { "BLE advertising unavailable" }
        val token = generation
        state = "Starting GATT server"
        val callback = object : BluetoothGattServerCallback() {
            override fun onServiceAdded(status: Int, service: BluetoothGattService) { handler.post {
                if (token != generation) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) { stop("GATT service failed: $status"); return@post }
                val adv = object : AdvertiseCallback() {
                    override fun onStartSuccess(settings: AdvertiseSettings) { handler.post {
                        if (token == generation) state = "Advertising lab probe (60 seconds)"
                    } }
                    override fun onStartFailure(code: Int) { handler.post {
                        if (token == generation) stop("Advertising failed: $code")
                    } }
                }
                advertiseCallback = adv
                try {
                    advertiser.startAdvertising(AdvertiseSettings.Builder()
                        .setConnectable(true).setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).build(),
                        AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).build(), adv)
                } catch (_: Exception) { stop("Advertising unavailable or permission revoked") }
            } }
            override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int,
                characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean,
                responseNeeded: Boolean, offset: Int, value: ByteArray) { handler.post {
                if (token != generation) return@post
                val valid = characteristic.uuid == ECHO && !preparedWrite && offset == 0 &&
                    value.size == 16 && (echoes.containsKey(device.address) || echoes.size < 8)
                if (valid) echoes[device.address] = value.copyOf()
                try { if (responseNeeded) server?.sendResponse(device, requestId,
                    if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
                } catch (_: Exception) { stop("GATT response failed") }
            } }
            override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int,
                offset: Int, characteristic: BluetoothGattCharacteristic) { handler.post {
                if (token != generation) return@post
                val value = if (offset == 0 && characteristic.uuid == ECHO) echoes.remove(device.address) else null
                try {
                    server?.sendResponse(device, requestId, if (value != null) BluetoothGatt.GATT_SUCCESS
                        else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, value)
                    if (value != null) { successes++; state = "Probe echoed; still advertising" }
                } catch (_: Exception) { stop("GATT response failed") }
            } }
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) { handler.post {
                if (token == generation && newState == BluetoothProfile.STATE_DISCONNECTED) echoes.remove(device.address)
            } }
        }
        server = manager?.openGattServer(activity, callback)
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(BluetoothGattCharacteristic(ECHO,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE))
        check(server?.addService(service) == true) { "Could not register GATT service" }
        expires(token, 60_000)
    }

    fun scan() {
        stop(); ready()
        val token = generation
        val scanner = requireNotNull(adapter?.bluetoothLeScanner)
        state = "Scanning for lab probes (30 seconds)"
        val callback = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) { handler.post {
                if (token != generation || peers.values.any { it == result.device } || peers.size >= 16) return@post
                peers["Probe ${peers.size + 1}"] = result.device
            } }
            override fun onScanFailed(code: Int) { handler.post { if (token == generation) stop("Scan failed: $code") } }
        }
        scanCallback = callback
        scanner.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()),
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
        expires(token, 30_000)
    }

    fun probe(id: String) {
        val device = requireNotNull(peers[id]) { "Scan again and choose a current probe" }
        stop(); ready()
        val token = generation
        val challenge = ByteArray(16).also(SecureRandom()::nextBytes)
        val started = android.os.SystemClock.elapsedRealtime()
        var stage = 0
        state = "Connecting to GATT probe"
        fun failed(message: String) { if (token == generation) stop(message) }
        client = device.connectGatt(activity, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) { handler.post {
                if (token != generation) return@post
                if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                    failed("GATT disconnected/status $status"); return@post
                }
                if (newState == BluetoothProfile.STATE_CONNECTED && stage == 0) {
                    stage = 1
                    try { if (!gatt.discoverServices()) failed("Cannot discover GATT services") }
                    catch (_: Exception) { failed("GATT discovery failed") }
                }
            } }
            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) { handler.post {
                if (token != generation || stage != 1) return@post
                val characteristic = gatt.getService(SERVICE)?.getCharacteristic(ECHO)
                if (status != BluetoothGatt.GATT_SUCCESS || characteristic == null) { failed("Lab service missing"); return@post }
                stage = 2
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                characteristic.value = challenge
                try { if (!gatt.writeCharacteristic(characteristic)) failed("Cannot write probe") }
                catch (_: Exception) { failed("Probe write failed") }
            } }
            override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) { handler.post {
                if (token != generation || stage != 2 || characteristic.uuid != ECHO) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) { failed("Probe rejected: $status"); return@post }
                stage = 3
                try { if (!gatt.readCharacteristic(characteristic)) failed("Cannot read echo") }
                catch (_: Exception) { failed("Echo read failed") }
            } }
            override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                val received = characteristic.value?.copyOf()
                handler.post {
                    if (token != generation || stage != 3 || characteristic.uuid != ECHO) return@post
                    if (status == BluetoothGatt.GATT_SUCCESS && received?.contentEquals(challenge) == true) {
                        successes++; elapsedMs = android.os.SystemClock.elapsedRealtime() - started
                        stop("Bidirectional GATT probe passed")
                    } else failed("Echo mismatch/status $status")
                }
            }
        }, BluetoothDevice.TRANSPORT_LE)
        check(client != null) { "Cannot start GATT connection" }
        expires(token, 15_000)
    }

    companion object {
        private val SERVICE = UUID.fromString("9e2c7a60-32cb-48c9-a31f-a9cc07105001")
        private val ECHO = UUID.fromString("9e2c7a60-32cb-48c9-a31f-a9cc07105002")
    }
}
