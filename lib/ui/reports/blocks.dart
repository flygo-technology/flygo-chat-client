// Khối của một bản báo cáo (dữ liệu AI đẩy vào, xem flygo-chat-server reports/src/blocks.ts): KPI, đường, cột, cột ngang,
// tỉ trọng, bảng, cảnh báo, chữ, việc. Chạm vào khối có số để xem nguồn (công cụ, cách tính, số liệu đến lúc nào).
import 'package:flutter/material.dart';

import '../markdown_view.dart';
import '../shell_highlight.dart' show kMonoFont;
import '../theme.dart';
import 'api.dart';
import 'charts.dart';
import 'charts_more.dart';

const kReportColor = Color(0xFF4B55C9);
const _numeric = {
  'kpi',
  'line',
  'area',
  'bar',
  'stacked_bar',
  'hbar',
  'pie',
  'gauge',
  'funnel',
  'waterfall',
  'scatter',
  'heatmap',
  'treemap',
  'progress',
  'table',
};

List<double> _nums(Object? v) => [for (final x in (v as List? ?? const [])) (x as num).toDouble()];
List<String> _strs(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
List<({String name, List<double> values})> _series(Json b) => [
  for (final s in (b['series'] as List? ?? const [])) (name: '${(s as Map)['name']}', values: _nums(s['values'])),
];

/// Màu trạng thái (luôn đi kèm biểu tượng + chữ, không chỉ dựa vào màu).
({Color fg, Color bg}) statusColors(BuildContext context, String level) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (level) {
    'crit' => dark ? (fg: const Color(0xFFFF7A7A), bg: const Color(0xFF3D1616)) : (fg: const Color(0xFFC62828), bg: const Color(0xFFFDE5E5)),
    'good' => dark ? (fg: const Color(0xFF4CC47F), bg: const Color(0xFF143222)) : (fg: const Color(0xFF1A8F4E), bg: const Color(0xFFE3F5EA)),
    'info' => dark ? (fg: const Color(0xFF8EC3FF), bg: const Color(0xFF0F2A4A)) : (fg: const Color(0xFF0B4A9E), bg: const Color(0xFFDCEBFF)),
    _ => dark ? (fg: const Color(0xFFF2B451), bg: const Color(0xFF3A2A0C)) : (fg: const Color(0xFFB26A00), bg: const Color(0xFFFFF1D6)),
  };
}

Color aiColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB3A1FF) : const Color(0xFF6B4FD6);
Color aiBg(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF251E40) : const Color(0xFFF1EDFD);

/// Thẻ nền cho một khối.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.child, this.color, this.onTap, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Material(
      color: color ?? p.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: color == null ? BorderSide(color: p.divider) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Dấu nguồn nhỏ ở góc khối số.
class SourceMark extends StatelessWidget {
  const SourceMark({super.key, required this.block});
  final Json block;
  @override
  Widget build(BuildContext context) {
    final src = block['source'] as Map?;
    final p = Pal.of(context);
    final ok = src?['tool'] != null;
    return Tooltip(
      message: ok ? 'Nguồn: ${src!['tool']}' : 'Nguồn: ${src?['note'] ?? 'không rõ'}',
      child: Icon(ok ? Icons.verified_outlined : Icons.edit_note_rounded, size: 15, color: ok ? p.accentText : p.sub),
    );
  }
}

