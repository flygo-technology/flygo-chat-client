package vn.flygo.chat

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Cập nhật qua Google Play (bản flavor play; Dart: lib/update/play_update.dart). Kênh "flygo/playupdate":
///   "check"    -> {available, versionCode, priority, staleDays, immediate, flexible, status} (lỗi: PlatformException)
///   "start"    {immediate} -> true nếu đã mở luồng cập nhật của Play
///   "complete" -> khởi động lại để cài bản đã tải (cập nhật linh hoạt)
///   "state" (gửi sang Dart) {status, bytes, total}: tiến độ tải của cập nhật linh hoạt.
class PlayUpdate(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "flygo/playupdate")
    private val manager = AppUpdateManagerFactory.create(activity)
    private var last: AppUpdateInfo? = null
    private val listener = InstallStateUpdatedListener { s ->
        channel.invokeMethod("state", mapOf("status" to s.installStatus(), "bytes" to s.bytesDownloaded(), "total" to s.totalBytesToDownload()))
    }

    init {
        manager.registerListener(listener)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "check" -> manager.appUpdateInfo
                    .addOnSuccessListener { info ->
                        last = info
                        val avail = info.updateAvailability()
                        result.success(mapOf(
                            "available" to (avail == UpdateAvailability.UPDATE_AVAILABLE || avail == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS),
                            "versionCode" to info.availableVersionCode(),
                            "priority" to info.updatePriority(),
                            "staleDays" to info.clientVersionStalenessDays(),
                            "immediate" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                            "flexible" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                            "status" to info.installStatus(),
                        ))
                    }
                    .addOnFailureListener { e -> result.error("play", e.message ?: e.javaClass.simpleName, null) }
                "start" -> {
                    val info = last ?: return@setMethodCallHandler result.success(false)
                    val type = if (call.argument<Boolean>("immediate") == true) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
                    if (!info.isUpdateTypeAllowed(type)) return@setMethodCallHandler result.success(false)
                    try {
                        @Suppress("DEPRECATION")
                        val started = manager.startUpdateFlowForResult(info, activity, AppUpdateOptions.newBuilder(type).build(), REQUEST)
                        // Luồng cập nhật chỉ dùng được một lần: lần sau phải "check" lại.
                        last = null
                        result.success(started)
                    } catch (e: Exception) {
                        result.error("play", e.message ?: e.javaClass.simpleName, null)
                    }
                }
                "complete" -> {
                    manager.completeUpdate()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val REQUEST = 7301
    }
}
