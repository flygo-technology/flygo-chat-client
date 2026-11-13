// Số bản để HIỂN THỊ (Sếp, 2026-11-13): chỉ số build ("461"), không hiện "1.0.4". Phiên bản đầy đủ vẫn dùng nội bộ
// (pubspec, app_version gửi Flygo ID, so sánh phiên bản, version.json).
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Số bản trong chuỗi phiên bản bất kỳ: "1.0.4+461" / "1.0.4 (461)" / "461" -> "461". Không có số bản thì trả lại nguyên.
String buildLabel(String v) {
  final s = v.trim();
  final m = RegExp(r'\+(\d+)$').firstMatch(s) ?? RegExp(r'\((\d+)\)$').firstMatch(s);
  return m?.group(1) ?? s;
}

/// Số bản của app đang chạy (rỗng nếu chưa đọc được).
final currentBuild = ValueNotifier<String>('');

Future<String> loadCurrentBuild() async {
  if (currentBuild.value.isNotEmpty) return currentBuild.value;
  try {
    final i = await PackageInfo.fromPlatform();
    currentBuild.value = i.buildNumber.isNotEmpty ? i.buildNumber : buildLabel(i.version);
  } catch (_) {}
  return currentBuild.value;
}