// ---------------------------------------------------------------- KPI
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.block, this.prev, this.onTap});
  final Json block;
  final num? prev; // giá trị cùng mã ở bản trước
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final v = (block['value'] as num).toDouble();
    final unit = block['unit'] as String?;
    final cmp = block['compare'] as Map?;
    final target = (block['target'] as num?)?.toDouble();
    final good = block['good'] == 'down' ? -1 : 1;
    final base = (cmp?['value'] as num?)?.toDouble() ?? prev?.toDouble();
    final delta = base == null || base == 0 ? null : (v - base) / base.abs();
    final better = delta == null ? null : delta * good >= 0;
    final s = statusColors(
      context,
      better == null
          ? 'info'
          : better
          ? 'good'
          : 'crit',
    );
    final valueText = fmtValue(v, unit);
    final sp = valueText.lastIndexOf(' ');
    return ReportCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${block['title'] ?? block['id']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.sub, height: 1.25),
                ),
              ),
              SourceMark(block: block),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: sp > 0 && !RegExp(r'^\d').hasMatch(valueText.substring(sp + 1)) ? valueText.substring(0, sp) : valueText,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text, letterSpacing: -.3),
                ),
                if (sp > 0 && !RegExp(r'^\d').hasMatch(valueText.substring(sp + 1)))
                  TextSpan(
                    text: ' ${valueText.substring(sp + 1)}',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.sub),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (target != null && target != 0) ...[
            const SizedBox(height: 8),
            _Progress(value: v / target),
            const SizedBox(height: 4),
            Text('${(v / target * 100).round()}% kế hoạch ${fmtValue(target, unit)}', style: TextStyle(fontSize: 12, color: p.sub)),
          ],
          if (delta != null) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(delta >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: s.fg),
                  ),
                  TextSpan(
                    text: fmtPct(delta).replaceFirst(RegExp(r'^[+-]'), ''),
                    style: TextStyle(color: s.fg, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' so với ${cmp?['label'] ?? 'bản trước'}'),
                ],
              ),
              style: TextStyle(fontSize: 12, color: p.sub),
              maxLines: 2,
            ),
          ],
          if ((block['trend'] as List?)?.isNotEmpty == true) ...[const SizedBox(height: 6), Sparkline(values: _nums(block['trend']))],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      height: 8,
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: kReportColor, borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- khối có tiêu đề
class BlockView extends StatelessWidget {
  const BlockView({super.key, required this.block, this.onSource});
  final Json block;
  final VoidCallback? onSource;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final type = '${block['type']}';
    final title = block['title'] as String?;
    switch (type) {
      case 'alert':
        final level = '${block['level'] ?? 'warn'}';
        final s = statusColors(context, level);
        return ReportCard(
          color: s.bg,
          onTap: onSource,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                level == 'crit'
                    ? Icons.error_outline_rounded
                    : level == 'info'
                    ? Icons.info_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 20,
                color: s.fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.text),
                      ),
                    MarkdownView(
                      text: '${block['text'] ?? ''}',
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: p.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'text':
        final ai = block['style'] == 'ai';
        return ReportCard(
          color: ai ? aiBg(context) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ai || title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      if (ai) Icon(Icons.auto_awesome, size: 15, color: aiColor(context)),
                      if (ai) const SizedBox(width: 6),
                      Text(
                        title ?? 'AI nhận định',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ai ? aiColor(context) : p.text),
                      ),
                    ],
                  ),
                ),
              MarkdownView(
                text: '${block['text'] ?? ''}',
                style: TextStyle(fontSize: 14.5, height: 1.5, color: p.text),
              ),
            ],
          ),
        );
      case 'todo':
        return ReportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title ?? 'Việc cần làm',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text),
              ),
              const SizedBox(height: 6),
              for (final it in (block['items'] as List? ?? const []))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon((it as Map)['done'] == true ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18, color: p.sub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownView(
                              text: '${it['text']}',
                              style: TextStyle(fontSize: 14, color: p.text),
                            ),
                            if (it['assignee'] != null) Text('${it['assignee']}', style: TextStyle(fontSize: 12.5, color: p.accentText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
    }
    // Khối số: tiêu đề + nguồn + biểu đồ / bảng.
    Widget body;
    final unit = block['unit'] as String?;
    switch (type) {
      case 'line':
      case 'area':
        body = LineChart(x: _strs(block['x']), series: _series(block), unit: unit, fill: type == 'area');
      case 'bar' when block['series'] != null:
      case 'stacked_bar':
        body = MultiBarChart(labels: _strs(block['labels']), series: _series(block), stacked: type == 'stacked_bar', unit: unit);
      case 'bar':
      case 'hbar':
        body = BarChart(
          labels: _strs(block['labels']),
          values: _nums(block['values']),
          unit: unit,
          highlight: block['highlight'] as int?,
          horizontal: type == 'hbar',
        );
      case 'gauge':
        body = Center(
          child: GaugeChart(
            value: (block['value'] as num).toDouble(),
            max: (block['max'] as num).toDouble(),
            min: (block['min'] as num? ?? 0).toDouble(),
            target: (block['target'] as num?)?.toDouble(),
            unit: unit,
          ),
        );
      case 'funnel':
        body = FunnelChart(labels: _strs(block['labels']), values: _nums(block['values']), unit: unit);
      case 'waterfall':
        body = WaterfallChart(start: (block['start'] as num).toDouble(), labels: _strs(block['labels']), values: _nums(block['values']), unit: unit);
      case 'scatter':
        body = ScatterChart(
          points: [
            for (final pt in (block['points'] as List? ?? const []))
              (x: ((pt as Map)['x'] as num).toDouble(), y: (pt['y'] as num).toDouble(), label: pt['label'] as String?),
          ],
          xLabel: block['x_label'] as String?,
          yLabel: block['y_label'] as String?,
          xUnit: unit,
          yUnit: block['y_unit'] as String?,
        );
      case 'heatmap':
        body = HeatmapChart(x: _strs(block['x']), y: _strs(block['y']), matrix: [for (final r in (block['matrix'] as List? ?? const [])) _nums(r)], unit: unit);
      case 'treemap':
        body = TreemapChart(labels: _strs(block['labels']), values: _nums(block['values']), unit: unit);
      case 'progress':
        body = ProgressList(
          items: [
            for (final it in (block['progress'] as List? ?? const []))
              (label: '${(it as Map)['label']}', value: (it['value'] as num).toDouble(), target: (it['target'] as num).toDouble()),
          ],
          unit: unit,
        );
      case 'pie':
        body = PieChart(labels: _strs(block['labels']), values: _nums(block['values']), unit: unit);
      case 'table':
        body = ReportTable(block: block);
      default:
        body = Text('Khối "$type" chưa hỗ trợ trên bản app này', style: TextStyle(color: p.sub));
    }
    return ReportCard(
      onTap: onSource,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title ?? '${block['id']}',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text),
                ),
              ),
              if (_numeric.contains(type)) SourceMark(block: block),
            ],
          ),
          if (unit != null && const {'line', 'area', 'bar', 'stacked_bar', 'waterfall', 'heatmap'}.contains(type))
            Text(unit == 'VND' ? 'đơn vị: ₫' : 'đơn vị: $unit', style: TextStyle(fontSize: 12, color: p.sub)),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- bảng
