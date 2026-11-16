package vn.flygo.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Drive: dịch vụ nền (foreground, loại dataSync) giữ app chạy khi tắt màn hình / thoát app trong lúc hàng đợi tải lên
// (lib/ui/drive/uploads.dart) còn việc. Phần tải do Dart làm; dịch vụ chỉ giữ tiến trình và hiện thông báo tiến độ.
// Kênh "flygo/drive_upload": start {title, text}, update {title, text, progress 0-100}, stop.
class DriveUploadService : Service() {
    companion object {
        private const val CHANNEL = "drive_upload"
        private const val ID = 7301
        private var running = false

        fun register(context: Context, messenger: BinaryMessenger) {
            MethodChannel(messenger, "flygo/drive_upload").setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // Play chưa khai báo quyền FOREGROUND_SERVICE_DATA_SYNC (Sếp, 2026-11-16): tạm không mở dịch vụ nền,
                        // tải lên chạy khi app còn mở và tiếp tục khi mở lại app.
                        "start", "update", "stop" -> result.success(null)
                        "start_fg", "update_fg" -> {
                            val i = Intent(context, DriveUploadService::class.java)
                                .putExtra("title", call.argument<String>("title") ?: "")
                                .putExtra("text", call.argument<String>("text") ?: "")
                                .putExtra("progress", call.argument<Int>("progress") ?: -1)
                            if (!running && call.method == "update") return@setMethodCallHandler result.success(null)
                            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
                            result.success(null)
                        }
                        "stop" -> {
                            context.stopService(Intent(context, DriveUploadService::class.java))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // Android 12+ có thể chặn mở dịch vụ nền khi app không ở trên cùng: vẫn tải khi app còn mở.
                    result.error("fg", e.message, null)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun build(title: String, text: String, progress: Int): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Tải lên Drive", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        b.setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (progress >= 0) b.setProgress(100, progress, false) else b.setProgress(0, 0, true)
        return b.build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = build(intent?.getStringExtra("title") ?: "", intent?.getStringExtra("text") ?: "", intent?.getIntExtra("progress", -1) ?: -1)
        if (!running) {
            if (Build.VERSION.SDK_INT >= 29) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else startForeground(ID, n)
            running = true
        } else {
            getSystemService(NotificationManager::class.java).notify(ID, n)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    // Android 15: dataSync có giới hạn thời gian; hết giờ thì dừng (Dart tải tiếp khi app mở lại).
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }
}
