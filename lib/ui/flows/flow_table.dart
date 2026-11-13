import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_form.dart' show MoneyInputFormatter;
import 'flow_lookup.dart';
import 'flow_logic.dart';

/// Trường kiểu bảng (nhiều dòng, vd sản phẩm của đơn hàng): tính cột tự tính + tổng giống máy chủ
/// (máy chủ vẫn tính lại khi nhận), ô nhập trong form, bảng xem trong chi tiết luồng.

num? _num(Object? v) => v is num ? v : (v is String ? (parseMoney(v) ?? num.tryParse(v.replaceAll(',', '.'))) : null);

num _round(num x, String type) {
  if (type == 'money') return x.round();
  final r = (x * 1e6).round() / 1e6;
  return r == r.roundToDouble() ? r.toInt() : r;
}

/// Giá trị cột tự tính của một dòng; null nếu thiếu số hoặc chia cho 0.
num? calcValue(FlowField c, Map row) {
  final k = c.calc;
  if (k == null) return null;
  final a = _num(row[k['a']]), b = _num(row[k['b']]);
  if (a == null || b == null) return null;
  final num x = switch ('${k['op']}') {
    'add' => a + b,
    'sub' => a - b,
    'div' => b == 0 ? double.nan : a / b,
    _ => a * b,
  };
  return x.isNaN ? null : _round(x, c.type);
}

/// Các dòng đã tính cột tự tính + tổng từng cột số.
(List<Map<String, dynamic>>, Map<String, num>) computeTable(FlowField f, Object? value) {
  final rows = [for (final r in (value is List ? value : const [])) if (r is Map) Map<String, dynamic>.of(r.cast<String, dynamic>())];
  final totals = <String, num>{for (final c in f.columns) if (c.type == 'money' || c.type == 'number') c.key: 0};
  for (final r in rows) {
    for (final c in f.columns) {
      if (c.calc != null) {
        final v = calcValue(c, r);
        v == null ? r.remove(c.key) : r[c.key] = v;
      }
      if (totals.containsKey(c.key)) totals[c.key] = totals[c.key]! + (_num(r[c.key]) ?? 0);
    }
  }
  return (rows, {for (final e in totals.entries) e.key: _round(e.value, f.columns.firstWhere((c) => c.key == e.key).type)});
}

/// "3 dòng · tổng Thành tiền 28.500.000 đ".
String tableSummary(FlowField f, Object? value) {
  final (rows, totals) = computeTable(f, value);
  final money = f.columns.lastWhere((c) => c.type == 'money', orElse: () => const FlowField(key: '', label: '', type: ''));
  return [
    tr('{0} dòng', [rows.length]),
    if (money.key.isNotEmpty && rows.isNotEmpty) tr('tổng {0} {1}', [money.label.toLowerCase(), showFieldValue(money, totals[money.key])]),
  ].join(' · ');
}

String _cell(FlowField c, Object? v) => v == null ? '' : showFieldValue(c, v);

/// Cột có dòng tổng: cột tự tính và cột số (số lượng). Cột tiền nhập tay (đơn giá) chỉ cộng khi bảng không có cột
/// tự tính, vì cộng đơn giá không có nghĩa.
bool tableTotalShown(FlowField f, FlowField c) =>
    c.calc != null || c.type == 'number' || (c.type == 'money' && !f.columns.any((x) => x.calc != null));

// ---------------------------------------------------------------------------------------------- nhập

class FlowTableInput extends StatefulWidget {
  final FlowField field;
  final Object? value;
  final String? error;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  /// Để tra danh mục cho cột có lookup (bỏ trống: cột đó thành ô chữ thường).
  final FlowsApi? api;
  final String? flowId;
  const FlowTableInput({super.key, required this.field, required this.value, required this.onChanged, this.error, this.api, this.flowId});
  @override
  State<FlowTableInput> createState() => _FlowTableInputState();
}

class _FlowTableInputState extends State<FlowTableInput> {
  late final List<Map<String, dynamic>> _rows = [
    for (final r in (widget.value is List ? widget.value as List : const [])) if (r is Map) Map<String, dynamic>.of(r.cast<String, dynamic>()),
  ];
  late final List<int> _ids = [for (var i = 0; i < _rows.length; i++) i];
  late int _next = _rows.length;

  List<FlowField> get _cols => widget.field.columns;