class ReportTable extends StatelessWidget {
  const ReportTable({super.key, required this.block, this.maxRows = 8});
  final Json block;
  final int maxRows;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final cols = [for (final c in (block['columns'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];
    final rows = [for (final r in (block['rows'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    String cell(Json c, Object? v) {
      if (v == null) return '';
      return switch ('${c['type']}') {
        'money' => v is num ? fmtValue(v, 'VND') : '$v',
        'percent' => v is num ? fmtValue(v, '%') : '$v',
        'number' => v is num ? fmtValue(v) : '$v',
        _ => '$v',
      };
    }

    final num0 = {for (final c in cols) c['key']: c['type'] != 'text' && c['type'] != 'date'};
    final head = TextStyle(fontSize: 11.5, color: p.sub, fontWeight: FontWeight.w500);
    final body = TextStyle(fontSize: 13, color: p.text, fontFeatures: const [FontFeature.tabularFigures()]);
    final shown = rows.take(maxRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          columnWidths: {for (var i = 0; i < cols.length; i++) i: i == 0 ? const FlexColumnWidth(2) : const FlexColumnWidth(1)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.divider)),
              ),
              children: [
                for (final c in cols)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                    child: Text('${c['label']}', style: head, textAlign: num0[c['key']]! ? TextAlign.right : TextAlign.left),
                  ),
              ],
            ),
            for (final r in shown)
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.divider)),
                ),
                children: [
                  for (final c in cols)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
                      child: Text(
                        cell(c, r[c['key']]),
                        style: body,
                        textAlign: num0[c['key']]! ? TextAlign.right : TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (rows.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('+ ${rows.length - shown.length} dòng nữa (chạm để xem hết)', style: TextStyle(fontSize: 12, color: p.accentText)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- nguồn số liệu
Future<void> showSourceSheet(BuildContext context, Json block) {
  final p = Pal.of(context);
  final src = Map<String, dynamic>.from((block['source'] as Map?) ?? const {});
  final type = '${block['type']}';
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: type == 'table' ? .8 : .55,
      maxChildSize: .95,
      builder: (c, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${block['title'] ?? block['id']}',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
          ),
          if (type == 'kpi') ...[
            const SizedBox(height: 6),
            SelectableText(
              fmtValue(block['value'] as num, block['unit'] as String?),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p.text),
            ),
            if (block['unit'] == 'VND')
              Text('${(block['value'] as num).round()} ₫'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.'), style: TextStyle(color: p.sub)),
          ],
          const SizedBox(height: 14),
          if (src.isEmpty)
            Text('Khối này không ghi nguồn.', style: TextStyle(color: p.sub))
          else ...[
            _kv(context, src['tool'] != null ? 'AI lấy bằng' : 'Nguồn', '${src['tool'] ?? src['note']}', mono: src['tool'] != null),
            if (src['tool'] != null && src['note'] != null) _kv(context, 'Ghi chú', '${src['note']}'),
            if (src['calc'] != null) _kv(context, 'Cách tính', '${src['calc']}', mono: true),
            if (src['as_of'] != null) _kv(context, 'Số liệu đến', fmtAsOf('${src['as_of']}')),
            if (src['args'] != null) _kv(context, 'Tham số', '${src['args']}', mono: true),
            if (src['calls'] != null) _kv(context, 'Mã lần gọi', (src['calls'] as List).join(', '), mono: true),
          ],
          if (type == 'table') ...[const SizedBox(height: 14), ReportTable(block: block, maxRows: 500)],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
            child: Text(
              src['tool'] != null
                  ? 'Số do AI lấy từ công cụ trên bằng quyền của người ra lệnh, rồi đẩy vào báo cáo. Muốn đối chiếu thì hỏi AI hoặc mở nguồn gốc.'
                  : 'Số không lấy từ công cụ: kiểm lại với người ghi nguồn.',
              style: TextStyle(fontSize: 12.5, color: p.sub, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _kv(BuildContext context, String k, String v, {bool mono = false}) {
  final p = Pal.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: TextStyle(fontSize: 12, color: p.sub, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: mono ? const EdgeInsets.all(8) : EdgeInsets.zero,
          decoration: mono ? BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)) : null,
          child: SelectableText(
            v,
            style: TextStyle(fontSize: mono ? 12.5 : 14, color: p.text, fontFamily: mono ? kMonoFont : null),
          ),
        ),
      ],
    ),
  );
}
