import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

import '../../i18n/i18n.dart';

/// Ngôn ngữ biểu thức của Flows (như `flows_engine::expr` của máy chủ): dùng chung cho điều kiện của Rẽ nhánh,
/// `show_if`, kiểm tra chéo, Tính toán `expr`, bước Đặt biến và phần trong `{{…}}` của mẫu chữ.
/// Tự phân tích, không eval. Ở app dùng để kiểm nhanh khi soạn (lỗi tiếng Việt dễ hiểu) và để tính `show_if`
/// trên biểu mẫu.
///
/// Thứ tự ưu tiên (chặt dần): `or` < `and` < `not` < so sánh / `in` < `+ -` < `* / %` < dấu trừ đứng trước.
/// Tên biến được chứa dấu `-` (`steps.de-xuat.output.x`), nên phép trừ giữa hai biến phải có dấu cách.

/// Một hàm dùng được: tên, số tham số tối thiểu / tối đa, mẫu chèn, mô tả ngắn.
class ExprFunc {
  final String name, template, hint;
  final int min, max;
  const ExprFunc(this.name, this.min, this.max, this.template, this.hint);
}

/// Các hàm của máy chủ (cùng số tham số với `expr::FUNCS`).
const exprFuncs = <ExprFunc>[
  ExprFunc('today', 0, 0, 'today()', 'Ngày hôm nay (giờ Việt Nam)'),
  ExprFunc('now', 0, 0, 'now()', 'Ngày giờ bây giờ "YYYY-MM-DD HH:MM"'),
  ExprFunc('days_between', 2, 2, 'days_between(a, b)', 'Số ngày từ ngày a tới ngày b'),
  ExprFunc('add_days', 2, 2, 'add_days(ngay, 3)', 'Ngày cộng thêm n ngày (âm = lùi)'),
  ExprFunc('add_workdays', 2, 2, 'add_workdays(ngay, 3)', 'Ngày cộng n ngày làm việc theo lịch công ty'),
  ExprFunc('year', 1, 1, 'year(ngay)', 'Năm của ngày'),
  ExprFunc('month', 1, 1, 'month(ngay)', 'Tháng (1–12) của ngày'),
  ExprFunc('len', 1, 1, 'len(x)', 'Số ký tự của chữ / số dòng của bảng'),
  ExprFunc('sum', 1, 3, 'sum(bang, "cot")', 'Tổng một cột số của bảng (có thể thêm điều kiện lọc dòng)'),
  ExprFunc('count', 1, 2, 'count(bang, item.cot > 0)', 'Đếm số dòng (thoả điều kiện, dùng item.<cột>)'),
  ExprFunc('contains', 2, 2, 'contains(chu, "x")', 'Chữ có chứa x / danh sách có phần tử x'),
  ExprFunc('empty', 1, 1, 'empty(x)', 'Trống (chưa điền, chữ toàn dấu cách, danh sách rỗng)'),
  ExprFunc('lower', 1, 1, 'lower(x)', 'Chữ thường'),
  ExprFunc('upper', 1, 1, 'upper(x)', 'Chữ hoa'),
  ExprFunc('round', 1, 2, 'round(x, 0)', 'Làm tròn n số lẻ (n âm = tròn chục / trăm / nghìn)'),
  ExprFunc('min', 1, 50, 'min(a, b)', 'Số nhỏ nhất'),
  ExprFunc('max', 1, 50, 'max(a, b)', 'Số lớn nhất'),
  ExprFunc('abs', 1, 1, 'abs(x)', 'Trị tuyệt đối'),
  ExprFunc('if', 3, 3, 'if(dieu_kien, a, b)', 'a nếu điều kiện đúng, không thì b'),
  ExprFunc('prefix', 2, 2, 'prefix(chu, ".")', 'Phần trước dấu phân cách đầu tiên ("ABC.2" → "ABC"); không có dấu thì cả chữ'),
  ExprFunc('suffix', 2, 2, 'suffix(chu, ".")', 'Phần sau dấu phân cách đầu tiên ("ABC.2" → "2"); không có dấu thì rỗng'),
  ExprFunc('before', 2, 2, 'before(chu, ".")', 'Như prefix: phần trước dấu phân cách đầu tiên'),
  ExprFunc('after', 2, 2, 'after(chu, ".")', 'Như suffix: phần sau dấu phân cách đầu tiên'),
  ExprFunc('starts_with', 2, 2, 'starts_with(chu, "LQF:")', 'Chữ bắt đầu bằng ...'),
  ExprFunc('money', 1, 1, 'money(so_tien)', 'Số tiền kiểu Việt Nam: 1.080.000 ₫'),
  ExprFunc('date_vn', 1, 1, 'date_vn(ngay)', 'Ngày kiểu Việt Nam: 10/11/2026'),
  ExprFunc('hash', 1, 1, 'hash(item)', 'Mã băm SHA-256 của nội dung (để biết dữ liệu có đổi không)'),
];

