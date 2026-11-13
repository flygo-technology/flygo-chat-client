import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/update/build_label.dart';
import 'package:flygo_chat/update/updater.dart';

/// Chỉ hiện số bản (Sếp, 2026-11-13): "1.0.4+461" / "1.0.4 (461)" -> "461".
void main() {
  test('lấy số bản từ mọi dạng phiên bản', () {
    expect(buildLabel('1.0.4+461'), '461');
    expect(buildLabel('1.0.4 (461)'), '461');
    expect(buildLabel('461'), '461');
    expect(buildLabel(' 1.0.4+461 '), '461');
    expect(buildLabel('1.0.4'), '1.0.4', reason: 'không có số bản thì giữ nguyên');
    expect(buildLabel(''), '');
  });

  test('bản mới trên máy chủ chỉ hiện số bản', () {
    expect(UpdateInfo(462, '1.0.4', '', 'a.apk').label, '462');
    expect(UpdateInfo.play(462).label, 'Google Play');
  });
}
