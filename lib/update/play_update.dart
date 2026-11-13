// Cập nhật qua Google Play cho bản flavor play (Android): hỏi Play có bản mới không (In-App Updates API, Kotlin:
// PlayUpdate.kt), cập nhật linh hoạt (tải nền rồi "Khởi động lại để cập nhật") hoặc bắt buộc khi Play báo độ ưu tiên
// cao (inAppUpdatePriority >= 4, đặt khi đăng bản lên Play). Bản tự cập nhật (sideload) và máy tính dùng [Updater].
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kết quả hỏi Play.
class PlayUpdateInfo {
  final bool available;
  final int versionCode;
  final int priority;
  final int? staleDays;
  final bool immediateAllowed;
  final bool flexibleAllowed;
  final int status;
  const PlayUpdateInfo({
    required this.available,
    this.versionCode = 0,
    this.priority = 0,
    this.staleDays,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.status = 0,
  });

  factory PlayUpdateInfo.fromMap(Map m) => PlayUpdateInfo(
        available: m['available'] == true,
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        staleDays: (m['staleDays'] as num?)?.toInt(),
        immediateAllowed: m['immediate'] == true,
        flexibleAllowed: m['flexible'] == true,
        status: (m['status'] as num?)?.toInt() ?? 0,
      );

  /// Bắt buộc cập nhật (màn hình Play che app) khi độ ưu tiên >= 4 và Play cho phép; còn lại cập nhật linh hoạt.
  bool get immediate => immediateAllowed && (priority >= 4 || !flexibleAllowed);

  /// Bản mới đã tải xong (cập nhật linh hoạt), chỉ chờ khởi động lại.
  bool get downloaded => status == PlayUpdate.statusDownloaded;
}

class PlayUpdate {
  static const _channel = MethodChannel('flygo/playupdate');

  /// InstallStatus của Play.
  static const statusDownloading = 2, statusDownloaded = 11, statusFailed = 5, statusCanceled = 6;

  /// Lần hỏi gần nhất (null: chưa hỏi hoặc lỗi).
  static final info = ValueNotifier<PlayUpdateInfo?>(null);

  /// Đang tải bản mới (cập nhật linh hoạt): 0..1, null khi không tải.
  static final progress = ValueNotifier<double?>(null);

  /// Bản mới đã tải xong, chỉ chờ "Khởi động lại để cập nhật".
  static final downloaded = ValueNotifier<bool>(false);

  /// Lỗi lần hỏi gần nhất (cài không qua Play, máy không có Play...).
  static String? lastError;

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'state') return;
      final m = call.arguments as Map;
      final status = (m['status'] as num?)?.toInt() ?? 0;
      final bytes = (m['bytes'] as num?)?.toInt() ?? 0, total = (m['total'] as num?)?.toInt() ?? 0;
      if (status == statusDownloading) progress.value = total > 0 ? bytes / total : 0;
      if (status == statusDownloaded) {
        progress.value = null;
        downloaded.value = true;
      }
      if (status == statusFailed || status == statusCanceled) progress.value = null;
    });
  }

  /// Hỏi Play có bản mới không. Lỗi thì trả về null ([lastError] ghi lý do).
  static Future<PlayUpdateInfo?> check() async {
    _listen();
    lastError = null;
    try {
      final m = await _channel.invokeMethod<Map>('check');
      final i = m == null ? null : PlayUpdateInfo.fromMap(m);
      info.value = i;
      if (i?.downloaded == true) downloaded.value = true;
      return i;
    } on PlatformException catch (e) {
      lastError = e.message ?? e.code;
    } on MissingPluginException catch (e) {
      lastError = e.message;
    }
    info.value = null;
    return null;
  }

  /// Mở luồng cập nhật của Play (bắt buộc hoặc linh hoạt theo [PlayUpdateInfo.immediate]). Trả về true nếu đã mở.
  static Future<bool> start() async {
    final i = info.value ?? await check();
    if (i == null || !i.available) return false;
    final ok = await _channel.invokeMethod<bool>('start', {'immediate': i.immediate}) ?? false;
    // Luồng chỉ dùng được một lần: hỏi lại cho lần sau.
    unawaited(check());
    return ok;
  }

  /// Cập nhật linh hoạt đã tải xong: khởi động lại app để cài.
  static Future<void> complete() => _channel.invokeMethod('complete');

  /// Mở trang Flygo Chat trên Google Play.
  static Future<void> openStore() async {
    final market = Uri.parse('market://details?id=vn.flygo.chat');
    if (!await launchUrl(market, mode: LaunchMode.externalApplication)) {
      await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=vn.flygo.chat'), mode: LaunchMode.externalApplication);
    }
  }
}
