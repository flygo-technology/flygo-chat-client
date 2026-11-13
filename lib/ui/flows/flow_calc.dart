import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange;
import 'flow_cond.dart';
import 'flow_editor.dart' show CondDialog, slugKey;
import 'flow_editor_expr.dart';
import 'flow_editor_expr_field.dart';

/// Bước "Tính toán": các biến từ phép tính chọn sẵn (không gõ công thức). Mỗi biến `{name, label, op, args}`;
/// tham số là `{"path": thông tin của luồng}` hoặc `{"value": giá trị nhập}`.

/// Phép tính: (mã, nhãn, nhóm, kiểu kết quả).
const calcOps = <(String, String, String, String)>[
  ('add', 'Cộng (A + B)', 'Số học', 'number'),
  ('sub', 'Trừ (A − B)', 'Số học', 'number'),
  ('mul', 'Nhân (A × B)', 'Số học', 'number'),
  ('div', 'Chia (A ÷ B)', 'Số học', 'number'),
  ('pct', 'Phần trăm (B% của A)', 'Số học', 'number'),
  ('percent', 'Tỉ lệ phần trăm (A chiếm bao nhiêu % của B)', 'Số học', 'number'),
  ('round', 'Làm tròn', 'Số học', 'number'),
  ('sum', 'Tổng', 'Gộp', 'number'),
  ('max', 'Lớn nhất (Max)', 'Gộp', 'number'),
  ('min', 'Nhỏ nhất (Min)', 'Gộp', 'number'),
  ('avg', 'Trung bình', 'Gộp', 'number'),
  ('count', 'Đếm số dòng', 'Gộp', 'number'),
  ('days_between', 'Số ngày giữa hai ngày', 'Ngày', 'number'),
  ('add_days', 'Ngày + N ngày', 'Ngày', 'date'),
  ('add_workdays', 'Ngày + N ngày làm việc', 'Ngày', 'date'),
  ('today', 'Hôm nay', 'Ngày', 'date'),
  ('month_start', 'Ngày đầu tháng', 'Ngày', 'date'),
  ('month_end', 'Ngày cuối tháng', 'Ngày', 'date'),
  ('month', 'Tháng của ngày', 'Ngày', 'number'),
  ('year', 'Năm của ngày', 'Ngày', 'number'),
  ('concat', 'Nối chữ', 'Chữ', 'text'),
  ('upper', 'Chữ hoa', 'Chữ', 'text'),
  ('lower', 'Chữ thường', 'Chữ', 'text'),
  ('if', 'Nếu… thì… không thì…', 'Điều kiện', 'text'),
  ('accumulate', 'Cộng dồn (trong vòng lặp)', 'Vòng lặp', 'number'),
  ('expr', 'Biểu thức (gõ công thức)', 'Biểu thức', 'number'),
  ('now', 'Bây giờ (mốc thời gian)', 'Thời gian & vị trí', 'number'),
  ('minutes_between', 'Số phút giữa hai mốc', 'Thời gian & vị trí', 'number'),
  ('distance_m', 'Khoảng cách (m)', 'Thời gian & vị trí', 'number'),
];

String calcOpLabel(String op) => tr(calcOps.where((o) => o.$1 == op).firstOrNull?.$2 ?? op);
String calcOpType(String op) => calcOps.where((o) => o.$1 == op).firstOrNull?.$4 ?? 'number';
const _aggregates = {'sum', 'max', 'min', 'avg', 'count', 'concat'};

String _exprType(String src) {
  try {
    return exprType(parseExpr(src));
  } on ExprError {
    return 'number';
  }
}

/// Biến của các bước Tính toán (cho "Chèn thông tin", điều kiện, tham số...).
List<CondVar> calcVars(String stepId, String stepName, List vars) => [
      for (final v in vars)
        if (v is Map && '${v['name'] ?? ''}'.isNotEmpty)
          CondVar('steps.$stepId.output.${v['name']}', '${stepName.isEmpty ? tr('Tính toán') : stepName} › ${'${v['label'] ?? ''}'.isEmpty ? v['name'] : v['label']}',
              v['op'] == 'expr' ? _exprType('${(v['args'] as Map?)?['expr'] ?? ''}') : calcOpType('${v['op']}')),
    ];

