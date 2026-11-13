import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/agent_view.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Vòng hạn mức: trong = ngữ cảnh, ngoài = hạn mức tài khoản engine; chú thích có số liệu; màu đổi theo mức dùng.
void main() {
  final now = DateTime(2026, 11, 4, 9, 0);
  int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
  Map<String, dynamic> raw({int five = 12, int week = 40, DateTime? fiveReset}) => {
        'engine': 'codex',
        'at': now.millisecondsSinceEpoch,
        'plan': 'plus',
        'windows': [
          {'id': 'five_hour', 'usedPercent': five, 'windowMins': 300, 'resetsAt': sec(fiveReset ?? DateTime(2026, 11, 4, 13, 5))},
          {'id': 'seven_day', 'usedPercent': week, 'windowMins': 10080, 'resetsAt': sec(DateTime(2026, 11, 9, 8, 30))},
        ],
      };

  Widget wrap(Widget w, {Brightness b = Brightness.light}) =>
      MaterialApp(theme: buildTheme(b), home: Scaffold(body: Center(child: w)));

  CircularProgressIndicator ring(WidgetTester t, String key) =>
      t.widget<CircularProgressIndicator>(find.byKey(ValueKey(key)));

  test('parse limits, max window, stale reset counts as 0', () {
    final l = AgentLimits.parse(raw(five: 97, week: 40))!;
    expect(l.engine, 'codex');
    expect(l.plan, 'plus');
    expect(l.windows.map((w) => w.id), ['five_hour', 'seven_day']);
    expect(l.maxUsed(now), 97);
    // Đã qua lúc đặt lại của cửa sổ 5 giờ: tính 0, cửa sổ tuần thành lớn nhất.
    final stale = AgentLimits.parse(raw(five: 97, week: 40, fiveReset: DateTime(2026, 11, 4, 8)))!;
    expect(stale.maxUsed(now), 40);
    expect(AgentLimits.parse(null), isNull);
    expect(AgentLimits.parse({'engine': 'claude', 'windows': []}), isNull);
    expect(agentLimitLine(l.windows.first, now), 'Phiên 5 giờ: đã dùng 97% · đặt lại lúc 13:05 (04/11)');
    expect(agentLimitLabel(const AgentLimitWindow(id: 'codex_spark:five_hour', label: 'GPT Spark', usedPercent: 1)), 'GPT Spark · Phiên 5 giờ');
    expect(agentLimitLabel(const AgentLimitWindow(id: '60m', usedPercent: 1, windowMins: 60)), 'Cửa sổ 1 giờ');
  });

  test('usage colors: normal, orange > 80%, red > 95%', () {
    const n = Color(0xFF123456);
    expect(usageColor(.5, n), n);
    expect(usageColor(.8, n), n);
    expect(usageColor(.81, n), const Color(0xFFF5A623));
    expect(usageColor(.96, n), const Color(0xFFE5484D));
  });

  testWidgets('two rings side by side: context used and quota used; tap opens details with progress bars', (t) async {
    await t.pumpWidget(wrap(AgentUsageRing(
      ctx: (used: 50000, max: 200000, model: ''),
      limits: AgentLimits.parse(raw(five: 85, week: 40)),
      now: now,
    )));
    expect(find.byKey(const ValueKey('usage-context-ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-limit-ring')), findsOneWidget);
    expect(ring(t, 'usage-context-ring').value, closeTo(.25, 1e-9));
    // Vòng 2: % đã dùng của cửa sổ dùng nhiều nhất (85%), màu cam.
    expect(ring(t, 'usage-limit-ring').value, closeTo(.85, 1e-9));
    expect(ring(t, 'usage-limit-ring').color, const Color(0xFFF5A623));
    expect(find.text('25'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    final tips = [for (final w in t.widgetList<Tooltip>(find.byType(Tooltip))) w.message!];
    expect(tips.first, 'Ngữ cảnh: 50k / 200k token (25%)');
    expect(tips.last, contains('Phiên 5 giờ: đã dùng 85% · đặt lại lúc 13:05 (04/11)'));
    expect(tips.last, contains('Hàng tuần: đã dùng 40% · đặt lại lúc 08:30 (09/11)'));

    // Bấm vòng nào cũng mở hộp chi tiết: thanh tiến độ cho ngữ cảnh và từng cửa sổ hạn mức.
    await t.tap(find.byType(InkWell).last);
    await t.pumpAndSettle();
    expect(find.text('Hạn mức Codex (gói plus)'), findsOneWidget);
    expect(find.text('Hàng tuần: đã dùng 40% · đặt lại lúc 08:30 (09/11)'), findsOneWidget);
    expect(find.text('đã dùng 85%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
  });

  testWidgets('quota ring hidden when unknown; red when near the cap (dark); header always shows both', (t) async {
    await t.pumpWidget(wrap(const AgentUsageRing(ctx: (used: 10000, max: 400000, model: 'gpt-5.5')), b: Brightness.dark));
    expect(find.byKey(const ValueKey('usage-limit-ring')), findsNothing);
    expect(find.byKey(const ValueKey('usage-context-ring')), findsOneWidget);

    await t.pumpWidget(wrap(AgentUsageRing(ctx: null, limits: AgentLimits.parse(raw(five: 99)), now: now), b: Brightness.dark));
    expect(ring(t, 'usage-limit-ring').color, const Color(0xFFE5484D));
    expect(find.text('99'), findsOneWidget);

    await t.pumpWidget(wrap(const AgentUsageRing(ctx: null)));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Đầu chat trợ lý: luôn có hai vòng, chưa có số liệu thì để trống; bấm vẫn mở hộp chi tiết.
    await t.pumpWidget(wrap(const AgentUsageRing(ctx: null, always: true)));
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    await t.tap(find.byType(InkWell).first);
    await t.pumpAndSettle();
    expect(find.text('Chưa có số liệu: trợ lý gửi sau lượt chạy đầu tiên của phiên.'), findsOneWidget);
  });
}
