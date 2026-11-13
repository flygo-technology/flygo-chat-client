import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowRed;
import 'flow_cond.dart';
import 'flow_doc.dart';
import 'flow_editor_expr.dart';
import 'flow_editor.dart' show editorCtx;
import 'flow_editor_expr_field.dart';

/// Bước bảng (Lọc bảng, Thêm cột, Nhóm bảng, Ghép bảng) và khung Lặp bảng: hình, tóm tắt, nguồn bảng, cột biết
/// trước, thông tin dùng được ở bước sau, ô cấu hình. Giống `flows_engine::table` / lint của máy chủ.

/// Loại bước bảng.
const tableNodeTypes = {'mcp_pages', 'table_filter', 'table_add_field', 'table_group', 'table_join'};

/// Màu nhóm "Bảng".
const kGroupTable = Color(0xFF6366F1);

(IconData, Color, String) tableLook(String type) => switch (type) {
      'mcp_pages' => (Icons.auto_stories_outlined, kGroupTable, tr('Đọc hết trang')),
      'table_filter' => (Icons.filter_alt_outlined, kGroupTable, tr('Lọc bảng')),
      'table_add_field' => (Icons.view_column_outlined, kGroupTable, tr('Thêm cột')),
      'table_group' => (Icons.workspaces_outline, kGroupTable, tr('Nhóm bảng')),
      'table_join' => (Icons.join_inner_rounded, kGroupTable, tr('Ghép bảng')),
      _ => (Icons.table_rows_outlined, kGroupTable, tr('Lặp bảng')),
    };

/// Mục trong bảng "Thêm bước", nhóm Bảng.
const insertTableItems = [
  ('mcp_pages', 'Gọi công cụ chỉ đọc lặp từng trang (vd 100 chứng từ / trang) và gộp hết thành một bảng'),
  ('table_filter', 'Giữ các dòng thoả điều kiện, sắp xếp, lấy tối đa n dòng'),
  ('table_add_field', 'Thêm cột tính từ các cột khác cho mỗi dòng (cột sau dùng được cột trước)'),
  ('table_group', 'Gom các dòng cùng giá trị ở các cột chọn thành nhóm, kèm số dòng và tổng'),
  ('table_join', 'Ghép hai bảng theo cột khoá: dòng khớp, chỉ có ở A, chỉ có ở B, khoá bị trùng'),
  ('table_loop', 'Chạy các bước bên trong lần lượt cho từng dòng; lượt lỗi không dừng cả vòng'),
];

/// Bước bảng mới với cấu hình mặc định.
Map<String, dynamic> newTableNode(String type, String id) => switch (type) {
      'mcp_pages' => {
          'id': id,
          'type': type,
          'name': tr('Đọc hết trang'),
          'params': <String, dynamic>{'args': <String, dynamic>{}},
          'paging': <String, dynamic>{'mode': 'cursor', 'cursor_arg': 'cursor', 'next': 'next_cursor', 'more': 'has_more'},
          'rows': 'rows',
        },
      'table_filter' => {'id': id, 'type': type, 'name': tr('Lọc bảng'), 'table': '', 'cond': ''},
      'table_add_field' => {
          'id': id,
          'type': type,
          'name': tr('Thêm cột'),
          'table': '',
          'fields': [
            {'key': 'cot_1', 'expr': ''},
          ],
        },
      'table_group' => {'id': id, 'type': type, 'name': tr('Nhóm bảng'), 'table': '', 'by': <String>[]},
      _ => {
          'id': id,
          'type': 'table_join',
          'name': tr('Ghép bảng'),
          'a': '',
          'b': '',
          'keys': [
            {'a': '', 'b': ''},
          ],
        },
    };

/// Tên mặc định của kết quả.
const tableOutputLabels = {
  'rows': 'Các dòng',
  'count': 'Số dòng',
  'groups': 'Các nhóm',
  'khop': 'Dòng khớp',
  'chi_a': 'Chỉ có ở A',
  'chi_b': 'Chỉ có ở B',
  'trung.a': 'Khoá trùng ở A',
  'trung.b': 'Khoá trùng ở B',
  'khop_count': 'Số dòng khớp',
  'chi_a_count': 'Số dòng chỉ có ở A',
  'chi_b_count': 'Số dòng chỉ có ở B',
  'trung_a_count': 'Số dòng khoá trùng ở A',
  'trung_b_count': 'Số dòng khoá trùng ở B',
  'ok': 'Số lượt xong',
  'pages': 'Số trang',
  'truncated': 'Bị cắt bớt',
  'loi': 'Lỗi từng lượt',
};

String _name(FStep s) => s.name.isEmpty ? tableLook(s.type).$3 : s.name;

/// Các bảng (danh sách dòng) bước [s] tạo ra: (đường dẫn, khoá kết quả).
List<(String, String)> tableOutputs(FStep s) => switch (s.type) {
      'mcp_pages' || 'table_filter' || 'table_add_field' => [('steps.${s.id}.output.rows', 'rows')],
      'table_group' => [('steps.${s.id}.output.groups', 'groups')],
      'table_join' => [
          for (final k in const ['khop', 'chi_a', 'chi_b', 'trung.a', 'trung.b']) ('steps.${s.id}.output.$k', k),
        ],
      _ => const [],
    };