/// Một dòng tóm tắt: "Tổng tiền = Tổng của Sản phẩm › Thành tiền".
String calcSummary(Map v, List<CondVar> vars, List<FlowField> form) {
  final a = (v['args'] as Map?) ?? const {};
  String ref(Object? r) {
    if (r is! Map) return '?';
    if (r['path'] != null) return vars.where((x) => x.path == r['path']).firstOrNull?.label ?? '${r['path']}';
    return '${r['value'] ?? '?'}';
  }

  // Mốc thời gian: giờ trong ngày, "Bây giờ", hoặc thời điểm lấy vị trí / Wi-Fi.
  String moment(Object? r) => r is Map && r['path'] == null ? (r['value'] == 'now' ? tr('Bây giờ') : '${r['value'] ?? '?'}') : ref(r);
  final table = form.where((f) => 'form.${f.key}' == a['table']).firstOrNull;
  final col = table?.columns.where((c) => c.key == a['col']).firstOrNull;
  final src = table != null ? '${table.label}${col == null ? '' : ' › ${col.label}'}${'${a['cond'] ?? ''}'.isNotEmpty ? tr(' (có lọc)') : ''}' : [for (final x in (a['values'] as List? ?? const [])) ref(x)].join(', ');
  final body = switch ('${v['op']}') {
    'add' => '${ref(a['a'])} + ${ref(a['b'])}',
    'sub' => '${ref(a['a'])} − ${ref(a['b'])}',
    'mul' => '${ref(a['a'])} × ${ref(a['b'])}',
    'div' => '${ref(a['a'])} ÷ ${ref(a['b'])}',
    'pct' => '${ref(a['b'])}% ${tr('của')} ${ref(a['a'])}',
    'percent' => tr('{0} chiếm bao nhiêu % của {1}', [ref(a['a']), ref(a['b'])]),
    'add_workdays' => '${ref(a['a'])} + ${ref(a['n'])} ${tr('ngày làm việc')}',
    'expr' => exprDisplay('${a['expr'] ?? ''}'.trim(), (p) => vars.where((x) => x.path == p).firstOrNull?.label ?? p),
    'round' => tr('Làm tròn {0}', [ref(a['a'])]),
    'today' => tr('Hôm nay'),
    'month_start' => tr('Đầu tháng {0}/{1}', [a['m'] == null ? tr('này') : ref(a['m']), a['y'] == null ? tr('năm nay') : ref(a['y'])]),
    'month_end' => tr('Cuối tháng {0}/{1}', [a['m'] == null ? tr('này') : ref(a['m']), a['y'] == null ? tr('năm nay') : ref(a['y'])]),
    'month' => tr('Tháng của {0}', [ref(a['a'])]),
    'year' => tr('Năm của {0}', [ref(a['a'])]),
    'days_between' => tr('Số ngày từ {0} tới {1}', [ref(a['a']), ref(a['b'])]),
    'add_days' => '${ref(a['a'])} + ${ref(a['n'])} ${tr('ngày')}',
    'if' => tr('Nếu … thì {0}, không thì {1}', [ref(a['then']), ref(a['else'])]),
    'accumulate' => tr('Cộng dồn {0}', [ref(a['a'])]),
    'now' => tr('Bây giờ'),
    'minutes_between' => tr('Số phút từ {0} tới {1}', [moment(a['a']), moment(a['b'])]),
    'distance_m' => tr('Khoảng cách từ {0} tới {1}', [ref(a['a']), a['b'] == null && a['lat2'] != null ? '(${ref(a['lat2'])}, ${ref(a['lon2'])})' : ref(a['b'])]),
    'upper' || 'lower' => '${calcOpLabel('${v['op']}')} ${ref(a['a'])}',
    final op => '${calcOpLabel(op)} $src',
  };
  return '${'${v['label'] ?? ''}'.isEmpty ? v['name'] : v['label']} = $body';
}

