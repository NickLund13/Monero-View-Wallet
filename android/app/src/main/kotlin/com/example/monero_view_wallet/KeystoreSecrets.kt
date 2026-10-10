package com.example.monero_view_wallet

import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/**
 * The app's secure storage on Android, where the saved wallet's password is
 * kept (lib/android_keystore.dart is the other end).
 *
 * The secrets are kept together in [file], in the app's own folder that
 * Android never backs up, encrypted with AES-GCM under a key the Android
 * Keystore makes and keeps. The key never leaves the Keystore (on most phones
 * its secure hardware): it can't be read out, backed up or moved to another
 * phone, so a copy of the file can't be opened anywhere else.
 *
 * Nothing here logs a name or a secret, and an error is reported by its
 * kind only.
 */
class KeystoreSecrets private constructor(private val file: File) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val KEY = "monero_view_wallet.secrets"

        // Ties the encrypted file to its use here.
        private val AAD = "Monero View Wallet secrets 1".toByteArray(Charsets.UTF_8)
        private const val VERSION: Byte = 1
        private const val IV_SIZE = 12
        private const val TAG_BITS = 128

        fun register(messenger: BinaryMessenger, file: File) {
            MethodChannel(messenger, "monero_view_wallet/keystore")
                .setMethodCallHandler(KeystoreSecrets(file))
        }
    }

    // One call at a time, in the order Dart made them, and off the main
    // thread: the Keystore can take a while to answer.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /**
     * "load": whether the Keystore can keep secrets, and the secrets kept so
     * far. "write" a secret under a name: true once it is kept. "delete" the
     * secret under a name.
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
        val secret = call.argument<String>("secret")
        worker.execute {
            val answer: Any? =
                try {
                    when (call.method) {
                        "load" -> load()
                        "write" -> write(name!!, secret!!)
                        "delete" -> delete(name!!)
                        else -> {
                            main.post { result.notImplemented() }
                            return@execute
                        }
                    }
                } catch (e: Exception) {
                    main.post { result.error("keystore", e.javaClass.simpleName, null) }
                    return@execute
                }
            main.post { result.success(answer) }
        }
    }

    private fun load(): Map<String, Any> {
        val key =
            try {
                key()
            } catch (e: Exception) {
                return mapOf("available" to false, "secrets" to emptyMap<String, String>())
            }
        return mapOf("available" to true, "secrets" to read(key))
    }

    private fun write(name: String, secret: String): Boolean =
        try {
            val key = key()
            save(key, read(key) + (name to secret))
            true
        } catch (e: Exception) {
            false
        }

    private fun delete(name: String): Boolean {
        val key = key()
        val secrets = read(key)
        if (name in secrets) save(key, secrets - name)
        return true
    }

    /** The Keystore's key for [file], made the first time. */
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY, null) as SecretKey?)?.let { return it }
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                    KEY,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    /**
     * The secrets in [file], none if there is no file yet. A file that can't
     * be opened (damaged, or the key is gone) counts as none: the wallet it
     * held a password for then can't be opened either, and setup says so.
     */
    private fun read(key: SecretKey): Map<String, String> {
        if (!file.exists()) return emptyMap()
        return try {
            val bytes = file.readBytes()
            if (bytes.size <= 1 + IV_SIZE || bytes[0] != VERSION) return emptyMap()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(TAG_BITS, bytes, 1, IV_SIZE),
            )
            cipher.updateAAD(AAD)
            val json = JSONObject(
                String(
                    cipher.doFinal(bytes, 1 + IV_SIZE, bytes.size - 1 - IV_SIZE),
                    Charsets.UTF_8,
                )
            )
            json.keys().asSequence().associateWith { json.getString(it) }
        } catch (e: Exception) {
            emptyMap()
        }
    }

    /**
     * Replaces [file] with [secrets], encrypted under [key] with a new random
     * IV that the Keystore picks. Written next to it first, then moved into
     * place, so a crash leaves the old file or the new one, never half of one.
     */
    private fun save(key: SecretKey, secrets: Map<String, String>) {
        if (secrets.isEmpty()) {
            file.delete()
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(AAD)
        val encrypted = cipher.doFinal(JSONObject(secrets).toString().toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        check(iv.size == IV_SIZE)
        file.parentFile?.mkdirs()
        val next = File(file.path + ".new")
        next.writeBytes(byteArrayOf(VERSION) + iv + encrypted)
        if (!next.renameTo(file)) {
            next.delete()
            error("not saved")
        }
    }
}
