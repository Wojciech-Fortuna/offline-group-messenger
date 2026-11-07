package com.offlinegroupmessenger.offline_connectivity

import java.security.SecureRandom

/** Ephemeral local group credentials. Do not log or persist this object/fields. */
internal class OfflineGroupCredentials private constructor(val networkName: String, val passphrase: String) {
    companion object {
        fun create(): OfflineGroupCredentials {
            val random = SecureRandom()
            fun hex(count: Int): String = ByteArray(count).also(random::nextBytes)
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
            return OfflineGroupCredentials("DIRECT-${hex(1)}-OGM-${hex(4)}", hex(16))
        }
    }
}
