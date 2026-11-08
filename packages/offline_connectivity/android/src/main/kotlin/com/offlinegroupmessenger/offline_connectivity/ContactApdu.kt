package com.offlinegroupmessenger.offline_connectivity

/** Bounded request/response ISO-DEP framing, separate from group-invitation AID. */
internal class ContactApdu(private val exchange: (ByteArray) -> ByteArray) {
    private var selected = false
    private var request = ByteArray(0)
    private var written = 0
    private var response = ByteArray(0)
    @Synchronized fun reset() { selected = false; request = ByteArray(0); response = ByteArray(0); written = 0 }
    @Synchronized fun respond(command: ByteArray): ByteArray = try {
        if (command.contentEquals(SELECT)) { reset(); selected = true; ok() }
        else {
            require(selected && command.size >= 5 && command[0] == 0.toByte())
            val offset = ((command[2].toInt() and 255) shl 8) or (command[3].toInt() and 255)
            val length = command[4].toInt() and 255
            when (command[1].toInt() and 255) {
                0x10 -> { require(command.size == 5 && offset in 1..MAX && length == 0)
                    request = ByteArray(offset); written = 0; response = ByteArray(0); ok() }
                0x20 -> { require(length in 1..CHUNK && command.size == 5 + length && offset == written && offset + length <= request.size)
                    command.copyInto(request, offset, 5); written += length; ok() }
                0x30 -> { require(command.size == 5 && offset == 0 && length == 0 && request.isNotEmpty() && written == request.size)
                    response = exchange(request); require(response.size in 1..MAX)
                    request = ByteArray(0); written = 0
                    byteArrayOf((response.size shr 8).toByte(), response.size.toByte()) + ok() }
                0xB0 -> { require(command.size == 5 && length in 1..CHUNK && offset + length <= response.size)
                    response.copyOfRange(offset, offset + length) + ok() }
                else -> error("Unsupported APDU")
            }
        }
    } catch (_: Exception) { reset(); byteArrayOf(0x69, 0x85.toByte()) }
    companion object {
        const val MAX = 8192
        const val CHUNK = 200
        val SELECT = byteArrayOf(0, 0xA4.toByte(), 4, 0, 9, 0xF0.toByte(), 0x4F, 0x46, 0x46, 0x4C, 0x49, 0x4E, 0x45, 2)
        private fun ok() = byteArrayOf(0x90.toByte(), 0)
        fun request(bytes: ByteArray, transceive: (ByteArray) -> ByteArray): ByteArray {
            require(bytes.size in 1..MAX)
            fun send(command: ByteArray): ByteArray {
                val reply = transceive(command)
                require(reply.size in 2..(CHUNK + 2) && reply.takeLast(2).toByteArray().contentEquals(ok()))
                return reply.copyOf(reply.size - 2)
            }
            fun command(code: Int, offset: Int, length: Int) = byteArrayOf(0, code.toByte(), (offset shr 8).toByte(), offset.toByte(), length.toByte())
            send(command(0x10, bytes.size, 0))
            for (offset in bytes.indices step CHUNK) {
                val size = minOf(CHUNK, bytes.size - offset)
                send(command(0x20, offset, size) + bytes.copyOfRange(offset, offset + size))
            }
            val header = send(command(0x30, 0, 0)); require(header.size == 2)
            val size = ((header[0].toInt() and 255) shl 8) or (header[1].toInt() and 255)
            require(size in 1..MAX)
            val output = ByteArray(size)
            for (offset in output.indices step CHUNK) {
                val length = minOf(CHUNK, size - offset)
                val chunk = send(command(0xB0, offset, length)); require(chunk.size == length)
                chunk.copyInto(output, offset)
            }
            return output
        }
    }
}
