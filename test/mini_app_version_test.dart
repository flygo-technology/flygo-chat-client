import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/ui/mini_app_windows.dart' show formatTvCode;

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

  test('features trong manifest: cờ bật / tắt, thiếu = tắt', () {
    final a = MiniApp.fromJson({'id': 'vn.flygo.web.youtube-tv', 'origin': 'https://www.youtube.com',
        'features': {'window': true, 'keep_visible': true, 'tv_code': false}});
    expect(a.feature('window'), isTrue);
    expect(a.feature('keep_visible'), isTrue);
    expect(a.feature('tv_code'), isFalse);
    expect(MiniApp.fromJson(a.toJson()).feature('window'), isTrue);
    expect(MiniApp.fromJson({'id': 'x.y.z', 'origin': 'https://a.test'}).feature('window'), isFalse);
  });

  test('mã TV hiện theo nhóm 3 số', () {
    expect(formatTvCode('110621207476'), '110 621 207 476');
    expect(formatTvCode('1234567'), '123 456 7');
  });
}
