import 'dart:convert';

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowRed;

/// Bước người làm (duyệt, điền, tiếp nhận...): đã có dòng riêng trong "Diễn biến" từ sự kiện, không lặp lại.
const _humanTypes = {'start', 'approval', 'approval_request', 'form_task', 'claim', 'task', 'confirm', 'delegate_request', 'delegate_approve', 'start_flow'};

/// Bước chỉ để rẽ nhánh / báo tiến độ: chỉ hiện trong phần gỡ lỗi.
const _quietTypes = {'condition', 'progress', 'join', 'parallel'};

bool _shown(Map n) => !_humanTypes.contains(n['type']) && !_quietTypes.contains(n['type']);

Map<String, Map<String, dynamic>> _nodes(Map def) => {
      for (final n in (def['nodes'] as List? ?? const []))
        if (n is Map) '${n['id']}': n.cast<String, dynamic>(),
    };

/// Bước kế tiếp theo đường chính: các cạnh, và với bước điều kiện là quy tắc đầu tiên (nhánh `else` thường là nhánh lỗi).
List<String> _next(Map def, Map<String, dynamic> n) => [
      for (final e in (def['edges'] as List? ?? const []))
        if (e is List && e.length >= 2 && '${e[0]}' == n['id']) '${e[1]}',
      if (n['type'] == 'condition')
        for (final r in (n['rules'] as List? ?? const []).take(1))
          if (r is Map && r['to'] != null) '${r['to']}',
      // Bước Duyệt: đường chính là nhánh Phê duyệt.
      if (n['type'] == 'approval_request' && '${n['approve_to'] ?? ''}'.isNotEmpty) '${n['approve_to']}',
    ];

/// Các bước sắp tới (chưa chạy) theo đường chính, tính từ các bước đang chờ.
List<String> flowUpcoming(Map def, Map steps, List active) {
  final nodes = _nodes(def);
  final out = <String>[];
  final seen = <String>{...steps.keys.map((k) => '$k')};
  var front = [for (final t in active) if (t is Map) '${t['node']}'];
  while (front.isNotEmpty && out.length < 30) {
    final next = <String>[];
    for (final id in front) {
      final n = nodes[id];
      if (n == null) continue;
      for (final to in _next(def, n)) {
        if (seen.add(to)) {
          out.add(to);
          next.add(to);
        }
      }
    }
    front = next;
  }
  return out;
}

String _dur(int ms) {
  final s = (ms / 1000).round();
  if (s < 60) return tr('{0} giây', ['$s']);
  final m = s ~/ 60;
  if (m < 60) return s % 60 == 0 ? tr('{0} phút', ['$m']) : tr('{0} phút {1} giây', ['$m', '${s % 60}']);
  return tr('{0} giờ {1} phút', ['${m ~/ 60}', '${m % 60}']);
}

/// Một dòng trong "Diễn biến": sự kiện (nộp, duyệt...), bước tự động đã / đang chạy, hoặc bước sắp tới (mờ).
class FlowTimelineLine {
  final String text;
  final int at;
  final String kind; // event | done | active | error | next
  final String? detail;
  const FlowTimelineLine(this.text, this.at, this.kind, [this.detail]);
}

/// Dựng "Diễn biến": sự kiện + bước tự động theo thời gian, rồi các bước sắp tới (khi đơn còn chạy).
List<FlowTimelineLine> flowTimeline(Map<String, dynamic> d, List<(String, int)> events, String Function(String id) stepName) {
  final def = (d['def'] as Map?) ?? const {};
  final nodes = _nodes(def);
  final steps = ((d['steps'] as Map?) ?? const {}).cast<String, dynamic>();
  final now = DateTime.now().millisecondsSinceEpoch;
  final lines = <FlowTimelineLine>[for (final (text, at) in events) FlowTimelineLine(text, at, 'event')];
  for (final e in steps.entries) {
    final n = nodes[e.key];
    final st = e.value;
    if (n == null || st is! Map || !_shown(n)) continue;
    final start = (st['started_at'] as num?)?.toInt() ?? 0;
    final end = (st['ended_at'] as num?)?.toInt();
    final status = '${st['status']}';
    final kind = status == 'error' ? 'error' : (status == 'active' ? 'active' : 'done');
    final took = kind == 'active' ? _dur(now - start) : (end != null && end - start >= 1000 ? _dur(end - start) : null);
    lines.add(FlowTimelineLine(stepName(e.key), start, kind, took));
  }
  lines.sort((a, b) => a.at.compareTo(b.at));
  if (d['status'] == 'running') {
    for (final id in flowUpcoming(def, steps, (d['waiting'] as List?) ?? const [])) {
      final n = nodes[id];
      if (n != null && _shown(n)) lines.add(FlowTimelineLine(stepName(id), 0, 'next'));
    }
  }
  return lines;
}