/// Thông tin dùng được ở bước sau (điều kiện, chèn thông tin): các số đếm.
List<CondVar> tableVars(FStep s) {
  final name = _name(s);
  CondVar v(String k) => CondVar('steps.${s.id}.output.$k', '$name › ${tr(tableOutputLabels[k]!)}', 'number');
  return switch (s.type) {
    'mcp_pages' => [v('count'), v('pages'), CondVar('steps.${s.id}.output.truncated', '$name › ${tr(tableOutputLabels['truncated']!)}', 'bool')],
    'table_filter' || 'table_add_field' || 'table_group' => [v('count')],
    'table_join' => [for (final k in const ['khop_count', 'chi_a_count', 'chi_b_count', 'trung_a_count', 'trung_b_count']) v(k)],
    _ => const [],
  };
}

/// Kết quả của khung Lặp bảng dùng được ở bước sau.
List<CondVar> loopVars(FLoop l) {
  final name = l.name.isEmpty ? tr('Lặp bảng') : l.name;
  if (l.legacy) return const [];
  return [
    CondVar('steps.${l.id}.output.count', '$name › ${tr('Số dòng')}', 'number'),
    CondVar('steps.${l.id}.output.ok', '$name › ${tr(tableOutputLabels['ok']!)}', 'number'),
  ];
}

/// Các bảng chọn được làm nguồn cho bước / khung ở [at]: trường bảng của biểu mẫu, danh sách trong kết quả công cụ / AI,
/// kết quả bước bảng đứng trước, dòng nhóm của khung lặp chứa nó. (đường dẫn, tên dễ đọc).
List<(String, String)> tableSources(FlowDoc doc, FItem at) {
  final form = FlowField.listOf(doc.meta['form']);
  final before = doc.predecessorsOf(at.id);
  final out = <(String, String)>[
    for (final f in form)
      if (f.type == 'table') ('form.${f.key}', f.label),
  ];
  for (final s in doc.allSteps) {
    if (!before.contains(s.id) && s.id != at.id) continue;
    if (s.id == at.id) continue;
    if (s.type == 'auto' || s.type == 'ai') {
      final name = s.name.isEmpty ? tr('Gọi công cụ') : s.name;
      final schema = toolOutputSchema(s.node, editorCtx?.integ ?? const {});
      final fromSchema = [for (final (k, l, t) in schemaFields(schema)) if (t == 'table') ('steps.${s.id}.output.$k', '$name › $l')];
      out.addAll(fromSchema);
      for (final e in ((s.node['output_schema'] as Map?) ?? const {}).entries) {
        final path = 'steps.${s.id}.output.${e.key}';
        if (e.value == 'json' && !fromSchema.any((x) => x.$1 == path)) out.add((path, '$name › ${e.key}'));
      }
    }
    for (final (path, k) in tableOutputs(s)) {
      out.add((path, '${_name(s)} › ${tr(tableOutputLabels[k]!)}'));
    }
  }
  for (final l in enclosingLoops(doc, at)) {
    final a = l.alias.trim().isEmpty ? 'item' : l.alias.trim();
    if (l.items.contains('.output.groups')) out.add(('$a.rows', '${l.name.isEmpty ? tr('Lặp bảng') : l.name} › ${tr('Các dòng của nhóm')}'));
  }
  return out;
}

/// Các khung Lặp bảng chứa [at], từ ngoài vào trong.
List<FLoop> enclosingLoops(FlowDoc doc, FItem at) {
  final out = <FLoop>[];
  bool walk(List<FItem> l, List<FLoop> chain) {
    for (final x in l) {
      if (identical(x, at) || x.id == at.id) {
        out.addAll(chain);
        return true;
      }
      final subs = switch (x) {
        FCondition c => [for (final b in c.branches) (b.steps, chain)],
        FParallel p => [for (final b in p.branches) (b, chain)],
        FLoop lp => [(lp.body, [...chain, lp])],
        FStep s => [for (final p in s.ports) (p.steps, chain)],
      };
      for (final (items, ch) in subs) {
        if (walk(items, ch)) return true;
      }
    }
    return false;
  }

  walk(doc.steps, []);
  return out;
}