ExprFunc? exprFunc(String name) => exprFuncs.where((f) => f.name == name).firstOrNull;

// ------------------------------------------------------------------ cây biểu thức

sealed class ExprNode {
  const ExprNode();
}

class ELit extends ExprNode {
  final Object? value;
  const ELit(this.value);
}

class EVar extends ExprNode {
  final String path;
  const EVar(this.path);
}

class EList extends ExprNode {
  final List<ExprNode> items;
  const EList(this.items);
}

class ENot extends ExprNode {
  final ExprNode a;
  const ENot(this.a);
}

class ENeg extends ExprNode {
  final ExprNode a;
  const ENeg(this.a);
}

/// Hai ngôi: and, or, == != > >= < <=, in, + - * / %.
class EBin extends ExprNode {
  final ExprNode a, b;
  final String op;
  const EBin(this.a, this.op, this.b);
}

class ECall extends ExprNode {
  final String name;
  final List<ExprNode> args;
  const ECall(this.name, this.args);
}

/// Lỗi đọc biểu thức: vị trí (ký tự) + câu tiếng Việt dễ hiểu.
class ExprError implements Exception {
  final int pos;
  final String message;
  const ExprError(this.pos, this.message);
  @override
  String toString() => message;
}

// ------------------------------------------------------------------ đọc chữ

/// Loại mảnh của biểu thức.
enum ExprTokKind { num, str, ident, op, lp, rp, lb, rb, comma }

class ExprToken {
  final ExprTokKind kind;
  final String text;
  final Object? value;
  final int start, end;
  const ExprToken(this.kind, this.text, this.start, this.end, [this.value]);
  bool get isIdent => kind == ExprTokKind.ident;
}

const _keywords = {'and', 'or', 'not', 'in'};

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool _isAlpha(String c) => RegExp(r'[\p{L}_]', unicode: true).hasMatch(c);
bool _isWord(String c) => RegExp(r'[\p{L}\p{N}_.\-]', unicode: true).hasMatch(c);

bool _endsValue(ExprToken? t) =>
    t != null && (t.kind == ExprTokKind.num || t.kind == ExprTokKind.str || t.kind == ExprTokKind.rp || t.kind == ExprTokKind.rb || (t.kind == ExprTokKind.ident && !_keywords.contains(t.text)));

