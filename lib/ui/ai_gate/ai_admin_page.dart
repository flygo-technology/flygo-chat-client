// Quản trị "Cổng AI" (native, mục Quản trị): MỘT màn hình (Sếp 2026-11-17: "gộp các tab thành 1 màn hình full to ở PC,
// cuộn dọc ở mobile"). Máy tính: lưới 12 cột dùng hết bề ngang; điện thoại: các mục xếp dọc, bảng thành thẻ.
// Mục: số liệu tháng/hôm nay/dự báo/cảnh báo · chi phí theo ngày · theo ứng dụng · người dùng · nhà cung cấp (khoá chỉ nhập) ·
// hạng & ngân sách · mức AI & model (chuỗi dự phòng) · cộng thêm · nhật ký. Trang web <chat>/__apps/ai/admin giữ làm dự phòng.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_shell.dart';
import '../theme.dart';
import 'ai_gate_api.dart';

Future<void> openAiAdmin(BuildContext context) async {
  final state = context.read<AppState>();
  final host = AppHost.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final api = await AiGateApi.current(state.token);
    if (api == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    await host.open(key: 'admin:ai', title: tr('Quản trị Cổng AI'), builder: (_) => AiAdminPage(api: api));
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

const kAiRate = 26000; // đ / USD, chỉ để hiển thị

String usdText(double v) => '${v.toStringAsFixed(v >= 1 ? 2 : 4)} USD';
String vndText(double v) {
  final s = (v * kAiRate).round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b đ';
}

/// Màu theo % đã dùng: xanh < 80, vàng < 100, đỏ từ 100.
Color usageColor(Pal pal, int pct) => pct >= 100 ? const Color(0xFFFF6B6B) : pct >= 80 ? const Color(0xFFF5B544) : pal.accent;

String stateLabel(String s) => switch (s) { 'warn' => tr('Sắp hết'), 'degraded' => tr('Tiết kiệm'), 'blocked' => tr('Đã chặn'), _ => tr('Bình thường') };
Color stateColor(String s) => switch (s) { 'warn' || 'degraded' => const Color(0xFFF5B544), 'blocked' => const Color(0xFFFF6B6B), _ => const Color(0xFF3DD68C) };

Widget usageBar(Pal pal, int pct, {double height = 8}) => ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1).toDouble(), minHeight: height, color: usageColor(pal, pct), backgroundColor: pal.surface2),
    );

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
double? _num(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));

/// Logo chữ của nhà cung cấp.
(String, Color) providerBadge(String id) => switch (id) {
      'anthropic' => ('A', const Color(0xFFC96442)),
      'openai' => ('O', const Color(0xFF10A37F)),
      'gemini' => ('G', const Color(0xFF4285F4)),
      'workers' => ('CF', const Color(0xFFF38020)),
      'deepseek' => ('D', const Color(0xFF4D6BFE)),
      'qwen' => ('Q', const Color(0xFF6E43E8)),
      'openrouter' => ('OR', const Color(0xFF475569)),
      _ => ('·', const Color(0xFF6B7280)),
    };

Widget providerLogo(String id, {double size = 28}) {
  final (l, c) = providerBadge(id);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(size * .28)),
    child: Text(l, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .42)),
  );
}

class AiAdminPage extends StatefulWidget {
  const AiAdminPage({super.key, required this.api});
  final AiGateApi api;
  @override
  State<AiAdminPage> createState() => _AiAdminPageState();
}

class _AiAdminPageState extends State<AiAdminPage> {
  Map<String, dynamic>? _ov, _tiers;
  List<AiQuota>? _users;
  List<Map<String, dynamic>> _extras = const [], _log = const [], _providers = const [], _aliases = const [];
  String? _error;
  String _filter = '';
  String _sort = 'month'; // month | day | user
  final _cm = TextEditingController(), _cd = TextEditingController();

  AiGateApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cm.dispose();
    _cd.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([api.overview(), api.users(), api.tiers(), api.extras(), api.log(limit: 8), api.providers(), api.aliases()]);
      if (!mounted) return;
      setState(() {
        _ov = r[0] as Map<String, dynamic>;
        _users = r[1] as List<AiQuota>;
        _tiers = r[2] as Map<String, dynamic>;
        _extras = r[3] as List<Map<String, dynamic>>;
        _log = r[4] as List<Map<String, dynamic>>;
        _providers = r[5] as List<Map<String, dynamic>>;
        _aliases = r[6] as List<Map<String, dynamic>>;
        _cm.text = '${_ov!['month_usd']}';
        _cd.text = '${_ov!['day_usd']}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      m.showSnackBar(toast(Text(done)));
      await _load();
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final o = _ov;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.surface,
        foregroundColor: pal.text,
        titleSpacing: 8,
        title: Row(children: [
          Icon(Icons.smart_toy_rounded, color: pal.accent),
          const SizedBox(width: 8),
          Text(tr('Cổng AI')),
          if (o != null) ...[
            const SizedBox(width: 10),
            Flexible(child: Text('${o['company']} · ${tr('tháng')} ${o['month']}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub))),
          ],
        ]),
        actions: [IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
            ])))
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth;
                  final cols = w >= 1100 ? 12 : w >= 720 ? 6 : 1; // máy tính / máy tính nhỏ / điện thoại
                  final pad = cols == 1 ? 12.0 : 20.0, gap = cols == 1 ? 10.0 : 14.0;
                  final inner = w - pad * 2;
                  double span(int s) => cols == 1 ? inner : cols == 6 ? (s >= 6 ? inner : (inner - gap) / 2) : (inner - gap * (12 / s - 1)) / (12 / s);
                  Widget box(int s, Widget child) => SizedBox(width: span(s), child: child);
                  final phone = cols == 1;
                  return RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: EdgeInsets.fromLTRB(pad, 14, pad, 32), children: [
                      Wrap(spacing: gap, runSpacing: gap, children: [
                        ..._kpis(pal, phone).map((k) => box(phone ? 12 : 3, k)),
                        box(8, _chartCard(pal, phone)),
                        box(4, _appsCard(pal)),
                        box(8, _usersCard(pal, phone)),
                        box(4, _providersCard(pal)),
                        box(4, _tiersCard(pal)),
                        box(4, _aliasesCard(pal)),
                        box(4, Column(children: [_extrasCard(pal), SizedBox(height: gap), _logCard(pal)])),
                      ]),
                    ]),
                  );
                }),
    );
  }

  // ---------------------------------------------------------------- khung chung
  Widget _card(Pal pal, {required IconData icon, required String title, Widget? action, required List<Widget> children, Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 19, color: pal.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: pal.text))),
            ?action,
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );
  Widget _k(Pal pal, String s) => Text(s, style: TextStyle(fontSize: 12, color: pal.sub));
  Widget _chip(Pal pal, String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
        child: Text(s, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
      );
  Widget _small(String label, VoidCallback? onPressed, {IconData? icon, bool primary = false}) {
    final child = icon == null ? Text(label) : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)]);
    const st = ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)));
    return primary ? FilledButton(style: st, onPressed: onPressed, child: child) : OutlinedButton(style: st, onPressed: onPressed, child: child);
  }

  // ---------------------------------------------------------------- số liệu
  List<Widget> _kpis(Pal pal, bool phone) {
    final o = _ov!;
    double n(String k) => (o[k] as num?)?.toDouble() ?? 0;
    final pct = (o['used_pct'] as num?)?.toInt() ?? 0;
    final dayPct = n('day_usd') > 0 ? (n('today_usd') / n('day_usd') * 100).round() : 0;
    final fpct = n('month_usd') > 0 ? (n('forecast_usd') / n('month_usd') * 100).round() : 0;
    Widget kpi(IconData i, String k, String v, String sub, int? p, {Color? color}) => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(i, size: 17, color: color ?? pal.accent), const SizedBox(width: 6), _k(pal, k)]),
            const SizedBox(height: 4),
            Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(height: 2),
            _k(pal, sub),
            if (p != null) ...[const SizedBox(height: 8), usageBar(pal, p, height: 6)],
          ]),
        );
    final warn = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.notifications_rounded, size: 17, color: Color(0xFFF5B544)), const SizedBox(width: 6), _k(pal, tr('Cảnh báo'))]),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final (v, l, c) in [
            ('${o['users_warn']}', tr('sắp hết'), const Color(0xFFF5B544)),
            ('${o['users_degraded']}', tr('tiết kiệm'), const Color(0xFFF5B544)),
            ('${o['users_blocked']}', tr('chặn'), const Color(0xFFFF6B6B)),
          ])
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c)),
              const SizedBox(width: 4),
              _k(pal, l),
            ]),
        ]),
        const SizedBox(height: 4),
        _k(pal, tr('Telegram cho Sếp ở 50 / 80 / 100%')),
      ]),
    );
    final month = kpi(Icons.account_balance_wallet_rounded, tr('Ngân sách tháng'), usdText(n('spent_usd')),
        '${tr('trên')} ${_n(n('month_usd'))} USD · $pct% · ≈ ${vndText(n('spent_usd'))}', pct);
    final today = kpi(Icons.today_rounded, tr('Hôm nay'), usdText(n('today_usd')),
        n('day_usd') > 0 ? '${tr('trần ngày')} ${_n(n('day_usd'))} USD · $dayPct%' : tr('Không đặt trần ngày'), n('day_usd') > 0 ? dayPct : null);
    final fc = kpi(Icons.trending_up_rounded, tr('Dự báo cuối tháng'), usdText(n('forecast_usd')), '${tr('theo tốc độ hiện tại')} · $fpct%', fpct,
        color: fpct >= 100 ? const Color(0xFFFF6B6B) : null);
    if (!phone) return [month, today, fc, warn];
    // Điện thoại: tháng + hôm nay + dự báo gộp một thẻ, cảnh báo một hàng.
    return [
      Container(
        key: const ValueKey('ai-phone-budget'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _k(pal, '${tr('Ngân sách tháng')} ${o['month']}'),
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text(usdText(n('spent_usd')), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
            Padding(padding: const EdgeInsets.only(bottom: 3), child: _k(pal, '/ ${_n(n('month_usd'))} USD · $pct%')),
          ]),
          const SizedBox(height: 8),
          usageBar(pal, pct, height: 6),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            _k(pal, '${tr('Hôm nay')} ${usdText(n('today_usd'))}${n('day_usd') > 0 ? ' / ${_n(n('day_usd'))}' : ''}'),
            _k(pal, '${tr('Dự báo')} ${usdText(n('forecast_usd'))}'),
          ]),
        ]),
      ),
      warn,
    ];
  }

  // ---------------------------------------------------------------- biểu đồ chi phí theo ngày
  Widget _chartCard(Pal pal, bool phone) {
    final o = _ov!;
    final days = <int, double>{};
    for (final d in (o['by_day'] as List? ?? const [])) {
      final k = '${(d as Map)['k']}';
      final day = int.tryParse(k.length >= 10 ? k.substring(8, 10) : '') ?? 0;
      if (day > 0) days[day] = (d['usd'] as num?)?.toDouble() ?? 0;
    }
    final month = '${o['month']}';
    final y = int.tryParse(month.split('-').first) ?? DateTime.now().year, m = int.tryParse(month.split('-').last) ?? DateTime.now().month;
    final nDays = DateTime(y, m + 1, 0).day;
    final today = DateTime.now().day;
    final monthUsd = (o['month_usd'] as num?)?.toDouble() ?? 0;
    final calls = (o['by_day'] as List? ?? const []).fold<int>(0, (s, d) => s + (((d as Map)['n'] as num?)?.toInt() ?? 0));
    return _card(pal,
        key: const ValueKey('ai-chart'),
        icon: Icons.bar_chart_rounded,
        title: tr('Chi phí theo ngày'),
        action: _k(pal, tr('{0} người dùng · {1} lượt', ['${o['users_active']}', '$calls'])),
        children: [
          SizedBox(
            height: phone ? 150 : 210,
            width: double.infinity,
            child: CustomPaint(painter: _DayChart(days: days, nDays: nDays, today: today, month: m, avgCap: monthUsd > 0 ? monthUsd / nDays : 0, pal: pal,
                font: Theme.of(context).textTheme.bodySmall?.fontFamily ?? DefaultTextStyle.of(context).style.fontFamily)),
          ),
        ]);
  }

  // ---------------------------------------------------------------- theo ứng dụng
  Widget _appsCard(Pal pal) {
    final apps = (_ov!['top_apps'] as List? ?? const []).cast<Map>();
    final total = apps.fold<double>(0, (s, a) => s + ((a['usd'] as num?)?.toDouble() ?? 0));
    String label(String k) => k.startsWith('bot:') ? '${tr('Trợ lý')} @${k.substring(4)}' : switch (k) {
          'vn.flygo.dich' => tr('Dịch'),
          'vn.flygo.mail' => tr('Thư'),
          'vn.flygo.agent' => tr('Trợ lý (runner)'),
          'chat' => tr('Chat'),
          _ => k,
        };
    return _card(pal, icon: Icons.apps_rounded, title: tr('Theo ứng dụng'), children: [
      if (apps.isEmpty) _k(pal, tr('Chưa có lượt nào tháng này')),
      for (final a in apps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label('${a['k']}'), overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text))),
              Text(usdText((a['usd'] as num?)?.toDouble() ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            ]),
            const SizedBox(height: 4),
            usageBar(pal, total > 0 ? (((a['usd'] as num?)?.toDouble() ?? 0) / total * 100).round() : 0, height: 5),
          ]),
        ),
    ]);
  }

  // ---------------------------------------------------------------- người dùng
  Widget _usersCard(Pal pal, bool phone) {
    final list = _users!.where((u) => _filter.isEmpty || u.user.contains(_filter.toLowerCase())).toList()
      ..sort((a, b) => switch (_sort) { 'user' => a.user.compareTo(b.user), 'day' => b.dayPct.compareTo(a.dayPct), _ => b.usedPct.compareTo(a.usedPct) });
    final search = SizedBox(
      width: phone ? double.infinity : 220,
      height: 36,
      child: TextField(
        decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 18), hintText: tr('Tìm email'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)), contentPadding: const EdgeInsets.symmetric(vertical: 8)),
        onChanged: (v) => setState(() => _filter = v.trim()),
      ),
    );
    Widget sortHead(String id, String label) => InkWell(
          onTap: () => setState(() => _sort = id),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _sort == id ? pal.text : pal.sub))),
            if (_sort == id) Icon(Icons.arrow_drop_down_rounded, size: 18, color: pal.text),
          ]),
        );
    return _card(pal,
        key: const ValueKey('ai-users'),
        icon: Icons.group_rounded,
        title: tr('Người dùng'),
        action: Row(mainAxisSize: MainAxisSize.min, children: [if (!phone) ...[search, const SizedBox(width: 8)], _small(tr('Mở AI'), _addUser, icon: Icons.person_add_alt_1_rounded, primary: true)]),
        children: [
          if (phone) ...[search, const SizedBox(height: 6)],
          if (list.isEmpty) Padding(padding: const EdgeInsets.all(12), child: _k(pal, tr('Chưa có ai'))),
          if (!phone && list.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(flex: 26, child: sortHead('user', tr('Người dùng'))),
                Expanded(flex: 12, child: _k(pal, tr('Hạng'))),
                Expanded(flex: 20, child: sortHead('day', tr('Hôm nay / trần ngày'))),
                Expanded(flex: 20, child: sortHead('month', tr('Tháng / trần tháng'))),
                Expanded(flex: 14, child: _k(pal, tr('Trạng thái'))),
                const SizedBox(width: 28),
              ]),
            ),
            Divider(height: 1, color: pal.divider),
          ],
          for (final u in list) phone ? _userTile(pal, u) : _userRow(pal, u),
        ]);
  }

  Widget _userRow(Pal pal, AiQuota u) => InkWell(
        onTap: () => _editUser(u),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
          child: Row(children: [
            Expanded(flex: 26, child: Text(u.user, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text))),
            Expanded(flex: 12, child: Text(u.tierName, style: TextStyle(color: pal.text, fontSize: 12.5))),
            Expanded(flex: 20, child: Row(children: [
              SizedBox(width: 60, child: usageBar(pal, u.dayPct, height: 5)),
              const SizedBox(width: 6),
              Flexible(child: Text('${u.dayPct}% · ${_n(u.dayUsd)}\$${u.customDay != null ? ' ✎' : ''}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub))),
            ])),
            Expanded(flex: 20, child: Row(children: [
              SizedBox(width: 70, child: usageBar(pal, u.usedPct, height: 5)),
              const SizedBox(width: 6),
              Flexible(child: Text('${u.usedPct}% · ${_n(u.monthUsd)}\$${u.extraUsd > 0 ? ' +${_n(u.extraUsd)}' : ''}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub))),
            ])),
            Expanded(flex: 14, child: Align(alignment: Alignment.centerLeft, child: _chip(pal, u.access ? stateLabel(u.state) : tr('Chưa mở'), u.access ? stateColor(u.state) : pal.sub))),
            SizedBox(width: 28, child: Icon(Icons.edit_rounded, size: 16, color: pal.sub)),
          ]),
        ),
      );

  Widget _userTile(Pal pal, AiQuota u) => InkWell(
        onTap: () => _editUser(u),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(u.user, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text))),
              _chip(pal, u.tierName, pal.accent),
              const SizedBox(width: 5),
              _chip(pal, u.access ? stateLabel(u.state) : tr('Chưa mở'), u.access ? stateColor(u.state) : pal.sub),
            ]),
            const SizedBox(height: 6),
            for (final (l, p, cap) in [(tr('Hôm nay'), u.dayPct, u.dayUsd), (tr('Tháng'), u.usedPct, u.monthUsd)])
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  SizedBox(width: 62, child: _k(pal, l)),
                  Expanded(child: usageBar(pal, p, height: 5)),
                  SizedBox(width: 78, child: Text('$p% · ${_n(cap)}\$', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: pal.sub))),
                ]),
              ),
          ]),
        ),
      );

  Future<void> _addUser() async {
    final c = TextEditingController();
    final email = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Mở AI công ty cho')),
      content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'ten@flygo.vn')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Mở')))],
    ));
    if (email == null || email.isEmpty) return;
    await _run(() => api.setUser(email, {'access': true}), tr('Đã mở AI cho {0}', [email]));
  }

  Future<void> _editUser(AiQuota u) async {
    final tiers = ((_tiers?['tiers'] as Map?) ?? const {}).cast<String, dynamic>();
    final def = '${_tiers?['default_tier'] ?? ''}';
    String? tier = u.customTier;
    final day = TextEditingController(text: u.customDay?.toString() ?? '');
    final month = TextEditingController(text: u.customMonth?.toString() ?? '');
    var blocked = u.blocked, access = u.access;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final pal = Pal.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u.user, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(height: 4),
            Text(tr('Đã dùng {0}% tháng · {1}% hôm nay', ['${u.usedPct}', '${u.dayPct}']), style: TextStyle(color: pal.sub)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: tier,
              decoration: InputDecoration(labelText: tr('Hạng'), border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: null, child: Text(tr('Mặc định ({0})', ['${(tiers[def] as Map?)?['name'] ?? def}']))),
                for (final e in tiers.entries) DropdownMenuItem(value: e.key, child: Text('${(e.value as Map)['name'] ?? e.key}')),
              ],
              onChanged: (v) => set(() => tier = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: day, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Trần ngày (USD)'), hintText: _n(u.dayUsd), helperText: tr('Trống = theo hạng'), border: const OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: month, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Trần tháng (USD)'), hintText: _n(u.monthUsd), helperText: tr('Trống = theo hạng'), border: const OutlineInputBorder()))),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: access, onChanged: (v) => set(() => access = v), title: Text(tr('Được dùng AI công ty'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: blocked, onChanged: (v) => set(() => blocked = v), title: Text(tr('Tạm khoá'))),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(onPressed: () { Navigator.pop(ctx); _addExtra(target: u.user); }, icon: const Icon(Icons.add_card_rounded), label: Text(tr('Cộng thêm'))),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
            ]),
          ]),
        );
      }),
    );
    if (ok != true) return;
    await _run(() => api.setUser(u.user, {'tier': tier, 'day_usd': _num(day.text), 'month_usd': _num(month.text), 'blocked': blocked, 'access': access}),
        tr('Đã lưu {0}', [u.user]));
  }

  // ---------------------------------------------------------------- nhà cung cấp
  Widget _providersCard(Pal pal) => _card(pal,
        key: const ValueKey('ai-providers'),
        icon: Icons.key_rounded,
        title: tr('Nhà cung cấp'),
        action: _small(tr('Thêm'), _addCustomProvider, icon: Icons.add_rounded),
        children: [
          for (final p in _providers) _providerRow(pal, p),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.lock_rounded, size: 14, color: pal.accent),
            const SizedBox(width: 6),
            Expanded(child: _k(pal, tr('Khoá chỉ nhập, không xem lại được; mã hoá trên máy chủ, agent không đặt được khoá.'))),
          ]),
        ]);

  Widget _providerRow(Pal pal, Map<String, dynamic> p) {
    final id = '${p['id']}';
    final has = p['has_key'] == true, on = p['enabled'] == 1 || p['enabled'] == true;
    final safe = p['sensitive_ok'] == 1 || p['sensitive_ok'] == true;
    final cap = (p['month_cap_usd'] as num?)?.toDouble();
    final spent = (p['month_usd'] as num?)?.toDouble() ?? 0;
    final testOk = p['test_ok'] == 1 || p['test_ok'] == true;
    final meta = has
        ? '…${p['key_last4']} · ${p['key_added_by'] ?? ''}${p['test_at'] != null ? ' · ${testOk ? 'OK' : tr('lỗi')} ${p['test_msg'] ?? ''}' : ''}'
        : (p['note'] as String?) ?? tr('Chưa có khoá');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
      child: Row(children: [
        providerLogo(id),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${p['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            if (has && on) _chip(pal, tr('Đang dùng'), const Color(0xFF3DD68C)),
            if (has && p['test_at'] != null && !testOk) _chip(pal, tr('Khoá lỗi'), const Color(0xFFF5B544)),
            if (!safe) _chip(pal, tr('Không dùng cho dữ liệu nhạy cảm'), const Color(0xFFFF6B6B)),
          ]),
          const SizedBox(height: 2),
          Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.sub)),
          if (has && (cap != null || spent > 0)) Text('${tr('Tháng này')} ${_n(spent)}${cap != null ? ' / ${_n(cap)}' : ''} USD', style: TextStyle(fontSize: 11.5, color: pal.sub)),
        ])),
        if (!has)
          _small(tr('Thêm khoá'), () => _setKey(p), icon: Icons.key_rounded, primary: true)
        else ...[
          IconButton(tooltip: tr('Kiểm tra'), visualDensity: VisualDensity.compact, onPressed: () => _testProvider(p), icon: const Icon(Icons.bolt_rounded, size: 19)),
          Switch(value: on, onChanged: (v) => _run(() => api.updateProvider(id, {'enabled': v}), v ? tr('Đã bật {0}', ['${p['name']}']) : tr('Đã tắt {0}', ['${p['name']}']))),
        ],
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, size: 19, color: pal.sub),
          onSelected: (v) => switch (v) {
            'key' => _setKey(p),
            'cap' => _setCap(p),
            'unkey' => _run(() => api.removeProviderKey(id), tr('Đã gỡ khoá')),
            'del' => _run(() => api.removeProvider(id), tr('Đã xoá')),
            _ => null,
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'key', child: Text(has ? tr('Thay khoá') : tr('Thêm khoá'))),
            PopupMenuItem(value: 'cap', child: Text(tr('Trần chi tiêu tháng'))),
            if (has) PopupMenuItem(value: 'unkey', child: Text(tr('Gỡ khoá'))),
            if (p['preset'] != true) PopupMenuItem(value: 'del', child: Text(tr('Xoá nhà cung cấp'))),
          ],
        ),
      ]),
    );
  }

  Future<void> _testProvider(Map<String, dynamic> p) async {
    final m = ScaffoldMessenger.of(context);
    try {
      final r = await api.testProvider('${p['id']}');
      m.showSnackBar(toast(Text('${p['name']}: ${r['msg']} (${r['ms']} ms)')));
      await _load();
    } catch (e) {
      m.showSnackBar(toast(Text('${p['name']}: $e')));
    }
  }

  /// Thêm / thay khoá: ô nhập dạng mật khẩu, khoá chỉ đi lên máy chủ, không lưu trên máy này.
  Future<void> _setKey(Map<String, dynamic> p) async {
    final key = TextEditingController(), cap = TextEditingController(text: p['month_cap_usd'] == null ? '' : '${p['month_cap_usd']}');
    final acct = TextEditingController(text: '${(p['extra'] as Map?)?['account_id'] ?? ''}');
    final needs = (p['needs'] as List?)?.cast<String>() ?? const [];
    final ok = await showDialog<bool>(context: context, builder: (ctx) {
      final pal = Pal.of(ctx);
      return AlertDialog(
        title: Row(children: [providerLogo('${p['id']}', size: 26), const SizedBox(width: 10), Expanded(child: Text('${p['has_key'] == true ? tr('Thay khoá') : tr('Thêm khoá')} ${p['name']}'))]),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p['has_key'] == true) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${tr('Khoá hiện tại')}: …${p['key_last4']} · ${p['key_added_by'] ?? ''}', style: TextStyle(color: pal.sub, fontSize: 12.5))),
          if (needs.contains('account_id')) TextField(controller: acct, decoration: const InputDecoration(labelText: 'Account ID')),
          TextField(controller: key, obscureText: true, autofocus: true, enableSuggestions: false, autocorrect: false,
              decoration: InputDecoration(labelText: tr('Khoá API (sau khi lưu không xem lại được)'))),
          TextField(controller: cap, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Trần chi tiêu mỗi tháng (USD, tuỳ chọn)'))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.lock_rounded, color: pal.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Máy chủ gọi thử khoá trước, rồi mã hoá và lưu. App, agent và nhật ký chỉ thấy 4 ký tự cuối.'), style: TextStyle(fontSize: 12.5, color: pal.text))),
            ]),
          ),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu và kiểm tra')))],
      );
    });
    if (ok != true) return;
    final id = '${p['id']}';
    await _run(() async {
      if (needs.contains('account_id') || cap.text.trim().isNotEmpty) {
        await api.updateProvider(id, {
          if (needs.contains('account_id')) 'extra': {'account_id': acct.text.trim()},
          if (cap.text.trim().isNotEmpty) 'month_cap_usd': _num(cap.text),
        });
      }
      if (key.text.trim().isNotEmpty) await api.setProviderKey(id, key.text.trim());
    }, tr('Đã lưu khoá {0}', ['${p['name']}']));
    key.clear();
  }

  Future<void> _setCap(Map<String, dynamic> p) async {
    final cap = TextEditingController(text: p['month_cap_usd'] == null ? '' : '${p['month_cap_usd']}');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('${tr('Trần chi tiêu tháng')} · ${p['name']}'),
      content: TextField(controller: cap, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'USD', helperText: tr('Trống = không đặt trần; hết trần thì mức AI chuyển sang nhà kế tiếp trong chuỗi'))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu')))],
    ));
    if (ok != true) return;
    await _run(() => api.updateProvider('${p['id']}', {'month_cap_usd': _num(cap.text)}), tr('Đã lưu'));
  }

  Future<void> _addCustomProvider() async {
    final name = TextEditingController(), base = TextEditingController(text: 'https://');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Nhà cung cấp kiểu OpenAI')),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: tr('Tên'), hintText: tr('vd. AI nội bộ'))),
        TextField(controller: base, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://…/v1')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Thêm')))],
    ));
    if (ok != true) return;
    final slug = name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    await _run(() => api.updateProvider('custom-${slug.isEmpty ? 'nha-1' : slug}', {'name': name.text.trim(), 'base_url': base.text.trim()}), tr('Đã thêm, giờ thêm khoá'));
  }

  // ---------------------------------------------------------------- hạng & ngân sách
  Widget _tiersCard(Pal pal) {
    final tiers = ((_tiers?['tiers'] as Map?) ?? const {}).cast<String, dynamic>();
    final o = _ov!;
    return _card(pal, key: const ValueKey('ai-tiers'), icon: Icons.tune_rounded, title: tr('Hạng & ngân sách'), children: [
      Row(children: [
        Expanded(child: TextField(controller: _cm, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, labelText: tr('Công ty / tháng'), suffixText: 'USD', border: const OutlineInputBorder()))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _cd, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, labelText: tr('/ ngày'), suffixText: 'USD', border: const OutlineInputBorder()))),
        const SizedBox(width: 8),
        _small(tr('Lưu'), () => _run(() => api.setCompany(monthUsd: _num(_cm.text), dayUsd: _num(_cd.text)), tr('Đã lưu ngân sách')), primary: true),
      ]),
      const SizedBox(height: 10),
      for (final e in tiers.entries) _TierRow(key: ValueKey('tier-${e.key}'), id: e.key, t: (e.value as Map).cast<String, dynamic>(), isDefault: e.key == _tiers?['default_tier'],
          onSave: (v) => _run(() => api.setTier(e.key, v), tr('Đã lưu hạng'))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _k(pal, o['access'] == 'all' ? tr('Đang mở cho mọi nhân viên') : tr('Đang mở cho {0} người trong danh sách', ['${o['access']}']))),
        if (o['access'] != 'all') _small(tr('Mở cho mọi người'), _confirmAll) else _small(tr('Quay về danh sách'), () => _run(() => api.setAccessAll(false), tr('Đã quay về danh sách'))),
      ]),
    ]);
  }

  Future<void> _confirmAll() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('Mở AI công ty cho mọi nhân viên?')),
      content: Text(tr('Mỗi người dùng theo hạng mặc định và trần ngày/tháng của hạng.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Mở')))],
    ));
    if (ok == true) await _run(() => api.setAccessAll(true), tr('Đã mở cho mọi nhân viên'));
  }

  // ---------------------------------------------------------------- mức AI & model
  String _aliasName(String a) => switch (a) { 'flygo-fast' => tr('Nhanh'), 'flygo-smart' => tr('Kỹ hơn'), 'flygo-agent' => tr('Agent nhiều bước'), _ => a };
  IconData _aliasIcon(String a) => switch (a) { 'flygo-fast' => Icons.bolt_rounded, 'flygo-smart' => Icons.auto_awesome_rounded, _ => Icons.smart_toy_rounded };

  Widget _aliasesCard(Pal pal) => _card(pal, key: const ValueKey('ai-aliases'), icon: Icons.alt_route_rounded, title: tr('Mức AI & model'), children: [
        for (final a in _aliases)
          InkWell(
            onTap: () => _editAlias(a),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_aliasIcon('${a['id']}'), size: 17, color: pal.accent),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${_aliasName('${a['id']}')} · ${a['id']}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
                  Icon(Icons.edit_rounded, size: 15, color: pal.sub),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final (i, r) in [{'provider': a['provider'], 'model': a['model']}, ...((a['chain'] as List?) ?? const []).cast<Map>()].indexed) ...[
                    if (i > 0) Icon(Icons.arrow_forward_rounded, size: 14, color: pal.sub),
                    Container(
                      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
                      decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(7)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        providerLogo('${r['provider']}', size: 16),
                        const SizedBox(width: 5),
                        Text('${r['model']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.text)),
                      ]),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 6),
        _k(pal, tr('Nhà đầu lỗi hoặc hết trần tháng thì tự chạy bước kế tiếp. App chỉ gọi tên mức, không cần cập nhật.')),
      ]);

  Future<void> _editAlias(Map<String, dynamic> a) async {
    final steps = [
      ({'provider': '${a['provider']}', 'model': '${a['model']}'}),
      ...((a['chain'] as List?) ?? const []).cast<Map>().map((r) => {'provider': '${r['provider']}', 'model': '${r['model']}'}),
    ];
    var insecure = a['allow_insensitive'] == true;
    final provs = _providers.where((p) => p['has_key'] == true).toList();
    final models = <String, List<String>>{};
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final pal = Pal.of(ctx);
      Future<void> loadModels(String id) async {
        if (models.containsKey(id)) return;
        models[id] = const [];
        try {
          final l = await api.providerModels(id);
          set(() => models[id] = l);
        } catch (_) {}
      }
      for (final s in steps) {
        loadModels(s['provider']!);
      }
      return AlertDialog(
        title: Text('${_aliasName('${a['id']}')} · ${a['id']}'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(width: 56, child: Text(i == 0 ? tr('Chính') : '${tr('Dự phòng')} $i', style: TextStyle(fontSize: 12, color: pal.sub))),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: provs.any((p) => p['id'] == s['provider']) ? s['provider'] : null,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: [for (final p in provs) DropdownMenuItem(value: '${p['id']}', child: Text('${p['name']}', overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => set(() { s['provider'] = v ?? s['provider']!; loadModels(s['provider']!); }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Autocomplete<String>(
                  initialValue: TextEditingValue(text: s['model']!),
                  optionsBuilder: (v) => (models[s['provider']] ?? const <String>[]).where((m) => m.contains(v.text)).take(30),
                  onSelected: (v) => s['model'] = v,
                  fieldViewBuilder: (c, ctl, f, _) => TextField(controller: ctl, focusNode: f, onChanged: (v) => s['model'] = v.trim(),
                      decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: tr('model'))),
                )),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: i == 0 ? null : () => set(() => steps.removeAt(i)),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ]),
            ),
          if (steps.length < 6)
            TextButton.icon(onPressed: () => set(() => steps.add({'provider': provs.isEmpty ? 'anthropic' : '${provs.first['id']}', 'model': ''})),
                icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm bước dự phòng'))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: insecure,
            onChanged: (v) => set(() => insecure = v),
            title: Text(tr('Cho phép nhà không dùng cho dữ liệu nhạy cảm (DeepSeek, Qwen)')),
            subtitle: Text(tr('Chỉ bật khi mức này chỉ dùng cho nội dung công khai')),
          ),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu mức AI')))],
      );
    }));
    if (ok != true) return;
    final clean = steps.where((s) => (s['model'] ?? '').isNotEmpty).toList();
    if (clean.isEmpty) return;
    await _run(() => api.setAlias('${a['id']}', {
          'provider': clean.first['provider'],
          'model': clean.first['model'],
          'chain': [for (final s in clean.skip(1)) {'provider': s['provider'], 'model': s['model']}],
          'allow_insensitive': insecure,
        }), tr('Đã lưu mức AI'));
  }

  // ---------------------------------------------------------------- cộng thêm
  Widget _extrasCard(Pal pal) => _card(pal, key: const ValueKey('ai-extras'), icon: Icons.add_card_rounded, title: tr('Cộng thêm'), action: _small(tr('Cộng thêm'), () => _addExtra(), icon: Icons.add_rounded), children: [
        if (_extras.isEmpty) _k(pal, tr('Không có khoản nào')),
        for (final e in _extras)
          Row(children: [
            Icon(e['scope'] == 'dept' ? Icons.groups_rounded : Icons.person_rounded, size: 18, color: pal.accent),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['target']} +${e['usd']} USD', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              _k(pal, '${tr('đến')} ${_date(e['until'])}${'${e['reason'] ?? ''}'.isEmpty ? '' : ' · ${e['reason']}'} · ${e['by']}'),
            ])),
            IconButton(tooltip: tr('Bỏ'), visualDensity: VisualDensity.compact, onPressed: () => _run(() => api.removeExtra((e['id'] as num).toInt()), tr('Đã bỏ')), icon: const Icon(Icons.delete_outline_rounded, size: 19)),
          ]),
      ]);

  String _date(Object? ms) {
    if (ms is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Future<void> _addExtra({String? target}) async {
    final t = TextEditingController(text: target ?? ''), usd = TextEditingController(), days = TextEditingController(), reason = TextEditingController();
    var scope = 'user';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: Text(tr('Cộng thêm hạn mức')),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<String>(
          segments: [ButtonSegment(value: 'user', label: Text(tr('Người dùng'))), ButtonSegment(value: 'dept', label: Text(tr('Phòng ban')))],
          selected: {scope}, onSelectionChanged: (v) => set(() => scope = v.first)),
        TextField(controller: t, decoration: InputDecoration(labelText: scope == 'user' ? 'Email' : tr('Mã phòng ban'))),
        Row(children: [
          Expanded(child: TextField(controller: usd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'USD'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Số ngày'), hintText: tr('đến hết tháng')))),
        ]),
        TextField(controller: reason, decoration: InputDecoration(labelText: tr('Lý do'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cộng thêm')))],
    )));
    if (ok != true) return;
    await _run(() => api.addExtra(scope: scope, target: t.text.trim(), usd: _num(usd.text) ?? 0, days: int.tryParse(days.text), reason: reason.text.trim()), tr('Đã cộng thêm'));
  }

  // ---------------------------------------------------------------- nhật ký
  static const _actions = {
    'user.set': 'Đổi hạn mức người dùng', 'override.add': 'Cộng thêm', 'override.del': 'Bỏ khoản cộng thêm', 'company.set': 'Đổi ngân sách công ty',
    'tier.set': 'Sửa hạng', 'access.all': 'Đổi phạm vi truy cập', 'admin.login': 'Đăng nhập trang web', 'admin.denied': 'Bị từ chối', 'policy.put': 'Sửa chính sách',
    'provider.key': 'Thêm / thay khoá', 'provider.key.del': 'Gỡ khoá', 'provider.set': 'Sửa nhà cung cấp', 'provider.del': 'Xoá nhà cung cấp', 'alias.set': 'Sửa mức AI',
    'capture.on': 'Bật chụp request', 'capture.off': 'Tắt chụp request',
  };

  String _logLine(Map<String, dynamic> r) {
    final d = r['detail'];
    if (r['action'] == 'provider.key' && d is Map) return '${tr('Thêm khoá')} ${d['id']} · …${d['last4']}';
    if (r['action'] == 'user.set' && d is Map) return '${tr('Đổi hạn mức')} ${d['user']}${d['day_usd'] != null ? ' · ${tr('ngày')} ${d['day_usd']}\$' : ''}';
    if (r['action'] == 'override.add' && d is Map) return '${tr('Cộng thêm')} ${d['usd']}\$ ${d['target']}';
    return tr(_actions['${r['action']}'] ?? '${r['action']}');
  }

  Widget _logCard(Pal pal) => _card(pal, key: const ValueKey('ai-log'), icon: Icons.history_rounded, title: tr('Nhật ký'), action: TextButton(onPressed: _moreLog, child: Text(tr('Xem thêm'))), children: [
        if (_log.isEmpty) _k(pal, tr('Chưa có thao tác nào')),
        for (final r in _log.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 44, child: _k(pal, _when(r['ts']))),
              Expanded(child: Text(_logLine(r), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.text))),
              const SizedBox(width: 6),
              Flexible(child: Text('${r['by']}'.split('@').first, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.sub))),
            ]),
          ),
      ]);

  String _when(Object? ms) {
    if (ms is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return d.day == now.day && d.month == now.month ? '${two(d.hour)}:${two(d.minute)}' : '${two(d.day)}/${two(d.month)}';
  }

  Future<void> _moreLog() async {
    final all = await api.log(limit: 100).catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) {
      final pal = Pal.of(ctx);
      return AlertDialog(
        title: Text(tr('Nhật ký quản trị')),
        content: SizedBox(width: 560, height: 480, child: ListView(children: [
          for (final r in all)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_logLine(r), style: TextStyle(color: pal.text)),
              subtitle: Text('${r['by']} · ${_when(r['ts'])}', style: TextStyle(color: pal.sub, fontSize: 12)),
            ),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
      );
    });
  }
}