/// Cột biết trước của bảng [src] (null: không biết, vd kết quả công cụ).
List<String>? tableColumns(FlowDoc doc, String src, [int depth = 0]) {
  if (depth > 8) return null;
  final p = src.trim().split('.');
  if (p.length == 2 && p[0] == 'form') {
    final f = FlowField.listOf(doc.meta['form']).where((f) => f.key == p[1] && f.type == 'table').firstOrNull;
    return f == null ? null : [for (final c in f.columns) c.key];
  }
  if (p.length >= 4 && p[0] == 'steps' && p[2] == 'output') {
    final s = doc.allSteps.where((x) => x.id == p[1]).firstOrNull;
    if (s == null) return null;
    final out = p.sublist(3).join('.');
    final n = s.node;
    Map<String, String> renames(String k) => {for (final e in ((n[k] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
    final info = tableColumnInfo(doc, src);
    if (info != null && (s.type == 'auto' || s.type == 'mcp_pages')) return info.keys.toList();
    switch ((s.type, out)) {
      case ('table_filter', 'rows'):
        return tableColumns(doc, '${n['table'] ?? ''}', depth + 1);
      case ('table_add_field', 'rows'):
        final base = tableColumns(doc, '${n['table'] ?? ''}', depth + 1);
        final added = [for (final f in (n['fields'] as List? ?? const [])) if (f is Map) '${f['key']}'];
        return base == null ? null : {...base, ...added}.toList();
      case ('table_group', 'groups'):
        return [
          for (final b in (n['by'] as List? ?? const [])) '$b',
          'count',
          'rows',
          for (final a in (n['aggregates'] as List? ?? const [])) if (a is Map) '${a['key']}',
        ];
      case ('table_join', 'khop'):
        final a = tableColumns(doc, '${n['a'] ?? ''}', depth + 1);
        final b = tableColumns(doc, '${n['b'] ?? ''}', depth + 1);
        if (a == null || b == null) return null;
        final ra = renames('rename_a'), rb = renames('rename_b');
        return {for (final c in a) ra[c] ?? c, for (final c in b) rb[c] ?? c}.toList();
      case ('table_join', 'chi_a' || 'trung.a'):
        return tableColumns(doc, '${n['a'] ?? ''}', depth + 1);
      case ('table_join', 'chi_b' || 'trung.b'):
        return tableColumns(doc, '${n['b'] ?? ''}', depth + 1);
    }
    return null;
  }
  return null;
}

/// Cột (khoá → (tên, kiểu)) của bảng là kết quả công cụ có khuôn (bước tự động MCP, Đọc hết trang), hoặc đi qua Lọc /
/// Thêm cột / Nhóm từ bảng đó. null = không biết.
Map<String, (String, String)>? tableColumnInfo(FlowDoc doc, String src, [int depth = 0]) {
  if (depth > 8) return null;
  final p = src.trim().split('.');
  if (p.length < 4 || p[0] != 'steps' || p[2] != 'output') return null;
  final s = doc.allSteps.where((x) => x.id == p[1]).firstOrNull;
  if (s == null) return null;
  final out = p.sublist(3).join('.');
  final integ = editorCtx?.integ ?? const {};
  switch (s.type) {
    case 'auto':
      return schemaColumns(schemaAt(toolOutputSchema(s.node, integ), out));
    case 'mcp_pages' when out == 'rows':
      return schemaColumns(schemaAt(toolOutputSchema(s.node, integ), '${s.node['rows'] ?? 'rows'}'));
    case 'table_filter' when out == 'rows':
      return tableColumnInfo(doc, '${s.node['table'] ?? ''}', depth + 1);
    case 'table_add_field' when out == 'rows':
      final base = tableColumnInfo(doc, '${s.node['table'] ?? ''}', depth + 1);
      if (base == null) return null;
      return {...base, for (final f in (s.node['fields'] as List? ?? const [])) if (f is Map) '${f['key']}': ('${f['key']}', 'text')};
    case 'table_group' when out == 'groups':
      final base = tableColumnInfo(doc, '${s.node['table'] ?? ''}', depth + 1) ?? const {};
      return {
        for (final b in (s.node['by'] as List? ?? const [])) '$b': base['$b'] ?? ('$b', 'text'),
        'count': (tr('Số dòng'), 'number'),
        for (final a in (s.node['aggregates'] as List? ?? const [])) if (a is Map) '${a['key']}': ('${a['key']}', 'number'),
      };
  }
  return null;
}

/// Dòng đang xét trong khung Lặp bảng và trong Lọc bảng / Thêm cột: `<as>.<cột>` / `item.<cột>` (cột biết trước),
/// hoặc cả dòng khi không biết cột.
List<CondVar> rowVars(FlowDoc doc, FItem at) {
  final out = <CondVar>[];
  void row(String root, String label, List<String>? cols, {List<FlowField> typed = const [], Map<String, (String, String)>? info}) {
    if (cols == null) {
      out.add(CondVar(root, label, 'text'));
      return;
    }
    for (final c in cols) {
      if (c == 'rows') continue;
      final f = typed.where((x) => x.key == c).firstOrNull;
      final i = info?[c];
      if (i != null && i.$2 == 'table') continue;
      out.add(CondVar('$root.$c', '$label › ${f?.label ?? i?.$1 ?? c}', f?.type ?? i?.$2 ?? (c == 'count' ? 'number' : 'text'), f?.options ?? const []));
    }
  }

  List<FlowField> typedOf(String src) {
    final p = src.trim().split('.');
    if (p.length != 2 || p[0] != 'form') return const [];
    return FlowField.listOf(doc.meta['form']).where((f) => f.key == p[1]).firstOrNull?.columns ?? const [];
  }

  final loops = enclosingLoops(doc, at);
  for (final l in loops) {
    if (l.legacy) continue;
    final a = l.alias.trim();
    final label = l.name.isEmpty ? tr('Lặp bảng') : l.name;
    if (a.isNotEmpty) row(a, '$label › ${tr('Dòng đang xét')}', tableColumns(doc, l.items), typed: typedOf(l.items), info: tableColumnInfo(doc, l.items));
  }
  if (loops.isNotEmpty && !loops.last.legacy) {
    final l = loops.last;
    row('item', tr('Dòng đang xét'), tableColumns(doc, l.items), typed: typedOf(l.items), info: tableColumnInfo(doc, l.items));
    out.add(CondVar('loop.index', tr('Số thứ tự dòng'), 'number'));
    out.add(CondVar('loop.count', tr('Số dòng'), 'number'));
  }
  // Lọc bảng / Thêm cột: item là dòng của chính bảng nguồn (cột thêm trước dùng được ở cột sau).
  if (at is FStep && (at.type == 'table_filter' || at.type == 'table_add_field')) {
    out.removeWhere((v) => v.path == 'item' || v.path.startsWith('item.'));
    final src = '${at.node['table'] ?? ''}';
    var cols = tableColumns(doc, src);
    if (cols != null && at.type == 'table_add_field') cols = [...cols, for (final f in (at.node['fields'] as List? ?? const [])) if (f is Map) '${f['key']}'];
    row('item', tr('Dòng đang xét'), cols, typed: typedOf(src), info: tableColumnInfo(doc, src));
  }
  return out;
}

/// Tóm tắt trên sơ đồ.
String tableSummary(FStep s, String Function(String path) label) {
  final n = s.node;
  String src(Object? v) => '${v ?? ''}'.trim().isEmpty ? tr('chưa chọn bảng') : '«${label('$v'.trim())}»';
  switch (s.type) {
    case 'mcp_pages':
      final p = (n['params'] as Map?) ?? const {};
      final pg = (n['paging'] as Map?) ?? const {};
      final tool = '${p['tool'] ?? ''}';
      return [
        tool.isEmpty ? tr('chưa chọn công cụ') : '${p['app'] ?? p['server'] ?? ''} › $tool',
        pg['mode'] == 'offset' ? tr('theo vị trí, {0} dòng / trang', [pg['size'] ?? '?']) : tr('theo con trỏ'),
        tr('dòng ở «{0}»', [n['rows'] ?? '']),
      ].join(' · ');
    case 'table_filter':
      final cond = '${n['cond'] ?? ''}'.trim();
      final lim = (n['limit'] as num?)?.toInt() ?? 0;
      return [
        src(n['table']),
        cond.isEmpty ? tr('giữ mọi dòng') : tr('giữ dòng có {0}', [exprDisplay(cond, label)]),
        if ((n['sort'] as List? ?? const []).isNotEmpty) tr('sắp theo {0}', [(n['sort'] as List).map((k) => '${(k as Map)['col']}${k['desc'] == true ? ' ↓' : ''}').join(', ')]),
        if (lim > 0) tr('tối đa {0} dòng', [lim]),
      ].join(' · ');
    case 'table_add_field':
      final f = [for (final x in (n['fields'] as List? ?? const [])) if (x is Map) '${x['key']}'];
      return '${src(n['table'])} · ${f.isEmpty ? tr('chưa có cột') : tr('thêm {0}', [f.join(', ')])}';
    case 'table_group':
      final by = [for (final x in (n['by'] as List? ?? const [])) '$x'];
      return '${src(n['table'])} · ${by.isEmpty ? tr('chưa chọn cột nhóm') : tr('nhóm theo {0}', [by.join(', ')])}';
    case 'table_join':
      final keys = [for (final k in (n['keys'] as List? ?? const [])) if (k is Map) '${k['a']} = ${k['b']}'];
      return '${src(n['a'])} + ${src(n['b'])} · ${keys.isEmpty ? tr('chưa có khoá') : keys.join(', ')}';
  }
  return '';
}

// ---------------------------------------------------------------------------------------------- ô cấu hình

/// Ô chọn bảng: danh sách nguồn có sẵn, hoặc gõ biểu thức (vd `process.props.chung_tu`).
class TableSourceField extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> sources;
  final List<CondVar> vars;
  final ValueChanged<String> onChanged;
  const TableSourceField({super.key, required this.label, required this.value, required this.sources, required this.vars, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final known = sources.any((s) => s.$1 == value);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: known ? value : (value.isEmpty ? null : ''),
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: [
          for (final (path, name) in sources) DropdownMenuItem(value: path, child: Text(name, overflow: TextOverflow.ellipsis)),
          DropdownMenuItem(value: '', child: Text(tr('Biểu thức khác…'))),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      ),
      if (!known && value.isNotEmpty || (sources.isEmpty))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ExprField(key: ValueKey('src-$label'), label: tr('Bảng (biểu thức)'), value: value, vars: vars, lines: 1, onChanged: onChanged),
        ),
    ]);
  }
}

/// Cấu hình bước bảng. Sửa trực tiếp [n] (bản sao của node trong bảng cấu hình).
class TableConfig extends StatefulWidget {
  final Map<String, dynamic> n;
  final List<CondVar> vars;
  final FlowDoc? doc;
  const TableConfig({super.key, required this.n, required this.vars, required this.doc});
  @override
  State<TableConfig> createState() => _TableConfigState();
}

class _TableConfigState extends State<TableConfig> {
  Map<String, dynamic> get n => widget.n;
  String get type => '${n['type']}';

  late final FStep? _self = widget.doc?.allSteps.where((s) => s.id == '${n['id']}').firstOrNull;
  late final List<(String, String)> _sources = (widget.doc != null && _self != null) ? tableSources(widget.doc!, _self) : const [];

  void _set(VoidCallback f) => setState(f);
  Widget _gap([double h = 14]) => SizedBox(height: h);
  Widget _title(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: Theme.of(context).textTheme.labelLarge));
  Widget _hint(String t) => Padding(padding: const EdgeInsets.only(top: 4), child: Text(t, style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)));

  List<String>? _cols(String k) => widget.doc == null ? null : tableColumns(widget.doc!, '${n[k] ?? ''}');

  Widget _source(String k, String label) => TableSourceField(
        key: ValueKey('$k-${n[k]}'),
        label: label,
        value: '${n[k] ?? ''}',
        sources: _sources,
        vars: widget.vars,
        onChanged: (v) => _set(() => n[k] = v),
      );

  /// Ô tên cột: chọn trong cột biết trước, hoặc gõ.
  Widget _col(String label, String value, List<String>? cols, ValueChanged<String> pick, {Key? key}) {
    if (cols != null && cols.isNotEmpty && (value.isEmpty || cols.contains(value))) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: value.isEmpty ? null : value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: [for (final c in cols) if (c != 'rows') DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => _set(() => pick(v ?? '')),
      );
    }
    return TextFormField(
      key: key,
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      onChanged: (v) => _set(() => pick(v.trim())),
    );
  }

  List<Map<String, dynamic>> _rows(String k) {
    final l = [for (final x in (n[k] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    n[k] = l;
    return l;
  }

  Widget _delete(VoidCallback onTap) => IconButton(icon: const Icon(Icons.close_rounded, size: 18), tooltip: tr('Xoá'), onPressed: () => _set(onTap));

  Widget _add(String label, VoidCallback onTap) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: () => _set(onTap), icon: const Icon(Icons.add_rounded, size: 18), label: Text(label)),
      );

  List<Widget> _sort(String k, List<String>? cols) {
    final rows = _rows(k);
    return [
      _title(k == 'sort' ? tr('Sắp xếp') : tr('Sắp xếp dòng trong nhóm')),
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: _col(tr('Cột'), '${rows[i]['col'] ?? ''}', cols, (v) => rows[i]['col'] = v, key: ValueKey('$k-col-$i'))),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(tr('Tăng'))), ButtonSegment(value: true, label: Text(tr('Giảm')))],
              selected: {rows[i]['desc'] == true},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _set(() => s.first ? rows[i]['desc'] = true : rows[i].remove('desc')),
            ),
            _delete(() => rows.removeAt(i)),
          ]),
        ),
      _add(tr('Thêm cột sắp xếp'), () => rows.add({'col': ''})),
      _hint(tr('Số theo số, chữ theo thứ tự chữ; ô trống luôn xếp cuối')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = switch (type) {
      'table_filter' => _filter(),
      'table_add_field' => _addField(),
      'table_group' => _group(),
      _ => _join(),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  List<Widget> _filter() {
    final cols = _cols('table');
    return [
      _source('table', tr('Bảng cần lọc')),
      _gap(),
      ExprField(
        key: const ValueKey('cond'),
        label: tr('Giữ dòng khi'),
        value: '${n['cond'] ?? ''}',
        vars: widget.vars,
        hint: tr('Dùng «Dòng đang xét». Bỏ trống = giữ mọi dòng'),
        onChanged: (v) => v.trim().isEmpty ? n.remove('cond') : n['cond'] = v,
      ),
      _gap(),
      ..._sort('sort', cols),
      _gap(),
      TextFormField(
        initialValue: (n['limit'] as num?)?.toString() ?? '',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: tr('Lấy tối đa (dòng)'), hintText: tr('Bỏ trống = không giới hạn'), isDense: true, border: const OutlineInputBorder()),
        onChanged: (v) => _set(() {
          final x = int.tryParse(v.trim()) ?? 0;
          x > 0 ? n['limit'] = x : n.remove('limit');
        }),
      ),
      _hint(tr('Kết quả: Các dòng, Số dòng')),
    ];
  }

  List<Widget> _addField() {
    final rows = _rows('fields');
    final keys = <String>{};
    return [
      _source('table', tr('Bảng cần thêm cột')),
      _gap(),
      _title(tr('Cột mới (tính lần lượt, cột sau dùng được cột trước)')),
      for (var i = 0; i < rows.length; i++) ...[
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('fk-$i'),
              initialValue: '${rows[i]['key'] ?? ''}',
              decoration: InputDecoration(
                labelText: tr('Tên cột'),
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch('${rows[i]['key'] ?? ''}')
                    ? tr('Chữ không dấu, số, _')
                    : (!keys.add('${rows[i]['key']}') ? tr('Trùng tên cột') : null),
              ),
              onChanged: (v) => _set(() => rows[i]['key'] = v.trim()),
            ),
          ),
          _delete(() => rows.removeAt(i)),
        ]),
        const SizedBox(height: 6),
        ExprField(key: ValueKey('fe-$i'), label: tr('Giá trị'), value: '${rows[i]['expr'] ?? ''}', vars: widget.vars, lines: 1, onChanged: (v) => rows[i]['expr'] = v),
        _gap(10),
      ],
      _add(tr('Thêm cột'), () => rows.add({'key': 'cot_${rows.length + 1}', 'expr': ''})),
      _hint(tr('Vd mã nhóm: prefix(«Số CT», ".") + "|" + «Ngày CT»; mã băm nội dung: hash(item)')),
    ];
  }

  List<Widget> _group() {
    final cols = _cols('table');
    final by = [for (final x in (n['by'] as List? ?? const [])) '$x'];
    n['by'] = by;
    final aggs = _rows('aggregates');
    const ops = {'sum': 'Tổng', 'count': 'Đếm', 'min': 'Nhỏ nhất', 'max': 'Lớn nhất'};
    return [
      _source('table', tr('Bảng cần nhóm')),
      _gap(),
      _title(tr('Nhóm theo cột')),
      for (var i = 0; i < by.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: _col(tr('Cột'), by[i], cols, (v) => by[i] = v, key: ValueKey('by-$i'))),
            _delete(() => by.removeAt(i)),
          ]),
        ),
      _add(tr('Thêm cột nhóm'), () => by.add('')),
      if (by.isEmpty) Text(tr('Chọn ít nhất một cột'), style: const TextStyle(color: kFlowRed, fontSize: 12.5)),
      _gap(),
      _title(tr('Tổng hợp mỗi nhóm')),
      for (var i = 0; i < aggs.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('ak-$i'),
                initialValue: '${aggs[i]['key'] ?? ''}',
                decoration: InputDecoration(labelText: tr('Tên'), isDense: true, border: const OutlineInputBorder()),
                onChanged: (v) => _set(() => aggs[i]['key'] = v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: ops.containsKey(aggs[i]['op']) ? '${aggs[i]['op']}' : 'sum',
              items: [for (final e in ops.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
              onChanged: (v) => _set(() => aggs[i]['op'] = v ?? 'sum'),
            ),
            const SizedBox(width: 8),
            Expanded(child: _col(tr('Cột'), '${aggs[i]['col'] ?? ''}', cols, (v) => v.isEmpty ? aggs[i].remove('col') : aggs[i]['col'] = v, key: ValueKey('ac-$i'))),
            _delete(() => aggs.removeAt(i)),
          ]),
        ),
      _add(tr('Thêm tổng hợp'), () => aggs.add({'key': 'tong', 'op': 'sum', 'col': ''})),
      _gap(),
      ..._sort('sort_in_group', cols),
      _hint(tr('Kết quả: Các nhóm (mỗi nhóm có các cột nhóm, rows, count và tổng hợp), Số nhóm')),
    ];
  }

  List<Widget> _join() {
    final keys = _rows('keys');
    final ca = _cols('a'), cb = _cols('b');
    Map<String, dynamic> ren(String k) => ((n[k] as Map?) ?? <String, dynamic>{}).cast<String, dynamic>();
    final ra = ren('rename_a'), rb = ren('rename_b');
    // Cột không phải khoá có ở cả hai bảng (khi biết trước cột): phải đổi tên một bên.
    final dup = <String>[];
    if (ca != null && cb != null) {
      final na = {for (final c in ca) '${ra[c] ?? c}'};
      final nb = {for (final c in cb) '${rb[c] ?? c}'};
      final same = {for (final k in keys) if ('${ra[k['a']] ?? k['a']}' == '${rb[k['b']] ?? k['b']}') '${ra[k['a']] ?? k['a']}'};
      dup.addAll(na.intersection(nb).difference(same));
    }
    Widget renames(String k, String side, List<String>? cols) {
      final m = ren(k);
      final entries = m.entries.toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: _col(tr('Cột bảng {0}', [side]), entries[i].key, cols, (v) {
                final val = m.remove(entries[i].key);
                m[v] = val;
                n[k] = m;
              }, key: ValueKey('$k-f-$i-${entries[i].key}'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 16)),
              Expanded(
                child: TextFormField(
                  key: ValueKey('$k-t-$i'),
                  initialValue: '${entries[i].value}',
                  decoration: InputDecoration(labelText: tr('Tên mới'), isDense: true, border: const OutlineInputBorder()),
                  onChanged: (v) => _set(() {
                    m[entries[i].key] = v.trim();
                    n[k] = m;
                  }),
                ),
              ),
              _delete(() {
                m.remove(entries[i].key);
                m.isEmpty ? n.remove(k) : n[k] = m;
              }),
            ]),
          ),
        _add(tr('Đổi tên cột bảng {0}', [side]), () {
          m[dup.where((d) => !m.containsKey(d)).firstOrNull ?? ''] = '';
          n[k] = m;
        }),
      ]);
    }

    return [
      _source('a', tr('Bảng A')),
      _gap(10),
      _source('b', tr('Bảng B')),
      _gap(),
      _title(tr('Cột khoá (mọi cặp phải bằng nhau)')),
      for (var i = 0; i < keys.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: _col(tr('Cột A'), '${keys[i]['a'] ?? ''}', ca, (v) => keys[i]['a'] = v, key: ValueKey('ka-$i'))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('=')),
            Expanded(child: _col(tr('Cột B'), '${keys[i]['b'] ?? ''}', cb, (v) => keys[i]['b'] = v, key: ValueKey('kb-$i'))),
            _delete(() => keys.removeAt(i)),
          ]),
        ),
      _add(tr('Thêm cặp khoá'), () => keys.add({'a': '', 'b': ''})),
      _hint(tr('So chữ đã bỏ khoảng trắng hai đầu; khoá trống không bao giờ khớp')),
      _gap(),
      _title(tr('Đổi tên cột')),
      if (dup.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('Cột có ở cả hai bảng: {0}. Đổi tên ở một bên.', [dup.join(', ')]), style: const TextStyle(color: kFlowRed, fontSize: 12.5))),
      renames('rename_a', 'A', ca),
      renames('rename_b', 'B', cb),
      _hint(tr('Kết quả: Dòng khớp (1–1, gộp cột A và B), Chỉ có ở A, Chỉ có ở B, Khoá trùng (không nằm trong ba nhóm kia) và các số đếm')),
    ];
  }
}

