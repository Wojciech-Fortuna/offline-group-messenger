package com.offlinegroupmessenger.offline_connectivity

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import com.nimbusds.jose.util.JSONObjectUtils
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** One process-wide book is shared by the Flutter bridge and foreground HCE service. */
internal object ContactVault {
    private const val SIGN = "ogm.contact.sign.v1"
    private const val STORE = "ogm.contact.store.v1"
    private val aad = "ogm-contact-store-v1".toByteArray()
    private var cached: ContactBook? = null
    @Synchronized fun open(context: Context): ContactBook {
        cached?.let { return it }
        val file = AtomicFile(File(context.noBackupFilesDir, "contacts-v1.enc"))
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        // Never replace missing keys under an existing encrypted file.
        if (!keys.containsAlias(SIGN) || !keys.containsAlias(STORE)) {
            check(!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) {
                "Contact keys unavailable. Reset contacts and pair again."
            }
            if (!keys.containsAlias(SIGN)) KeyPairGenerator.getInstance("EC", "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(SIGN, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256).build())
            }.generateKeyPair()
            if (!keys.containsAlias(STORE)) KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(STORE, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
        }
        val crypto = ContactCrypto(keys.getCertificate(SIGN).publicKey as ECPublicKey,
            keys.getKey(SIGN, null) as PrivateKey)
        val secret = keys.getKey(STORE, null) as SecretKey
        val saved = try {
            val bytes = file.openRead().use { stream ->
                val data = stream.readBytes()
                require(data.size in 29..1048576)
                data
            }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.updateAAD(aad)
            cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
        } catch (e: java.io.FileNotFoundException) {
            if (file.baseFile.exists()) throw e
            null
        }
        fun write(raw: String) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secret)
            cipher.updateAAD(aad)
            require(cipher.iv.size == 12)
            val bytes = cipher.iv + cipher.doFinal(raw.toByteArray(Charsets.UTF_8))
            val stream = file.startWrite()
            try { stream.write(bytes); file.finishWrite(stream) }
            catch (e: Exception) { file.failWrite(stream); throw e }
        }
        if (saved == null) write(JSONObjectUtils.toJSONString(mapOf("v" to 1, "identity" to crypto.key, "contacts" to emptyList<Any>())))
        return ContactBook(crypto, saved, ::write).also { cached = it }
    }
    @Synchronized fun reset(context: Context) {
        cached = null
        AtomicFile(File(context.noBackupFilesDir, "contacts-v1.enc")).delete()
        KeyStore.getInstance("AndroidKeyStore").apply {
            load(null); deleteEntry(SIGN); deleteEntry(STORE)
        }
    }
}