/// Sửa một biến. Trả về biến mới, hoặc null (huỷ).
class CalcVarDialog extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic>? value;
  final List<CondVar> vars;
  final List<FlowField> form;
  final Set<String> taken;
  const CalcVarDialog({super.key, required this.app, this.value, required this.vars, required this.form, this.taken = const {}});
  @override
  State<CalcVarDialog> createState() => _CalcVarDialogState();
}

class _CalcVarDialogState extends State<CalcVarDialog> {
  late final label = TextEditingController(text: '${widget.value?['label'] ?? ''}');
  late String op = '${widget.value?['op'] ?? 'add'}';
  late Map<String, dynamic> args = Map<String, dynamic>.of(((widget.value?['args'] as Map?) ?? const {}).cast<String, dynamic>());
  late bool fromTable = widget.value == null || args['table'] != null || args['values'] == null;

  List<FlowField> get _tables => [for (final f in widget.form) if (f.type == 'table') f];

  String get _name {
    final cur = '${widget.value?['name'] ?? ''}';
    if (cur.isNotEmpty) return cur;
    final base = slugKey(label.text).isEmpty ? 'bien' : slugKey(label.text);
    var n = base;
    for (var i = 2; widget.taken.contains(n); i++) {
      n = '${base}_$i';
    }
    return n;
  }

