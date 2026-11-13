package vn.flygo.chat

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Nhận chia sẻ từ app khác (SEND / SEND_MULTIPLE: ảnh, video, tệp, chữ, link). Tệp được chép vào thư mục tạm của app
/// (luồng content:// của app gửi chỉ đọc được lúc này), rồi báo Dart qua kênh "flygo/share" (Dart: lib/ui/share_intake.dart):
///   "take"   -> {files: [đường dẫn], text} hoặc null (lấy xong thì xoá)
///   "shared" (gửi sang Dart) -> có nội dung mới, gọi "take".
class ShareIn(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "flygo/share")
    private var pending: Map<String, Any>? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "take") return@setMethodCallHandler result.notImplemented()
            result.success(pending)
            pending = null
        }
    }

    fun handle(intent: Intent?) {
        if (intent == null || (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE)) return
        val text = listOfNotNull(intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()).filter { it.isNotEmpty() }.joinToString("\n")
        val uris = streams(intent)
        // Đã đọc: lần dựng lại activity (xoay màn hình...) không nhận lại lần nữa.
        intent.action = null
        // Chép tệp ở luồng nền (video lớn không làm đơ giao diện), xong mới báo Dart.
        Thread {
            val dir = File(activity.cacheDir, "shared").apply { mkdirs() }
            val stamp = System.currentTimeMillis()
            val files = uris.mapIndexedNotNull { i, u -> copy(u, dir, "${stamp}_${i + 1}") }
            if (files.isEmpty() && text.isEmpty()) return@Thread
            activity.runOnUiThread {
                pending = mapOf("files" to files, "text" to text)
                channel.invokeMethod("shared", null)
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        )
        else -> (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                 else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()
    }

    /// Chép một tệp được chia sẻ, giữ tên gốc (thêm tiền tố để không trùng). Lỗi thì bỏ qua tệp đó.
    private fun copy(uri: Uri, dir: File, prefix: String): String? = try {
        val r = activity.contentResolver
        var name: String? = null
        r.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0)
        }
        if (name.isNullOrBlank()) {
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(r.getType(uri) ?: "") ?: "bin"
            name = "tep.$ext"
        }
        val out = File(dir, "${prefix}_${name!!.replace(Regex("[\\\\/:*?\"<>|]"), "_")}")
        r.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } } ?: return null
        out.absolutePath
    } catch (e: Exception) {
        null
    }
}
