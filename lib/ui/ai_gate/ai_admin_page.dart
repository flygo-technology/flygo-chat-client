// Quản trị "Cổng AI" (native, mục Quản trị): ngân sách công ty, hạn mức từng người (trần ngày, trần tháng, hạng),
// cộng thêm, sổ chi phí, nhật ký. Trang web <chat>/__apps/ai/admin vẫn giữ làm dự phòng.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../theme.dart';
import 'ai_gate_api.dart';

Future<void> openAiAdmin(BuildContext context) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final api = await AiGateApi.current(state.token);
    if (api == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    await nav.push(AppPageRoute(builder: (_) => AiAdminPage(api: api)));
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

class AiAdminPage extends StatefulWidget {
  const AiAdminPage({super.key, required this.api, this.initialTab = 0});
  final AiGateApi api;
  final int initialTab;
  @override
  State<AiAdminPage> createState() => _AiAdminPageState();
}

class _AiAdminPageState extends State<AiAdminPage> {
  Map<String, dynamic>? _ov, _tiers;
  List<AiQuota>? _users;
  List<Map<String, dynamic>>? _extras, _log;
  String? _error;
  String _filter = '';

  AiGateApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([api.overview(), api.users(), api.tiers(), api.extras(), api.log()]);
      if (!mounted) return;
      setState(() {
        _ov = r[0] as Map<String, dynamic>;
        _users = r[1] as List<AiQuota>;
        _tiers = r[2] as Map<String, dynamic>;
        _extras = r[3] as List<Map<String, dynamic>>;
        _log = r[4] as List<Map<String, dynamic>>;
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
    final tabs = [tr('Tổng quan'), tr('Người dùng'), tr('Hạng & ngân sách'), tr('Cộng thêm'), tr('Nhật ký')];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          foregroundColor: pal.text,
          title: Text(tr('Cổng AI')),
          actions: [IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: pal.text,
            unselectedLabelColor: pal.sub,
            indicatorColor: pal.accent,
            tabs: [for (final t in tabs) Tab(text: t)],
          ),
        ),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
              ])))
            : _ov == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [_overview(pal), _usersTab(pal), _tiersTab(pal), _extrasTab(pal), _logTab(pal)]),
      ),
    );
  }

  // ---------------------------------------------------------------- khung chung
  Widget _page(List<Widget> children) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: children)),
        ),
      );

  Widget _card(Pal pal, List<Widget> c, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding,
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: c),
      );

  Widget _k(Pal pal, String s) => Text(s, style: TextStyle(fontSize: 12.5, color: pal.sub));
  Widget _v(Pal pal, String s, {Color? color}) => Text(s, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color ?? pal.text));

  // ---------------------------------------------------------------- Tổng quan
  Widget _overview(Pal pal) {
    final o = _ov!;
    double n(String k) => (o[k] as num?)?.toDouble() ?? 0;
    final pct = (o['used_pct'] as num?)?.toInt() ?? 0;
    final dayPct = n('day_usd') > 0 ? (n('today_usd') / n('day_usd') * 100).round() : 0;
    final days = (o['by_day'] as List? ?? const []).cast<Map>();
    final maxDay = days.fold<double>(0, (m, d) => ((d['usd'] as num?)?.toDouble() ?? 0) > m ? (d['usd'] as num).toDouble() : m);
    final aliases = (_tiers?['aliases'] as Map?) ?? const {};
    return _page([
      _card(pal, [
        Row(children: [Expanded(child: _k(pal, tr('Ngân sách tháng {0}', ['${o['month']}']))), _chip(pal, tr('Trần {0}', [usdText(n('month_usd'))]), pal.accent)]),
        const SizedBox(height: 6),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
          _v(pal, usdText(n('spent_usd'))),
          Padding(padding: const EdgeInsets.only(bottom: 3), child: _k(pal, '≈ ${vndText(n('spent_usd'))} · $pct%')),
        ]),
        const SizedBox(height: 10),
        usageBar(pal, pct, height: 12),
        const SizedBox(height: 8),
        _k(pal, tr('Dự báo cuối tháng: {0}', [usdText(n('forecast_usd'))])),
      ]),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth >= 640 ? (c.maxWidth - 24) / 3 : c.maxWidth;
        Widget box(List<Widget> ch) => SizedBox(width: w, child: _card(pal, ch));
        return Wrap(spacing: 12, children: [
          box([_k(pal, tr('Hôm nay')), const SizedBox(height: 4), _v(pal, usdText(n('today_usd'))), const SizedBox(height: 6),
            if (n('day_usd') > 0) ...[usageBar(pal, dayPct), const SizedBox(height: 6)],
            _k(pal, n('day_usd') > 0 ? tr('Trần ngày {0}', [usdText(n('day_usd'))]) : tr('Không đặt trần ngày'))]),
          box([_k(pal, tr('Người dùng')), const SizedBox(height: 4), _v(pal, tr('{0} đang dùng', ['${o['users_active']}'])), const SizedBox(height: 6),
            _k(pal, o['access'] == 'all' ? tr('Mở cho mọi nhân viên') : tr('Mở cho {0} người', ['${o['access']}']))]),
          box([_k(pal, tr('Cảnh báo')), const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final (n, label, c) in [
                ('${o['users_warn']}', tr('sắp hết'), const Color(0xFFF5B544)),
                ('${o['users_degraded']}', tr('tiết kiệm'), const Color(0xFFF5B544)),
                ('${o['users_blocked']}', tr('chặn'), const Color(0xFFFF6B6B)),
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [_v(pal, n, color: c), const SizedBox(width: 5), _k(pal, label)]),
            ]),
            const SizedBox(height: 6), _k(pal, tr('Báo Telegram cho Sếp ở 50 / 80 / 100%'))]),
        ]);
      }),
      _card(pal, [
        Text(tr('Chi phí theo ngày'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 12),
        if (days.isEmpty) _k(pal, tr('Chưa có lượt nào tháng này'))
        else SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in days)
              Expanded(child: Tooltip(
                message: '${d['k']}: ${usdText((d['usd'] as num).toDouble())} · ${d['n']} ${tr('lượt')}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    height: maxDay > 0 ? 8 + 104 * ((d['usd'] as num).toDouble() / maxDay) : 8,
                    decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              )),
          ]),
        ),
      ]),
      _card(pal, [
        Text(tr('Mức AI và model'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 6),
        for (final e in aliases.entries)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            Icon(e.key == 'flygo-fast' ? Icons.bolt_rounded : e.key == 'flygo-smart' ? Icons.auto_awesome_rounded : Icons.smart_toy_rounded, size: 18, color: pal.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(_aliasName('${e.key}'), style: TextStyle(color: pal.text))),
            Text('${e.value}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ])),
      ]),
    ]);
  }

  String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  String _aliasName(String a) => switch (a) { 'flygo-fast' => tr('Nhanh'), 'flygo-smart' => tr('Kỹ hơn'), 'flygo-agent' => tr('Agent nhiều bước'), _ => a };

  Widget _chip(Pal pal, String s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
        child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      );

  // ---------------------------------------------------------------- Người dùng
  Widget _usersTab(Pal pal) {
    final list = _users!.where((u) => _filter.isEmpty || u.user.contains(_filter.toLowerCase())).toList();
    return _page([
      Row(children: [
        Expanded(child: TextField(
          decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm email'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (v) => setState(() => _filter = v.trim()),
        )),
        const SizedBox(width: 10),
        FilledButton.icon(onPressed: _addUser, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: Text(tr('Mở AI'))),
      ]),
      const SizedBox(height: 12),
      if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: _k(pal, tr('Chưa có ai')))),
      for (final u in list) _userCard(pal, u),
    ]);
  }

  Widget _userCard(Pal pal, AiQuota u) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _editUser(u),
        child: _card(pal, [
          Row(children: [
            Expanded(child: Text(u.user, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text), overflow: TextOverflow.ellipsis)),
            _chip(pal, u.tierName, pal.accent),
            const SizedBox(width: 6),
            _chip(pal, u.access ? stateLabel(u.state) : tr('Chưa mở'), u.access ? stateColor(u.state) : pal.sub),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(width: 74, child: _k(pal, tr('Hôm nay'))),
            Expanded(child: usageBar(pal, u.dayPct)),
            const SizedBox(width: 10),
            SizedBox(width: 132, child: Text('${u.daySpentUsd.toStringAsFixed(2)} / ${_n(u.dayUsd)} USD', textAlign: TextAlign.end, style: TextStyle(fontSize: 12.5, color: pal.sub))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(width: 74, child: _k(pal, tr('Tháng'))),
            Expanded(child: usageBar(pal, u.usedPct)),
            const SizedBox(width: 10),
            SizedBox(width: 132, child: Text('${u.usedPct}% · ${_n(u.monthUsd)}${u.extraUsd > 0 ? ' +${_n(u.extraUsd)}' : ''} USD', textAlign: TextAlign.end, style: TextStyle(fontSize: 12.5, color: pal.sub))),
          ]),
        ], padding: const EdgeInsets.fromLTRB(16, 12, 16, 14)),
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
                  decoration: InputDecoration(labelText: tr('Trần ngày (USD)'), hintText: '${u.dayUsd}', helperText: tr('Trống = theo hạng'), border: const OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: month, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Trần tháng (USD)'), hintText: '${u.monthUsd}', helperText: tr('Trống = theo hạng'), border: const OutlineInputBorder()))),
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
    double? num_(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));
    await _run(() => api.setUser(u.user, {'tier': tier, 'day_usd': num_(day.text), 'month_usd': num_(month.text), 'blocked': blocked, 'access': access}),
        tr('Đã lưu {0}', [u.user]));
  }

  // ---------------------------------------------------------------- Hạng & ngân sách
  Widget _tiersTab(Pal pal) {
    final o = _ov!;
    final tiers = ((_tiers?['tiers'] as Map?) ?? const {}).cast<String, dynamic>();
    final cm = TextEditingController(text: '${o['month_usd']}'), cd = TextEditingController(text: '${o['day_usd']}');
    return _page([
      _card(pal, [
        Text(tr('Ngân sách công ty'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: cm, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Tháng (USD)'), border: const OutlineInputBorder()))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: cd, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Ngày (USD)'), border: const OutlineInputBorder()))),
          const SizedBox(width: 12),
          FilledButton(onPressed: () => _run(() => api.setCompany(monthUsd: double.tryParse(cm.text), dayUsd: double.tryParse(cd.text)), tr('Đã lưu ngân sách')), child: Text(tr('Lưu'))),
        ]),
        const SizedBox(height: 8),
        _k(pal, tr('Hết trần công ty là chặn mọi người. Đổi trần sẽ báo Telegram cho Sếp.')),
      ]),
      for (final e in tiers.entries) _tierCard(pal, e.key, (e.value as Map).cast<String, dynamic>(), e.key == _tiers?['default_tier']),
      _card(pal, [
        Text(tr('Ai được dùng'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 6),
        _k(pal, o['access'] == 'all' ? tr('Đang mở cho mọi nhân viên') : tr('Đang mở cho {0} người trong danh sách', ['${o['access']}'])),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          OutlinedButton(onPressed: o['access'] == 'all' ? null : () => _confirmAll(), child: Text(tr('Mở cho mọi nhân viên'))),
          OutlinedButton(onPressed: o['access'] == 'all' ? () => _run(() => api.setAccessAll(false), tr('Đã quay về danh sách')) : null, child: Text(tr('Quay về danh sách'))),
        ]),
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

  Widget _tierCard(Pal pal, String id, Map<String, dynamic> t, bool isDefault) {
    final m = TextEditingController(text: '${t['month_usd']}'), d = TextEditingController(text: '${t['day_usd']}');
    final s = TextEditingController(text: t['smart_per_month'] == null ? '' : '${t['smart_per_month']}');
    return _card(pal, [
      Row(children: [
        Text('${t['name'] ?? id}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        if (isDefault) ...[const SizedBox(width: 8), _chip(pal, tr('mặc định'), const Color(0xFF3DD68C))],
        const Spacer(),
        Flexible(child: Text([for (final a in (t['aliases'] as List? ?? const [])) _aliasName('$a')].join(' · '), style: TextStyle(fontSize: 12.5, color: pal.sub), overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: d, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, labelText: tr('Ngày (USD)'), border: const OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: m, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, labelText: tr('Tháng (USD)'), border: const OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: s, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, labelText: tr('Lượt Kỹ hơn'), hintText: '∞', border: const OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: () => _run(() => api.setTier(id, {'month_usd': double.tryParse(m.text), 'day_usd': double.tryParse(d.text), 'smart_per_month': s.text.trim().isEmpty ? null : int.tryParse(s.text.trim())}), tr('Đã lưu hạng')),
          child: Text(tr('Lưu hạng')),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- Cộng thêm
  Widget _extrasTab(Pal pal) => _page([
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () => _addExtra(), icon: const Icon(Icons.add_rounded), label: Text(tr('Cộng thêm')))),
        const SizedBox(height: 12),
        if (_extras!.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: _k(pal, tr('Không có khoản nào')))),
        for (final e in _extras!)
          _card(pal, [
            Row(children: [
              Icon(e['scope'] == 'dept' ? Icons.groups_rounded : Icons.person_rounded, color: pal.accent),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['target']}', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                _k(pal, '+${e['usd']} USD · ${tr('đến')} ${_date(e['until'])}${'${e['reason'] ?? ''}'.isEmpty ? '' : ' · ${e['reason']}'} · ${e['by']}'),
              ])),
              IconButton(tooltip: tr('Bỏ'), onPressed: () => _run(() => api.removeExtra((e['id'] as num).toInt()), tr('Đã bỏ')), icon: const Icon(Icons.delete_outline_rounded)),
            ]),
          ], padding: const EdgeInsets.fromLTRB(14, 10, 6, 10)),
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
    await _run(() => api.addExtra(scope: scope, target: t.text.trim(), usd: double.tryParse(usd.text.replaceAll(',', '.')) ?? 0,
        days: int.tryParse(days.text), reason: reason.text.trim()), tr('Đã cộng thêm'));
  }

  // ---------------------------------------------------------------- Nhật ký
  static const _actions = {
    'user.set': 'Đổi hạn mức người dùng', 'override.add': 'Cộng thêm', 'override.del': 'Bỏ khoản cộng thêm', 'company.set': 'Đổi ngân sách công ty',
    'tier.set': 'Sửa hạng', 'access.all': 'Đổi phạm vi truy cập', 'admin.login': 'Đăng nhập trang web', 'admin.denied': 'Bị từ chối', 'policy.put': 'Sửa chính sách',
  };

  Widget _logTab(Pal pal) => _page([
        if (_log!.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: _k(pal, tr('Chưa có thao tác nào')))),
        for (final r in _log!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history_rounded, color: pal.sub),
            title: Text(tr(_actions['${r['action']}'] ?? '${r['action']}'), style: TextStyle(color: pal.text)),
            subtitle: Text('${r['by']} · ${_when(r['ts'])}\n${_detail(r['detail'])}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
            isThreeLine: true,
          ),
      ]);

  String _when(Object? ms) {
    if (ms is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)} ${two(d.day)}/${two(d.month)}';
  }

  String _detail(Object? d) => d is Map ? [for (final e in d.entries) if (e.value != null) '${e.key}: ${e.value}'].join(', ') : '';
}
