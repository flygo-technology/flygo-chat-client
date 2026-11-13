package vn.flygo.chat

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

/// Kênh "flygo/devicekey": khoá thiết bị cho tính năng "Thiết bị" / xác thực từ xa (Dart: lib/security/device_key.dart).
/// EC P-256 trong Android Keystore (StrongBox nếu có), không xuất được, mỗi lần ký phải qua vân tay / khuôn mặt
/// (BiometricPrompt + CryptoObject), mất hiệu lực khi thêm vân tay mới.
class DeviceKey(private val activity: FragmentActivity, messenger: BinaryMessenger) {
    private val alias = "flygo.device.v1"

    init {
        MethodChannel(messenger, "flygo/devicekey").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "create" -> result.success(create())
                    "delete" -> {
                        keyStore().deleteEntry(alias)
                        result.success(true)
                    }
                    "sign" -> sign(
                        Base64.decode(call.argument<String>("data") ?: "", Base64.NO_WRAP),
                        call.argument<String>("title") ?: "Xác thực",
                        call.argument<String>("subtitle") ?: "",
                        result,
                    )
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("devicekey", e.message ?: e.toString(), null)
            }
        }
    }

    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun biometricState(): String =
        when (BiometricManager.from(activity).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "ok"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "none_enrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE, BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "no_hardware"
            else -> "unavailable"
        }

    /// Khoá có trong phần cứng an toàn (TEE / StrongBox) không.
    private fun hwBacked(key: PrivateKey): Boolean = try {
        val info = KeyFactory.getInstance(key.algorithm, "AndroidKeyStore").getKeySpec(key, KeyInfo::class.java)
        if (Build.VERSION.SDK_INT >= 31) {
            info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        } else {
            @Suppress("DEPRECATION")
            info.isInsideSecureHardware
        }
    } catch (_: Exception) {
        false
    }

    private fun publicKey(): String? {
        val cert = keyStore().getCertificate(alias) ?: return null
        val pub = cert.publicKey as ECPublicKey
        fun pad(b: ByteArray): ByteArray {
            val v = b.dropWhile { it == 0.toByte() }.toByteArray()
            return ByteArray(32 - v.size) + v
        }
        val raw = byteArrayOf(4) + pad(pub.w.affineX.toByteArray()) + pad(pub.w.affineY.toByteArray())
        return Base64.encodeToString(raw, Base64.NO_WRAP)
    }

    private fun status(): Map<String, Any?> {
        val ks = keyStore()
        val key = ks.getKey(alias, null) as? PrivateKey
        return mapOf(
            "supported" to true,
            "biometric" to biometricState(),
            "enrolled" to (key != null),
            "hw_backed" to (key?.let { hwBacked(it) } ?: false),
            "biometric_bound" to (key != null),
            "public_key" to publicKey(),
        )
    }

    private fun spec(strongBox: Boolean): KeyGenParameterSpec {
        val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= 30) {
            b.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            b.setUserAuthenticationValidityDurationSeconds(-1)
        }
        if (strongBox && Build.VERSION.SDK_INT >= 28) b.setIsStrongBoxBacked(true)
        return b.build()
    }

    /// Tạo khoá mới (xoá khoá cũ). Trả về trạng thái kèm khoá công khai.
    private fun create(): Map<String, Any?> {
        if (biometricState() != "ok") throw IllegalStateException("Máy chưa cài vân tay / khuôn mặt (sinh trắc học mạnh)")
        keyStore().deleteEntry(alias)
        val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        try {
            gen.initialize(spec(strongBox = true))
            gen.generateKeyPair()
        } catch (_: Exception) {
            // StrongBox không có (hoặc không tạo được khoá EC ở đó): dùng TEE.
            keyStore().deleteEntry(alias)
            gen.initialize(spec(strongBox = false))
            gen.generateKeyPair()
        }
        return status()
    }

    /// Ký [data] (ECDSA P-256 / SHA-256, DER) sau khi người dùng xác thực bằng vân tay / khuôn mặt.
    private fun sign(data: ByteArray, title: String, subtitle: String, result: MethodChannel.Result) {
        val key = keyStore().getKey(alias, null) as? PrivateKey
            ?: return result.error("no_key", "Thiết bị chưa có khoá xác thực", null)
        val sig = Signature.getInstance("SHA256withECDSA")
        try {
            sig.initSign(key)
        } catch (_: KeyPermanentlyInvalidatedException) {
            return result.error("invalidated", "Vân tay trên máy đã thay đổi: hãy đăng ký lại thiết bị", null)
        }
        var done = false
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                if (done) return
                done = true
                try {
                    val s = r.cryptoObject?.signature ?: sig
                    s.update(data)
                    result.success(Base64.encodeToString(s.sign(), Base64.NO_WRAP))
                } catch (e: Exception) {
                    result.error("sign", e.message ?: e.toString(), null)
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                if (done) return
                done = true
                result.error(if (code == BiometricPrompt.ERROR_USER_CANCELED || code == BiometricPrompt.ERROR_NEGATIVE_BUTTON) "cancelled" else "auth", msg.toString(), null)
            }
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText("Hủy")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(sig))
    }
}
