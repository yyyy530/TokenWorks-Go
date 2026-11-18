package io.github.yyyy530.tokenworks_go

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val storageQueue = messenger.makeBackgroundTaskQueue()
        registerStore(messenger, storageQueue, "desktop_store", "desktop-session")
        registerStore(messenger, storageQueue, "campus_store", "campus-session")
        MethodChannel(messenger, "tokenworks_go/campus_navigation").setMethodCallHandler { call, result ->
            try {
                val intent = when (call.method) {
                    "openHttps" -> {
                        val uri = Uri.parse(requireNotNull(call.arguments as? String))
                        require(uri.scheme == "https" && uri.host?.endsWith(".ustc.edu.cn") == true)
                        require(uri.userInfo == null)
                        Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
                    }
                    "openIwan" -> {
                        val iwan = trustedIwanIntent()
                        if (iwan != null) startActivity(iwan)
                        result.success(iwan != null)
                        return@setMethodCallHandler
                    }
                    "takeCampusReturn" -> {
                        val launch = this.intent
                        val incoming = launch.data
                        if (incoming?.scheme == "io.github.yyyy530.tokenworks-go" &&
                            incoming.authority == "auth" && incoming.path == "/campus"
                        ) {
                            setIntent(Intent(launch).setData(null))
                            result.success(incoming.toString())
                        } else {
                            result.success(null)
                        }
                        return@setMethodCallHandler
                    }
                    "openVpnSettings" -> Intent(Settings.ACTION_VPN_SETTINGS)
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                startActivity(intent)
                result.success(null)
            } catch (_: Exception) {
                result.error("navigation-unavailable", "Campus navigation is unavailable", null)
            }
        }
    }

    private fun trustedIwanIntent(): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        val certificate = iwanReleaseCertificate.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        if (!packageManager.hasSigningCertificate(
                iwanPackage, certificate, PackageManager.CERT_INPUT_SHA256
            )) {
            return null
        }
        return packageManager.getLaunchIntentForPackage(iwanPackage)
    }

    private fun registerStore(
        messenger: BinaryMessenger,
        queue: BinaryMessenger.TaskQueue,
        channelName: String,
        fileName: String
    ) {
        val file = AtomicFile(File(noBackupFilesDir, fileName))
        MethodChannel(
            messenger,
            "tokenworks_go/$channelName",
            StandardMethodCodec.INSTANCE,
            queue
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(read(file))
                    "save" -> {
                        save(file, requireNotNull(call.arguments as? String))
                        result.success(null)
                    }
                    "clear" -> {
                        file.delete()
                        check(!file.baseFile.exists())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("storage-unavailable", "Credential storage is unavailable", null)
            }
        }
    }

    private fun read(file: AtomicFile): String? {
        val encrypted = try {
            file.readFully()
        } catch (exception: FileNotFoundException) {
            if (!file.baseFile.exists()) return null
            throw exception
        }
        require(encrypted.size > nonceBytes)
        val cipher = Cipher.getInstance(cipherName)
        cipher.init(
            Cipher.DECRYPT_MODE,
            checkNotNull(storedKey()),
            GCMParameterSpec(128, encrypted, 0, nonceBytes)
        )
        return cipher.doFinal(encrypted, nonceBytes, encrypted.size - nonceBytes)
            .toString(Charsets.UTF_8)
    }

    private fun save(file: AtomicFile, value: String) {
        val cipher = Cipher.getInstance(cipherName)
        cipher.init(Cipher.ENCRYPT_MODE, storedKey() ?: createKey())
        check(cipher.iv.size == nonceBytes)
        val encrypted = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try {
            stream.write(encrypted)
            file.finishWrite(stream)
        } catch (exception: Exception) {
            file.failWrite(stream)
            throw exception
        }
    }

    private fun storedKey(): SecretKey? =
        KeyStore.getInstance(keyStoreName).apply { load(null) }.getKey(keyAlias, null) as? SecretKey

    private fun createKey(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, keyStoreName).apply {
            init(
                KeyGenParameterSpec.Builder(
                    keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
        }.generateKey()

    private companion object {
        const val keyStoreName = "AndroidKeyStore"
        const val keyAlias = "tokenworks-desktop-session"
        const val iwanPackage = "com.panabit.client"
        const val iwanReleaseCertificate = "92ff1f3ecc54c2319b78b59bbf846edc9bc9520229495ef0d4918205b5e42be5"
        const val cipherName = "AES/GCM/NoPadding"
        const val nonceBytes = 12
    }
}
