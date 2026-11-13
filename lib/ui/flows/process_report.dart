import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_logic.dart' show flowStatusLabel;
import 'flows_page.dart' show flowStatusColor;
import 'flow_nav.dart';
import 'process_list.dart';

/// Báo cáo tiến trình của một quy trình: tổng số, theo trạng thái, theo bước (thanh ngang), cộng / trung bình các thống kê
/// số, biểu đồ cột theo ngày (tạo / xong / lỗi). Lọc theo khoảng ngày (7 / 30 / 90 ngày hoặc tự chọn) và nhãn.
class ProcessReportPage extends StatefulWidget {
  final AppState app;
  final String flowId, flowName;
  /// Nhãn để chọn ở bộ lọc; null thì tự lấy từ các tiến trình của quy trình.
  final List<String>? labels;
  const ProcessReportPage({super.key, required this.app, required this.flowId, required this.flowName, this.labels});
  @override
  State<ProcessReportPage> createState() => _ProcessReportPageState();
}

class _ProcessReportPageState extends State<ProcessReportPage> {
  late final api = FlowsApi(widget.app.token);
  /// Số ngày gần đây; 0 = khoảng tự chọn [_range].
  int _days = 30;
  DateTimeRange? _range;
  String? _label;
  List<String> _labels = const [];
  Map<String, dynamic>? _d;
  /// Thời gian theo bước (GET /reports/steps); null = chưa có / máy chủ cũ.
  Map<String, dynamic>? _steps;
  String? _err;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _labels = widget.labels ?? const [];
    if (widget.labels == null) {
      api.processes(flow: widget.flowId, limit: 200).then((list) {
        if (mounted) setState(() => _labels = ({for (final p in list) ...p.labels}.toList()..sort()));
      }).catchError((_) {});
    }
    _load();
  }

  (int, int) get _span {
    if (_days == 0 && _range != null) {
      final r = _range!;
      return (DateTime(r.start.year, r.start.month, r.start.day).millisecondsSinceEpoch, DateTime(r.end.year, r.end.month, r.end.day + 1).millisecondsSinceEpoch - 1);
    }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (_days - 1));
    return (start.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _err = null);
    try {
      final (from, to) = _span;
      final d = await api.processReport(widget.flowId, from: from, to: to, label: _label);
      if (mounted && seq == _seq) setState(() => _d = d);
      final st = await api.stepsReport(widget.flowId, from: from, to: to).then<Map<String, dynamic>?>((x) => x).catchError((_) => null);
      if (mounted && seq == _seq) setState(() => _steps = st);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _err = '$e');
    }
  }

  Future<void> _pickRange(int v) async {
    if (v != 0) {
      setState(() => _days = v);
      _load();
      return;
    }
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now),
    );
    if (r == null || !mounted) return;
    setState(() {
      _days = 0;
      _range = r;
    });
    _load();
  }

  String get _rangeLabel {
    if (_days > 0) return tr('{0} ngày', [_days]);
    final r = _range!;
    String f(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${f(r.start)} – ${f(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        leading: flowLeading(context),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Báo cáo tiến trình')),
          Text(widget.flowName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub, fontWeight: FontWeight.w400)),
        ]),
        actions: [IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in [7, 30, 90])
              ChoiceChip(label: Text(tr('{0} ngày', [v])), selected: _days == v, onSelected: (_) => _pickRange(v), visualDensity: VisualDensity.compact),
            ChoiceChip(
              avatar: const Icon(Icons.date_range_rounded, size: 16),
              label: Text(_days == 0 ? _rangeLabel : tr('Tự chọn')),
              selected: _days == 0,
              onSelected: (_) => _pickRange(0),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              tooltip: tr('Lọc theo nhãn'),
              onSelected: (v) {
                setState(() => _label = v.isEmpty ? null : v);
                _load();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: '', child: Text(tr('Tất cả nhãn'))),
                for (final l in _labels) PopupMenuItem(value: l, child: Text(l)),
              ],
              child: Chip(
                avatar: Icon(Icons.sell_outlined, size: 16, color: _label == null ? pal.sub : pal.accentText),
                label: Text(_label ?? tr('Nhãn')),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
        ),
        Expanded(
          child: _err != null
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Text(tr('Không tải được báo cáo: {0}', [_err]), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
                    ]),
                  ),
                ])
              : d == null
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
                        FlowReportCards(data: d),
                        if ((_steps?['steps'] as List? ?? const []).isNotEmpty) FlowStepTimes(data: _steps!),
                      ]),
                    ),
        ),
      ]),
    );
  }
}

