import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Nội dung đang soạn dở theo từng chat / luồng: đổi sang chat khác rồi quay lại, hay tắt app mở lại, vẫn còn.
/// Khoá theo máy chủ + kênh + tin gốc của luồng. Lưu trên máy (drafts.json), ghi trễ 0,5 giây khi đang gõ.
class Drafts {
  static final Map<String, String> _m = {};
  static Future<void>? _loading;
  static Timer? _save;

  static String key(String channelId, [String? threadRoot]) => '$serverKey|$channelId|${threadRoot ?? ''}';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}drafts.json');
  }

  /// Đọc nháp đã lưu (một lần mỗi lần chạy app).
  static Future<void> load() => _loading ??= () async {
        try {
          final f = await _file();
          if (!await f.exists()) return;
          final j = jsonDecode(await f.readAsString());
          if (j is Map) {
            j.forEach((k, v) {
              if (v is String && v.trim().isNotEmpty) _m.putIfAbsent('$k', () => v);
            });
          }
        } catch (_) {}
      }();

  static String get(String key) => _m[key] ?? '';

  /// Ghi nháp (chuỗi trống = xoá nháp).
  static void set(String key, String text) {
    if (text.trim().isEmpty) {
      if (_m.remove(key) == null) return;
    } else {
      if (_m[key] == text) return;
      _m[key] = text;
    }
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), _flush);
  }

  static Future<void> _flush() async {
    try {
      await (await _file()).writeAsString(jsonEncode(_m));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _m.clear();
    _loading = Future.value();
    _save?.cancel();
  }
}