/// Tách biểu thức thành các mảnh (giữ vị trí, để báo lỗi và để hiện tên dễ đọc).
List<ExprToken> exprTokens(String src) {
  final out = <ExprToken>[];
  final c = src.split('');
  var i = 0;
  while (i < c.length) {
    final ch = c[i];
    if (ch.trim().isEmpty) {
      i++;
      continue;
    }
    final start = i;
    switch (ch) {
      case '(':
        out.add(ExprToken(ExprTokKind.lp, ch, start, ++i));
      case ')':
        out.add(ExprToken(ExprTokKind.rp, ch, start, ++i));
      case '[':
        out.add(ExprToken(ExprTokKind.lb, ch, start, ++i));
      case ']':
        out.add(ExprToken(ExprTokKind.rb, ch, start, ++i));
      case ',':
        out.add(ExprToken(ExprTokKind.comma, ch, start, ++i));
      case '+' || '*' || '/' || '%':
        out.add(ExprToken(ExprTokKind.op, ch, start, ++i));
      case '-' when _endsValue(out.lastOrNull) || !(i + 1 < c.length && _isDigit(c[i + 1])):
        out.add(ExprToken(ExprTokKind.op, '-', start, ++i));
      case '=' || '!' || '>' || '<':
        final next = i + 1 < c.length ? c[i + 1] : '';
        final op = switch ((ch, next)) {
          ('=', '=') => '==',
          ('!', '=') => '!=',
          ('>', '=') => '>=',
          ('<', '=') => '<=',
          ('>', _) => '>',
          ('<', _) => '<',
          ('=', _) => throw ExprError(start, tr('Dùng "==" để so sánh bằng (một dấu "=" không dùng được)')),
          _ => throw ExprError(start, tr('Dùng "not" thay cho "!"')),
        };
        i += op.length;
        out.add(ExprToken(ExprTokKind.op, op, start, i));
      case '&' || '|':
        throw ExprError(start, ch == '&' ? tr('Dùng "and" thay cho "&&"') : tr('Dùng "or" thay cho "||"'));
      case "'" || '"':
        final b = StringBuffer();
        i++;
        var closed = false;
        while (i < c.length) {
          if (c[i] == ch) {
            i++;
            closed = true;
            break;
          }
          if (c[i] == r'\' && i + 1 < c.length) {
            b.write(c[i + 1]);
            i += 2;
            continue;
          }
          b.write(c[i]);
          i++;
        }
        if (!closed) throw ExprError(start, tr('Chuỗi chữ chưa có dấu nháy đóng'));
        out.add(ExprToken(ExprTokKind.str, src.substring(start, i), start, i, b.toString()));
      default:
        if (_isDigit(ch) || ch == '-') {
          i++;
          while (i < c.length && (_isDigit(c[i]) || c[i] == '.' || c[i] == '_')) {
            i++;
          }
          final raw = src.substring(start, i).replaceAll('_', '');
          final n = num.tryParse(raw);
          if (n == null) throw ExprError(start, tr('Số không hợp lệ: {0}', [src.substring(start, i)]));
          out.add(ExprToken(ExprTokKind.num, src.substring(start, i), start, i, n));
        } else if (_isAlpha(ch)) {
          while (i < c.length && _isWord(c[i])) {
            i++;
          }
          out.add(ExprToken(ExprTokKind.ident, src.substring(start, i), start, i));
        } else {
          throw ExprError(start, tr('Ký tự không dùng được: "{0}"', [ch]));
        }
    }
  }
  return out;
}

class _P {
  final List<ExprToken> t;
  final int len;
  int i = 0;
  _P(this.t, this.len);

  ExprToken? get peek => i < t.length ? t[i] : null;
  int get pos => peek?.start ?? len;
  bool kw(String w) => peek?.kind == ExprTokKind.ident && peek!.text == w;
  String? op(Set<String> ops) => peek?.kind == ExprTokKind.op && ops.contains(peek!.text) ? peek!.text : null;

  ExprNode or() {
    var l = and();
    while (kw('or')) {
      i++;
      l = EBin(l, 'or', and());
    }
    return l;
  }

  ExprNode and() {
    var l = not();
    while (kw('and')) {
      i++;
      l = EBin(l, 'and', not());
    }
    return l;
  }

  ExprNode not() {
    if (kw('not')) {
      i++;
      return ENot(not());
    }
    return cmp();
  }

  ExprNode cmp() {
    final l = add();
    final o = op(const {'==', '!=', '>', '>=', '<', '<='});
    if (o != null) {
      i++;
      return EBin(l, o, add());
    }
    if (kw('in')) {
      i++;
      return EBin(l, 'in', add());
    }
    return l;
  }

  ExprNode add() {
    var l = mul();
    for (var o = op(const {'+', '-'}); o != null; o = op(const {'+', '-'})) {
      i++;
      l = EBin(l, o, mul());
    }
    return l;
  }

  ExprNode mul() {
    var l = unary();
    for (var o = op(const {'*', '/', '%'}); o != null; o = op(const {'*', '/', '%'})) {
      i++;
      l = EBin(l, o, unary());
    }
    return l;
  }

  ExprNode unary() {
    if (op(const {'-'}) != null) {
      i++;
      final x = unary();
      return x is ELit && x.value is num ? ELit(-(x.value as num)) : ENeg(x);
    }
    return atom();
  }