/// Các thẻ báo cáo của một quy trình (tổng, theo trạng thái, theo bước, thống kê số, theo ngày). [runs]: dữ liệu của
/// GET /defs/{id}/runs-report (theo lần chạy: `by_status`, `avg_duration_ms`) thay cho báo cáo tiến trình.
class FlowReportCards extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool runs;
  const FlowReportCards({super.key, required this.data, this.runs = false});

  Widget _card(Pal pal, String title, List<Widget> children, {String? sub}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: pal.text)),
          if (sub != null) Text(sub, style: TextStyle(color: pal.sub, fontSize: 12.5)),
          const SizedBox(height: 10),
          if (children.isEmpty) Text(tr('Chưa có dữ liệu'), style: TextStyle(color: pal.sub)) else ...children,
        ]),
      );

  /// Một thanh ngang: nhãn, thanh tỉ lệ, số.
  Widget _bar(Pal pal, String label, num count, num max, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 128, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.text))),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: max <= 0 ? 0 : (count / max).clamp(0.0, 1.0).toDouble(), minHeight: 10, color: color, backgroundColor: pal.divider),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 44, child: Text(processStatValue(count), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
        ]),
      );

  Widget _legend(Pal pal, Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(fontSize: 12, color: pal.sub)),
      ]);

  /// "3 ngày 4 giờ", "2 giờ 15 phút", "12 phút".
  static String duration(num ms) {
    final m = (ms / 60000).round();
    if (m < 60) return tr('{0} phút', [m < 1 ? 1 : m]);
    final h = m ~/ 60;
    if (h < 24) return m % 60 == 0 ? tr('{0} giờ', [h]) : tr('{0} giờ {1} phút', [h, m % 60]);
    return h % 24 == 0 ? tr('{0} ngày', [h ~/ 24]) : tr('{0} ngày {1} giờ', [h ~/ 24, h % 24]);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = data;
    List<Map> list(String k) => [for (final x in (d[k] as List? ?? const [])) if (x is Map) x];
    final byState = ((d[runs ? 'by_status' : 'by_state'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num?) ?? 0));
    final known = runs ? const ['running', 'returned', 'failed', 'done', 'rejected', 'cancelled'] : const ['running', 'failed', 'done', 'cancelled', 'skipped'];
    final stateOrder = [...known, ...byState.keys.where((k) => !known.contains(k))];
    final maxState = byState.values.fold<num>(0, (m, v) => v > m ? v : m);
    final steps = list('by_step');
    final maxStep = steps.fold<num>(0, (m, s) => ((s['count'] as num?) ?? 0) > m ? (s['count'] as num) : m);
    final stats = list('stats');
    final daily = list('daily');
    final avg = d['avg_duration_ms'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _card(pal, tr('Tổng số tiến trình'), [
            Text(processStatValue((d['total'] as num?) ?? 0), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: pal.text)),
          ], sub: tr('Tạo trong khoảng đã chọn')),
        ),
        if (runs) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _card(pal, tr('Thời gian trung bình'), [
              Text(avg is num ? duration(avg) : '—', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: pal.text)),
            ], sub: tr('Từ lúc tạo tới khi hoàn tất ({0} tiến trình)', [processStatValue((d['done_count'] as num?) ?? 0)])),
          ),
        ],
      ]),
      _card(pal, tr('Theo trạng thái'), [
        for (final k in stateOrder)
          if (byState.containsKey(k))
            runs
                ? _bar(pal, flowStatusLabel(k), byState[k]!, maxState, flowStatusColor(k, pal.accentText))
                : _bar(pal, processStateLabel(k), byState[k]!, maxState, processStateColor(k)),
      ]),
      _card(pal, tr('Theo bước'), [
        for (final s in steps) _bar(pal, '${s['title'] ?? s['key']}', (s['count'] as num?) ?? 0, maxStep, pal.accentText),
      ], sub: tr('Số tiến trình đang ở mỗi bước')),
      if (!runs)
        _card(pal, tr('Thống kê'), [
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text('${s['label'] ?? s['key']}', style: TextStyle(fontSize: 13.5, color: pal.text, fontWeight: FontWeight.w600))),
                // Màn hẹp: số liệu xuống dòng trong phần của nó, không tràn.
                const SizedBox(width: 8),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(tr('Tổng {0}', [processStatValue(s['sum'])]), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: pal.text)),
                    Text(tr('TB {0} · {1} tiến trình', [processStatValue(s['avg']), processStatValue(s['count'])]), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: pal.sub)),
                  ]),
                ),
              ]),
            ),
        ]),
      _card(pal, tr('Theo ngày'), [
        if (daily.isNotEmpty) ...[
          SizedBox(height: 170, child: CustomPaint(painter: ProcessDailyChart(daily: daily, axis: pal.divider, text: pal.sub, created: pal.accentText, font: Theme.of(context).textTheme.bodySmall?.fontFamily))),
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [
            _legend(pal, pal.accentText, tr('Tạo mới')),
            _legend(pal, kFlowGreen, tr('Xong')),
            _legend(pal, kFlowRed, tr('Lỗi')),
          ]),
        ],
      ]),
    ]);
  }
}

