// Báo cáo (vn.flygo.reports): trang chủ — báo cáo của tôi và được chia sẻ, bản mới nhất kèm KPI chính, chấm "mới" khi chưa xem.
// Không có trình soạn: báo cáo do AI lập (nút "Nhờ AI"), người xem đọc, bình luận, chia sẻ. Máy tính: danh sách trái, bản báo cáo phải.
// Link /r/<id>[/<bản>] (tin của bot, QR) mở thẳng báo cáo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../state/app_state.dart';
import '../app_shell.dart';
import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'ask_ai.dart';
import 'blocks.dart';
import 'edition_page.dart';

Future<void> openReports(BuildContext context, MiniApp app, {String? path}) async {
  final state = context.read<AppState>();
  final host = AppHost.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await FlygoId.current(state.token);
    if (id == null) throw StateError('Máy chủ này chưa có Flygo ID');
    final api = ReportsApi(base: app.baseUrl, id: id);
    final m = path == null ? null : RegExp(r'/r/([A-Za-z0-9_-]{6,40})(?:/([A-Za-z0-9_-]{6,40}))?').firstMatch(path);
    if (m != null) {
      await host.open(key: app.id, title: app.name, deep: true, builder: (_) => EditionPage(api: api, reportId: m.group(1)!, editionId: m.group(2)));
    } else {
      await host.open(key: app.id, title: app.name, builder: (_) => ReportsHome(api: api, title: app.name));
    }
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

const reportIcons = <String, IconData>{
  'wb_sunny': Icons.wb_sunny_outlined,
  'account_balance': Icons.account_balance_outlined,
  'trending_up': Icons.trending_up_rounded,
  'schedule': Icons.schedule_rounded,
  'inventory_2': Icons.inventory_2_outlined,
  'receipt_long': Icons.receipt_long_outlined,
  'task_alt': Icons.task_alt_rounded,
  'assignment': Icons.assignment_outlined,
  'description': Icons.description_outlined,
};

Color _hex(String? s, Color d) {
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(s ?? '');
  return m == null ? d : Color(int.parse('FF${m.group(1)}', radix: 16));
}

class ReportsHome extends StatefulWidget {
  const ReportsHome({super.key, required this.api, this.title = 'Báo cáo', this.initialSelected});
  final ReportsSource api;
  final String title;

  /// Máy tính / ảnh chụp: báo cáo đang mở ở khung phải.
  final String? initialSelected;
  @override
  State<ReportsHome> createState() => _ReportsHomeState();
}

class _ReportsHomeState extends State<ReportsHome> {
  List<Json>? _reports;
  Object? _error;
  String _scope = 'all', _q = '';
  bool _searching = false;
  String? _selected;
  ReportsLive? _live;
  StreamSubscription<Json>? _liveSub;
  Timer? _reload;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected;
    _load();
    _connect();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _live?.close();
    _reload?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _live = await widget.api.live(all: true);
      _liveSub = _live?.events.listen((m) {
        if (m['type'] == 'edition' || m['type'] == 'report' || m['type'] == 'deleted') {
          _reload?.cancel();
          _reload = Timer(const Duration(milliseconds: 400), _load);
        }
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/reports', {'scope': _scope, if (_q.isNotEmpty) 'q': _q});
      if (!mounted) return;
      setState(() {
        _reports = [for (final r in (j['reports'] as List)) Map<String, dynamic>.from(r as Map)];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _askNew() => showAskAi(
    context,
    title: 'Nhờ AI lập báo cáo',
    hint: 'Vd: Cho anh báo cáo dòng tiền tuần này so với tuần trước, theo từng tài khoản. Mỗi sáng thứ Hai 8h gửi lại.',
    context_:
        'Lập báo cáo trong app Báo cáo: xem report_templates, report_create (hoặc dùng báo cáo có sẵn), lấy số bằng công cụ nguồn, '
        'rồi report_publish; mọi khối số ghi source; trả link báo cáo.',
  );

  Future<void> _open(Json r, bool wide) async {
    if (wide) {
      setState(() => _selected = '${r['id']}');
      return;
    }
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => EditionPage(api: widget.api, reportId: '${r['id']}'),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final list = _list(context, wide);
    return Scaffold(
      backgroundColor: wide ? p.bg : p.surface,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Tìm báo cáo…', border: InputBorder.none),
                onChanged: (v) {
                  _q = v.trim();
                  _load();
                },
              )
            : Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: kReportColor, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.insert_chart_outlined_rounded, color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                ],
              ),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching && _q.isNotEmpty) {
                _q = '';
                _load();
              }
            }),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          ),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _askNew,
                style: FilledButton.styleFrom(backgroundColor: kReportColor),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Nhờ AI lập báo cáo'),
              ),
            ),
        ],
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              onPressed: _askNew,
              backgroundColor: kReportColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Nhờ AI'),
            ),
      body: wide
          ? Row(
              children: [
                SizedBox(
                  width: 380,
                  child: ColoredBox(color: p.surface, child: list),
                ),
                VerticalDivider(width: 1, color: p.divider),
                Expanded(
                  child: _selected == null
                      ? Center(
                          child: Text('Chọn một báo cáo để xem', style: TextStyle(color: p.sub)),
                        )
                      : EditionPage(key: ValueKey(_selected), api: widget.api, reportId: _selected!, embedded: true, onChanged: _load),
                ),
              ],
            )
          : list,
    );
  }

  Widget _list(BuildContext context, bool wide) {
    final p = Pal.of(context);
    final rs = _reports;
    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Wrap(
        spacing: 6,
        children: [
          for (final (k, t) in [('all', 'Tất cả'), ('mine', 'Của tôi'), ('shared', 'Được chia sẻ')])
            ChoiceChip(
              label: Text(t),
              selected: _scope == k,
              showCheckmark: false,
              onSelected: (_) {
                setState(() => _scope = k);
                _load();
              },
            ),
        ],
      ),
    );
    if (_error != null && rs == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$_error',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub),
          ),
        ),
      );
    }
    if (rs == null) return const Center(child: CircularProgressIndicator());
    if (rs.isEmpty) {
      return ListView(
        children: [
          chips,
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              children: [
                Icon(Icons.insert_chart_outlined_rounded, size: 60, color: kReportColor.withValues(alpha: .7)),
                const SizedBox(height: 12),
                Text(
                  'Chưa có báo cáo nào',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nhắn trợ lý AI điều bạn muốn biết. AI tự lấy số liệu, chọn biểu đồ và lập báo cáo trong vài giây.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.sub, height: 1.4),
                ),
                const SizedBox(height: 14),
                for (final ex in [
                  'Báo cáo dòng tiền tuần này so với tuần trước',
                  'Mỗi sáng 7h30: tiền về, doanh số tháng, công nợ quá hạn',
                  'Tiến độ các quy trình đang chạy theo phòng',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ActionChip(
                      avatar: Icon(Icons.auto_awesome, size: 16, color: aiColor(context)),
                      label: Text(ex),
                      onPressed: () => showAskAi(
                        context,
                        title: 'Nhờ AI lập báo cáo',
                        initial: ex,
                        context_: 'Lập báo cáo trong app Báo cáo (report_templates → report_create → report_publish).',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    // Mới (chưa xem) lên đầu, rồi theo thời gian bản mới nhất.
    final unread = [
      for (final r in rs)
        if ((r['last'] as Map?)?['unread'] == true) r,
    ];
    final rest = [
      for (final r in rs)
        if ((r['last'] as Map?)?['unread'] != true) r,
    ];
    Widget sec(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.sub, letterSpacing: .4),
      ),
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          chips,
          if (unread.isNotEmpty) sec('Mới'),
          for (final r in unread) _ReportTile(r: r, selected: wide && _selected == r['id'], onTap: () => _open(r, wide)),
          if (rest.isNotEmpty) sec(unread.isEmpty ? 'Báo cáo' : 'Đã xem'),
          for (final r in rest) _ReportTile(r: r, selected: wide && _selected == r['id'], onTap: () => _open(r, wide)),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.r, required this.onTap, this.selected = false});
  final Json r;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final last = r['last'] as Map?;
    final color = _hex(r['color'] as String?, kReportColor);
    final kpis = [for (final k in (last?['kpis'] as List? ?? const [])) Map<String, dynamic>.from(k as Map)];
    final alerts = last?['alerts'] as int? ?? 0;
    final schedule = r['schedule'] as Map?;
    final warn = statusColors(context, 'warn');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: p.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? kReportColor : p.divider, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(10)),
                      child: Icon(reportIcons[r['icon']] ?? Icons.insert_chart_outlined_rounded, color: color, size: 21),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${r['title']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: p.text),
                                ),
                              ),
                              if (last?['unread'] == true)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(6)),
                                  child: const Text(
                                    'MỚI',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                              if (r['sensitive'] == true)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.lock_outline_rounded, size: 14, color: p.sub),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            last == null
                                ? 'Chưa có bản nào${schedule != null ? ' · ${schedule['when']}' : ''}'
                                : [
                                    '${last['period']?.toString().isNotEmpty == true ? last['period'] : 'bản #${last['seq']}'}',
                                    fmtMs(last['created_at'] as int).split(' ').first,
                                    if (last['by_ai'] == true) 'AI',
                                    if (schedule != null) '${schedule['when']}',
                                  ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: p.sub),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (kpis.isNotEmpty || alerts > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final k in kpis) _KpiChip(k: k),
                      if (alerts > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: warn.bg, borderRadius: BorderRadius.circular(7)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 13, color: warn.fg),
                              const SizedBox(width: 4),
                              Text(
                                '$alerts điểm cần chú ý',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: warn.fg),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({required this.k});
  final Json k;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = (k['delta'] as num?)?.toDouble();
    final better = d == null ? null : (k['good'] == 'down' ? -d : d) >= 0;
    final s = statusColors(
      context,
      better == null
          ? 'info'
          : better
          ? 'good'
          : 'crit',
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(7)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${k['title']} ',
              style: TextStyle(color: p.sub),
            ),
            TextSpan(
              text: '${k['value']}',
              style: TextStyle(fontWeight: FontWeight.w700, color: p.text),
            ),
            if (d != null) ...[
              const TextSpan(text: ' '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(d >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: s.fg),
              ),
              TextSpan(
                text: fmtPct(d).replaceFirst(RegExp(r'^[+-]'), ''),
                style: TextStyle(fontWeight: FontWeight.w700, color: s.fg),
              ),
            ],
          ],
        ),
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}
