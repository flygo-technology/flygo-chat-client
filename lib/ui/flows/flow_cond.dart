import 'dart:convert';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import 'flow_calc.dart' show calcVars;
import 'flow_doc.dart';
import 'flow_editor_expr.dart';
import 'flow_editor_set.dart' show setVars;
import 'flow_editor.dart' show editorCtx;
import 'flow_editor_tables.dart';
import 'flow_editor_vars.dart';
import 'flow_logic.dart';

/// Điều kiện rẽ nhánh dựng bằng giao diện (không gõ công thức): các nhóm "VÀ", giữa các nhóm là "HOẶC"
/// (đủ để diễn tả mọi tổ hợp VÀ / HOẶC). Đổi qua lại với biểu thức của máy chủ: `a > 1 and b == "x" or c in [..]`.

/// Thông tin dùng được trong điều kiện / nội dung: trường biểu mẫu hoặc kết quả của bước AI.
class CondVar {
  final String path, label, type;
  final List<String> options;
  const CondVar(this.path, this.label, this.type, [this.options = const []]);
}

/// Thành phần của trường Vị trí / Wi-Fi (app tự lấy) → tên hiển thị.
String fieldPartLabel(String type, String part) => switch ((type, part)) {
      ('location', 'lat') => tr('Vĩ độ'),
      ('location', 'lon') => tr('Kinh độ'),
      ('location', 'accuracy') => tr('Độ chính xác (m)'),
      ('location' || 'wifi', 'at') => tr('Lúc lấy'),
      ('wifi', 'ssid') => tr('Tên Wi-Fi'),
      ('wifi', 'bssid') => tr('Mã điểm phát'),
      _ => part,
    };

/// Thành phần dùng được trong điều kiện của trường Vị trí / Wi-Fi: (khoá, kiểu).
List<(String, String)> fieldParts(String type) => switch (type) {
      'location' => const [('lat', 'number'), ('lon', 'number'), ('accuracy', 'number')],
      'wifi' => const [('ssid', 'text'), ('bssid', 'text')],
      _ => const [],
    };

/// Trường không dùng trong điều kiện / chèn thông tin (tệp, ảnh).
const _noVarTypes = {'files', 'images', 'photo'};

/// Kết quả bước "Bắt đầu quy trình khác" khi mở nhiều luồng (mỗi dòng / mỗi người).
/// Kết quả bước "Tính khoảng cách GPS" (geo_distance) → tên hiển thị.
const geoOutputLabels = {
  'distance_m': 'Khoảng cách (m)',
  'inside': 'Trong khu vực',
  'radius': 'Bán kính (m)',
  'accuracy': 'Độ chính xác GPS (m)',
};

const childOutputLabels = {
  'children': 'Các luồng đã xong',
  'total': 'Số luồng',
  'people': 'Người nhận',
  'pending': 'Người / dòng chưa xong',
  'pending_count': 'Số luồng chưa xong',
  'timed_out': 'Quá hạn chờ',
  'instance_id': 'Mã tiến trình mới',
};

/// "12:00": giờ trong ngày (bước Chờ, phép tính số phút).
bool isClockText(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  return m != null && int.parse(m[1]!) < 24 && int.parse(m[2]!) < 60;
}

