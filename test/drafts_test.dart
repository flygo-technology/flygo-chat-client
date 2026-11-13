import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/state/drafts.dart';

/// Nháp tin nhắn theo chat / luồng.
void main() {
  setUp(() {
    kServerUrl = 'https://chat.flygo.vn';
    Drafts.resetForTest();
  });

  test('mỗi chat và mỗi luồng một nháp riêng', () {
    final a = Drafts.key('kenhA'), b = Drafts.key('kenhB'), t = Drafts.key('kenhA', 'goc1');
    Drafts.set(a, 'Đang soạn dở ở A');
    Drafts.set(t, 'Trả lời trong luồng');
    expect(Drafts.get(a), 'Đang soạn dở ở A');
    expect(Drafts.get(b), '');
    expect(Drafts.get(t), 'Trả lời trong luồng');
  });

  test('chuỗi trống hoặc chỉ khoảng trắng là xoá nháp', () {
    final a = Drafts.key('kenhA');
    Drafts.set(a, 'x');
    Drafts.set(a, '   ');
    expect(Drafts.get(a), '');
  });

  test('khác máy chủ thì khác nháp', () {
    final a = Drafts.key('kenhA');
    Drafts.set(a, 'ở Flygo');
    kServerUrl = 'https://chat.example.com';
    expect(Drafts.get(Drafts.key('kenhA')), '');
  });
}