/// "Thời gian theo bước": mỗi bước số lượt đã rời bước, số đang ở, thời gian trung bình / P50 / P90, số lượt quá hạn.
class FlowStepTimes extends StatelessWidget {
  final Map<String, dynamic> data;
  const FlowStepTimes({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final steps = [for (final x in (data['steps'] as List? ?? const [])) if (x is Map) x];
    String dur(Object? v) => v is num && v > 0 ? FlowReportCards.duration(v) : '—';
    TextStyle head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.sub);
    Widget cell(String t, {bool right = true, TextStyle? style, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: style ?? TextStyle(fontSize: 13, color: color ?? pal.text)),
        );
    return Container(
      key: const ValueKey('step-times'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Thời gian theo bước'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: pal.text)),
        Text(tr('Tính từ lúc vào tới lúc rời bước; quá hạn theo hạn của bước'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            columnWidths: const {0: MinColumnWidth(IntrinsicColumnWidth(), FixedColumnWidth(170))},
            border: TableBorder(horizontalInside: BorderSide(color: pal.divider)),
            children: [
              TableRow(children: [
                cell(tr('Bước'), right: false, style: head),
                for (final h in ['Số lượt', 'Đang ở', 'TB', 'P50', 'P90', 'Quá hạn']) cell(tr(h), style: head),
              ]),
              for (final s in steps)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['title'] ?? s['key']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text)),
                      if ('${s['sla'] ?? ''}'.isNotEmpty) Text(tr('Hạn {0}', [durLabelShort('${s['sla']}')]), style: TextStyle(fontSize: 11.5, color: pal.sub)),
                    ]),
                  ),
                  cell(processStatValue((s['count'] as num?) ?? 0)),
                  cell(processStatValue((s['active'] as num?) ?? 0)),
                  cell(dur(s['avg_ms'])),
                  cell(dur(s['p50_ms'])),
                  cell(dur(s['p90_ms'])),
                  cell(processStatValue((s['overdue'] as num?) ?? 0), color: ((s['overdue'] as num?) ?? 0) > 0 ? kFlowOrange : pal.text),
                ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// "8h" → "8 giờ", "2d" → "2 ngày", "3wd" → "3 ngày làm việc".
String durLabelShort(String d) {
  final m = RegExp(r'^(\d+)\s*(wd|[smhdw])$').firstMatch(d.trim());
  if (m == null) return d;
  return switch (m[2]) {
    'wd' => tr('{0} ngày làm việc', [m[1]]),
    's' => tr('{0} giây', [m[1]]),
    'm' => tr('{0} phút', [m[1]]),
    'h' => tr('{0} giờ', [m[1]]),
    'd' => tr('{0} ngày', [m[1]]),
    _ => tr('{0} tuần', [m[1]]),
  };
}

/// Thống kê chạy của một quy trình kèm chọn khoảng (7 / 30 / 90 ngày), tự tải: báo cáo tiến trình hoặc ([runs]) báo cáo
/// theo lần chạy. Dùng ở phần giới thiệu của trang quy trình.
class FlowStatsPanel extends StatefulWidget {
  final AppState app;
  final String flowId;
  final bool runs;
  const FlowStatsPanel({super.key, required this.app, required this.flowId, this.runs = false});
  @override
  State<FlowStatsPanel> createState() => _FlowStatsPanelState();
}

class _FlowStatsPanelState extends State<FlowStatsPanel> {
  late final api = FlowsApi(widget.app.token);
  int _days = 30;
  Map<String, dynamic>? _d;
  String? _err;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FlowStatsPanel old) {
    super.didUpdateWidget(old);
    if (old.flowId != widget.flowId || old.runs != widget.runs) _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - (_days - 1)).millisecondsSinceEpoch;
    final to = now.millisecondsSinceEpoch;
    try {
      final d = widget.runs ? await api.runsReport(widget.flowId, from: from, to: to) : await api.processReport(widget.flowId, from: from, to: to);
      if (mounted && seq == _seq) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Màn hẹp (điện thoại): tiêu đề một dòng, các ô chọn ngày xuống dòng dưới thay vì tràn.
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
        Text(tr('Thống kê chạy'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text)),
        Wrap(spacing: 6, children: [
          for (final v in [7, 30, 90])
            ChoiceChip(
              label: Text(tr('{0} ngày', [v])),
              selected: _days == v,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                setState(() => _days = v);
                _load();
              },
            ),
        ]),
      ]),
      const SizedBox(height: 10),
      if (_err != null)
        Text(tr('Không tải được báo cáo: {0}', [_err]), style: TextStyle(color: pal.sub))
      else if (_d == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        FlowReportCards(data: _d!, runs: widget.runs),
    ]);
  }
}