/// Một hạng: sửa ngay trên dòng (trần ngày, trần tháng, lượt Kỹ hơn).
class _TierRow extends StatefulWidget {
  const _TierRow({super.key, required this.id, required this.t, required this.isDefault, required this.onSave});
  final String id;
  final Map<String, dynamic> t;
  final bool isDefault;
  final void Function(Map<String, dynamic>) onSave;
  @override
  State<_TierRow> createState() => _TierRowState();
}

class _TierRowState extends State<_TierRow> {
  late final _d = TextEditingController(text: '${widget.t['day_usd']}');
  late final _m = TextEditingController(text: '${widget.t['month_usd']}');
  late final _s = TextEditingController(text: widget.t['smart_per_month'] == null ? '' : '${widget.t['smart_per_month']}');

  @override
  void dispose() {
    _d.dispose();
    _m.dispose();
    _s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    InputDecoration dec(String l, [String? hint]) => InputDecoration(isDense: true, labelText: l, hintText: hint, border: const OutlineInputBorder());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 86,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.t['name'] ?? widget.id}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            if (widget.isDefault) Text(tr('mặc định'), style: const TextStyle(fontSize: 11, color: Color(0xFF3DD68C))),
          ]),
        ),
        Expanded(child: TextField(controller: _d, keyboardType: TextInputType.number, decoration: dec(tr('Ngày \$')))),
        const SizedBox(width: 6),
        Expanded(child: TextField(controller: _m, keyboardType: TextInputType.number, decoration: dec(tr('Tháng \$')))),
        const SizedBox(width: 6),
        Expanded(child: TextField(controller: _s, keyboardType: TextInputType.number, decoration: dec(tr('Kỹ hơn'), '∞'))),
        IconButton(
          tooltip: tr('Lưu hạng'),
          visualDensity: VisualDensity.compact,
          onPressed: () => widget.onSave({'day_usd': _num(_d.text), 'month_usd': _num(_m.text), 'smart_per_month': _s.text.trim().isEmpty ? null : int.tryParse(_s.text.trim())}),
          icon: Icon(Icons.check_circle_rounded, color: pal.accent),
        ),
      ]),
    );
  }
}