// ---------------------------------------------------------------------------------------------- Đọc hết trang

/// Cách lật trang đoán theo tham số của công cụ: có `cursor` → theo con trỏ (LinkQ); có `start` + `count` / `limit` →
/// theo vị trí (M-Invoice).
Map<String, dynamic> guessPaging(List<String> args) {
  if (args.contains('start') && (args.contains('count') || args.contains('limit'))) {
    return {'mode': 'offset', 'start_arg': 'start', 'size_arg': args.contains('count') ? 'count' : 'limit', 'size': 100};
  }
  return {'mode': 'cursor', 'cursor_arg': args.contains('cursor') ? 'cursor' : (args.where((a) => a.contains('cursor')).firstOrNull ?? 'cursor'), 'next': 'next_cursor', 'more': 'has_more'};
}

/// Cấu hình lật trang và giới hạn của bước Đọc hết trang. Sửa trực tiếp [n]. [toolArgs]: tham số của công cụ đã chọn.
class PagesConfig extends StatefulWidget {
  final Map<String, dynamic> n;
  final List<String> toolArgs;
  final VoidCallback onChanged;
  const PagesConfig({super.key, required this.n, required this.toolArgs, required this.onChanged});
  @override
  State<PagesConfig> createState() => _PagesConfigState();
}