/// Các thông tin có trong luồng: trường biểu mẫu + kết quả các bước AI.
/// [at]: bước đang soạn; nằm trong khối lặp thì có thêm "Dòng đang xét › cột" và số thứ tự dòng.
List<CondVar> flowVars(FlowDoc doc, {FItem? at}) {
  final form = FlowField.listOf(doc.meta['form']);
  final out = <CondVar>[
    for (final f in form)
      if (f.type == 'table') ...[
        // Bảng: dùng số dòng và tổng các cột số (máy chủ tính sẵn).
        CondVar('form.${f.key}__so_dong', '${f.label} › ${tr('Số dòng')}', 'number'),
        for (final c in f.columns)
          if (c.type == 'money' || c.type == 'number') CondVar('form.${f.key}__tong.${c.key}', '${f.label} › ${tr('Tổng')} ${c.label.toLowerCase()}', c.type),
      ] else if (fieldParts(f.type).isNotEmpty) ...[
        // Vị trí / Wi-Fi: cả trường (cho phép tính khoảng cách, số phút) và từng thành phần (cho điều kiện).
        CondVar('form.${f.key}', f.label, f.type),
        for (final (k, t) in fieldParts(f.type)) CondVar('form.${f.key}.$k', '${f.label} › ${fieldPartLabel(f.type, k)}', t),
      ] else if (!_noVarTypes.contains(f.type))
        CondVar('form.${f.key}', f.label, f.type, f.options),
  ];
  FLoop? loopOfAt;
  void walk(List<FItem> l, FLoop? inLoop) {
    for (final x in l) {
      if (at != null && identical(x, at)) loopOfAt = inLoop;
      switch (x) {
        // Thẻ, tiến trình, chờ người dùng, tạo phê duyệt.
        case FStep s when editorNodeTypes.contains(s.type):
          out.addAll(nodeVars(s, s.name.isEmpty ? nodeDefaultName(s.type) : s.name));
        case FStep s when s.type == 'ai' || s.type == 'auto':
          final name = s.name.isEmpty ? (s.type == 'ai' ? tr('Bước AI') : tr('Gọi công cụ')) : s.name;
          // Khuôn kết quả của công cụ (máy chủ trả về, có mô tả tiếng Việt): chọn thông tin theo cấu trúc, không gõ tay.
          final known = <String>{};
          for (final (k, l, t) in schemaFields(toolOutputSchema(s.node, editorCtx?.integ ?? const {}))) {
            if (t == 'table') continue;
            known.add(k);
            out.add(CondVar('steps.${s.id}.output.$k', '$name › $l', t));
          }
          for (final e in ((s.node['output_schema'] as Map?) ?? const {}).entries) {
            if (e.value == 'json' || known.contains(e.key)) continue;
            out.add(CondVar('steps.${s.id}.output.${e.key}', '$name › ${e.key}', e.value == 'text' ? 'text' : '${e.value}'));
          }
        // Người tiếp nhận / người duyệt, và thông tin điền ở bước Điền thông tin.
        case FStep s when s.type == 'wait_event':
          final name = s.name.isEmpty ? tr('Chờ sự kiện') : s.name;
          out.add(CondVar('steps.${s.id}.output.timeout', '$name › ${tr('Hết thời gian chờ')}', 'bool'));
        // Bước bảng: số dòng (và các số đếm của Ghép bảng).
        case FStep s when tableNodeTypes.contains(s.type):
          out.addAll(tableVars(s));
        // Soạn nội dung: tiêu đề, nội dung HTML / chữ thường (cho gửi thư, gửi tin).
        case FStep s when s.type == 'compose':
          final name = s.name.isEmpty ? tr('Soạn nội dung') : s.name;
          for (final (k, l) in const [('subject', 'Tiêu đề'), ('html', 'Nội dung HTML'), ('text', 'Nội dung chữ thường')]) {
            out.add(CondVar('steps.${s.id}.output.$k', '$name › ${tr(l)}', 'text'));
          }
        case FStep s when s.type == 'calc':
          out.addAll(calcVars(s.id, s.name, s.node['vars'] as List? ?? const []));
        // Đặt biến: vars.<tên> (dùng ở mọi bước sau) và kết quả của bước.
        case FStep s when s.type == 'set':
          out.addAll(setVars(s, form));
        // Tính khoảng cách GPS: khoảng cách (số), trong khu vực (đúng / sai) để rẽ nhánh.
        case FStep s when s.type == 'geo_distance':
          final name = s.name.isEmpty ? tr('Tính khoảng cách GPS') : s.name;
          for (final (k, t) in const [('distance_m', 'number'), ('inside', 'bool'), ('radius', 'number'), ('accuracy', 'number')]) {
            out.add(CondVar('steps.${s.id}.output.$k', '$name › ${tr(geoOutputLabels[k]!)}', t));
          }
        case FStep s when s.type == 'claim':
          out.add(CondVar('steps.${s.id}.output.by', tr('Người tiếp nhận ở "{0}"', [s.name.isEmpty ? tr('Tiếp nhận') : s.name]), 'user'));
        case FStep s when s.type == 'buttons':
          final name = s.name.isEmpty ? tr('Nút trên tin') : s.name;
          final labels = [for (final b in (s.node['buttons'] as List? ?? const [])) if (b is Map && '${b['url'] ?? ''}'.isEmpty) '${b['label']}'];
          if (labels.isNotEmpty) {
            out.add(CondVar('steps.${s.id}.output.clicked', tr('{0} › Nút đã bấm', [name]), 'select', labels));
            out.add(CondVar('steps.${s.id}.output.by', tr('Người bấm ở "{0}"', [name]), 'user'));
          }
        case FStep s when s.type == 'approval':
          out.add(CondVar('steps.${s.id}.output.by', tr('Người duyệt ở "{0}"', [s.name.isEmpty ? tr('Duyệt') : s.name]), 'user'));
        case FStep s when s.type == 'form_task':
          final name = s.name.isEmpty ? tr('Điền thông tin') : s.name;
          for (final f in FlowField.listOf(s.node['fields'])) {
            if (_noVarTypes.contains(f.type) || f.type == 'table') continue;
            out.add(CondVar('steps.${s.id}.output.${f.key}', '$name › ${f.label}', f.type, f.options));
            for (final (k, t) in fieldParts(f.type)) {
              out.add(CondVar('steps.${s.id}.output.${f.key}.$k', '$name › ${f.label} › ${fieldPartLabel(f.type, k)}', t));
            }
          }
        // Mở nhiều luồng (mỗi dòng / mỗi người): số luồng, số luồng chưa xong, quá hạn chờ.
        case FStep s when s.type == 'start_flow' && (s.node['each'] != null || s.node['each_person'] != null):
          final name = s.name.isEmpty ? tr('Bắt đầu quy trình khác') : s.name;
          out.add(CondVar('steps.${s.id}.output.total', '$name › ${tr(childOutputLabels['total']!)}', 'number'));
          if (s.node['wait'] == true && s.node['timeout'] != null) {
            out.add(CondVar('steps.${s.id}.output.pending_count', '$name › ${tr(childOutputLabels['pending_count']!)}', 'number'));
            out.add(CondVar('steps.${s.id}.output.timed_out', '$name › ${tr(childOutputLabels['timed_out']!)}', 'bool'));
          }
        case FCondition c:
          for (final b in c.branches) {
            walk(b.steps, inLoop);
          }
        case FParallel p:
          for (final b in p.branches) {
            walk(b, inLoop);
          }
        case FLoop lp:
          walk(lp.body, lp);
          out.addAll(loopVars(lp));
        default:
      }
      // Nhánh Lỗi: «<bước> › Lỗi › Nội dung / Mã».
      if (x is FStep && FStep.errorBranch(x.node)) out.addAll(errorVars(x));
      // Các bước trong nhánh của bước nhiều cổng.
      if (x is FStep) {
        for (final p in x.ports) {
          walk(p.steps, inLoop);
        }
      }
    }
  }

  walk(doc.steps, null);
  out.addAll(processVars(doc.allSteps));
  // Tạo tiến trình nhiều (each): phần tử đang tạo (cột của bảng) và số thứ tự.
  if (at is FStep && at.type == 'process_create' && '${at.node['each'] ?? ''}'.trim().isNotEmpty) {
    final each = '${at.node['each']}'.trim();
    final t = form.where((f) => 'form.${f.key}' == each).firstOrNull;
    for (final c in t?.columns ?? const <FlowField>[]) {
      out.add(CondVar('item.${c.key}', '${tr('Phần tử đang tạo')} › ${c.label}', c.type, c.options));
    }
    if (t == null) out.add(CondVar('item', tr('Phần tử đang tạo'), 'text'));
    out.add(CondVar('index', tr('Số thứ tự'), 'number'));
  }
  // Khung Lặp bảng (tên dòng của mọi khung chứa, item / loop của khung trong cùng), Lọc bảng / Thêm cột (item).
  if (at != null) out.addAll(rowVars(doc, at));
  final lp = loopOfAt;
  if (lp != null && lp.legacy) {
    final t = form.where((f) => 'form.${f.key}' == lp.items).firstOrNull;
    for (final c in t?.columns ?? const <FlowField>[]) {
      out.add(CondVar('item.${c.key}', '${tr('Dòng đang xét')} › ${c.label}', c.type, c.options));
    }
    out.add(CondVar('loop.index', tr('Số thứ tự dòng'), 'number'));
  }
  return out;
}