  ExprNode atom() {
    final x = peek;
    if (x == null) throw ExprError(len, tr('Biểu thức còn thiếu (chưa có giá trị ở cuối)'));
    i++;
    switch (x.kind) {
      case ExprTokKind.num:
        return ELit(x.value);
      case ExprTokKind.str:
        return ELit(x.value);
      case ExprTokKind.lp:
        final e = or();
        if (peek?.kind != ExprTokKind.rp) throw ExprError(pos, tr('Thiếu dấu ")"'));
        i++;
        return e;
      case ExprTokKind.lb:
        final items = <ExprNode>[];
        if (peek?.kind == ExprTokKind.rb) {
          i++;
          return EList(items);
        }
        while (true) {
          items.add(add());
          if (peek?.kind == ExprTokKind.comma) {
            i++;
          } else if (peek?.kind == ExprTokKind.rb) {
            i++;
            return EList(items);
          } else {
            throw ExprError(pos, tr('Thiếu dấu "]" hoặc ","'));
          }
        }
      case ExprTokKind.ident:
        final w = x.text;
        if (w == 'true' || w == 'false') return ELit(w == 'true');
        if (w == 'null') return const ELit(null);
        if (_keywords.contains(w)) throw ExprError(x.start, tr('Thiếu giá trị trước "{0}"', [w]));
        if (peek?.kind == ExprTokKind.lp) {
          final f = exprFunc(w);
          if (f == null) throw ExprError(x.start, tr('Không có hàm "{0}"', [w]));
          i++;
          final args = <ExprNode>[];
          if (peek?.kind == ExprTokKind.rp) {
            i++;
          } else {
            while (true) {
              args.add(or());
              if (peek?.kind == ExprTokKind.comma) {
                i++;
              } else if (peek?.kind == ExprTokKind.rp) {
                i++;
                break;
              } else {
                throw ExprError(pos, tr('Thiếu dấu ")" hoặc "," trong hàm {0}', [w]));
              }
            }
          }
          if (args.length < f.min || args.length > f.max) {
            final want = f.min == f.max ? '${f.min}' : '${f.min}–${f.max}';
            throw ExprError(x.start, tr('Hàm {0} cần {1} tham số (đang có {2})', [w, want, args.length]));
          }
          return ECall(w, args);
        }
        if (w.split('.').any((p) => p.isEmpty) || w.endsWith('-')) throw ExprError(x.start, tr('Tên thông tin không hợp lệ: {0}', [w]));
        return EVar(w);
      case ExprTokKind.op:
        throw ExprError(x.start, tr('Thiếu giá trị trước "{0}"', [x.text]));
      case ExprTokKind.rp || ExprTokKind.rb || ExprTokKind.comma:
        throw ExprError(x.start, tr('Không mong đợi "{0}" ở đây', [x.text]));
    }
  }
}

/// Đọc biểu thức; sai thì ném [ExprError].
ExprNode parseExpr(String src) {
  if (src.length > 2000) throw ExprError(0, tr('Biểu thức quá dài'));
  final toks = exprTokens(src);
  if (toks.isEmpty) throw ExprError(0, tr('Chưa có biểu thức'));
  final p = _P(toks, src.length);
  final e = p.or();
  if (p.peek != null) {
    final t = p.peek!;
    throw ExprError(t.start, tr('Thừa "{0}" sau biểu thức (thiếu "and" / "or" / phép tính?)', [t.text]));
  }
  return e;
}

/// Mọi biến dùng trong biểu thức (bỏ `item.*` trong điều kiện lọc của count / sum).
List<String> exprVars(ExprNode e) {
  final out = <String>[];
  void walk(ExprNode e, {bool inFilter = false}) {
    switch (e) {
      case ELit _:
        break;
      case EVar v:
        if (!(inFilter && v.path.startsWith('item.'))) out.add(v.path);
      case EList l:
        l.items.forEach(walk);
      case ENot n:
        walk(n.a, inFilter: inFilter);
      case ENeg n:
        walk(n.a, inFilter: inFilter);
      case EBin b:
        walk(b.a, inFilter: inFilter);
        walk(b.b, inFilter: inFilter);
      case ECall c:
        final filterAt = c.name == 'count' ? 1 : (c.name == 'sum' ? 2 : -1);
        for (var i = 0; i < c.args.length; i++) {
          walk(c.args[i], inFilter: inFilter || i == filterAt);
        }
    }
  }

  walk(e);
  return out;
}

