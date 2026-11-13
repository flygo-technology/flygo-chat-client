import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowRed;
import 'flow_cond.dart';
import 'flow_doc.dart';
import 'flow_editor_expr.dart';
import 'flow_editor_expr_field.dart';

/// Bước "Đặt biến" (`set`): danh sách phép gán `{to: "vars.<tên>" | "form.<trường>", expr}` hoặc
/// `{to, number: {counter, format, reset}}` (số chứng từ tự tăng, không trùng kể cả khi nhiều luồng chạy cùng lúc).

/// Kiểu trường biểu mẫu sửa được bằng bước Đặt biến (không phải trường tự tính / bảng / tệp / app tự lấy).
const _settableTypes = {'text', 'textarea', 'number', 'money', 'date', 'select', 'bool', 'user'};

List<FlowField> settableFields(List<FlowField> form) => [for (final f in form) if (f.calc == null && _settableTypes.contains(f.type)) f];

/// Tên của phép gán (phần sau `vars.` / `form.`).
String assignName(Object? to) => '${to ?? ''}'.split('.').skip(1).join('.');

/// Kiểu của giá trị gán (để chọn phép so sánh ở bước sau).
String assignType(Map a) {
  if (a['number'] != null) return 'text';
  try {
    return exprType(parseExpr('${a['expr'] ?? ''}'));
  } on ExprError {
    return 'text';
  }
}

/// Biến do bước Đặt biến [s] tạo: `vars.<tên>` (tên «Biến › tên»).
List<CondVar> setVars(FStep s, List<FlowField> form) => [
      for (final a in (s.node['assign'] as List? ?? const []))
        if (a is Map && '${a['to'] ?? ''}'.startsWith('vars.') && assignName(a['to']).isNotEmpty)
          CondVar('${a['to']}', '${tr('Biến')} › ${assignName(a['to'])}', assignType(a)),
    ];

/// Tóm tắt trên sơ đồ: "so_phieu = số PC-{yyyy}-{0000} · vat = round(«Số tiền» * 0.08)".
String setSummary(Map n, List<CondVar> vars, List<FlowField> form) {
  final rows = [for (final a in (n['assign'] as List? ?? const [])) if (a is Map) a];
  if (rows.isEmpty) return tr('Chưa có phép gán');
  String target(Map a) {
    final to = '${a['to'] ?? ''}';
    if (to.startsWith('form.')) return form.where((f) => f.key == assignName(to)).firstOrNull?.label ?? assignName(to);
    return assignName(to);
  }

  return [
    for (final a in rows)
      a['number'] is Map
          ? '${target(a)} = ${tr('số {0}', ['${(a['number'] as Map)['format'] ?? ''}'])}'
          : '${target(a)} = ${exprDisplay('${a['expr'] ?? ''}'.trim(), (p) => vars.where((v) => v.path == p).firstOrNull?.label ?? p)}',
  ].join(' · ');
}

const numberResets = {'': 'Theo dạng số', 'year': 'Mỗi năm', 'month': 'Mỗi tháng', 'day': 'Mỗi ngày', 'never': 'Không đặt lại'};

/// Cấu hình bước Đặt biến. Sửa trực tiếp [n] (bản sao của node trong bảng cấu hình).
class SetConfig extends StatefulWidget {
  final Map<String, dynamic> n;
  final List<CondVar> vars;
  final List<FlowField> form;
  const SetConfig({super.key, required this.n, required this.vars, required this.form});
  @override
  State<SetConfig> createState() => _SetConfigState();
}

class _SetConfigState extends State<SetConfig> {
  Map<String, dynamic> get n => widget.n;

  List<Map<String, dynamic>> get _rows {
    final cur = n['assign'];
    if (cur is List<Map<String, dynamic>>) return cur;
    final l = [for (final x in (cur as List? ?? const [])) if (x is Map) (x is Map<String, dynamic> ? x : Map<String, dynamic>.from(x))];
    n['assign'] = l;
    return l;
  }

