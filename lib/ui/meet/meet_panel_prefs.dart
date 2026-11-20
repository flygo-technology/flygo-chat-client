import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// Panel bên phải của cuộc họp trên máy tính: độ rộng và tab mở gần nhất, nhớ qua các lần họp (tệp nhỏ trên máy).
class MeetPanelPrefs {
  static double width = 400;
  static String tab = '';
  static bool _loaded = false;

  /// Cho test: dùng giá trị đã đặt sẵn, không đọc tệp.
  @visibleForTesting
  static void debugSet({double? width, String? tab}) {
    _loaded = true;
    if (width != null) MeetPanelPrefs.width = width;
    if (tab != null) MeetPanelPrefs.tab = tab;
  }

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/meet-panel.json');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final j = jsonDecode(await (await _file()).readAsString());
      if (j is Map) {
        width = ((j['width'] as num?)?.toDouble() ?? width).clamp(320.0, 720.0);
        tab = '${j['tab'] ?? ''}';
      }
    } catch (_) {}
  }

  static Future<void> save({double? width, String? tab}) async {
    if (width != null) MeetPanelPrefs.width = width;
    if (tab != null) MeetPanelPrefs.tab = tab;
    try {
      await (await _file()).writeAsString(jsonEncode({'width': MeetPanelPrefs.width, 'tab': MeetPanelPrefs.tab}));
    } catch (_) {}
  }
}