/// Kiểu kết quả đoán được (để chọn phép so sánh, kiểu biến của bước Đặt biến): number / date / bool / text.
String exprType(ExprNode e) => switch (e) {
      ELit(value: num _) || ENeg _ => 'number',
      ELit(value: bool _) || ENot _ => 'bool',
      EBin(op: 'and' || 'or' || '==' || '!=' || '>' || '>=' || '<' || '<=' || 'in') => 'bool',
      EBin(op: '-' || '*' || '/' || '%') => 'number',
      EBin(op: '+', a: final a, b: final b) => exprType(a) == 'text' || exprType(b) == 'text' ? 'text' : 'number',
      ECall(name: 'today' || 'add_days' || 'add_workdays') => 'date',
      ECall(name: 'contains' || 'empty' || 'starts_with') => 'bool',
      ECall(name: 'lower' || 'upper' || 'now' || 'prefix' || 'suffix' || 'before' || 'after' || 'hash' || 'money' || 'date_vn') => 'text',
      ECall(name: 'if', args: final a) => exprType(a[1]),
      ECall _ => 'number',
      _ => 'text',
    };

/// Kết quả kiểm nhanh: [error] (không lưu được) hoặc [warning] (vẫn lưu được, vd thông tin lạ).
class ExprCheck {
  final String? error, warning;
  final int? pos;
  const ExprCheck({this.error, this.warning, this.pos});
  bool get ok => error == null;
}

const _roots = {'form', 'steps', 'vars', 'requester', 'item', 'loop', 'result', 'instance', 'title', 'row', 'data'};

/// Kiểm biểu thức như máy chủ (cú pháp, tên hàm, số tham số) và, khi có [known], báo thông tin chưa biết.
/// Gặp lỗi hay gặp "a-b" (thiếu dấu cách trong phép trừ) thì nhắc cách viết đúng.
ExprCheck checkExpr(String src, {Iterable<String>? known}) {
  if (src.trim().isEmpty) return ExprCheck(error: tr('Chưa có biểu thức'), pos: 0);
  final ExprNode e;
  try {
    e = parseExpr(src);
  } on ExprError catch (x) {
    return ExprCheck(error: x.message, pos: x.pos);
  }
  if (known == null) return const ExprCheck();
  final set = known.toSet();
  bool isKnown(String p) => set.contains(p) || set.any((k) => p.startsWith('$k.')) || p.startsWith('item.') || p.startsWith('loop.') || p.startsWith('requester');
  for (final v in exprVars(e)) {
    if (isKnown(v)) continue;
    // "form.a-form.b": tên biến được chứa dấu "-", nên đây là một tên lạ chứ không phải phép trừ.
    final parts = v.split('-');
    if (parts.length > 1 && parts.skip(1).any((p) => _roots.contains(p.split('.').first) || RegExp(r'^\d').hasMatch(p))) {
      return ExprCheck(error: tr('Phép trừ cần dấu cách hai bên: viết "{0}"', [parts.join(' - ')]));
    }
    if (!_roots.contains(v.split('.').first)) return ExprCheck(error: tr('Không có thông tin "{0}" (thiếu dấu nháy nếu là chữ?)', [v]));
    return ExprCheck(warning: tr('Chưa thấy thông tin "{0}" trong quy trình', [v]));
  }
  return const ExprCheck();
}

/// Biểu thức → chữ đọc được: mỗi biến thay bằng «tên» ([label]), phần còn lại giữ nguyên.
String exprDisplay(String src, String Function(String path) label) {
  final List<ExprToken> toks;
  try {
    toks = exprTokens(src);
  } on ExprError {
    return src;
  }
  final b = StringBuffer();
  var at = 0;
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    b.write(src.substring(at, t.start));
    final call = i + 1 < toks.length && toks[i + 1].kind == ExprTokKind.lp;
    if (t.isIdent && !call && !_keywords.contains(t.text) && !const {'true', 'false', 'null'}.contains(t.text)) {
      b.write('«${label(t.text)}»');
    } else {
      b.write(t.text);
    }
    at = t.end;
  }
  b.write(src.substring(at));
  return b.toString();
}

// ------------------------------------------------------------------ tính (giờ Việt Nam)

/// "Bây giờ" để tính today() / now() (đổi được trong thử nghiệm).
DateTime Function() exprNow = DateTime.now;

