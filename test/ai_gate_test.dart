// Cổng AI: quản trị native + Hạn mức AI. Ảnh xem trước (chạy tay): AI_OUT=<thư mục> flutter test test/ai_gate_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/agent/agent_service.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_page.dart';
import 'package:flygo_chat/ui/ai_gate/ai_admin_page.dart';
import 'package:provider/provider.dart';
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

/// Từng model theo hạng (mẫu Sếp duyệt) + chỉnh riêng (cSmart = trần Nâng cao riêng).
List<Map<String, dynamic>> _models(String tier, int pct, {double? cSmart}) {
  final caps = switch (tier) { 'chuyen-sau' => [10.0, 15.0, 10.0], 'nang-cao' => [5.0, 5.0, null], _ => [3.0, null, null] };
  final ids = ['flygo-fast', 'flygo-smart', 'flygo-agent'];
  return [
    for (final (i, a) in ids.indexed)
      {
        'alias': a, 'allowed': caps[i] != null || (a == 'flygo-smart' && cSmart != null), 'custom': a == 'flygo-smart' && cSmart != null,
        'month_cap': a == 'flygo-smart' && cSmart != null ? cSmart : caps[i], 'used_usd': 1.0,
        'used_pct': caps[i] == null && !(a == 'flygo-smart' && cSmart != null) ? null : (i == 0 ? pct : (pct * .7).round()), 'day_cap': null, 'day_used_pct': null,
        'exhausted': i == 0 && pct >= 100,
      },
  ];
}