/// Biểu đồ cột chi phí từng ngày trong tháng: có trục, cột hôm nay tô vàng, vạch trung bình cho phép mỗi ngày (ngân sách / số ngày).
class _DayChart extends CustomPainter {
  _DayChart({required this.days, required this.nDays, required this.today, required this.month, required this.avgCap, required this.pal, this.font});
  final Map<int, double> days;
  final int nDays, today, month;
  final double avgCap;
  final Pal pal;
  /// Font chữ của app (TextPainter không tự lấy theo theme).
  final String? font;

  @override
  void paint(Canvas canvas, Size s) {
    const left = 40.0, bottom = 20.0, top = 6.0;
    final h = s.height - bottom - top, w = s.width - left - 4;
    final maxV = math.max(math.max(avgCap * 1.3, days.values.fold<double>(0, math.max)), 0.01);
    // bậc trục: 4 vạch, làm tròn đẹp
    final raw = maxV / 4, mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10].map((x) => x * mag).firstWhere((x) => x >= raw);
    final top4 = step * 4;
    final grid = Paint()..color = pal.divider..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, Offset at, {bool right = false}) {
      tp.text = TextSpan(text: t, style: TextStyle(fontSize: 10.5, color: pal.sub, fontFamily: font));
      tp.layout();
      tp.paint(canvas, right ? at - Offset(tp.width, tp.height / 2) : at);
    }
    for (var i = 0; i <= 4; i++) {
      final y = top + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(s.width - 4, y), grid);
      final v = step * i;
      label('${v >= 1 ? v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1) : v.toStringAsFixed(2)}\$', Offset(left - 6, y), right: true);
    }
    final bw = w / nDays;
    final bar = Paint()..color = pal.accent;
    final todayBar = Paint()..color = const Color(0xFFF5B544);
    for (var d = 1; d <= nDays; d++) {
      final v = days[d] ?? 0;
      final x = left + (d - 1) * bw + bw * .15;
      if (v > 0) {
        final bh = math.max(2.0, h * v / top4);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, top + h - bh, bw * .7, bh), const Radius.circular(3)), d == today ? todayBar : bar);
      }
      if (d == 1 || d % 5 == 0 || d == today) label('$d/$month', Offset(x - 2, top + h + 4));
    }
    if (avgCap > 0) {
      final y = top + h - h * avgCap / top4;
      final dash = Paint()..color = const Color(0xFFF5B544)..strokeWidth = 1.2;
      for (var x = left; x < s.width - 4; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, s.width - 4), y), dash);
      }
      tp.text = TextSpan(text: tr('TB cho phép {0}\$/ngày', [avgCap.toStringAsFixed(2)]), style: TextStyle(fontSize: 10.5, color: const Color(0xFFF5B544), fontFamily: font));
      tp.layout();
      tp.paint(canvas, Offset(s.width - tp.width - 6, y - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(_DayChart o) => o.days != days || o.pal != pal;
}
