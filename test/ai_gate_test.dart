// Cổng AI: quản trị native + Hạn mức AI. Ảnh xem trước (chạy tay): AI_OUT=<thư mục> flutter test test/ai_gate_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/ai_gate/ai_admin_page.dart';
import 'package:flygo_chat/ui/ai_gate/ai_gate_api.dart';
import 'package:flygo_chat/ui/ai_gate/ai_quota_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Map<String, dynamic> _user(String u, String tier, String name, int pct, int day, String state, {double dayUsd = 0.6, double month = 3, double? cDay, bool access = true}) => {
      'user': u, 'tier': tier, 'tier_name': name, 'state': state, 'used_pct': pct, 'day_used_pct': day, 'month_usd': month, 'used_usd': month * pct / 100,
      'day_usd': dayUsd, 'day_spent_usd': dayUsd * day / 100, 'smart_left': tier == 'co-ban' ? 12 : null, 'resets_at': 1796058000000, 'blocked': state == 'blocked',
      'access': access, 'extra_usd': 0, 'custom': {'tier': null, 'day_usd': cDay, 'month_usd': null},
    };

/// Máy chủ Cổng AI giả: ghi lại các lời gọi.
class FakeGate {
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  late final client = MockClient((r) async {
    calls.add('${r.method} ${r.url.path}');
    expect(r.headers['authorization'], 'Bearer T');
    if (r.body.isNotEmpty) bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
    final p = r.url.path.replaceFirst('/__apps/ai', '');
    final j = switch (p) {
      '/api/me/quota' => _user('lan@flygo.vn', 'co-ban', 'Cơ bản', 62, 30, 'ok'),
      '/admin/api/overview' => {
          'company': 'Flygo', 'month': '2026-11', 'month_usd': 40, 'spent_usd': 21.4, 'used_pct': 54, 'day_usd': 8, 'today_usd': 1.2, 'forecast_usd': 32.1,
          'access': 16, 'users_active': 14, 'users_warn': 2, 'users_degraded': 1, 'users_blocked': 0,
          'by_day': [for (var i = 1; i <= 17; i++) {'k': '2026-11-${i.toString().padLeft(2, '0')}', 'n': 40 + i, 'usd': [0.9, 1.4, .4, .3, 1.8, 1.7, 1.6][i % 7]}],
        },
      '/admin/api/users' => [
          _user('ba@flygo.vn', 'chuyen-sau', 'Chuyên sâu', 28, 10, 'ok', dayUsd: 6, month: 30),
          _user('hung@flygo.vn', 'nang-cao', 'Nâng cao', 86, 40, 'warn', dayUsd: 2, month: 10),
          _user('lan@flygo.vn', 'co-ban', 'Cơ bản', 62, 30, 'ok', dayUsd: 0.5, cDay: 0.5),
          _user('nam@flygo.vn', 'co-ban', 'Cơ bản', 104, 70, 'degraded'),
          _user('my@flygo.vn', 'co-ban', 'Cơ bản', 0, 0, 'ok', access: false),
        ],
      '/admin/api/tiers' => {
          'default_tier': 'co-ban',
          'tiers': {
            'co-ban': {'name': 'Cơ bản', 'month_usd': 3, 'day_usd': 0.6, 'aliases': ['flygo-fast', 'flygo-smart'], 'smart_per_month': 30},
            'nang-cao': {'name': 'Nâng cao', 'month_usd': 10, 'day_usd': 2, 'aliases': ['flygo-fast', 'flygo-smart']},
            'chuyen-sau': {'name': 'Chuyên sâu', 'month_usd': 30, 'day_usd': 6, 'aliases': ['flygo-fast', 'flygo-smart', 'flygo-agent']},
          },
          'aliases': {'flygo-fast': 'claude-haiku-5-5', 'flygo-smart': 'claude-sonnet-5-5', 'flygo-agent': 'claude-opus-5-5'},
        },
      '/admin/api/extras' => [
          {'id': 3, 'scope': 'user', 'target': 'hung@flygo.vn', 'usd': 5, 'until': 1795971600000, 'reason': 'Hồ sơ thầu Vinhomes', 'by': 'ba@flygo.vn'},
        ],
      '/admin/api/log' => [
          {'ts': 1794896000000, 'by': 'ba@flygo.vn', 'action': 'override.add', 'detail': {'target': 'hung@flygo.vn', 'usd': 5}},
          {'ts': 1794890000000, 'by': 'ba@flygo.vn (qua agent:jessica)', 'action': 'user.set', 'detail': {'user': 'lan@flygo.vn', 'day_usd': 0.5}},
        ],
      '/admin/api/user' => _user('lan@flygo.vn', 'nang-cao', 'Nâng cao', 62, 30, 'ok', dayUsd: 0.8, cDay: 0.8),
      _ => {'ok': true},
    };
    return http.Response.bytes(utf8.encode(jsonEncode(j)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  late final api = AiGateApi(base: 'https://chat.test/__apps/ai', ticket: () async => 'T', client: client);
}

void main() {
  final out = Platform.environment['AI_OUT'];
  final key = GlobalKey();

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> save(WidgetTester t, String name) async {
    if (out == null) return;
    await settle(t);
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: t.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  // Chuyển tab bằng TabController: khung điện thoại hẹp (nhất là font test Ahem khi không nạp font) đẩy tab ra ngoài màn hình.
  Future<void> tab(WidgetTester t, int i) async {
    DefaultTabController.of(t.element(find.byType(TabBarView))).animateTo(i);
    await settle(t);
  }

  Future<void> app(WidgetTester t, Size size, Brightness b, Widget home, {double ratio = 1}) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
  }

  testWidgets('quản trị: tổng quan, người dùng, sửa trần ngày (máy tính)', (t) async {
    final g = FakeGate();
    await app(t, const Size(1280, 860), Brightness.dark, AiAdminPage(api: g.api));
    expect(find.text('Cổng AI'), findsOneWidget);
    expect(find.text('21.40 USD'), findsOneWidget);
    await save(t, 'ai-admin-desktop-1-overview');
    await tab(t, 1); // Người dùng
    expect(find.text('hung@flygo.vn'), findsOneWidget);
    expect(find.text('Sắp hết'), findsOneWidget);
    await save(t, 'ai-admin-desktop-2-users');
    await t.tap(find.text('lan@flygo.vn'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Trần ngày (USD)'), '0.8');
    await save(t, 'ai-admin-desktop-3-edit-user');
    await t.tap(find.text('Lưu').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    expect(g.calls, contains('PUT /__apps/ai/admin/api/user'));
    expect(g.bodies.last, containsPair('day_usd', 0.8));
    expect(g.bodies.last, containsPair('user', 'lan@flygo.vn'));
  });

  testWidgets('quản trị: hạng & ngân sách, cộng thêm, nhật ký (điện thoại)', (t) async {
    final g = FakeGate();
    await app(t, const Size(390, 844), Brightness.dark, AiAdminPage(api: g.api), ratio: 2);
    await save(t, 'ai-admin-phone-1-overview');
    await tab(t, 1); // Người dùng
    await save(t, 'ai-admin-phone-2-users');
    await tab(t, 2); // Hạng & ngân sách
    expect(find.text('Chuyên sâu'), findsOneWidget);
    await save(t, 'ai-admin-phone-3-tiers');
    await tab(t, 3); // Cộng thêm
    expect(find.text('hung@flygo.vn'), findsOneWidget);
    await save(t, 'ai-admin-phone-4-extras');
    await tab(t, 4); // Nhật ký
    expect(find.text('Đổi hạn mức người dùng'), findsOneWidget);
    await save(t, 'ai-admin-phone-5-log');
  });

  testWidgets('Hạn mức AI của mình (điện thoại, sáng + tối)', (t) async {
    for (final b in [Brightness.dark, Brightness.light]) {
      final g = FakeGate();
      await app(t, const Size(390, 844), b, AiQuotaPage(api: g.api), ratio: 2);
      expect(find.text('62%'), findsWidgets);
      expect(find.textContaining('Hạng Cơ bản'), findsOneWidget);
      expect(find.textContaining('USD'), findsNothing); // nhân viên không thấy tiền
      await save(t, 'ai-quota-phone-${b.name}');
    }
  });

  test('lỗi máy chủ đọc được', () async {
    final api = AiGateApi(base: 'https://x', ticket: () async => 'T',
        client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode({'error': 'bạn chưa là quản trị Cổng AI'})), 403)));
    expect(() => api.overview(), throwsA(isA<AiGateException>().having((e) => e.message, 'message', contains('chưa là quản trị'))));
  });
}