/// Biểu đồ cột theo ngày: mỗi ngày 3 cột (tạo, xong, lỗi), trục ngày ghi ngày đầu, giữa, cuối.
class ProcessDailyChart extends CustomPainter {
  final List<Map> daily;
  final Color axis, text, created;
  /// Font chữ trục (theo theme của app).
  final String? font;
  ProcessDailyChart({required this.daily, required this.axis, required this.text, required this.created, this.font});

  static num _n(Object? v) => v is num ? v : 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (daily.isEmpty) return;
    const bottom = 18.0, left = 26.0;
    final h = size.height - bottom, w = size.width - left;
    final max = daily.fold<num>(1, (m, d) => [m, _n(d['created']), _n(d['done']), _n(d['failed'])].reduce((a, b) => a > b ? a : b));
    final line = Paint()
      ..color = axis
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, h), Offset(size.width, h), line);
    void label(String s, Offset at, {TextAlign align = TextAlign.center}) {
      final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: text, fontFamily: font)), textDirection: TextDirection.ltr)..layout();
      final dx = switch (align) { TextAlign.left => 0.0, TextAlign.right => -tp.width, _ => -tp.width / 2 };
      tp.paint(canvas, at + Offset(dx, 0));
    }

    label('$max', const Offset(0, 0), align: TextAlign.left);
    label('0', Offset(0, h - 12), align: TextAlign.left);
    canvas.drawLine(Offset(left, 0), Offset(size.width, 0), line..color = axis.withValues(alpha: .5));
    final slot = w / daily.length;
    final bw = (slot / 4).clamp(1.0, 10.0);
    final colors = [created, kFlowGreen, kFlowRed];
    for (final (i, d) in daily.indexed) {
      final x0 = left + slot * i + (slot - bw * 3) / 2;
      for (final (j, k) in ['created', 'done', 'failed'].indexed) {
        final v = _n(d[k]);
        if (v <= 0) continue;
        final bh = (v / max) * (h - 4);
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x0 + bw * j, h - bh, bw, bh), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
          Paint()..color = colors[j],
        );
      }
    }
    String day(Object? s) {
      final t = '${s ?? ''}';
      // "2026-11-07" → "07/11".
      final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})').firstMatch(t);
      return m == null ? t : '${m[2]}/${m[1]}';
    }

    final idx = {0, daily.length ~/ 2, daily.length - 1};
    for (final i in idx) {
      final cx = left + slot * i + slot / 2;
      label(day(daily[i]['date']), Offset(cx.clamp(left + 14, size.width - 14), h + 4));
    }
  }

  @override
  bool shouldRepaint(ProcessDailyChart old) => old.daily != daily || old.created != created || old.axis != axis;
}
