// Chi tiết trợ lý (Sếp, 2026-11-17): máy tính mở hộp thoại, điện thoại mở trang; mục Mức sử dụng của trợ lý.
// Ảnh xem trước (chạy tay): AGENT_OUT=<thư mục> flutter test test/agent_detail_usage_test.dart
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
  final now = DateTime.now();
  final bot = AgentBot('b1', 'jessica', 'Jessica', 'claude', const [], null, 'Kế toán, hoá đơn', false, '');
  final quota = AiQuota({
    'user': 'ba@flygo.vn', 'tier': 'co-ban', 'tier_name': 'Cơ bản', 'state': 'ok', 'used_pct': 62, 'day_used_pct': 30,
    'month_usd': 10, 'used_usd': 6.2, 'day_usd': 1, 'day_spent_usd': .3,
  });
  final usage = {
    'day': {'rows': [{'k': 'bot:jessica', 'n': 14, 'tok_in': 820000, 'tok_out': 41000, 'usd': .25}]},
    'month': {'rows': [{'k': 'vn.flygo.dich', 'n': 3, 'tok_in': 1000, 'tok_out': 500, 'usd': .01}, {'k': 'bot:jessica', 'n': 210, 'tok_in': 9100000, 'tok_out': 380000, 'usd': 3.1}]},
  };

  AppState state() {
    final app = AppState('test');
    final sec = now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000;
    MmPost run(String id, String ch, int at, int tokens) => MmPost({
          'id': id, 'channel_id': ch, 'user_id': 'b1', 'create_at': at, 'message': '',
          'props': {
            'flygo_agent': {
              'engine': 'claude',
              'config': {'model': 'claude-opus-5-5'},
              'usage': {
                'contextTokens': tokens, 'contextWindow': 200000,
                'limits': {
                  'engine': 'claude', 'at': now.millisecondsSinceEpoch, 'plan': 'max',
                  'windows': [
                    {'id': 'five_hour', 'usedPercent': 46, 'windowMins': 300, 'resetsAt': sec},
                    {'id': 'seven_day', 'usedPercent': 83, 'windowMins': 10080, 'resetsAt': sec + 3 * 86400},
                  ],
                },
              },
            },
          },
        });
    app.channels['c1'] = MmChannel({'id': 'c1', 'type': 'P', 'display_name': 'AI · Kế toán · Hoá đơn tháng 11', 'name': 'c1'});
    app.channels['c2'] = MmChannel({'id': 'c2', 'type': 'P', 'display_name': 'AI · Kế toán · Đối soát ngân hàng', 'name': 'c2'});
    app.debugPutPosts('c1', [run('p1', 'c1', now.millisecondsSinceEpoch, 128000)]);
    app.debugPutPosts('c2', [run('p2', 'c2', now.millisecondsSinceEpoch - 3600000, 186000)]);
    return app;
  }

  final key = GlobalKey();
  Future<void> host(WidgetTester t, Size size, Brightness b, {double ratio = 1}) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: FilledButton(onPressed: () => openAgentDetail(c, bot, previewQuota: quota, previewUsage: usage), child: const Text('mở')),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    for (var i = 0; i < 6; i++) {
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

  testWidgets('máy tính: chi tiết trợ lý là hộp thoại có nút đóng, có Mức sử dụng của trợ lý', (t) async {
    await host(t, const Size(1440, 900), Brightness.dark);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byTooltip('Đóng'), findsOneWidget);
    expect(find.text('MỨC SỬ DỤNG'), findsOneWidget);
    expect(find.text('Ngữ cảnh phiên gần đây'), findsOneWidget);
    // Phiên mới nhất trước.
    final a = t.getTopLeft(find.text('AI · Kế toán · Hoá đơn tháng 11')).dy, b = t.getTopLeft(find.text('AI · Kế toán · Đối soát ngân hàng')).dy;
    expect(a, lessThan(b));
    expect(find.text('128k / 200k token'), findsOneWidget);
    expect(find.text('Hạn mức gói max'), findsOneWidget);
    expect(find.text('đã dùng 83%'), findsOneWidget);
    // AI công ty: % hạn mức của mình, không hiện tiền.
    expect(find.text('31% hạn mức tháng'), findsOneWidget);
    expect(find.text('25% hạn mức ngày'), findsOneWidget);
    expect(find.text('210 lượt · 9.1M vào / 380k ra'), findsOneWidget);
    expect(find.textContaining('\$'), findsNothing);
    await save(t, 'agent-detail-dialog-desktop-dark');
    await t.drag(find.descendant(of: find.byType(Dialog), matching: find.byType(ListView)).first, const Offset(0, -700));
    await t.pump(const Duration(milliseconds: 300));
    await save(t, 'agent-detail-dialog-desktop-dark-2');
    await t.tap(find.byTooltip('Đóng'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('máy tính sáng', (t) async {
    await host(t, const Size(1440, 900), Brightness.light);
    expect(find.byType(Dialog), findsOneWidget);
    await save(t, 'agent-detail-dialog-desktop-light');
  });

  testWidgets('điện thoại: chi tiết trợ lý là trang mới (có nút quay lại), không phải hộp thoại', (t) async {
    await host(t, const Size(390, 844), Brightness.light, ratio: 2);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await save(t, 'agent-detail-page-phone-light');
    await t.drag(find.byType(ListView).last, const Offset(0, -420));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Hạn mức gói max'), findsOneWidget);
    await save(t, 'agent-detail-page-phone-light-usage');
  });

  test('dòng Cổng AI của trợ lý: khớp theo id / bot:username; không có thì null', () {
    expect(aiUsageRowOf(usage, 'month', bot)?['n'], 210);
    expect(aiUsageRowOf(usage, 'day', AgentBot('b9', 'other', 'Other', 'codex')), isNull);
    expect(aiUsageRowOf(null, 'day', bot), isNull);
  });
}
