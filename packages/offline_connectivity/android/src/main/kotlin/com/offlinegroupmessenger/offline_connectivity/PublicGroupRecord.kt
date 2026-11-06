package com.offlinegroupmessenger.offline_connectivity

/** Only these public service records belong in the app's discovery list. */
internal object PublicGroupRecord {
    const val INSTANCE = "OfflineMessenger"
    const val TYPE = "_ogm._tcp"
    fun accepts(domain: String, record: Map<String, String>): Boolean =
        domain.trimEnd('.').equals("$INSTANCE.$TYPE.local", ignoreCase = true) &&
            record["app"] == "offline-group-messenger" && record["v"] == "3" && record["mode"] == "public"
    fun fields(): Map<String, String> = mapOf(
        "app" to "offline-group-messenger", "v" to "3", "mode" to "public"
    )
}
