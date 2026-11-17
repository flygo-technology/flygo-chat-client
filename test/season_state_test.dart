import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/ui/season/season_art.dart';
import 'package:flygo_chat/ui/season/season_state.dart';

Map<String, dynamic> _org({bool enabled = true, String mode = 'mix', List<Map<String, String>>? kws, Map<String, bool>? features}) => {
      'cfg': {
        'seasons': {
          'giangsinh': {'enabled': enabled, 'from': '12-01', 'to': '12-26', 'features': features ?? {}},
        },
        'effect': {'mode': mode, 'keywords': kws ?? [{'k': 'Giáng sinh vui vẻ', 'fx': 'gifts'}, {'k': 'Merry Christmas', 'fx': 'snow'}, {'k': 'Noel', 'fx': 'mix'}]},
        'defaults': {'bubble': null, 'wallpaper': null},
      },
      'version': 1,
      'windows': [
        {'id': 'giangsinh', 'start': '2026-12-01', 'end': '2026-12-26', 'enabled': enabled, 'active': false},
      ],
    };

void main() {
  final s = SeasonState.instance;
  final dec10 = DateTime.utc(2026, 12, 10, 3);
  setUp(() {
    s.app = MiniApp.fromJson({'id': kAppearanceApp, 'origin': 'https://chat.test', 'base_url': 'https://chat.test/__apps/appearance'});
    s.org = _org();
    s.mine = {};
    s.wallpapers = {};
  });

  test('máy chủ không có dịch vụ Giao diện: không có mùa lễ', () {
    s.org = null;
    expect(s.activeSeason(dec10), isNull);
    expect(s.on('lights', dec10), isFalse);
    expect(s.resolveWallpaper('c1', true), isNull);
  });

  test('khung ngày theo giờ Việt Nam', () {
    expect(s.activeSeason(DateTime.utc(2026, 11, 30, 16, 59)), isNull); // 23:59 30/11 VN
    expect(s.activeSeason(DateTime.utc(2026, 11, 30, 17, 0)), 'giangsinh'); // 00:00 01/12 VN
    expect(s.activeSeason(DateTime.utc(2026, 12, 26, 17, 0)), isNull); // 00:00 27/12 VN
    s.org = _org(enabled: false);
    expect(s.activeSeason(dec10), isNull);
  });

  test('công ty tắt một phần, mình tắt một phần, mình tắt hẳn', () {
    s.org = _org(features: {'banner': false});
    expect(s.on('banner', dec10), isFalse);
    expect(s.on('lights', dec10), isTrue);
    s.mine = {'mode': 'custom', 'lights': false};
    expect(s.on('lights', dec10), isFalse);
    s.mine = {'mode': 'custom', 'off': true};
    expect(s.on('effect', dec10), isFalse);
  });

  test('trong mùa: hình nền + bong bóng mùa tự áp; mình tắt mùa lễ thì thôi', () {
    s.clock = () => DateTime.utc(2026, 12, 10, 3);
    expect(s.resolveWallpaper('c1', true)?.art?.id, 'giangsinh');
    expect(s.seasonBubble('u1')?.def?.group, 'giangsinh');
    expect(s.seasonBubble('u1')?.style, s.seasonBubble('u1')?.style); // ổn định
    (s.org!['cfg']['seasons']['giangsinh'] as Map)['bubble'] = {'mode': 'one', 'style': 'munoel'};
    expect(s.seasonBubble('u9')?.style, 'munoel');
    (s.org!['cfg']['seasons']['giangsinh'] as Map)['wallpaper'] = 'off';
    expect(s.resolveWallpaper('c1', true), isNull);
    s.mine = {'mode': 'custom', 'off': true};
    expect(s.seasonBubble('u9'), isNull);
    s.clock = DateTime.now;
  });

  test('hình nền: riêng chat > mặc định của mình > theo mùa', () {
    // Ngoài mùa: "theo mùa lễ" = không có hình nền.
    s.org = _org(enabled: false);
    expect(s.resolveWallpaper('c1', true), isNull);
    s.wallpapers = {'c1': 'tuyettrang'}; // mã cũ → Giáng sinh (một hình nền, tự đổi sáng / tối)
    expect(s.resolveWallpaper('c1', true)?.art?.id, 'giangsinh');
    s.mine = {'mode': 'custom'};
    s.wallpapers = {'_default': 'plain:1F2933'};
    expect(s.resolveWallpaper('c2', false)?.color?.toARGB32(), 0xFF1F2933);
    s.wallpapers = {'_default': 'photo', 'c3': 'none'};
    expect(s.resolveWallpaper('c2', false)?.photoKey, '_default');
    expect(s.resolveWallpaper('c3', false), isNull);
  });

  test('hiệu ứng lời chúc: trộn / theo từ khoá, bỏ dấu, nguyên từ', () {
    final now = DateTime.now();
    // effectFor dùng giờ máy: đặt khung ngày phủ hôm nay.
    final today = now.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);
    s.org = _org()..['windows'] = [{'id': 'giangsinh', 'start': today, 'end': today, 'enabled': true}];
    expect(s.effectFor('Giáng sinh vui vẻ cả nhà!'), BurstKind.mix);
    expect(s.effectFor('Noelia gửi file'), isNull);
    expect(s.effectFor('chúc mừng noel'), BurstKind.mix);
    s.org = _org(mode: 'keyword')..['windows'] = [{'id': 'giangsinh', 'start': today, 'end': today, 'enabled': true}];
    expect(s.effectFor('giang sinh vui ve nhe'), BurstKind.gifts);
    expect(s.effectFor('MERRY CHRISTMAS'), BurstKind.snow);
    expect(s.effectFor('Họp lúc 3 giờ'), isNull);
    s.mine = {'mode': 'custom', 'effect': false};
    expect(s.effectFor('Merry Christmas'), isNull);
  });

  test('xem thử: chỉ quản trị viên, bất kể ngày và công ty chưa bật', () {
    final nov = DateTime.utc(2026, 11, 17, 3);
    s.org = _org(enabled: false);
    s.mine = {'preview': 'giangsinh'};
    expect(s.activeSeason(nov), isNull); // không phải quản trị viên
    s.org = _org(enabled: false)..['can_admin'] = true;
    expect(s.activeSeason(nov), 'giangsinh');
    expect(s.on('lights', nov), isTrue);
    s.mine = {};
    expect(s.activeSeason(nov), isNull);
  });

  test('nền Trang chủ: theo cài đặt admin (điện thoại / máy tính), cài riêng', () {
    s.clock = () => DateTime.utc(2026, 12, 10, 3);
    expect(s.homeChoice(desktop: false)?.art?.id, 'giangsinh'); // admin chưa đặt: điện thoại theo mùa lễ
    expect(s.homeChoice(desktop: true), isNull); // máy tính: không nền
    (s.org!['cfg'] as Map)['defaults'] = {'home_bg_phone': 'anhden', 'home_bg_desktop': 'plain:0E9F8E'};
    expect(s.homeChoice(desktop: false)?.art?.id, 'anhden');
    expect(s.homeChoice(desktop: true)?.color?.toARGB32(), 0xFF0E9F8E);
    // Lựa chọn riêng chỉ có hiệu lực khi "Cài riêng".
    s.mine = {'home_bg_phone': 'none'};
    expect(s.homeChoice(desktop: false)?.art?.id, 'anhden');
    s.mine = {'mode': 'custom', 'home_bg_phone': 'none'};
    expect(s.homeChoice(desktop: false), isNull);
    s.clock = () => DateTime.utc(2027, 1, 10, 3); // ngoài mùa: "theo mùa lễ" = không nền
    s.mine = {'mode': 'custom', 'home_bg_phone': 'season'};
    expect(s.homeChoice(desktop: false), isNull);
    s.clock = DateTime.now;
  });

  test('theo cài đặt admin: bỏ qua tắt mùa lễ riêng; admin tắt tự đổi giao diện chat', () {
    final dec = DateTime.utc(2026, 12, 10, 3);
    s.mine = {'off': true};
    expect(s.on('lights', dec), isTrue);
    s.mine = {'mode': 'custom', 'off': true};
    expect(s.on('lights', dec), isFalse);
    s.mine = {};
    s.wallpapers = {'c1': 'anhden'};
    expect(s.wallpaperOf('c1'), 'anhden');
    (s.org!['cfg'] as Map)['defaults'] = {'allow_chat_custom': false};
    expect(s.wallpaperOf('c1'), isNull);
  });
}
