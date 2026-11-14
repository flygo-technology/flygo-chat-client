import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';

void main() {
  test('mốc min_client là số trơn: so với số build', () {
    expect(compareAppVersion('1.0.4+417', '416'), greaterThan(0));
    expect(compareAppVersion('1.0.4+416', '416'), 0);
    expect(compareAppVersion('1.0.4+415', '416'), lessThan(0));
    expect(compareAppVersion('1.0.4', '416'), 0); // không có số build: không chặn
  });

  test('mốc đầy đủ như cũ', () {
    expect(compareAppVersion('1.0.4+417', '1.0.4+416'), greaterThan(0));
    expect(compareAppVersion('1.0.4+415', '1.0.4+416'), lessThan(0));
    expect(compareAppVersion('1.0.5+1', '1.0.4+416'), greaterThan(0));
    expect(compareAppVersion('1.0.3+999', '1.0.4'), lessThan(0));
    expect(compareAppVersion('1.0.4+10', '1.0.4'), 0);
  });

  test('user_agent trong manifest: đọc được, giữ qua toJson; rỗng = null', () {
    const ua = 'Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) TV Safari/537.36';
    final a = MiniApp.fromJson({'id': 'vn.flygo.web.youtube-tv', 'origin': 'https://www.youtube.com', 'user_agent': ua});
    expect(a.userAgent, ua);
    expect(MiniApp.fromJson(a.toJson()).userAgent, ua);
    expect(MiniApp.fromJson({'id': 'x.y.z', 'origin': 'https://a.test'}).userAgent, isNull);
  });
}