num? exprNum(Object? v) {
  if (v is num) return v;
  if (v is String) {
    final t = v.replaceAll(RegExp(r'[., _]'), '');
    if (t.isEmpty || !RegExp(r'^-?\d+$').hasMatch(t)) return null;
    return num.tryParse(t);
  }
  return null;
}

bool exprTruthy(Object? v) => switch (v) {
      null => false,
      bool b => b,
      num n => n != 0,
      String s => s.isNotEmpty,
      List l => l.isNotEmpty,
      Map m => m.isNotEmpty,
      _ => true,
    };

num _clean(num n) {
  if (n is int) return n;
  if (!n.isFinite) return n;
  final r = n.abs() < 1e9 && n != n.roundToDouble() ? (n * 1e9).round() / 1e9 : n;
  return r == r.roundToDouble() && r.abs() < 9e15 ? r.toInt() : r;
}

String exprText(Object? v) => switch (v) {
      null => '',
      String s => s,
      num n => '${_clean(n)}',
      _ => jsonEncode(v),
    };

bool _equal(Object? a, Object? b) {
  final x = exprNum(a), y = exprNum(b);
  if (x != null && y != null && (a is num || b is num)) return x == y;
  if (a is num && b is num) return a == b;
  return jsonEncode(a) == jsonEncode(b);
}

/// Ngày (số ngày từ 1970-01-01): "YYYY-MM-DD" (có thể kèm giờ), "DD/MM/YYYY", mốc ms (giờ VN).
int? _day(Object? v) {
  if (v is num) return _vnDay(v.toInt());
  if (v is! String) return null;
  final s = v.trim();
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m != null) return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)).millisecondsSinceEpoch ~/ 86400000;
  m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
  if (m != null) return DateTime.utc(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)).millisecondsSinceEpoch ~/ 86400000;
  return null;
}

int _vnDay(int ms) => (ms + 7 * 3600000) ~/ 86400000;

String _dayText(int d) {
  final t = DateTime.fromMillisecondsSinceEpoch(d * 86400000, isUtc: true);
  return '${t.year}-${'${t.month}'.padLeft(2, '0')}-${'${t.day}'.padLeft(2, '0')}';
}

List _rows(Object? v) => v is List ? v : (v == null ? const [] : [v]);

Map<String, dynamic> _withItem(Map<String, dynamic> ctx, Object? row) => {...ctx, 'item': row};

Object? _lookup(Map<String, dynamic> ctx, String path) {
  Object? cur = ctx;
  for (final p in path.split('.')) {
    if (cur is Map) {
      cur = cur[p];
    } else if (cur is List) {
      final i = int.tryParse(p);
      cur = i != null && i >= 0 && i < cur.length ? cur[i] : null;
    } else {
      return null;
    }
  }
  return cur;
}

Object? _arith(String op, Object? x, Object? y) {
  num? n(Object? v) => v == null ? 0 : exprNum(v);
  final a = n(x), b = n(y);
  if (a != null && b != null) {
    return switch (op) {
      '+' => _clean(a + b),
      '-' => _clean(a - b),
      '*' => _clean(a * b),
      '/' => b == 0 ? null : _clean(a / b),
      _ => b == 0 ? null : _clean(a % b),
    };
  }
  return op == '+' ? exprText(x) + exprText(y) : null;
}

