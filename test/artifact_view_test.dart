import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/artifact_view.dart';
import 'package:flygo_chat/ui/voice_mode.dart';

void main() {
  test('CSP chèn sau <head>, không có head thì đặt đầu trang', () {
    final a = withCsp('<!doctype html><html><head><title>x</title></head><body></body></html>');
    expect(a.indexOf('Content-Security-Policy'), greaterThan(a.indexOf('<head>')));
    expect(a.indexOf('Content-Security-Policy'), lessThan(a.indexOf('<title>')));
    expect(a, contains("connect-src 'none'"));
    final b = withCsp('<div>hi</div>');
    expect(b.startsWith('<meta http-equiv="Content-Security-Policy"'), isTrue);
  });

  test('đọc to: bỏ markdown, link, khối mã', () {
    expect(speakableText('**Xong** rồi, xem [báo cáo](https://x.y/z) và https://a.b\n\n```sh\nls\n```'), 'Xong rồi, xem báo cáo và  \n (đoạn mã)');
  });
}