/// Mã lỗi của nhánh Lỗi (`steps.<bước>.output.error.code`).
const errorCodes = ['timeout', 'http_400', 'http_404', 'http_500', 'http_502', 'bad_output', 'child_failed', 'child_cancelled', 'error'];

/// Kết quả lỗi của bước [s] có nhánh Lỗi: nội dung và mã lỗi.
List<CondVar> errorVars(FStep s) {
  final name = s.name.isEmpty ? errorStepDefaultName(s) : s.name;
  return [
    CondVar('steps.${s.id}.output.error.message', '$name › ${tr('Lỗi')} › ${tr('Nội dung')}', 'text'),
    CondVar('steps.${s.id}.output.error.code', '$name › ${tr('Lỗi')} › ${tr('Mã')}', 'select', errorCodes),
  ];
}

String errorStepDefaultName(FStep s) => switch (s.type) {
      'ai' => tr('Bước AI'),
      'wait_event' => tr('Chờ sự kiện'),
      'start_flow' => tr('Bắt đầu quy trình khác'),
      _ => tr('Gọi công cụ'),
    };

/// Phép so sánh dùng được theo kiểu thông tin.
List<String> condOps(String type) => switch (type) {
      'number' || 'money' => const ['>', '>=', '<', '<=', '==', '!='],
      'date' => const ['<', '>', '=='],
      'select' => const ['==', '!=', 'in'],
      'bool' => const ['=='],
      _ => const ['==', '!='],
    };

