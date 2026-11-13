import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/security/device_key.dart';

void main() {
  test('chuỗi ký khi xác thực từ xa theo devices-verify.md', () {
    const details = '{"action":"Đăng nhập","app":"Flows"}';
    final m = utf8.decode(DeviceKey.verifyMessage('vr_123', details, '42'));
    expect(m, 'flygo-verify-v1\nvr_123\n${sha256.convert(utf8.encode(details))}\n42');
    expect(m.split('\n')[2], hasLength(64));
  });

  test('trạng thái: không hỗ trợ khi chưa có sinh trắc', () {
    expect(DeviceKeyStatus.unsupported.label, 'Không hỗ trợ');
    final none = DeviceKeyStatus.fromMap({'supported': true, 'biometric': 'none_enrolled'});
    expect(none.available, isFalse);
    expect(none.label, contains('chưa cài vân tay'));
    final ok = DeviceKeyStatus.fromMap({'supported': true, 'biometric': 'ok', 'enrolled': true, 'hw_backed': true, 'biometric_bound': true});
    expect(ok.available, isTrue);
    expect(ok.label, contains('Khoá phần cứng'));
  });
}
