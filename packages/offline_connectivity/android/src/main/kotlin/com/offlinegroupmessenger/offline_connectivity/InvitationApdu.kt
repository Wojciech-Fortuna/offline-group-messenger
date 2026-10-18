package com.offlinegroupmessenger.offline_connectivity

/** Small proprietary ISO-DEP protocol, independent of Android for unit testing. */
internal class InvitationApdu(private val payload: () -> ByteArray?) {
    private var selected: ByteArray? = null

    fun reset() { selected = null }

    fun respond(command: ByteArray): ByteArray {
        val current = payload()
        if (current == null || current.isEmpty() || current.size > MAX_BYTES) {
            reset()
            return status(0x6985)
        }
        if (command.contentEquals(SELECT)) {
            selected = current
            return byteArrayOf((current.size shr 8).toByte(), current.size.toByte()) + status(0x9000)
        }
        if (selected !== current) return status(0x6985)
        if (command.size != 5 || command[0] != 0.toByte() || command[1] != 0xB0.toByte()) {
            return status(0x6D00)
        }
        val offset = ((command[2].toInt() and 255) shl 8) or (command[3].toInt() and 255)
        val length = command[4].toInt() and 255
        if (length !in 1..CHUNK || offset !in current.indices || offset + length > current.size) {
            return status(0x6B00)
        }
        return current.copyOfRange(offset, offset + length) + status(0x9000)
    }

    companion object {
        const val MAX_BYTES = 2048
        const val CHUNK = 200
        // Prototype application ID; keep in sync with res/xml/nfc_invitation_service.xml.
        val SELECT = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, 0x09,
            0xF0.toByte(), 0x4F, 0x46, 0x46, 0x4C, 0x49, 0x4E, 0x45, 0x01)

        private fun status(value: Int) = byteArrayOf((value shr 8).toByte(), value.toByte())

        fun read(transceive: (ByteArray) -> ByteArray): ByteArray {
            fun exchange(command: ByteArray): ByteArray {
                val reply = transceive(command)
                require(reply.size >= 2 && reply[reply.size - 2] == 0x90.toByte() && reply.last() == 0.toByte())
                return reply.copyOf(reply.size - 2)
            }
            val header = exchange(SELECT)
            require(header.size == 2)
            val size = ((header[0].toInt() and 255) shl 8) or (header[1].toInt() and 255)
            require(size in 1..MAX_BYTES)
            val data = ByteArray(size)
            var offset = 0
            while (offset < size) {
                val length = minOf(CHUNK, size - offset)
                val part = exchange(byteArrayOf(0, 0xB0.toByte(), (offset shr 8).toByte(), offset.toByte(), length.toByte()))
                require(part.size == length)
                part.copyInto(data, offset)
                offset += length
            }
            return data
        }
    }
}