String condOpLabel(String op, String type) => switch ((op, type)) {
      ('<', 'date') => tr('trước ngày'),
      ('>', 'date') => tr('sau ngày'),
      ('==', 'date') => tr('đúng ngày'),
      ('>', _) => tr('lớn hơn'),
      ('>=', _) => tr('từ'),
      ('<', _) => tr('nhỏ hơn'),
      ('<=', _) => tr('không quá'),
      ('==', _) => tr('là'),
      ('!=', _) => tr('khác'),
      ('in', _) => tr('là một trong'),
      _ => op,
    };

/// Vế phải là một thông tin khác của luồng (so hai thông tin với nhau, vd thuộc tính cũ ≠ kết quả mới).
class CondRef {
  final String path;
  const CondRef(this.path);
  @override
  bool operator ==(Object other) => other is CondRef && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

/// Một điều kiện: [path] [op] [value]. Với `in`, value là danh sách; [CondRef] = so với thông tin khác.
class CondTerm {
  String path, op;
  Object? value;
  CondTerm(this.path, this.op, this.value);
}

/// Nhóm "VÀ" (mọi điều kiện đều đúng); danh sách nhóm nối bằng "HOẶC".
typedef CondGroups = List<List<CondTerm>>;

String _lit(Object? v) => switch (v) {
      CondRef r => r.path,
      num n => n == n.roundToDouble() ? '${n.toInt()}' : '$n',
      bool b => '$b',
      null => 'null',
      _ => jsonEncode('$v'),
    };

String _termExpr(CondTerm t) => t.op == 'in' ? '${t.path} in [${[for (final x in (t.value as List? ?? const [])) _lit(x)].join(', ')}]' : '${t.path} ${t.op} ${_lit(t.value)}';

/// Nhóm → biểu thức máy chủ.
String condToExpr(CondGroups groups) {
  final gs = [for (final g in groups) if (g.isNotEmpty) g];
  return [
    for (final g in gs) gs.length > 1 && g.length > 1 ? '(${g.map(_termExpr).join(' and ')})' : g.map(_termExpr).join(' and '),
  ].join(' or ');
}

// ------------------------------------------------------------------ đọc biểu thức (để sửa lại bằng giao diện)

sealed class _E {}

class _Or extends _E {
  final _E a, b;
  _Or(this.a, this.b);
}

class _And extends _E {
  final _E a, b;
  _And(this.a, this.b);
}

class _Not extends _E {
  final _E a;
  _Not(this.a);
}

class _Cmp extends _E {
  final _E a, b;
  final String op;
  _Cmp(this.a, this.op, this.b);
}

class _In extends _E {
  final _E a, b;
  _In(this.a, this.b);
}

class _Var extends _E {
  final String path;
  _Var(this.path);
}

class _Lit extends _E {
  final Object? v;
  _Lit(this.v);
}

class _List extends _E {
  final List<_E> items;
  _List(this.items);
}

class _Parser {
  final List<String> t;
  int i = 0;
  _Parser(this.t);

  String? get peek => i < t.length ? t[i] : null;
  bool _kw(Set<String> w) => peek != null && w.contains(peek);

  _E or() {
    var l = and();
    while (_kw({'or', '||'})) {
      i++;
      l = _Or(l, and());
    }
    return l;
  }

  _E and() {
    var l = not();
    while (_kw({'and', '&&'})) {
      i++;
      l = _And(l, not());
    }
    return l;
  }