Map<String, dynamic> _user(String u, String tier, String name, int pct, int day, String state, {double dayUsd = 0.6, double month = 3, double? cDay, bool access = true, double? cSmart}) => {
      'models': _models(tier, pct, cSmart: cSmart), 'dept': u.startsWith('lan') || u.startsWith('my') ? 'ke-toan' : '',
      'user': u, 'tier': tier, 'tier_name': name, 'state': state, 'used_pct': pct, 'day_used_pct': day, 'month_usd': month, 'used_usd': month * pct / 100,
      'day_usd': dayUsd, 'day_spent_usd': dayUsd * day / 100, 'smart_left': tier == 'co-ban' ? 12 : null, 'resets_at': 1796058000000, 'blocked': state == 'blocked',
      'access': access, 'extra_usd': 0, 'custom': {'tier': null, 'day_usd': cDay, 'month_usd': null, 'models': cSmart == null ? {} : {'flygo-smart': {'enabled': true, 'month_usd': cSmart}}},
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
          'top_apps': [{'k': 'bot:ba-congai', 'n': 400, 'usd': 12.8}, {'k': 'vn.flygo.mail', 'n': 300, 'usd': 4.1}, {'k': 'vn.flygo.dich', 'n': 200, 'usd': 2.3}],
          'by_day': [for (var i = 1; i <= 17; i++) {'k': '2026-11-${i.toString().padLeft(2, '0')}', 'n': 40 + i, 'usd': [0.9, 1.4, .4, .3, 1.8, 1.7, 1.6][i % 7]}],
        },
      '/admin/api/users' => [
          _user('ba@flygo.vn', 'chuyen-sau', 'Chuyên sâu', 28, 10, 'ok', dayUsd: 6, month: 30),
          _user('hung@flygo.vn', 'nang-cao', 'Nâng cao', 86, 40, 'warn', dayUsd: 2, month: 10),
          _user('lan@flygo.vn', 'co-ban', 'Cơ bản', 62, 30, 'ok', dayUsd: 0.5, cDay: 0.5, cSmart: 20),
          _user('nam@flygo.vn', 'co-ban', 'Cơ bản', 104, 70, 'degraded'),
          _user('my@flygo.vn', 'co-ban', 'Cơ bản', 0, 0, 'ok', access: false),
        ],
      '/admin/api/tiers' => {
          'default_tier': 'co-ban',
          'tiers': {
            'co-ban': {'name': 'Cơ bản', 'month_usd': 3, 'day_usd': 0.6, 'aliases': ['flygo-fast'], 'models': {'flygo-fast': {'month_usd': 3}}},
            'nang-cao': {'name': 'Nâng cao', 'month_usd': 10, 'day_usd': 2, 'aliases': ['flygo-fast', 'flygo-smart'], 'models': {'flygo-fast': {'month_usd': 5}, 'flygo-smart': {'month_usd': 5}}},
            'chuyen-sau': {'name': 'Chuyên sâu', 'month_usd': 35, 'day_usd': 7, 'aliases': ['flygo-fast', 'flygo-smart', 'flygo-agent'],
              'models': {'flygo-fast': {'month_usd': 10}, 'flygo-smart': {'month_usd': 15}, 'flygo-agent': {'month_usd': 10}}},
          },
          'ladder': ['flygo-agent', 'flygo-smart', 'flygo-fast'],
          'aliases': {'flygo-fast': 'claude-haiku-5-5', 'flygo-smart': 'claude-sonnet-5-5', 'flygo-agent': 'claude-opus-5-5'},
        },
      '/admin/api/extras' => [
          {'id': 3, 'scope': 'user', 'target': 'hung@flygo.vn', 'usd': 5, 'until': 1795971600000, 'reason': 'Hồ sơ thầu Vinhomes', 'by': 'ba@flygo.vn'},
        ],
      '/admin/api/log' => [
          {'ts': 1794896000000, 'by': 'ba@flygo.vn', 'action': 'override.add', 'detail': {'target': 'hung@flygo.vn', 'usd': 5}},
          {'ts': 1794890000000, 'by': 'ba@flygo.vn (qua agent:jessica)', 'action': 'user.set', 'detail': {'user': 'lan@flygo.vn', 'day_usd': 0.5}},
        ],
      '/admin/api/providers' => [
          {'id': 'anthropic', 'name': 'Anthropic', 'kind': 'anthropic', 'enabled': 1, 'sensitive_ok': 1, 'has_key': true, 'key_last4': 'KgAA', 'key_added_by': 'ba@flygo.vn',
            'test_at': 1, 'test_ok': 1, 'test_msg': 'OK, 14 model', 'month_cap_usd': 30, 'month_usd': 18.3, 'preset': true},
          {'id': 'openai', 'name': 'OpenAI', 'kind': 'openai', 'enabled': 1, 'sensitive_ok': 1, 'has_key': true, 'key_last4': '3fQa', 'key_added_by': 'ba@flygo.vn',
            'test_at': 1, 'test_ok': 1, 'test_msg': 'OK, 52 model', 'month_cap_usd': 10, 'month_usd': 0.4, 'preset': true},
          {'id': 'gemini', 'name': 'Google Gemini', 'kind': 'openai', 'enabled': 0, 'sensitive_ok': 1, 'has_key': false, 'preset': true, 'note': 'Chỉ dùng gói trả tiền'},
          {'id': 'deepseek', 'name': 'DeepSeek', 'kind': 'openai', 'enabled': 0, 'sensitive_ok': 0, 'has_key': false, 'preset': true, 'note': 'Máy chủ ở Trung Quốc'},
        ],
      '/admin/api/aliases' => [
          {'id': 'flygo-fast', 'provider': 'anthropic', 'model': 'claude-haiku-5-5', 'max_tokens': 8192, 'chain': [{'provider': 'openai', 'model': 'gpt-6-luna'}], 'allow_insensitive': false},
          {'id': 'flygo-smart', 'provider': 'anthropic', 'model': 'claude-sonnet-5-5', 'max_tokens': 16384, 'chain': [{'provider': 'openai', 'model': 'gpt-6.1-terra'}], 'allow_insensitive': false},
          {'id': 'flygo-agent', 'provider': 'anthropic', 'model': 'claude-opus-5-5', 'max_tokens': 32000, 'chain': [], 'allow_insensitive': false},
        ],
      '/admin/api/providers/anthropic/models' => {'models': ['claude-haiku-5-5', 'claude-sonnet-5-5', 'claude-opus-5-5']},
      '/admin/api/providers/openai/models' => {'models': ['gpt-6-luna', 'gpt-6.1-terra']},
      '/admin/api/providers/gemini/key' => {'test': {'ok': true, 'ms': 300, 'msg': 'OK'}, 'models': []},
      '/admin/api/users/bulk' => {'count': 2, 'users': ['lan@flygo.vn', 'my@flygo.vn']},
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

  Future<void> app(WidgetTester t, Size size, Brightness b, Widget home, {double ratio = 1}) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
  }

  testWidgets('quản trị một màn hình (máy tính, tối + sáng): đủ mục, sửa trần ngày', (t) async {
    for (final b in [Brightness.dark, Brightness.light]) {
      final g = FakeGate();
      await app(t, const Size(1440, 1180), b, AiAdminPage(api: g.api));
      expect(find.text('Cổng AI'), findsOneWidget);
      for (final k in ['ai-chart', 'ai-users', 'ai-providers', 'ai-tiers', 'ai-aliases', 'ai-extras', 'ai-log']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.text('hung@flygo.vn'), findsWidgets);
      expect(find.text('Trợ lý @ba-congai'), findsOneWidget);
      expect(find.textContaining('KgAA'), findsOneWidget);
      // lưới: người dùng và nhà cung cấp cùng hàng (máy tính)
      expect((t.getTopLeft(find.byKey(const ValueKey('ai-users'))).dy - t.getTopLeft(find.byKey(const ValueKey('ai-providers'))).dy).abs(), lessThan(1));
      await save(t, 'ai-dashboard-desktop-${b.name}');
    }
    final g = FakeGate();
    await app(t, const Size(1440, 1180), Brightness.dark, AiAdminPage(api: g.api));
    await t.ensureVisible(find.text('lan@flygo.vn'));
    await settle(t);
    await t.tap(find.text('lan@flygo.vn'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Tổng / ngày (USD)'), '0.8');
    await t.ensureVisible(find.text('Lưu').last);
    await t.tap(find.text('Lưu').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    expect(g.calls, contains('PUT /__apps/ai/admin/api/user'));
    expect(g.bodies.last, containsPair('day_usd', 0.8));
    expect(g.bodies.last, containsPair('user', 'lan@flygo.vn'));
  });

  testWidgets('nhà cung cấp: thêm khoá (chỉ nhập), mức AI: sửa chuỗi dự phòng', (t) async {
    final g = FakeGate();
    await app(t, const Size(1440, 1180), Brightness.dark, AiAdminPage(api: g.api));
    final addKey = find.descendant(of: find.byKey(const ValueKey('ai-providers')), matching: find.text('Thêm khoá')).first;
    await t.ensureVisible(addKey);
    await settle(t);
    await t.tap(addKey);
    await settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Khoá API (sau khi lưu không xem lại được)'), 'AIzaSy-test-key-1234');
    await save(t, 'ai-dashboard-provider-key');
    await t.tap(find.text('Lưu và kiểm tra'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    expect(g.calls, contains('PUT /__apps/ai/admin/api/providers/gemini/key'));
    expect(g.bodies.last, containsPair('key', 'AIzaSy-test-key-1234'));
    expect(find.textContaining('AIzaSy'), findsNothing); // khoá không hiện lại ở đâu
    await t.ensureVisible(find.text('Mức Cơ bản · flygo-fast'));
    await settle(t);
    await t.tap(find.text('Mức Cơ bản · flygo-fast'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    expect(find.text('Dự phòng 1'), findsOneWidget);
    await save(t, 'ai-dashboard-alias-edit');
    await t.tap(find.text('Lưu mức AI'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    expect(g.calls, contains('PUT /__apps/ai/admin/api/aliases/flygo-fast'));
    expect(g.bodies.last['chain'], [{'provider': 'openai', 'model': 'gpt-6-luna'}]);
  });

  testWidgets('hạn mức từng model: cột trong bảng, chỉnh riêng một người, sửa hàng loạt', (t) async {
    final g = FakeGate();
    await app(t, const Size(1440, 1180), Brightness.dark, AiAdminPage(api: g.api));
    expect(find.descendant(of: find.byKey(const ValueKey('ai-users')), matching: find.text('Mức Nâng cao')), findsWidgets);
    expect(find.textContaining('20\$'), findsWidgets); expect(find.byKey(const ValueKey('custom-flygo-smart')), findsOneWidget); // lan: Nâng cao riêng 20$
    await t.ensureVisible(find.text('lan@flygo.vn'));
    await settle(t);
    await t.tap(find.text('lan@flygo.vn'));
    await settle(t);
    expect(find.byKey(const ValueKey('model-flygo-agent')), findsOneWidget);
    expect(find.text('riêng'), findsWidgets);
    await save(t, 'ai-models-user-detail');
    // bật Agent cho lan, trần tháng 4$
    await t.tap(find.descendant(of: find.byKey(const ValueKey('model-flygo-agent')), matching: find.byType(Switch)));
    await settle(t);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('model-flygo-agent')), matching: find.widgetWithText(TextField, 'Trần tháng (USD)')), '4');
    await t.ensureVisible(find.text('Lưu').last);
    await t.tap(find.text('Lưu').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    final body = g.bodies.last;
    expect(body['user'], 'lan@flygo.vn');
    expect((body['models'] as Map)['flygo-agent'], {'enabled': true, 'month_usd': 4.0, 'day_usd': null});
    expect((body['models'] as Map)['flygo-smart'], {'enabled': true, 'month_usd': 20.0, 'day_usd': null}); // giữ chỉnh riêng cũ
    expect((body['models'] as Map)['flygo-fast'], isNull); // theo hạng
    // sửa hàng loạt: phòng Kế toán → Nâng cao, Nâng cao 20$
    await t.ensureVisible(find.text('Sửa hàng loạt'));
    await settle(t);
    await t.tap(find.text('Sửa hàng loạt'));
    await settle(t);
    await t.tap(find.text('Theo phòng ban'));
    await settle(t);
    await save(t, 'ai-models-bulk');
    await t.tap(find.textContaining('Áp cho'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(t);
    expect(g.calls, contains('POST /__apps/ai/admin/api/users/bulk'));
    expect(g.bodies.last['filter'], {'dept': 'ke-toan'});
  });

  for (final (name, size, b) in [
    ('desktop-dark', const Size(1440, 1180), Brightness.dark),
    ('desktop-light', const Size(1440, 1180), Brightness.light),
    ('phone-dark', const Size(390, 844), Brightness.dark),
    ('phone-light', const Size(390, 844), Brightness.light),
  ]) {
    testWidgets('hạng & ngân sách gọn ($name): bảng nhãn, không ô nhập, sửa qua hộp thoại', (t) async {
      final g = FakeGate();
      await app(t, size, b, AiAdminPage(api: g.api), ratio: size.width < 600 ? 2 : 1);
      final card = find.byKey(const ValueKey('ai-tiers'));
      await t.ensureVisible(card);
      await settle(t);
      expect(find.descendant(of: card, matching: find.byType(TextField)), findsNothing);
      expect(find.descendant(of: card, matching: find.textContaining('Ngân sách công ty')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('10 \$/th')), findsWidgets); // tier Chuyên sâu: Cơ bản 10, Chuyên gia 10
      expect(find.descendant(of: card, matching: find.text('—')), findsWidgets);          // tier Cơ bản: no Nâng cao/Chuyên gia
      await save(t, 'ai-tiers-$name');
      if (name != 'desktop-dark') return;
      // sửa hạng Cơ bản: bật Nâng cao 2$/tháng
      await t.tap(find.byKey(const ValueKey('tier-co-ban')));
      await settle(t);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('tier-model-flygo-smart')), matching: find.byType(Switch)));
      await settle(t);
      await save(t, 'ai-tiers-edit');
      await t.enterText(find.widgetWithText(TextField, 'Trần tháng (USD)').at(1), '2');
      await t.tap(find.text('Lưu hạng'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(t);
      expect(g.calls, contains('PUT /__apps/ai/admin/api/tiers/co-ban'));
      final body = g.bodies.last;
      expect(body['aliases'], ['flygo-fast', 'flygo-smart']);
      expect((body['models'] as Map)['flygo-smart'], {'month_usd': 2.0, 'day_usd': null});
      // ngân sách công ty qua hộp thoại nhỏ
      await t.tap(find.byKey(const ValueKey('company-budget')));
      await settle(t);
      await save(t, 'ai-company-edit');
      await t.enterText(find.widgetWithText(TextField, 'Trần tháng (USD)'), '50');
      await t.tap(find.text('Lưu').last);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(t);
      expect(g.calls, contains('PUT /__apps/ai/admin/api/company'));
      expect(g.bodies.last['month_usd'], 50.0);
    });
  }

  testWidgets('quản trị trên điện thoại: một cột cuộn dọc, bảng thành thẻ', (t) async {
    for (final b in [Brightness.dark, Brightness.light]) {
      final g = FakeGate();
      await app(t, const Size(390, 2700), b, AiAdminPage(api: g.api), ratio: 2);
      expect(find.byKey(const ValueKey('ai-phone-budget')), findsOneWidget);
      final x = t.getTopLeft(find.byKey(const ValueKey('ai-users'))).dx;
      expect(t.getTopLeft(find.byKey(const ValueKey('ai-providers'))).dx, x); // xếp dọc
      expect(t.getTopLeft(find.byKey(const ValueKey('ai-providers'))).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey('ai-users'))).dy));
      await save(t, 'ai-dashboard-phone-${b.name}');
    }
  });

  testWidgets('Hạn mức AI của mình (điện thoại, sáng + tối)', (t) async {
    for (final b in [Brightness.dark, Brightness.light]) {
      final g = FakeGate();
      await app(t, const Size(390, 844), b, AiQuotaPage(api: g.api), ratio: 2);
      expect(find.text('62%'), findsWidgets);
      expect(find.textContaining('Hạng Cơ bản'), findsOneWidget);
      expect(find.textContaining('USD'), findsNothing); // nhân viên không thấy tiền
      expect(find.textContaining('còn'), findsWidgets);   // "Cơ bản: 62% · còn 38%"
      await save(t, 'ai-quota-phone-${b.name}');
    }
  });

  // Trang Trợ lý gộp dung lượng AI (Sếp 2026-11-17): máy tính 2 cột (trái trợ lý, phải dung lượng), điện thoại thẻ gọn ở trên.
  final bots = [
    AgentBot('b1', 'jessica', 'Jessica', 'claude', const [], null, 'Kế toán, hoá đơn', false, ''),
    AgentBot('b2', 'jenifer', 'Jenifer', 'codex', const [], null, '', false, ''),
  ];
  final quota = AiQuota(_user('ba@flygo.vn', 'co-ban', 'Cơ bản', 62, 30, 'ok'));
  Widget agent({AiQuota? q}) => ChangeNotifierProvider<AppState>.value(value: AppState('test'), child: AgentPage(previewBots: bots, previewQuota: q));

  testWidgets('Trợ lý + dung lượng AI: máy tính 2 cột', (t) async {
    await app(t, const Size(1280, 820), Brightness.dark, agent(q: quota));
    expect(find.text('Dung lượng AI công ty'), findsOneWidget);
    expect(find.text('Jessica'), findsOneWidget);
    expect(find.textContaining('USD'), findsNothing);
    final left = t.getTopLeft(find.text('Jessica')).dx, right = t.getTopLeft(find.text('Dung lượng AI công ty')).dx;
    expect(right, greaterThan(left + 400));
    await save(t, 'agent-usage-desktop');
  });

  testWidgets('Trợ lý + dung lượng AI: điện thoại thẻ gọn ở trên; không có Cổng AI thì không hiện', (t) async {
    await app(t, const Size(390, 844), Brightness.dark, agent(q: quota), ratio: 2);
    final card = t.getTopLeft(find.text('Dung lượng AI công ty')).dy, bot = t.getTopLeft(find.text('Jessica')).dy;
    expect(card, lessThan(bot));
    await save(t, 'agent-usage-phone');
    await app(t, const Size(390, 844), Brightness.dark, agent());
    expect(find.text('Dung lượng AI công ty'), findsNothing);
    expect(find.text('Dữ liệu gửi cho AI'), findsOneWidget);
  });

  test('lỗi máy chủ đọc được', () async {
    final api = AiGateApi(base: 'https://x', ticket: () async => 'T',
        client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode({'error': 'bạn chưa là quản trị Cổng AI'})), 403)));
    expect(() => api.overview(), throwsA(isA<AiGateException>().having((e) => e.message, 'message', contains('chưa là quản trị'))));
  });
}