  /// Thông tin dùng được ở dòng [i]: của quy trình + biến của các dòng trước (bỏ biến của chính bước này).
  List<CondVar> _before(int i) {
    final mine = {for (final a in _rows) '${a['to']}'};
    return [
      ...widget.vars.where((v) => !mine.contains(v.path) && !v.path.startsWith('steps.${n['id']}.')),
      for (final a in _rows.take(i))
        if ('${a['to'] ?? ''}'.startsWith('vars.')) CondVar('${a['to']}', '${tr('Biến')} › ${assignName(a['to'])}', assignType(a)),
    ];
  }

  String _newName() {
    final taken = {for (final a in _rows) assignName(a['to'])};
    var i = _rows.length + 1;
    while (taken.contains('bien_$i')) {
      i++;
    }
    return 'bien_$i';
  }

  Widget _row(int i, Map<String, dynamic> a, Pal pal) {
    final to = '${a['to'] ?? ''}';
    final isForm = to.startsWith('form.');
    final isNumber = a['number'] is Map;
    final fields = settableFields(widget.form);
    final names = [for (final x in _rows) assignName(x['to'])];
    final dup = names.where((x) => x == assignName(to)).length > 1;
    return Container(
      key: ObjectKey(a),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(tr('Biến của luồng'))), ButtonSegment(value: true, label: Text(tr('Trường biểu mẫu')))],
              selected: {isForm},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => a['to'] = s.first ? (fields.isEmpty ? 'form.' : 'form.${fields.first.key}') : 'vars.${_newName()}'),
            ),
            const SizedBox(height: 8),
            if (isForm)
              DropdownButtonFormField<String>(
                key: ValueKey('set-f-${identityHashCode(a)}'),
                initialValue: fields.any((f) => 'form.${f.key}' == to) ? to : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Sửa trường'),
                  helperText: fields.isEmpty ? tr('Biểu mẫu chưa có trường sửa được (trừ trường tự tính, bảng, tệp).') : null,
                  border: const OutlineInputBorder(),
                ),
                items: [for (final f in fields) DropdownMenuItem(value: 'form.${f.key}', child: Text(f.label, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => a['to'] = v),
              )
            else
              TextFormField(
                key: ValueKey('set-v-${identityHashCode(a)}'),
                initialValue: assignName(to),
                decoration: InputDecoration(
                  labelText: tr('Tên biến (chữ không dấu, số, _)'),
                  prefixText: 'vars.',
                  errorText: dup ? tr('Tên bị trùng với dòng khác') : null,
                  helperText: tr('Bước sau dùng «{0}»', ['${tr('Biến')} › ${assignName(to)}']),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => a['to'] = 'vars.${v.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}'),
              ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(tr('Biểu thức'))), ButtonSegment(value: true, label: Text(tr('Số chứng từ tự tăng')))],
              selected: {isNumber},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                if (s.first) {
                  a.remove('expr');
                  a['number'] = <String, dynamic>{'format': 'PC-{yyyy}-{0000}'};
                } else {
                  a.remove('number');
                  a['expr'] = '';
                }
              }),
            ),
            const SizedBox(height: 8),
            if (isNumber)
              _NumberEditor(key: ValueKey('set-n-${identityHashCode(a)}'), number: a['number'] as Map<String, dynamic>, onChanged: () => setState(() {}))
            else
              ExprField(
                key: ValueKey('set-e-${identityHashCode(a)}'),
                label: tr('Giá trị'),
                value: '${a['expr'] ?? ''}',
                vars: _before(i),
                lines: 1,
                hint: tr("Vd round(form.so_tien * 0.08) hoặc 'Phiếu ' + vars.so_phieu"),
                onChanged: (v) => a['expr'] = v,
              ),
          ]),
        ),
        IconButton(onPressed: () => setState(() => _rows.remove(a)), icon: const Icon(Icons.close_rounded, size: 18), tooltip: tr('Xoá')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final rows = _rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Chạy theo thứ tự, dòng sau dùng được kết quả dòng trước. Biến của luồng dùng ở mọi bước sau (điều kiện, nội dung, thẻ).'),
          style: TextStyle(color: pal.sub, fontSize: 12.5)),
      const SizedBox(height: 10),
      for (var i = 0; i < rows.length; i++) _row(i, rows[i], pal),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => rows.add({'to': 'vars.${_newName()}', 'expr': ''})),
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Thêm phép gán')),
        ),
      ),
      if (rows.isEmpty) Text(tr('Cần ít nhất một phép gán.'), style: const TextStyle(color: kFlowRed, fontSize: 12.5)),
    ]);
  }
}

