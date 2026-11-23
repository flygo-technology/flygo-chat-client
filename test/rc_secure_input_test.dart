// Điều khiển máy tính: ô mật khẩu macOS bật Secure Input chặn phím gõ từ xa → máy kia báo, máy điều khiển "Dán mật khẩu".
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/remote/rc_native.dart';
import 'package:flygo_chat/remote/rc_protocol.dart';

void main() {
  test('dán mật khẩu: mã hoá / giải mã, một dòng, giới hạn độ dài, không lộ trong toString', () {
    const p = RcPasteSecret('Mk@2026!');
    final back = RcInput.decode(p.encode());
    expect(back, isA<RcPasteSecret>());
    expect((back as RcPasteSecret).secret, 'Mk@2026!');
    expect(back.toString(), isNot(contains('Mk@2026')));
    // Xuống dòng / tab bị bỏ (Enter trong ô mật khẩu sẽ gửi biểu mẫu).
    expect((RcInput.decode('["p","ab\\ncd\\te"]') as RcPasteSecret).secret, 'abcde');
    expect(RcInput.decode('["p",""]'), isNull);
    expect(RcInput.decode('["p","${'x' * (kRcMaxSecret + 1)}"]'), isNull);
    expect(RcInput.decode('["p",5]'), isNull);
  });

  test('tin Secure Input của máy bị điều khiển', () {
    expect(rcSecureDecode(rcSecureEncode(true)), isTrue);
    expect(rcSecureDecode(rcSecureEncode(false)), isFalse);
    expect(rcSecureDecode('["x",2]'), isNull);
    expect(rcSecureDecode('["s","1",[]]'), isNull);
    expect(rcSecureDecode('không phải json'), isNull);
  });

  test('Windows / Linux (không có Secure Input): mật khẩu gõ như chữ; macOS: để dịch vụ dán qua bộ nhớ tạm', () {
    const screen = RcScreen(id: '1', x: 0, y: 0, width: 1000, height: 500);
    final win = RcInjector(mac: false, screen: screen, virtualDesk: const Rect.fromLTWH(0, 0, 1001, 501));
    expect(win.map(const RcPasteSecret('abc')), [
      {'op': 'text', 's': 'abc'}
    ]);
    final mac = RcInjector(mac: true, screen: screen, virtualDesk: Rect.zero);
    expect(mac.map(const RcPasteSecret('abc')), isEmpty);
  });
}