  _E not() {
    if (_kw({'not', '!'})) {
      i++;
      return _Not(not());
    }
    final l = atom();
    if (_kw({'==', '!=', '>', '>=', '<', '<='})) {
      final op = t[i++];
      return _Cmp(l, op, atom());
    }
    if (_kw({'in'})) {
      i++;
      return _In(l, atom());
    }
    return l;
  }

  _E atom() {
    final x = peek;
    if (x == null) throw const FormatException('end');
    i++;
    if (x == '(') {
      final e = or();
      if (peek != ')') throw const FormatException(')');
      i++;
      return e;
    }
    if (x == '[') {
      final items = <_E>[];
      while (peek != ']') {
        items.add(atom());
        if (peek == ',') i++;
        if (peek == null) throw const FormatException(']');
      }
      i++;
      return _List(items);
    }
    if (x.startsWith('"') || x.startsWith("'")) return _Lit(x.substring(1, x.length - 1).replaceAll(r'\"', '"').replaceAll(r"\'", "'"));
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(x)) return _Lit(num.parse(x));
    if (x == 'true' || x == 'false') return _Lit(x == 'true');
    if (x == 'null') return _Lit(null);
    if (RegExp(r'^[A-Za-z_][\w.\-]*$').hasMatch(x)) return _Var(x);
    throw FormatException(x);
  }
}

List<String> _tokens(String s) {
  final out = <String>[];
  final re = RegExp(r'''\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|-?\d+(?:\.\d+)?|==|!=|>=|<=|&&|\|\||[><()\[\],!]|[A-Za-z_][\w.\-]*)''');
  var pos = 0;
  while (pos < s.length) {
    if (s.substring(pos).trim().isEmpty) break;
    final m = re.matchAsPrefix(s, pos);
    if (m == null) throw FormatException(s.substring(pos));
    out.add(m[1]!);
    pos = m.end;
  }
  return out;
}

/// Biểu thức → nhóm điều kiện; null nếu biểu thức không theo khuôn dựng được bằng giao diện
/// (vd bot AI viết phức tạp) — khi đó giao diện cho làm lại từ đầu.
CondGroups? condFromExpr(String expr) {
  if (expr.trim().isEmpty) return [];
  try {
    final p = _Parser(_tokens(expr));
    final e = p.or();
    if (p.peek != null) return null;
    List<_E> flat(_E e, bool isOr) => switch (e) {
          _Or o when isOr => [...flat(o.a, true), ...flat(o.b, true)],
          _And a when !isOr => [...flat(a.a, false), ...flat(a.b, false)],
          _ => [e],
        };
    CondTerm term(_E e) => switch (e) {
          _Cmp(a: _Var v, b: _Lit l) => CondTerm(v.path, e.op, l.v),
          // So hai thông tin: "process.props.loi_hash != steps.lp.output.loi_hash".
          _Cmp(a: _Var v, b: _Var w) => CondTerm(v.path, e.op, CondRef(w.path)),
          _In(a: _Var v, b: _List l) when l.items.every((x) => x is _Lit) => CondTerm(v.path, 'in', [for (final x in l.items) (x as _Lit).v]),
          _Var v => CondTerm(v.path, '==', true),
          _Not(a: _Var v) => CondTerm(v.path, '==', false),
          _ => throw const FormatException('term'),
        };
    return [
      for (final g in flat(e, true)) [for (final t in flat(g, false)) term(t)],
    ];
  } on FormatException {
    return null;
  }
}

// ------------------------------------------------------------------ chữ dễ đọc