Object? _call(String name, List<ExprNode> args, Map<String, dynamic> ctx) {
  Object? ev(int i) => i < args.length ? evalExpr(args[i], ctx) : null;
  switch (name) {
    case 'today':
      return _dayText(_vnDay(exprNow().millisecondsSinceEpoch));
    case 'now':
      final t = exprNow().toUtc().add(const Duration(hours: 7));
      return '${_dayText(_vnDay(exprNow().millisecondsSinceEpoch))} ${'${t.hour}'.padLeft(2, '0')}:${'${t.minute}'.padLeft(2, '0')}';
    case 'days_between':
      final a = _day(ev(0)), b = _day(ev(1));
      return a == null || b == null ? null : b - a;
    case 'add_days':
      final d = _day(ev(0)), n = exprNum(ev(1));
      return d == null || n == null ? null : _dayText(d + n.toInt());
    case 'add_workdays':
      var d = _day(ev(0));
      final n = exprNum(ev(1));
      if (d == null || n == null) return null;
      final step = n < 0 ? -1 : 1;
      var left = n.toInt().abs();
      for (var guard = 0; left > 0 && guard < 3660; guard++) {
        d = d! + step;
        // Lịch mặc định của máy chủ: thứ Hai – thứ Sáu (1970-01-01 là thứ Năm).
        if ((d + 3) % 7 < 5) left--;
      }
      return _dayText(d!);
    case 'year' || 'month':
      final d = _day(ev(0));
      if (d == null) return null;
      final t = DateTime.fromMillisecondsSinceEpoch(d * 86400000, isUtc: true);
      return name == 'year' ? t.year : t.month;
    case 'len':
      return switch (ev(0)) { null => 0, String s => s.runes.length, List l => l.length, Map m => m.length, final o => exprText(o).length };
    case 'sum' || 'count':
      final rows = _rows(ev(0));
      final col = name == 'sum' && args.length > 1 ? exprText(ev(1)) : '';
      final cond = name == 'sum' ? (args.length > 2 ? args[2] : null) : (args.length > 1 ? args[1] : null);
      final keep = [for (final r in rows) if (cond == null || exprTruthy(evalExpr(cond, _withItem(ctx, r)))) r];
      if (name == 'count') return keep.length;
      num s = 0;
      for (final r in keep) {
        s += exprNum(col.isEmpty ? r : (r is Map ? r[col] : null)) ?? 0;
      }
      return _clean(s);
    case 'contains':
      final hay = ev(0), needle = ev(1);
      if (hay is List) return hay.any((x) => _equal(x, needle));
      if (hay == null) return false;
      return exprText(hay).contains(exprText(needle));
    case 'empty':
      return switch (ev(0)) { null => true, String s => s.trim().isEmpty, List l => l.isEmpty, Map m => m.isEmpty, _ => false };
    case 'lower':
      return exprText(ev(0)).toLowerCase();
    case 'upper':
      return exprText(ev(0)).toUpperCase();
    case 'round':
      final x = exprNum(ev(0));
      if (x == null) return null;
      final digits = (exprNum(ev(1)) ?? 0).clamp(-15, 15).toInt();
      var p = 1.0;
      for (var i = 0; i < digits.abs(); i++) {
        p *= 10;
      }
      return _clean(digits >= 0 ? (x * p).round() / p : (x / p).round() * p);
    case 'abs':
      final x = exprNum(ev(0));
      return x == null ? null : _clean(x.abs());
    case 'min' || 'max':
      final vals = args.length == 1 ? _rows(ev(0)) : [for (var i = 0; i < args.length; i++) ev(i)];
      final nums = [for (final v in vals) ?exprNum(v)];
      if (nums.isEmpty) return null;
      return _clean(nums.reduce((a, b) => name == 'min' ? (a < b ? a : b) : (a > b ? a : b)));
    case 'if':
      return exprTruthy(ev(0)) ? ev(1) : ev(2);
    case 'prefix' || 'suffix' || 'before' || 'after':
      final s = exprText(ev(0)), sep = exprText(ev(1));
      final i = sep.isEmpty ? -1 : s.indexOf(sep);
      final head = name == 'prefix' || name == 'before';
      if (i < 0) return head ? s : '';
      return head ? s.substring(0, i) : s.substring(i + sep.length);
    case 'money':
      final x = exprNum(ev(0));
      if (x == null) return '';
      final n = x.round().abs().toString();
      final b = StringBuffer(x < 0 ? '-' : '');
      for (var i = 0; i < n.length; i++) {
        if (i > 0 && (n.length - i) % 3 == 0) b.write('.');
        b.write(n[i]);
      }
      return '$b ₫';
    case 'date_vn':
      final d = _day(ev(0));
      if (d == null) return '';
      final t = DateTime.fromMillisecondsSinceEpoch(d * 86400000, isUtc: true);
      return '${'${t.day}'.padLeft(2, '0')}/${'${t.month}'.padLeft(2, '0')}/${t.year}';
    case 'starts_with':
      return exprText(ev(0)).startsWith(exprText(ev(1)));
    case 'hash':
      final v = ev(0);
      return sha256.convert(utf8.encode(v is String ? v : canonicalJson(v))).toString();
  }
  return null;
}