class _PagesConfigState extends State<PagesConfig> {
  Map<String, dynamic> get n => widget.n;
  Map<String, dynamic> get pg {
    final m = ((n['paging'] as Map?) ?? {'mode': 'cursor'}).cast<String, dynamic>();
    n['paging'] = m;
    return m;
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  Widget _text(String label, Map<String, dynamic> m, String k, {String? hint, bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: ValueKey('pg-$k-${pg['mode']}'),
          initialValue: '${m[k] ?? ''}',
          keyboardType: number ? TextInputType.number : null,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
          onChanged: (v) => _set(() {
            final t = v.trim();
            if (t.isEmpty) {
              m.remove(k);
            } else if (number) {
              final x = int.tryParse(t);
              x == null ? m.remove(k) : m[k] = x;
            } else {
              m[k] = t;
            }
          }),
        ),
      );

  /// Tham số của công cụ: chọn trong danh sách, hoặc gõ.
  Widget _arg(String label, String k) {
    final args = widget.toolArgs;
    final v = '${pg[k] ?? ''}';
    if (args.isEmpty || (v.isNotEmpty && !args.contains(v))) return _text(label, pg, k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        key: ValueKey('pg-$k'),
        initialValue: v.isEmpty ? null : v,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: [for (final a in args) DropdownMenuItem(value: a, child: Text(a))],
        onChanged: (x) => _set(() => x == null ? pg.remove(k) : pg[k] = x),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = pg['mode'] == 'offset' ? 'offset' : 'cursor';
    final hint = Pal.of(context).sub;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Lật trang'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [ButtonSegment(value: 'cursor', label: Text(tr('Theo con trỏ'))), ButtonSegment(value: 'offset', label: Text(tr('Theo vị trí')))],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _set(() => n['paging'] = s.first == 'offset'
            ? {'mode': 'offset', 'start_arg': 'start', 'size_arg': 'count', 'size': 100}
            : {'mode': 'cursor', 'cursor_arg': 'cursor', 'next': 'next_cursor', 'more': 'has_more'}),
      ),
      const SizedBox(height: 12),
      if (mode == 'cursor') ...[
        _arg(tr('Tham số nhận con trỏ'), 'cursor_arg'),
        _text(tr('Con trỏ trang sau (trong kết quả)'), pg, 'next', hint: 'next_cursor'),
        _text(tr('Còn trang (trong kết quả, tuỳ chọn)'), pg, 'more', hint: 'has_more'),
      ] else ...[
        _arg(tr('Tham số vị trí bắt đầu'), 'start_arg'),
        _arg(tr('Tham số số dòng mỗi trang'), 'size_arg'),
        _text(tr('Số dòng mỗi trang'), pg, 'size', number: true),
        _text(tr('Tổng số dòng (trong kết quả, tuỳ chọn)'), pg, 'total', hint: 'total'),
      ],
      _text(tr('Danh sách dòng trong kết quả mỗi trang'), n, 'rows', hint: 'rows · data.items'),
      Row(children: [
        Expanded(child: _text(tr('Tối đa số trang'), n, 'max_pages', hint: '50', number: true)),
        const SizedBox(width: 10),
        Expanded(child: _text(tr('Tối đa số dòng'), n, 'max_rows', hint: '20000', number: true)),
        const SizedBox(width: 10),
        Expanded(child: _text(tr('Thử lại mỗi trang'), n, 'retry', hint: '3', number: true)),
      ]),
      Text(tr('Kết quả là một bảng: Các dòng, Số dòng, Số trang, Bị cắt bớt. Một trang lỗi thì cả bước lỗi, không trả bảng thiếu.'),
          style: TextStyle(color: hint, fontSize: 12.5)),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------- khung Lặp bảng

/// Hộp cài đặt khung Lặp bảng: bảng, tên dòng, khoá dòng, dừng khi lỗi. Trả về true khi bấm Lưu (đã sửa [l]).
Future<bool> editLoopSettings(BuildContext context, FlowDoc doc, FLoop l, List<CondVar> vars) async {
  var table = l.items, alias = l.alias, key = l.key, stop = l.stopOnError;
  final sources = tableSources(doc, l);
  final outer = {for (final o in enclosingLoops(doc, l)) o.alias.trim()}..remove('');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) {
        final badAlias = alias.trim().isNotEmpty &&
            (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(alias.trim()) ||
                const {'form', 'steps', 'vars', 'item', 'loop', 'process', 'requester', 'index', 'result', 'data'}.contains(alias.trim()) ||
                outer.contains(alias.trim()));
        return AlertDialog(
          title: Text(tr('Lặp bảng')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TableSourceField(label: tr('Lặp qua từng dòng của'), value: table, sources: sources, vars: vars, onChanged: (v) => set(() => table = v)),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: alias,
                  decoration: InputDecoration(
                    labelText: tr('Tên dòng (as)'),
                    hintText: tr('vd nhom, ct; bỏ trống = item'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: badAlias ? tr('Chữ không dấu, số, _; không trùng khung ngoài hay tên có sẵn') : null,
                  ),
                  onChanged: (v) => set(() => alias = v.trim()),
                ),
                const SizedBox(height: 14),
                ExprField(label: tr('Nhận diện dòng (ghi vào lỗi từng lượt)'), value: key, vars: vars, lines: 1, onChanged: (v) => key = v),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: stop,
                  title: Text(tr('Dừng cả vòng khi một lượt lỗi')),
                  subtitle: Text(tr('Tắt (mặc định): lượt lỗi được ghi lại, vòng lặp chạy tiếp dòng sau')),
                  onChanged: (v) => set(() => stop = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: badAlias || table.trim().isEmpty ? null : () => Navigator.pop(d, true), child: Text(tr('Lưu'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return false;
  l
    ..items = table.trim()
    ..alias = alias.trim()
    ..key = key.trim()
    ..stopOnError = stop;
  return true;
}

// ---------------------------------------------------------------------------------------------- cấu trúc kết quả công cụ

/// Khuôn kết quả (`output_schema` JSON Schema) của công cụ bước [n] gọi (bước tự động MCP / Đọc hết trang), lấy từ danh
/// sách công cụ máy chủ trả về. Tên app / tool là mẫu thì không biết.
Map<String, dynamic>? toolOutputSchema(Map n, Map integ) {
  final p = n['params'] as Map? ?? const {};
  final key = '${p['app'] ?? ''}'.isNotEmpty ? '${p['app']}' : '${p['server'] ?? ''}';
  final tool = '${p['tool'] ?? ''}';
  if (key.isEmpty || tool.isEmpty || key.contains('{{') || tool.contains('{{')) return null;
  for (final g in (integ['mcp'] as List? ?? const [])) {
    if (g is! Map || g['name'] != key) continue;
    for (final t in (g['tools'] as List? ?? const [])) {
      if (t is Map && t['name'] == tool && t['output_schema'] is Map) return (t['output_schema'] as Map).cast<String, dynamic>();
    }
  }
  return null;
}

/// Kiểu thông tin của một khuôn JSON Schema.
String schemaType(Map s) => switch (s['type']) {
      'boolean' => 'bool',
      'number' || 'integer' => 'number',
      'array' => 'table',
      'object' => 'object',
      _ => s['format'] == 'date' ? 'date' : 'text',
    };

/// Tên dễ đọc của một khoá: mô tả (description) / tiêu đề của khuôn, không có thì chính khoá.
String schemaLabel(String key, Map s) {
  final d = '${s['title'] ?? s['description'] ?? ''}'.trim();
  if (d.isEmpty) return key;
  // Mô tả dài: lấy câu đầu.
  final first = d.split(RegExp(r'[.;:\n]')).first.trim();
  return first.length > 60 ? '${first.substring(0, 57)}…' : first;
}

/// Khuôn con theo đường dẫn "data.rows".
Map<String, dynamic>? schemaAt(Map<String, dynamic>? s, String path) {
  Map<String, dynamic>? cur = s;
  for (final k in path.split('.')) {
    final props = cur?['properties'] as Map?;
    final next = props?[k];
    if (next is! Map) return null;
    cur = next.cast<String, dynamic>();
  }
  return cur;
}

/// Các thông tin trong khuôn kết quả: (đường dẫn sau output., tên, kiểu). Object lồng mở một tầng; danh sách là bảng.
List<(String, String, String)> schemaFields(Map<String, dynamic>? s, {String prefix = '', String labelPrefix = '', int depth = 0}) {
  final out = <(String, String, String)>[];
  for (final e in ((s?['properties'] as Map?) ?? const {}).entries) {
    if (e.value is! Map) continue;
    final sub = (e.value as Map).cast<String, dynamic>();
    final path = prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}';
    final label = labelPrefix.isEmpty ? schemaLabel('${e.key}', sub) : '$labelPrefix › ${schemaLabel('${e.key}', sub)}';
    final t = schemaType(sub);
    if (t == 'object' && depth < 1) {
      out.addAll(schemaFields(sub, prefix: path, labelPrefix: label, depth: depth + 1));
    } else if (t != 'object') {
      out.add((path, label, t));
    }
  }
  return out;
}

/// Cột của bảng (danh sách) trong khuôn: khoá → (tên, kiểu).
Map<String, (String, String)>? schemaColumns(Map<String, dynamic>? arr) {
  final items = arr?['items'];
  if (items is! Map) return null;
  return {for (final (k, l, t) in schemaFields(items.cast<String, dynamic>())) k: (l, t)};
}
