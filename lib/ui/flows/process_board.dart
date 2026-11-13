import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange;
import 'process_list.dart';
import 'process_report.dart' show FlowReportCards;

/// Màu "Sắp hạn" (còn dưới 1/5 thời hạn của bước).
const kFlowAmber = Color(0xFFD99A06);

/// "Bảng theo dõi" (tab của trang Quy trình): tiến trình đang chạy / lỗi người xem được thấy, ở bước lâu nhất trước, nhóm
/// theo phòng ban của người đang được giao việc hoặc theo quy trình. Lọc phòng ban, quy trình, chỉ quá hạn. Đang hiện thì
/// 30 giây làm mới một lần. Bấm dòng mở trang tiến trình.
class ProcessBoardView extends StatefulWidget {
  final AppState app;
  final double bottomPadding;
  const ProcessBoardView({super.key, required this.app, this.bottomPadding = 0});
  @override
  State<ProcessBoardView> createState() => _ProcessBoardViewState();
}

class _ProcessBoardViewState extends State<ProcessBoardView> {
  late final api = FlowsApi(widget.app.token);
  Map<String, dynamic>? _d;
  String? _err;
  String? _dept, _flow;
  bool _overdue = false;
  /// true: nhóm theo phòng ban; false: theo quy trình.
  bool _byDept = true;
  Timer? _live;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _live?.cancel();
    final seq = ++_seq;
    try {
      final d = await api.board(dept: _dept, flow: _flow, overdue: _overdue);
      if (mounted && seq == _seq) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _err = '$e');
    }
    if (!mounted) return;
    _live = Timer(const Duration(seconds: 30), () {
      if (mounted && TickerMode.valuesOf(context).enabled) _load();
    });
  }

  List<Map<String, dynamic>> _list(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];

  Widget _filter(Pal pal, String label, String? value, List<Map<String, dynamic>> options, ValueChanged<String?> pick, String all) {
    final name = options.where((o) => '${o['id']}' == value).firstOrNull?['name'];
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: (v) => pick(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(all)),
        for (final o in options) PopupMenuItem(value: '${o['id']}', child: Text('${o['name'] ?? ''}')),
      ],
      child: Chip(
        avatar: Icon(Icons.filter_list_rounded, size: 16, color: value == null ? pal.sub : pal.accentText),
        label: Text(value == null ? label : '${name ?? label}'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _sla(Map<String, dynamic> p) => switch ('${(p['sla'] as Map?)?['state'] ?? 'none'}') {
        'overdue' => ProcessChip(text: tr('Quá hạn'), color: kFlowOrange, solid: true),
        'warn' => ProcessChip(text: tr('Sắp hạn'), color: kFlowAmber),
        _ => const SizedBox.shrink(),
      };

  Widget _row(Pal pal, Map<String, dynamic> p, {required bool showFlow}) {
    final fp = FlowProcess(p);
    final small = TextStyle(color: pal.sub, fontSize: 12.5);
    final names = [for (final a in _list(p['assignees'])) '${a['name'] ?? ''}'.trim()].where((x) => x.isNotEmpty).toList();
    final age = (p['age_ms'] as num?) ?? 0;
    final step = '${p['current_step_title'] ?? ''}'.trim();
    return InkWell(
      onTap: () async {
        await openProcess(context, widget.app, fp.id);
        if (mounted) _load();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          processIconBox(pal, fp, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(fp.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
                const SizedBox(width: 6),
                _sla(p),
              ]),
              const SizedBox(height: 2),
              Text(
                [if (showFlow) fp.flowName, if (step.isNotEmpty) tr('Bước: {0}', [step])].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small.copyWith(color: pal.text),
              ),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.person_outline_rounded, size: 14, color: pal.sub),
                const SizedBox(width: 3),
                Expanded(child: Text(names.isEmpty ? tr('Chưa giao ai') : names.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
                const SizedBox(width: 8),
                Icon(Icons.schedule_rounded, size: 14, color: pal.sub),
                const SizedBox(width: 3),
                Text(tr('ở bước {0}', [FlowReportCards.duration(age)]), style: small),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = _d;
    final depts = _list(d?['departments']);
    final flows = _list(d?['flows']);
    final procs = _list(d?['processes']);
    // Nhóm: theo phòng ban của người đang giao việc (một tiến trình có thể ở nhiều phòng) hoặc theo quy trình.
    final groups = <String, List<Map<String, dynamic>>>{};
    final none = tr('Chưa có phòng ban');
    for (final p in procs) {
      if (_byDept) {
        final ds = [for (final x in _list(p['departments'])) '${x['name'] ?? ''}'.trim()].where((x) => x.isNotEmpty).toSet();
        for (final n in ds.isEmpty ? {none} : ds) {
          (groups[n] ??= []).add(p);
        }
      } else {
        (groups['${p['flow_name'] ?? ''}'] ??= []).add(p);
      }
    }
    final keys = groups.keys.toList()..sort((a, b) => a == none ? 1 : (b == none ? -1 : a.compareTo(b)));
    final overdueCount = procs.where((p) => (p['sla'] as Map?)?['state'] == 'overdue').length;
    Widget body;
    if (_err != null && d == null) {
      body = ListView(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(tr('Không tải được bảng theo dõi: {0}', [_err]), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
          ]),
        ),
      ]);
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (procs.isEmpty) {
      body = ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_overdue ? tr('Không có tiến trình nào quá hạn.') : tr('Không có tiến trình nào đang chạy.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
        ),
      ]);
    } else {
      body = ListView(padding: EdgeInsets.only(bottom: 24 + widget.bottomPadding), children: [
        for (final k in keys) ...[
          Container(
            color: pal.surface2.withValues(alpha: .5),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Icon(_byDept ? Icons.groups_2_outlined : Icons.account_tree_outlined, size: 16, color: pal.sub),
              const SizedBox(width: 6),
              Expanded(child: Text(k, style: TextStyle(fontWeight: FontWeight.w800, color: pal.text))),
              Text(tr('{0} tiến trình', [groups[k]!.length]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ]),
          ),
          for (final p in groups[k]!) _row(pal, p, showFlow: _byDept),
        ],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(tr('Theo phòng ban'))),
              ButtonSegment(value: false, label: Text(tr('Theo quy trình'))),
            ],
            selected: {_byDept},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => setState(() => _byDept = s.first),
          ),
          _filter(pal, tr('Phòng ban'), _dept, depts, (v) {
            setState(() => _dept = v);
            _load();
          }, tr('Mọi phòng ban')),
          _filter(pal, tr('Quy trình'), _flow, flows, (v) {
            setState(() => _flow = v);
            _load();
          }, tr('Mọi quy trình')),
          FilterChip(
            label: Text(overdueCount > 0 && !_overdue ? tr('Chỉ quá hạn ({0})', [overdueCount]) : tr('Chỉ quá hạn')),
            selected: _overdue,
            visualDensity: VisualDensity.compact,
            onSelected: (v) {
              setState(() => _overdue = v);
              _load();
            },
          ),
        ]),
      ),
      Expanded(child: RefreshIndicator(onRefresh: _load, child: body)),
    ]);
  }
}
