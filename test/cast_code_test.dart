import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/cast/cast_api.dart';

void main() {
  test('mã màn hình từ QR / chữ gõ', () {
    expect(parseScreenCode('https://hello.flygo.vn/p/K7QM2XPR'), 'K7QM2XPR');
    expect(parseScreenCode(' k7qm-2xpr '), 'K7QM2XPR');
    expect(parseScreenCode('https://meet.flygo.vn/hop/pair/ABCDEFGH1234'), null);
    expect(parseScreenCode('K7QM-2XP0'), null);
  });
  test('màn hình thuộc máy chủ khác', () {
    expect(foreignScreenHost('https://hello.dnd-global.com/p/K7QM2XPR', 'https://chat.flygo.vn'), 'hello.dnd-global.com');
    expect(foreignScreenHost('https://hello.flygo.vn/p/K7QM2XPR', 'https://chat.flygo.vn'), null);
    expect(foreignScreenHost('K7QM2XPR', 'https://chat.flygo.vn'), null);
  });
}