/// JSON với khoá object sắp theo thứ tự (như `expr::canonical` của máy chủ).
String canonicalJson(Object? v) {
  if (v is Map) {
    final keys = [for (final k in v.keys) '$k']..sort();
    return '{${[for (final k in keys) '${jsonEncode(k)}:${canonicalJson(v[k])}'].join(',')}}';
  }
  if (v is List) return '[${v.map(canonicalJson).join(',')}]';
  return jsonEncode(v);
}

/// Tính biểu thức với ngữ cảnh [ctx] (vd {"form": {...}}), như máy chủ.
Object? evalExpr(ExprNode e, Map<String, dynamic> ctx) {
  switch (e) {
    case ELit l:
      return l.value;
    case EVar v:
      return _lookup(ctx, v.path);
    case EList l:
      return [for (final x in l.items) evalExpr(x, ctx)];
    case ENot n:
      return !exprTruthy(evalExpr(n.a, ctx));
    case ENeg n:
      final v = evalExpr(n.a, ctx);
      if (v == null) return 0;
      final x = exprNum(v);
      return x == null ? null : _clean(-x);
    case ECall c:
      return _call(c.name, c.args, ctx);
    case EBin b:
      switch (b.op) {
        case 'and':
          return exprTruthy(evalExpr(b.a, ctx)) && exprTruthy(evalExpr(b.b, ctx));
        case 'or':
          return exprTruthy(evalExpr(b.a, ctx)) || exprTruthy(evalExpr(b.b, ctx));
        case '+' || '-' || '*' || '/' || '%':
          return _arith(b.op, evalExpr(b.a, ctx), evalExpr(b.b, ctx));
        case 'in':
          final x = evalExpr(b.a, ctx), y = evalExpr(b.b, ctx);
          if (y is List) return y.any((i) => _equal(x, i));
          if (y is String) return x is String && y.contains(x);
          return false;
      }
      final x = evalExpr(b.a, ctx), y = evalExpr(b.b, ctx);
      switch (b.op) {
        case '==':
          return _equal(x, y);
        case '!=':
          return !_equal(x, y);
      }
      final p = exprNum(x), q = exprNum(y);
      final int c;
      if (p != null && q != null) {
        c = p.compareTo(q);
      } else if (x is String && y is String) {
        c = x.compareTo(y);
      } else {
        return false;
      }
      return switch (b.op) { '>' => c > 0, '>=' => c >= 0, '<' => c < 0, _ => c <= 0 };
  }
}

/// Phân tích rồi tính; biểu thức sai thì null.
Object? evalExprText(String src, Map<String, dynamic> ctx) {
  try {
    return evalExpr(parseExpr(src), ctx);
  } on ExprError {
    return null;
  }
}

// ------------------------------------------------------------------ số chứng từ

/// Chu kỳ đặt lại bộ đếm theo dạng (như máy chủ): có {dd} → day, có {mm} → month, có {yy}/{yyyy} → year, còn lại never.
String numberResetOf(String format) {
  if (format.contains('{dd}')) return 'day';
  if (format.contains('{mm}')) return 'month';
  if (format.contains('{yy}') || format.contains('{yyyy}')) return 'year';
  return 'never';
}

/// Xem trước số chứng từ thứ [n] theo [format] ("PC-{yyyy}-{0000}" → "PC-2026-0001"); không có chỗ số thì số nối
/// ở cuối. Chỗ chèn `{{…}}` hiện thành «…».
String numberPreview(String format, {int n = 1, DateTime? at}) {
  final t = (at ?? exprNow()).toUtc().add(const Duration(hours: 7));
  final f = format.replaceAllMapped(RegExp(r'\{\{\s*(.*?)\s*\}\}'), (m) => '«${m[1]}»');
  var hasNum = false;
  final out = f.replaceAllMapped(RegExp(r'\{(yyyy|yy|mm|dd|n|0+)\}'), (m) {
    switch (m[1]) {
      case 'yyyy':
        return '${t.year}';
      case 'yy':
        return '${t.year % 100}'.padLeft(2, '0');
      case 'mm':
        return '${t.month}'.padLeft(2, '0');
      case 'dd':
        return '${t.day}'.padLeft(2, '0');
      case 'n':
        hasNum = true;
        return '$n';
      default:
        hasNum = true;
        return '$n'.padLeft(m[1]!.length, '0');
    }
  });
  return hasNum ? out : '$out$n';
}