  /// Chọn giá trị: thông tin của luồng (theo kiểu) hoặc nhập tay.
  Widget _ref(String key, String title, Set<String> types) {
    final cur = (args[key] as Map?)?.cast<String, dynamic>();
    final vars = [for (final v in widget.vars) if (types.contains(v.type) || (types.contains('number') && v.type == 'money')) v];
    final path = cur?['path'] as String?;
    final typed = cur != null && cur['path'] == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: typed ? '\u0000' : (vars.any((v) => v.path == path) ? path : null),
            isExpanded: true,
            decoration: InputDecoration(labelText: title, isDense: true, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: '\u0000', child: Text(tr('Nhập giá trị…'), style: const TextStyle(fontStyle: FontStyle.italic))),
              for (final v in vars) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => args[key] = v == '\u0000' ? {'value': types.contains('number') ? 0 : ''} : {'path': v}),
          ),
        ),
        if (typed) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: '${cur['value'] ?? ''}',
              keyboardType: types.contains('number') ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
              decoration: InputDecoration(hintText: types.contains('date') ? 'YYYY-MM-DD' : tr('Giá trị'), isDense: true, border: const OutlineInputBorder()),
              onChanged: (t) => args[key] = {'value': types.contains('number') ? (num.tryParse(t.replaceAll(',', '.')) ?? 0) : t},
            ),
          ),
        ],
      ]),
    );
  }

  /// Vị trí: trường Vị trí của luồng; [fixed] cho phép nhập một điểm cố định (vĩ độ, kinh độ) vào lat2 / lon2.
  Widget _place(String key, String title, {bool fixed = false}) {
    final locs = [for (final v in widget.vars) if (v.type == 'location') v];
    final isFixed = fixed && args[key] == null && args['lat2'] != null;
    final path = (args[key] as Map?)?['path'] as String?;
    num? numOf(String k) => (args[k] as Map?)?['value'] as num?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (fixed) ...[
          SegmentedButton<bool>(
            segments: [ButtonSegment(value: false, label: Text(tr('Vị trí trong tiến trình'))), ButtonSegment(value: true, label: Text(tr('Điểm cố định')))],
            selected: {isFixed},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              if (s.first) {
                args.remove(key);
                args['lat2'] = {'value': 0};
                args['lon2'] = {'value': 0};
              } else {
                args.remove('lat2');
                args.remove('lon2');
                args[key] = {'path': locs.firstOrNull?.path};
              }
            }),
          ),
          const SizedBox(height: 8),
        ],
        if (isFixed)
          Row(children: [
            for (final (k, l) in [('lat2', tr('Vĩ độ')), ('lon2', tr('Kinh độ'))]) ...[
              Expanded(
                child: TextFormField(
                  initialValue: '${numOf(k) ?? ''}',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: '$title › $l', isDense: true, border: const OutlineInputBorder()),
                  onChanged: (t) => args[k] = {'value': num.tryParse(t.replaceAll(',', '.')) ?? 0},
                ),
              ),
              if (k == 'lat2') const SizedBox(width: 8),
            ],
          ])
        else if (locs.isEmpty)
          Text(tr('Chưa có trường kiểu Vị trí. Thêm trường Vị trí ở bước "Nhập dữ liệu" hoặc "Điền thông tin".'), style: const TextStyle(color: kFlowOrange))
        else
          DropdownButtonFormField<String>(
            initialValue: locs.any((v) => v.path == path) ? path : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: title, isDense: true, border: const OutlineInputBorder()),
            items: [for (final v in locs) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => args[key] = {'path': v}),
          ),
      ]),
    );
  }

  /// Mốc thời gian: giờ trong ngày ("08:00"), "Bây giờ", hoặc lúc lấy Vị trí / Wi-Fi.
  Widget _moment(String key, String title) {
    final cur = (args[key] as Map?)?.cast<String, dynamic>();
    final vars = [for (final v in widget.vars) if (v.type == 'location' || v.type == 'wifi') v];
    final sel = cur == null
        ? null
        : cur['path'] != null
            ? (vars.any((v) => v.path == cur['path']) ? '${cur['path']}' : null)
            : (cur['value'] == 'now' ? '\u0001now' : '\u0001clock');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: sel,
            isExpanded: true,
            decoration: InputDecoration(labelText: title, isDense: true, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: '\u0001clock', child: Text(tr('Giờ trong ngày…'), style: const TextStyle(fontStyle: FontStyle.italic))),
              DropdownMenuItem(value: '\u0001now', child: Text(tr('Bây giờ'))),
              for (final v in vars) DropdownMenuItem(value: v.path, child: Text(tr('Lúc lấy {0}', [v.label]), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => args[key] = switch (v) {
                  '\u0001clock' => {'value': '08:00'},
                  '\u0001now' => {'value': 'now'},
                  _ => {'path': v},
                }),
          ),
        ),
        if (sel == '\u0001clock') ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: '${cur?['value'] ?? ''}',
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(hintText: '08:00', isDense: true, border: const OutlineInputBorder()),
              onChanged: (t) => args[key] = {'value': t.trim()},
            ),
          ),
        ],
      ]),
    );
  }

  /// Nguồn cho phép gộp: một cột của bảng (có lọc dòng) hoặc danh sách giá trị.
  List<Widget> _source() {
    final numeric = op != 'count' && op != 'concat';
    final table = _tables.where((t) => 'form.${t.key}' == args['table']).firstOrNull;
    final cols = [for (final c in table?.columns ?? const <FlowField>[]) if (!numeric || c.type == 'number' || c.type == 'money') c];
    final values = [for (final x in (args['values'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    return [
      if (op != 'count')
        SegmentedButton<bool>(
          segments: [ButtonSegment(value: true, label: Text(tr('Cột của bảng'))), ButtonSegment(value: false, label: Text(tr('Các giá trị')))],
          selected: {fromTable},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            fromTable = v.first;
            fromTable ? args.remove('values') : (args..remove('table')..remove('col')..remove('cond'))['values'] = <Map<String, dynamic>>[];
          }),
        ),
      const SizedBox(height: 10),
      if (fromTable || op == 'count') ...[
        if (_tables.isEmpty) Text(tr('Biểu mẫu chưa có trường kiểu Bảng.'), style: const TextStyle(color: kFlowOrange)),
        if (_tables.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: table == null ? null : 'form.${table.key}',
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Bảng'), isDense: true, border: const OutlineInputBorder()),
            items: [for (final t in _tables) DropdownMenuItem(value: 'form.${t.key}', child: Text(t.label))],
            onChanged: (v) => setState(() {
              args['table'] = v;
              args.remove('col');
              args.remove('cond');
            }),
          ),
        if (table != null && op != 'count') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: cols.any((c) => c.key == args['col']) ? '${args['col']}' : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Cột'), isDense: true, border: const OutlineInputBorder()),
            items: [for (final c in cols) DropdownMenuItem(value: c.key, child: Text(c.label))],
            onChanged: (v) => setState(() => args['col'] = v),
          ),
        ],
        if (table != null) ...[
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final rowVars = [for (final c in table.columns) CondVar('item.${c.key}', '${tr('Dòng')} › ${c.label}', c.type, c.options)];
            final cond = '${args['cond'] ?? ''}';
            return OutlinedButton.icon(
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: Text(cond.isEmpty ? tr('Chỉ tính các dòng thoả điều kiện (tuỳ chọn)') : '${tr('Chỉ dòng')}: ${condLabel(cond, rowVars)}', maxLines: 2),
              onPressed: () async {
                final r = await showDialog<String>(context: context, builder: (_) => CondDialog(app: widget.app, expr: cond, vars: rowVars, canDelete: cond.isNotEmpty));
                if (r == null) return;
                setState(() => r == '\u0000delete' || r.isEmpty ? args.remove('cond') : args['cond'] = r);
              },
            );
          }),
        ],
      ] else ...[
        for (var i = 0; i < values.length; i++)
          Row(children: [
            Expanded(
              child: Builder(builder: (context) {
                args['_v$i'] = values[i];
                return _ref('_v$i', tr('Giá trị {0}', [i + 1]), op == 'concat' ? {'text', 'number', 'money', 'date', 'select', 'user'} : {'number'});
              }),
            ),
            IconButton(onPressed: () => setState(() => (args['values'] as List).removeAt(i)), icon: const Icon(Icons.close_rounded, size: 18)),
          ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => (args['values'] as List).add(<String, dynamic>{})),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Thêm giá trị')),
          ),
        ),
        if (op == 'concat')
          TextFormField(
            initialValue: '${args['sep'] ?? ' '}',
            decoration: InputDecoration(labelText: tr('Ngăn cách'), isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => args['sep'] = v,
          ),
      ],
    ];
  }

  List<Widget> _args() {
    const num = {'number'};
    return switch (op) {
      'add' || 'sub' || 'mul' || 'div' => [_ref('a', 'A', num), _ref('b', 'B', num)],
      'pct' => [_ref('a', tr('Số'), num), _ref('b', tr('Phần trăm'), num)],
      'percent' => [_ref('a', tr('Phần (A)'), num), _ref('b', tr('Tổng (B)'), num)],
      'add_workdays' => [
          _ref('a', tr('Ngày'), {'date'}),
          _ref('n', tr('Số ngày làm việc (âm = lùi lại)'), num),
          Text(tr('Theo lịch làm việc của công ty (ngày làm việc trong tuần, ngày lễ).'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ],
      'expr' => [
          ExprField(
            label: tr('Biểu thức'),
            value: '${args['expr'] ?? ''}',
            vars: widget.vars,
            hint: tr('Vd form.so_luong * form.don_gia - vars.giam'),
            onChanged: (v) => setState(() => args['expr'] = v),
          ),
        ],
      'round' => [_ref('a', tr('Số'), num), _ref('digits', tr('Số chữ số thập phân'), num)],
      'days_between' => [_ref('a', tr('Từ ngày'), {'date'}), _ref('b', tr('Tới ngày'), {'date'})],
      'add_days' => [_ref('a', tr('Ngày'), {'date'}), _ref('n', tr('Số ngày (âm = lùi lại)'), num)],
      'today' => [Text(tr('Ngày hôm nay lúc bước chạy (giờ Việt Nam).'))],
      'month_start' || 'month_end' => [
          _ref('m', tr('Tháng (1–12)'), {'number', 'select', 'text'}),
          _ref('y', tr('Năm'), {'number', 'select', 'text'}),
          Text(tr('Bỏ trống = tháng / năm hiện tại. Dùng cho "từ ngày" / "đến ngày" cả tháng, vd tải chứng từ ngân hàng.'),
              style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ],
      'month' || 'year' => [_ref('a', tr('Ngày'), {'date'})],
      'upper' || 'lower' => [_ref('a', tr('Chữ'), {'text', 'select'})],
      'accumulate' => [
          _ref('a', tr('Mỗi vòng cộng thêm'), num),
          Text(tr('Đặt bước này trong khối lặp: vòng đầu bắt đầu từ 0, mỗi vòng cộng thêm; sau khối lặp dùng kết quả cuối.'),
              style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ],
      'if' => [
          Builder(builder: (context) {
            final cond = '${args['cond'] ?? ''}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.rule_rounded, size: 18),
                label: Text(cond.isEmpty ? tr('Đặt điều kiện') : '${tr('Nếu')} ${condLabel(cond, widget.vars)}', maxLines: 3),
                onPressed: () async {
                  final r = await showDialog<String>(context: context, builder: (_) => CondDialog(app: widget.app, expr: cond, vars: widget.vars));
                  if (r != null && r != '\u0000delete') setState(() => args['cond'] = r);
                },
              ),
            );
          }),
          _ref('then', tr('Thì'), {'text', 'number', 'money', 'date', 'select', 'user'}),
          _ref('else', tr('Không thì'), {'text', 'number', 'money', 'date', 'select', 'user'}),
        ],
      'now' => [Text(tr('Mốc thời gian lúc bước chạy. Dùng với "Số phút giữa hai mốc".'))],
      'minutes_between' => [
          _moment('a', tr('Từ mốc')),
          _moment('b', tr('Tới mốc')),
          Text(tr('Vd phút đi muộn: từ 08:00 tới lúc lấy vị trí khi vào ca (âm = đến sớm).'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ],
      'distance_m' => [
          _place('a', tr('Vị trí A')),
          _place('b', tr('Vị trí B'), fixed: true),
          Text(tr('Vd khoảng cách từ vị trí khi vào ca tới xưởng (điểm cố định).'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ],
      _ when _aggregates.contains(op) => _source(),
      _ => const [],
    };
  }

  Map<String, dynamic> _result() {
    final a = Map<String, dynamic>.of(args);
    // Danh sách giá trị đang sửa ở các khoá tạm _v0, _v1...
    if (a['values'] is List) {
      a['values'] = [for (var i = 0; i < (a['values'] as List).length; i++) a['_v$i'] ?? (a['values'] as List)[i]];
    }
    a.removeWhere((k, _) => k.startsWith('_v'));
    return {'name': _name, if (label.text.trim().isNotEmpty) 'label': label.text.trim(), 'op': op, 'args': a};
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String>{for (final o in calcOps) o.$3};
    return AlertDialog(
      title: Text(widget.value == null ? tr('Thêm biến') : tr('Sửa biến')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: label, autofocus: widget.value == null, decoration: InputDecoration(labelText: tr('Tên biến'), hintText: tr('Vd Tổng tiền'), border: const OutlineInputBorder()), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: op,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Phép tính'), border: const OutlineInputBorder()),
              items: [
                for (final g in groups) ...[
                  DropdownMenuItem(enabled: false, value: 'group:$g', child: Text(tr(g).toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Pal.of(context).sub))),
                  for (final o in calcOps.where((o) => o.$3 == g)) DropdownMenuItem(value: o.$1, child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(tr(o.$2)))),
                ],
              ],
              onChanged: (v) => setState(() {
                if (v == null || v.startsWith('group:')) return;
                op = v;
                args = {};
                fromTable = true;
              }),
            ),
            const SizedBox(height: 12),
            ..._args(),
          ]),
        ),
      ),
      actions: [
        if (widget.value != null) TextButton(onPressed: () => Navigator.pop(context, <String, dynamic>{'\u0000delete': true}), child: Text(tr('Xoá'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: label.text.trim().isEmpty || (op == 'expr' && !checkExpr('${args['expr'] ?? ''}').ok) ? null : () => Navigator.pop(context, _result()),
          child: Text(tr('Xong')),
        ),
      ],
    );
  }
}
