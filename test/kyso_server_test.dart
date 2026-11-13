import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/runtime.dart';

/// Máy chủ ký số mặc định suy từ máy chủ chat: `chat.<miền>` -> `kyso.<miền>`.
void main() {
  test('chat.<miền> -> kyso.<miền>', () {
    expect(kysoServerFor('https://chat.example.com'), 'https://kyso.example.com');
    expect(kysoServerFor('https://chat.congty.example.vn/'), 'https://kyso.congty.example.vn');
  });
  test('máy chủ không theo quy ước: rỗng', () {
    expect(kysoServerFor('https://mm.example.com'), '');
    expect(kysoServerFor(''), '');
  });
}