String condValueLabel(Object? v, CondVar? cv, {String Function(String id)? userName}) {
  if (v is List) return v.map((x) => condValueLabel(x, cv, userName: userName)).join(', ');
  final type = cv?.type ?? '';
  if (v is bool) return v ? tr('Có') : tr('Không');
  if (v is num) return type == 'money' ? '${vnNumber(v)} đ' : (v.abs() >= 1000 ? vnNumber(v) : '$v');
  final s = '${v ?? ''}';
  if (type == 'date' && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
  if (type == 'user' && userName != null) return userName(s);
  return s;
}

String condTermLabel(CondTerm t, List<CondVar> vars, {String Function(String id)? userName}) {
  final cv = vars.where((v) => v.path == t.path).firstOrNull;
  final name = cv?.label ?? t.path;
  final ref = t.value;
  if (ref is CondRef) return '$name ${condOpLabel(t.op, cv?.type ?? '')} ${vars.where((v) => v.path == ref.path).firstOrNull?.label ?? ref.path}';
  return '$name ${condOpLabel(t.op, cv?.type ?? '')} ${condValueLabel(t.value, cv, userName: userName)}';
}

/// Biểu thức → câu đọc được: "Số tiền lớn hơn 20.000.000 đ và Loại chi là Mua vật tư".
String condLabel(String expr, List<CondVar> vars, {String Function(String id)? userName}) {
  final g = condFromExpr(expr);
  if (g == null) return exprLabel(expr, vars);
  if (g.isEmpty) return '';
  return [
    for (final grp in g)
      (g.length > 1 && grp.length > 1 ? '(%)' : '%').replaceFirst('%', grp.map((t) => condTermLabel(t, vars, userName: userName)).join(' ${tr('và')} ')),
  ].join(' ${tr('hoặc')} ');
}

/// Biểu thức không dựng được bằng giao diện (phép tính, hàm...) → chữ đọc được: mỗi thông tin thành «tên».
/// Biểu thức sai: "Biểu thức lỗi: …".
String exprLabel(String expr, List<CondVar> vars) {
  try {
    parseExpr(expr);
  } on ExprError catch (e) {
    return tr('Biểu thức lỗi: {0}', [e.message]);
  }
  return exprDisplay(expr.trim(), (p) => vars.where((v) => v.path == p).firstOrNull?.label ?? p);
}

// ------------------------------------------------------------------ nội dung có chèn thông tin

/// "{{form.so_tien}}" ↔ "[Số tiền]": người soạn chỉ thấy tên thông tin trong ngoặc vuông, chèn bằng nút.
String templateToDisplay(String raw, List<CondVar> vars) {
  var s = raw;
  for (final v in vars) {
    s = s.replaceAll(RegExp(r'\{\{\s*' + RegExp.escape(v.path) + r'\s*\}\}'), '[${v.label}]');
  }
  return s;
}

String templateFromDisplay(String shown, List<CondVar> vars) {
  var s = shown;
  final byLen = [...vars]..sort((a, b) => b.label.length.compareTo(a.label.length));
  for (final v in byLen) {
    s = s.replaceAll('[${v.label}]', '{{${v.path}}}');
  }
  return s;
}

// ------------------------------------------------------------------ tính điều kiện trong app (trường hiện theo điều kiện)

Object? _pathOf(Map<String, dynamic> ctx, String path) {
  Object? cur = ctx;
  for (final p in path.split('.')) {
    if (cur is Map) {
      cur = cur[p];
    } else {
      return null;
    }
  }
  return cur;
}

num? _asNum(Object? v) => v is num ? v : (v is String ? num.tryParse(v.replaceAll('.', '').replaceAll(',', '.')) : null);

bool _termTrue(CondTerm t, Map<String, dynamic> ctx) {
  final v = _pathOf(ctx, t.path);
  final ref = t.value;
  if (ref is CondRef) return _termTrue(CondTerm(t.path, t.op, _pathOf(ctx, ref.path)), ctx);
  switch (t.op) {
    case 'in':
      return (t.value as List? ?? const []).any((x) => '$x' == '$v');
    case '==':
      return t.value is num ? _asNum(v) == t.value : '${v ?? ''}' == '${t.value ?? ''}' || (t.value is bool && v == t.value);
    case '!=':
      return !(t.value is num ? _asNum(v) == t.value : '${v ?? ''}' == '${t.value ?? ''}');
  }
  final a = _asNum(v), b = _asNum(t.value);
  if (a != null && b != null) {
    return switch (t.op) { '>' => a > b, '>=' => a >= b, '<' => a < b, _ => a <= b };
  }
  final x = '${v ?? ''}', y = '${t.value ?? ''}';
  if (x.isEmpty) return false;
  final c = x.compareTo(y);
  return switch (t.op) { '>' => c > 0, '>=' => c >= 0, '<' => c < 0, _ => c <= 0 };
}

/// Biểu thức (dạng nhóm VÀ nối HOẶC) đúng không với [ctx] (vd {"form": {...}}). Không đọc được: coi là đúng.
bool condTrue(String expr, Map<String, dynamic> ctx) {
  if (expr.trim().isEmpty) return true;
  final g = condFromExpr(expr);
  if (g == null) {
    // Biểu thức có phép tính / hàm: tính như máy chủ; sai cú pháp thì coi là đúng (vẫn hiện trường).
    try {
      return exprTruthy(evalExpr(parseExpr(expr), ctx));
    } on ExprError {
      return true;
    }
  }
  return g.any((grp) => grp.every((t) => _termTrue(t, ctx)));
}
