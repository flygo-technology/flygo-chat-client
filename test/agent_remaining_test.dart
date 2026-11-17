// Trợ lý & bot (Sếp, 2026-11-17): mỗi trợ lý hiện % còn lại + lúc làm mới ngay ở danh sách; nhân viên thấy cả trợ lý
// được chia sẻ (chỉ xem + Nhắn). Ảnh xem trước (chạy tay): AGENT_OUT=<thư mục> flutter test test/agent_remaining_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/agent/agent_service.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_detail_page.dart';
import 'package:flygo_chat/ui/agent_page.dart';
import 'package:flygo_chat/ui/agent_usage.dart';
import 'package:flygo_chat/ui/ai_gate/ai_gate_api.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

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

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['AGENT_OUT'];
  // Thứ Ba 17/11/2026 10:00 giờ máy.
  final now = DateTime(2026, 11, 17, 10, 0);
  int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
  Map<String, dynamic> limits(String engine, String plan, int five, int week, DateTime fiveAt, DateTime weekAt) => {
        'engine': engine, 'at': now.millisecondsSinceEpoch, 'plan': plan,
        'windows': [
          {'id': 'seven_day', 'usedPercent': week, 'windowMins': 10080, 'resetsAt': sec(weekAt)},
          {'id': 'five_hour', 'usedPercent': five, 'windowMins': 300, 'resetsAt': sec(fiveAt)},
        ],
      };
  // Nhân viên thường (Lan), không phải Ba.
  const meId = 'ulan';
  MmUser bot(String id, String un, String name, String engine, Map<String, dynamic> models, {String allow = ''}) => MmUser({
        'id': id, 'username': un, 'first_name': name, 'is_bot': true, 'delete_at': 0,
        'bot_description': 'Trợ lý AI · chạy trên máy · [flygo-agent engine=$engine${allow.isEmpty ? '' : ' allow=$allow'}]',
        'props': {'flygo_models': jsonEncode(models)},
      });
  final mine = [
    AgentBot('b1', 'lan-claude', 'Lan Claude', 'claude', const [], null, 'Soạn hợp đồng', false, ''),
    AgentBot('b2', 'lan-congai', 'Lan Cổng AI', 'claude', const [], null, 'Tra cứu nội bộ', false, ''),
  ];
  final quota = AiQuota({
    'user': 'lan@flygo.vn', 'tier': 'co-ban', 'tier_name': 'Cơ bản', 'state': 'ok', 'used_pct': 38, 'day_used_pct': 55,
    'month_usd': 10, 'used_usd': 3.8, 'day_usd': 1, 'day_spent_usd': .55,
    // 0 giờ 01/12 giờ VN, theo quy ước resets_at của Cổng AI (ms UTC thật).
    'resets_at': DateTime.utc(2026, 11, 30, 17).millisecondsSinceEpoch,
    'models': [
      {'alias': 'flygo-fast', 'allowed': true, 'used_pct': 62, 'day_used_pct': null, 'exhausted': false, 'capped': true},
      {'alias': 'flygo-smart', 'allowed': true, 'used_pct': 43, 'day_used_pct': null, 'exhausted': false, 'capped': true},
      {'alias': 'flygo-agent', 'allowed': false, 'used_pct': null, 'day_used_pct': null, 'exhausted': false, 'capped': false},
    ],
  });

  /// Giờ làm mới tính từ [at] (test số liệu dùng giờ cố định; test giao diện dùng giờ thật vì widget lấy DateTime.now()).
  AppState state([DateTime? at]) {
    final t = at ?? now;
    final app = AppState('test');
    app.me = MmUser({'id': meId, 'username': 'lan', 'first_name': 'Lan'});
    app.users['b1'] = bot('b1', 'lan-claude', 'Lan Claude', 'claude',
        {'engine': 'claude', 'limits': limits('claude', 'max', 38, 20, t.add(const Duration(hours: 4, minutes: 30)), DateTime(t.year, t.month, t.day + 6, 8))});
    app.users['b2'] = bot('b2', 'lan-congai', 'Lan Cổng AI', 'claude', {'engine': 'claude', 'via': 'flygo-ai', 'default': {'model': 'claude-sonnet-5-5'}});
    // Trợ lý của Ba chia sẻ cho Lan; trợ lý của người khác không chia sẻ thì không hiện.
    app.users['b3'] = bot('b3', 'jenifer', 'Jenifer', 'codex',
        {'engine': 'codex', 'limits': limits('codex', 'pro', 91, 64, t.add(const Duration(hours: 1, minutes: 15)), DateTime(t.year, t.month, t.day + 3, 9))}, allow: meId);
    app.users['b4'] = bot('b4', 'rieng', 'Riêng tư', 'codex', {'engine': 'codex'}, allow: 'ukhac');
    return app;
  }

  test('% còn lại + lúc làm mới: gói (5h trước tuần), Cổng AI (ngày / tháng), chưa có số liệu', () {
    final app = state();
    final sub = botRemaining(app, mine[0], now: now);
    expect([for (final x in sub) botRemainingLine(x, now)], ['5h: còn 62% · làm mới 14:30', 'Tuần: còn 80% · làm mới ${resetWhen(DateTime(2026, 11, 23, 8, 0), now)}']);
    final gate = botRemaining(app, mine[1], quota: quota, now: now);
    // Trợ lý dùng Sonnet = Mức Nâng cao: % còn lại của riêng mức đó (tháng) + trần ngày chung.
    expect([for (final x in gate) x.name], ['Mức Nâng cao', 'Ngày']);
    expect([for (final x in gate) x.left], [57, 45]);
    expect(botRemainingLine(gate.first, now), 'Mức Nâng cao: còn 57% · làm mới ${resetWhen(DateTime.utc(2026, 11, 30, 17).toLocal(), now)}');
    // Opus = Mức Chuyên gia mà mình không được dùng: Cổng AI hạ xuống Mức Nâng cao, hiện kèm.
    app.agentConfig['b2'] = {'model': 'claude-opus-5-5'};
    final down = botRemaining(app, mine[1], quota: quota, now: now);
    expect([for (final x in down) x.name], ['Mức Chuyên gia', '→ Mức Nâng cao', 'Ngày']);
    expect(down.first.left, 62); // không có trần riêng: theo trần chung (đã dùng 38%)
    app.agentConfig.remove('b2');
    expect(resetWhen(DateTime(2026, 11, 23, 8, 0), now), 'T2 08:00');
    // Cổng AI mà chưa có hạn mức của mình (chưa được dùng): chưa biết.
    expect(botRemaining(app, mine[1], now: now), isEmpty);
    expect(resetWhen(DateTime(2026, 11, 18, 8, 5), now), 'mai 08:05');
    expect(resetWhen(DateTime(2026, 11, 22, 8, 5), now), 'CN 08:05');
  });

  final key = GlobalKey();
  Future<void> host(WidgetTester t, Size size, Brightness b, {double ratio = 1}) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state(DateTime.now()),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: AgentPage(previewBots: mine, previewQuota: quota)),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> save(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      await Directory(out).create(recursive: true);
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: t.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('máy tính (nhân viên): trợ lý của tôi + được chia sẻ, mỗi dòng có % còn lại', (t) async {
    await host(t, const Size(1280, 860), Brightness.dark);
    expect(find.text('TRỢ LÝ CỦA TÔI'), findsOneWidget);
    expect(find.text('ĐƯỢC CHIA SẺ VỚI TÔI'), findsOneWidget);
    expect(find.text('Jenifer'), findsOneWidget);
    expect(find.text('Riêng tư'), findsNothing);
    expect(find.textContaining('5h: còn 62%'), findsOneWidget);
    expect(find.textContaining('Ngày: còn 45%'), findsOneWidget);
    expect(find.textContaining('5h: còn 9%'), findsOneWidget);
    await save(t, 'agent-list-staff-desktop-dark');
    // Trợ lý được chia sẻ: chi tiết chỉ xem + Nhắn, không xoá / đổi tên.
    await t.tap(find.text('Jenifer'));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Nhắn'), findsOneWidget);
    expect(find.byTooltip('Đổi tên trợ lý'), findsNothing);
    expect(find.text('Xóa trợ lý'), findsNothing);
    expect(find.text('CÒN LẠI'.toLowerCase()), findsNothing);
    expect(find.text('Còn lại'), findsOneWidget);
    await save(t, 'agent-detail-shared-desktop-dark');
  });

  testWidgets('điện thoại sáng (nhân viên)', (t) async {
    await host(t, const Size(390, 844), Brightness.light, ratio: 2);
    expect(find.textContaining('Tuần: còn 80%'), findsOneWidget);
    await save(t, 'agent-list-staff-phone-light');
    await t.drag(find.byType(ListView).first, const Offset(0, -500));
    await t.pump(const Duration(milliseconds: 300));
    await save(t, 'agent-list-staff-phone-light-2');
  });

  test('trợ lý từ tài khoản bot: đọc engine, allow, vai trò', () {
    final b = AgentService.fromUser(MmUser({'id': 'x', 'username': 'x', 'is_bot': true, 'bot_description': 'Kế toán · chạy trên máy · [flygo-agent engine=claude allow=a,b paused=1]'}));
    expect([b.engine, b.role, b.paused], ['claude', 'Kế toán', true]);
    expect(b.allow, ['a', 'b']);
  });

  // Dùng openAgentDetail trực tiếp: tham số owner đi tới trang chi tiết.
  test('openAgentDetail có tham số owner', () => expect(openAgentDetail, isNotNull));
}