/// Số chứng từ: tên bộ đếm, dạng số (chèn {yyyy} {mm} {0000}...), chu kỳ đặt lại, xem trước.
class _NumberEditor extends StatefulWidget {
  final Map<String, dynamic> number;
  final VoidCallback onChanged;
  const _NumberEditor({super.key, required this.number, required this.onChanged});
  @override
  State<_NumberEditor> createState() => _NumberEditorState();
}

class _NumberEditorState extends State<_NumberEditor> {
  Map<String, dynamic> get m => widget.number;
  late final fmt = TextEditingController(text: '${m['format'] ?? ''}');

  @override
  void dispose() {
    fmt.dispose();
    super.dispose();
  }

  void _setFormat(String v) {
    v.isEmpty ? m.remove('format') : m['format'] = v;
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final f = fmt.text;
    final reset = '${m['reset'] ?? ''}';
    final shownReset = reset.isEmpty ? numberResetOf(f) : reset;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        initialValue: '${m['counter'] ?? ''}',
        decoration: InputDecoration(
          labelText: tr('Tên bộ đếm'),
          hintText: tr('Vd phieu-chi; bỏ trống = theo mã quy trình'),
          helperText: tr('Nhiều quy trình dùng chung một tên thì chung một dãy số. Chèn được {{form.don_vi}}.'),
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => v.trim().isEmpty ? m.remove('counter') : m['counter'] = v.trim(),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: fmt,
        decoration: InputDecoration(labelText: tr('Dạng số'), hintText: 'PC-{yyyy}-{0000}', border: const OutlineInputBorder()),
        onChanged: _setFormat,
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (t, l) in [('{yyyy}', 'Năm'), ('{yy}', 'Năm 2 số'), ('{mm}', 'Tháng'), ('{dd}', 'Ngày'), ('{0000}', 'Số thứ tự 4 chữ số'), ('{n}', 'Số thứ tự')])
          ActionChip(
            label: Text('$t · ${tr(l)}', style: const TextStyle(fontSize: 12)),
            onPressed: () {
              fmt.text = '${fmt.text}$t';
              _setFormat(fmt.text);
            },
          ),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: numberResets.containsKey(reset) ? reset : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Đặt lại số thứ tự'), border: const OutlineInputBorder()),
        items: [
          for (final e in numberResets.entries)
            DropdownMenuItem(value: e.key, child: Text(e.key.isEmpty ? '${tr(e.value)} (${tr(numberResets[shownReset]!)})' : tr(e.value))),
        ],
        onChanged: (v) {
          (v ?? '').isEmpty ? m.remove('reset') : m['reset'] = v;
          setState(() {});
        },
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(8)),
        child: Text(tr('Xem trước: {0}, {1}, …', [numberPreview(f), numberPreview(f, n: 2)]), style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 4),
      Text(tr('Số bắt đầu từ 1 mỗi chu kỳ (giờ Việt Nam), không bao giờ trùng kể cả khi nhiều luồng chạy cùng lúc; bước lỗi thì số không bị lấy mất.'),
          style: TextStyle(fontSize: 12, color: pal.sub)),
    ]);
  }
}