  @override
  void initState() {
    super.initState();
    if (_rows.isEmpty) _add(notify: false);
  }

  Map<String, dynamic> _blank() => {for (final c in _cols) if (c.defaultValue != null && c.calc == null) c.key: c.defaultValue};

  void _emit() => widget.onChanged([for (final r in _rows) Map.of(r)..removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty))]);

  void _add({bool notify = true, Map<String, dynamic>? from}) {
    setState(() {
      _rows.add(from == null ? _blank() : (Map.of(from)));
      _ids.add(_next++);
    });
    if (notify) _emit();
  }

  void _remove(int i) {
    setState(() {
      _rows.removeAt(i);
      _ids.removeAt(i);
    });
    _emit();
  }

  void _set(int i, FlowField c, Object? v) {
    setState(() => v == null ? _rows[i].remove(c.key) : _rows[i][c.key] = v);
    _emit();
  }

  Widget _input(BuildContext context, int i, FlowField c, {bool dense = false}) {
    final row = _rows[i];
    final key = ValueKey('${_ids[i]}-${c.key}');
    final deco = InputDecoration(
      labelText: dense ? null : (c.required ? '${c.label} *' : c.label),
      hintText: c.hint.isEmpty ? null : c.hint,
      isDense: true,
      border: const OutlineInputBorder(),
    );
    if (c.calc != null) {
      final v = calcValue(c, row);
      return InputDecorator(
        key: key,
        decoration: deco.copyWith(filled: true),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(v == null ? '—' : _cell(c, v), maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
    }
    if (c.lookup != null && widget.api != null && widget.flowId != null) {
      return LookupField(
        key: key,
        api: widget.api!,
        flowId: widget.flowId!,
        field: '${widget.field.key}.${c.key}',
        label: c.required ? '${c.label} *' : c.label,
        value: row[c.key] as String?,
        dense: dense,
        onPicked: (it) {
          _set(i, c, it['value']);
          // Điền các cột khác của dòng (vd đơn giá) theo cấu hình danh mục.
          for (final e in ((c.lookup!['fill'] as Map?) ?? const {}).entries) {
            final v = (it['data'] as Map?)?[e.value];
            final col = _cols.where((x) => x.key == '${e.key}').firstOrNull;
            if (v != null && col != null) _set(i, col, col.type == 'money' || col.type == 'number' ? (_num(v) ?? v) : v);
          }
          setState(() => _ids[i] = _next++);
        },
      );
    }
    switch (c.type) {
      case 'money' || 'number':
        final money = c.type == 'money';
        final v = row[c.key];
        return TextFormField(
          key: key,
          initialValue: v == null ? '' : (money && v is num ? vnNumber(v) : '$v'),
          keyboardType: TextInputType.number,
          inputFormatters: money ? [MoneyInputFormatter()] : null,
          decoration: deco.copyWith(suffixText: money ? 'đ' : null),
          onChanged: (t) => _set(i, c, t.trim().isEmpty ? null : (_num(t) ?? t)),
        );
      case 'select':
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: c.options.contains(row[c.key]) ? row[c.key] as String : null,
          isExpanded: true,
          decoration: deco,
          items: [for (final o in c.options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _set(i, c, v),
        );
      case 'bool':
        return InputDecorator(
          key: key,
          decoration: deco,
          child: Align(alignment: Alignment.centerLeft, child: Checkbox(value: row[c.key] == true, onChanged: (v) => _set(i, c, v == true))),
        );
      case 'date':
        final v = row[c.key];
        return InkWell(
          key: key,
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.tryParse('${v ?? ''}') ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (d != null) _set(i, c, d.toIso8601String().substring(0, 10));
          },
          child: InputDecorator(decoration: deco, child: Text(v == null ? tr('Chọn ngày') : _cell(c, v))),
        );
      default:
        return TextFormField(key: key, initialValue: '${row[c.key] ?? ''}', decoration: deco, onChanged: (t) => _set(i, c, t));
    }
  }

  Widget _rowMenu(int i) => PopupMenuButton<String>(
        tooltip: tr('Thao tác dòng'),
        icon: const Icon(Icons.more_vert_rounded, size: 20),
        onSelected: (a) => a == 'copy' ? _add(from: _rows[i]) : _remove(i),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'copy', child: Text(tr('Nhân bản dòng'))),
          PopupMenuItem(value: 'delete', child: Text(tr('Xoá dòng'), style: const TextStyle(color: Colors.redAccent))),
        ],
      );

  /// Màn rộng: dạng bảng như Excel.
  Widget _grid(BuildContext context, Pal pal) {
    int flex(FlowField c) => switch (c.type) { 'text' || 'textarea' => 4, 'money' => 3, _ => 2 };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 40, 6),
        child: Row(children: [
          for (final c in _cols)
            Expanded(
              flex: flex(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(c.required ? '${c.label} *' : c.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pal.sub)),
              ),
            ),
        ]),
      ),
      for (var i = 0; i < _rows.length; i++)
        Padding(
          key: ValueKey(_ids[i]),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 36, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(color: pal.sub))),
            for (final c in _cols) Expanded(flex: flex(c), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _input(context, i, c, dense: true))),
            SizedBox(width: 40, child: _rowMenu(i)),
          ]),
        ),
    ]);
  }

  /// Màn hẹp (điện thoại): mỗi dòng một thẻ.
  Widget _cards(BuildContext context, Pal pal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < _rows.length; i++)
          Container(
            key: ValueKey(_ids[i]),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(tr('Dòng {0}', [i + 1]), style: TextStyle(fontWeight: FontWeight.w700, color: pal.sub))),
                _rowMenu(i),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(spacing: 8, runSpacing: 10, children: [
                  for (final c in _cols)
                    LayoutBuilder(builder: (context, box) {
                      final half = c.type == 'number' || c.type == 'bool' || c.type == 'date';
                      return SizedBox(width: half ? (box.maxWidth - 8) / 2 : box.maxWidth, child: _input(context, i, c));
                    }),
                ]),
              ),
            ]),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final f = widget.field;
    final (_, totals) = computeTable(f, _rows);
    final shown = [for (final c in _cols) if (totals.containsKey(c.key) && tableTotalShown(f, c)) c];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.table_chart_outlined, size: 18, color: pal.accentText),
        const SizedBox(width: 6),
        Expanded(child: Text(f.required ? '${f.label} *' : f.label, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
        Text(tr('{0} dòng', [_rows.length]), style: TextStyle(color: pal.sub, fontSize: 12.5)),
      ]),
      if (f.hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(f.hint, style: TextStyle(color: pal.sub, fontSize: 12.5))),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) => box.maxWidth >= 600 ? _grid(context, pal) : _cards(context, pal)),
      Row(children: [
        TextButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm dòng'))),
        const Spacer(),
        if (shown.isNotEmpty)
          Flexible(
            child: Text(
              [for (final c in shown) '${tr('Tổng')} ${c.label.toLowerCase()}: ${_cell(c, totals[c.key])}'].join('\n'),
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
            ),
          ),
      ]),
      if (widget.error != null) Text(widget.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------- xem

/// Bảng chỉ đọc trong chi tiết luồng (cuộn ngang nếu nhiều cột), dòng tổng ở cuối.
class FlowTableView extends StatelessWidget {
  final FlowField field;
  final Object? value;
  const FlowTableView({super.key, required this.field, required this.value});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final (rows, totals) = computeTable(field, value);
    final cols = field.columns;
    bool right(FlowField c) => c.type == 'money' || c.type == 'number';
    Widget cell(String t, {bool bold = false, bool alignRight = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(t, textAlign: alignRight ? TextAlign.right : TextAlign.left, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color ?? pal.text, fontSize: 13.5)),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.divider)),
        clipBehavior: Clip.antiAlias,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: pal.divider)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: pal.surface2),
              children: [cell('#', bold: true, color: pal.sub), for (final c in cols) cell(c.label, bold: true, alignRight: right(c), color: pal.sub)],
            ),
            for (var i = 0; i < rows.length; i++)
              TableRow(children: [cell('${i + 1}', color: pal.sub), for (final c in cols) cell(_cell(c, rows[i][c.key]), alignRight: right(c))]),
            if (totals.isNotEmpty)
              TableRow(
                decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.08)),
                children: [
                  cell(tr('Tổng'), bold: true),
                  for (final c in cols) cell(totals.containsKey(c.key) && tableTotalShown(field, c) ? _cell(c, totals[c.key]) : '', bold: true, alignRight: right(c)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
