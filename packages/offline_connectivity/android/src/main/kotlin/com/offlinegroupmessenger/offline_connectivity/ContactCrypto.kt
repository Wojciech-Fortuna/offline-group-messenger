package com.offlinegroupmessenger.offline_connectivity

import com.nimbusds.jose.*
import com.nimbusds.jose.crypto.ECDSASigner
import com.nimbusds.jose.crypto.ECDSAVerifier
import com.nimbusds.jose.jwk.Curve
import com.nimbusds.jose.util.JSONObjectUtils
import java.security.*
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec
import java.math.BigInteger
import com.nimbusds.jose.util.Base64URL

/** Standard compact JWS; crypto primitives and signature encoding belong to Nimbus/JCA. */
internal class ContactCrypto(val publicKey: ECPublicKey, private val privateKey: PrivateKey) {
    val key: String get() = encode(publicKey.encoded)
    val id: String get() = fingerprint(key)
    fun sign(payload: Map<String, Any?>): String {
        val jws = JWSObject(JWSHeader.Builder(JWSAlgorithm.ES256)
            .type(JOSEObjectType(TYPE)).build(), Payload(JSONObjectUtils.toJSONString(payload)))
        jws.sign(ECDSASigner(privateKey, Curve.P_256))
        return jws.serialize()
    }
    companion object {
        const val TYPE = "ogm-contact-v1"
        fun encode(bytes: ByteArray): String = Base64URL.encode(bytes).toString()
        fun decode(text: String): ByteArray {
            require(text.length in 1..16384 && text.matches(Regex("[A-Za-z0-9_-]+")))
            return Base64URL(text).decode().also { require(encode(it) == text) }
        }
        fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun fingerprint(key: String): String = hash(public(key).encoded)
        fun public(key: String): ECPublicKey {
            require(key.length <= 256)
            val value = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(decode(key))) as ECPublicKey
            require(value.params.order == BigInteger("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551", 16))
            return value
        }
        fun nonce(): String = encode(ByteArray(32).also { SecureRandom().nextBytes(it) })
        fun verify(token: String, key: String): Map<String, Any?> {
            require(token.length in 1..16384)
            val jws = JWSObject.parse(token)
            require(jws.header.algorithm == JWSAlgorithm.ES256 && jws.header.type?.type == TYPE)
            require(jws.header.toJSONObject().keys == setOf("alg", "typ"))
            require(jws.verify(ECDSAVerifier(public(key))))
            return JSONObjectUtils.parse(jws.payload.toString())
        }
    }
}