class FlowTimelineRow extends StatelessWidget {
  final FlowTimelineLine line;
  final String when;
  const FlowTimelineRow({super.key, required this.line, required this.when});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final next = line.kind == 'next';
    final Widget dot = switch (line.kind) {
      'active' => SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accentText)),
      'done' => const Icon(Icons.check_circle_rounded, size: 14, color: kFlowGreen),
      'error' => const Icon(Icons.error_rounded, size: 14, color: kFlowRed),
      'next' => Icon(Icons.radio_button_unchecked_rounded, size: 12, color: pal.sub),
      _ => Icon(Icons.circle, size: 8, color: pal.accentText),
    };
    return Opacity(
      opacity: next ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 14, child: Padding(padding: const EdgeInsets.only(top: 3), child: Center(child: dot))),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: line.text, style: TextStyle(color: line.kind == 'error' ? kFlowRed : pal.text, fontWeight: line.kind == 'active' ? FontWeight.w700 : null)),
              if (line.kind == 'active') TextSpan(text: '  ${tr('đang chạy')}', style: TextStyle(color: pal.accentText, fontSize: 12)),
              if (line.detail != null) TextSpan(text: '  · ${line.detail}', style: TextStyle(color: pal.sub, fontSize: 12)),
            ])),
          ),
          const SizedBox(width: 8),
          Text(next ? '' : when, style: TextStyle(color: pal.sub, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Gỡ lỗi: dữ liệu thô của từng bước (trạng thái, thời gian, kết quả), bước đang chờ và tiến độ. Cập nhật cùng trang.
class FlowDebugPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(String id) stepName;
  final String Function(int ms) when;
  const FlowDebugPanel({super.key, required this.data, required this.stepName, required this.when});

  static String _json(Object? v, [int max = 4000]) {
    final s = const JsonEncoder.withIndent('  ').convert(v);
    return s.length > max ? '${s.substring(0, max)}\n… (${tr('cắt bớt, tổng {0} ký tự', ['${s.length}'])})' : s;
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final nodes = _nodes((data['def'] as Map?) ?? const {});
    final steps = ((data['steps'] as Map?) ?? const {}).entries.where((e) => e.value is Map).toList()
      ..sort((a, b) => ((a.value as Map)['started_at'] as num? ?? 0).compareTo((b.value as Map)['started_at'] as num? ?? 0));
    final mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'], fontSize: 11.5, color: pal.text);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: Text(tr('Gỡ lỗi')),
        subtitle: Text(tr('Dữ liệu từng bước, tự cập nhật khi đơn đang chạy'), style: TextStyle(color: pal.sub, fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            'status: ${data['status']} · version: ${data['flow_version']} · id: ${data['id']}\n'
            'waiting: ${[for (final t in (data['waiting'] as List? ?? const [])) if (t is Map) t['node']].join(', ')}\n'
            'progress: ${jsonEncode(data['progress'])}',
            style: mono,
          ),
          for (final e in steps)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text('${stepName('${e.key}')}  [${e.key} · ${nodes['${e.key}']?['type'] ?? '?'}]',
                    style: TextStyle(fontSize: 13, color: (e.value as Map)['status'] == 'error' ? kFlowRed : pal.text)),
                subtitle: Text(
                  '${(e.value as Map)['status']} · ${when(((e.value as Map)['started_at'] as num?)?.toInt() ?? 0)}'
                  '${(e.value as Map)['ended_at'] is num ? ' → ${when(((e.value as Map)['ended_at'] as num).toInt())}' : ''}',
                  style: TextStyle(fontSize: 12, color: pal.sub),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(6)),
                    child: SelectableText(_json((e.value as Map)['output']), style: mono),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
