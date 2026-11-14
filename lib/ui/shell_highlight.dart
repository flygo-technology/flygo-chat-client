// Tô màu lệnh shell và kết quả chạy lệnh trong thẻ bước của trợ lý (kiểu GitHub, theo sáng / tối).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../i18n/i18n.dart';

import 'theme.dart';

/// Bảng màu khối code: nền, chữ thường và từng loại token.
class CodeColors {
  final Color bg, border, text, dim, keyword, command, string, flag, variable, comment, op, path, number, error, warn;
  const CodeColors({
    required this.bg,
    required this.border,
    required this.text,
    required this.dim,
    required this.keyword,
    required this.command,
    required this.string,
    required this.flag,
    required this.variable,
    required this.comment,
    required this.op,
    required this.path,
    required this.number,
    required this.error,
    required this.warn,
  });

  static const light = CodeColors(
    bg: Color(0xFFF6F8FA),
    border: Color(0xFFD8DEE4),
    text: Color(0xFF1F2328),
    dim: Color(0xFF59636E),
    keyword: Color(0xFFCF222E),
    command: Color(0xFF8250DF),
    string: Color(0xFF0A3069),
    flag: Color(0xFF0550AE),
    variable: Color(0xFF953800),
    comment: Color(0xFF6E7781),
    op: Color(0xFFCF222E),
    path: Color(0xFF116329),
    number: Color(0xFF0550AE),
    error: Color(0xFFCF222E),
    warn: Color(0xFF9A6700),
  );

  static const dark = CodeColors(
    bg: Color(0xFF161B22),
    border: Color(0xFF30363D),
    text: Color(0xFFE6EDF3),
    dim: Color(0xFF9198A1),
    keyword: Color(0xFFFF7B72),
    command: Color(0xFFD2A8FF),
    string: Color(0xFFA5D6FF),
    flag: Color(0xFF79C0FF),
    variable: Color(0xFFFFA657),
    comment: Color(0xFF8B949E),
    op: Color(0xFFFF7B72),
    path: Color(0xFF7EE787),
    number: Color(0xFF79C0FF),
    error: Color(0xFFFF7B72),
    warn: Color(0xFFD29922),
  );

  static CodeColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

enum ShTok { text, keyword, command, string, flag, variable, comment, op, path, number, space }

const _keywords = {
  'if', 'then', 'else', 'elif', 'fi', 'for', 'in', 'do', 'done', 'while', 'until', 'case', 'esac', 'function', //
  'select', 'time', 'return', 'export', 'local', 'readonly', 'declare', 'unset', 'set', 'source', 'exec', 'eval',
};
// Sau các từ này, từ kế tiếp vẫn là tên lệnh (sudo git …, time make …).
const _prefixes = {'sudo', 'time', 'env', 'nohup', 'exec', 'then', 'else', 'do', 'xargs', 'watch', 'nice', '!', 'command', 'builtin'};

/// Tách một lệnh shell thành các token (không cần đúng ngữ pháp, chỉ để tô màu).
List<(ShTok, String)> shellTokens(String src) {
  final out = <(ShTok, String)>[];
  var i = 0;
  var cmdPos = true; // từ kế tiếp là tên lệnh
  void add(ShTok k, String s) {
    if (s.isEmpty) return;
    if (out.isNotEmpty && out.last.$1 == k && k != ShTok.command) {
      out[out.length - 1] = (k, out.last.$2 + s);
    } else {
      out.add((k, s));
    }
  }

  bool isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  bool isWordEnd(String c) => isSpace(c) || '|&;<>()'.contains(c);

  /// Đọc biến từ vị trí $ (trả về vị trí sau biến).
  int readVar(int at) {
    var j = at + 1;
    if (j >= src.length) return j;
    if (src[j] == '{' || src[j] == '(') {
      final close = src[j] == '{' ? '}' : ')';
      var depth = 0;
      for (; j < src.length; j++) {
        if (src[j] == src[at + 1]) depth++;
        if (src[j] == close && --depth == 0) return j + 1;
      }
      return src.length;
    }
    if (RegExp(r'[?#@*!$0-9-]').hasMatch(src[j])) return j + 1;
    while (j < src.length && RegExp(r'[A-Za-z0-9_]').hasMatch(src[j])) {
      j++;
    }
    return j;
  }

  while (i < src.length) {
    final c = src[i];
    if (isSpace(c)) {
      final s = i;
      while (i < src.length && isSpace(src[i])) {
        if (src[i] == '\n') cmdPos = true;
        i++;
      }
      add(ShTok.space, src.substring(s, i));
      continue;
    }
    // Chú thích: # ở đầu từ.
    if (c == '#' && (i == 0 || isSpace(src[i - 1]))) {
      final e = src.indexOf('\n', i);
      final end = e < 0 ? src.length : e;
      add(ShTok.comment, src.substring(i, end));
      i = end;
      continue;
    }
    // Toán tử: | || && ; ;; & > >> < 2>&1 &> ( )
    final op = RegExp(r'^(\d?>>?&?\d?|&>>?|<<-?|<<<|<|\|\||\||&&|;;|;|&|\(|\))').firstMatch(src.substring(i));
    if (op != null && (c != '2' && c != '1' || (op.group(0)!.length > 1))) {
      final t = op.group(0)!;
      add(ShTok.op, t);
      i += t.length;
      // Sau | && || ; ( là lệnh mới; sau > < là tên tệp.
      cmdPos = !t.contains('>') && !t.contains('<');
      continue;
    }
    // Một từ (có thể gồm chuỗi trong nháy và biến).
    final parts = <(ShTok, String)>[];
    final start = i;
    var hasPlain = false;
    while (i < src.length && !isWordEnd(src[i])) {
      final ch = src[i];
      if (ch == "'") {
        final e = src.indexOf("'", i + 1);
        final end = e < 0 ? src.length : e + 1;
        parts.add((ShTok.string, src.substring(i, end)));
        i = end;
      } else if (ch == '"') {
        var j = i + 1;
        var s = i;
        while (j < src.length && src[j] != '"') {
          if (src[j] == '\\') {
            j += 2;
            continue;
          }
          if (src[j] == r'$') {
            parts.add((ShTok.string, src.substring(s, j)));
            final e = readVar(j);
            parts.add((ShTok.variable, src.substring(j, e.clamp(j, src.length))));
            j = e;
            s = j;
            continue;
          }
          j++;
        }
        final end = j < src.length ? j + 1 : src.length;
        parts.add((ShTok.string, src.substring(s.clamp(0, end), end)));
        i = end;
      } else if (ch == '`') {
        final e = src.indexOf('`', i + 1);
        final end = e < 0 ? src.length : e + 1;
        parts.add((ShTok.variable, src.substring(i, end)));
        i = end;
      } else if (ch == r'$') {
        final e = readVar(i);
        parts.add((ShTok.variable, src.substring(i, e)));
        i = e;
      } else if (ch == '\\' && i + 1 < src.length) {
        parts.add((ShTok.text, src.substring(i, i + 2)));
        hasPlain = true;
        i += 2;
      } else {
        final s = i;
        while (i < src.length && !isWordEnd(src[i]) && !"'\"`\$\\".contains(src[i])) {
          i++;
        }
        parts.add((ShTok.text, src.substring(s, i)));
        hasPlain = true;
      }
    }
    final word = src.substring(start, i);
    if (word.isEmpty) {
      add(ShTok.text, c);
      i++;
      continue;
    }
    // Phân loại từ trơn (không có nháy / biến).
    final simple = parts.length == 1 && parts.first.$1 == ShTok.text;
    final assign = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\+?=').firstMatch(word);
    if (cmdPos && assign != null) {
      // VAR=giá trị trước lệnh: tên biến tô màu biến, phần còn lại giữ token.
      add(ShTok.variable, assign.group(0)!);
      final rest = shellTokens(word.substring(assign.end)).map((t) => t.$1 == ShTok.command ? (ShTok.text, t.$2) : t);
      for (final t in rest) {
        add(t.$1, t.$2);
      }
      continue;
    }
    if (simple && cmdPos) {
      if (_keywords.contains(word)) {
        add(ShTok.keyword, word);
        cmdPos = _prefixes.contains(word) || word == 'if' || word == 'while' || word == 'until' || word == '!';
      } else {
        add(ShTok.command, word);
        cmdPos = _prefixes.contains(word);
      }
      continue;
    }
    cmdPos = false;
    if (simple) {
      final k = _keywords.contains(word) && (word == 'in' || word == 'then' || word == 'do' || word == 'done' || word == 'fi' || word == 'esac')
          ? ShTok.keyword
          : word.startsWith('-')
              ? ShTok.flag
              : RegExp(r'^\d+(\.\d+)?[kKmMgG]?$').hasMatch(word)
                  ? ShTok.number
                  : (word.contains('/') || word.startsWith('~') || RegExp(r'\.[A-Za-z0-9]{1,6}$').hasMatch(word))
                      ? ShTok.path
                      : ShTok.text;
      if (k == ShTok.keyword && (word == 'then' || word == 'do' || word == 'else')) cmdPos = true;
      add(k, word);
      continue;
    }
    if (!hasPlain || parts.isNotEmpty) {
      for (final p in parts) {
        add(p.$1, p.$2);
      }
    }
  }
  return out;
}

/// Các đoạn chữ đã tô màu của một lệnh shell.
TextSpan shellSpan(String cmd, CodeColors c, TextStyle base) {
  Color? color(ShTok k) => switch (k) {
        ShTok.keyword => c.keyword,
        ShTok.command => c.command,
        ShTok.string => c.string,
        ShTok.flag => c.flag,
        ShTok.variable => c.variable,
        ShTok.comment => c.comment,
        ShTok.op => c.op,
        ShTok.path => c.path,
        ShTok.number => c.number,
        _ => null,
      };
  return TextSpan(style: base.copyWith(color: c.text), children: [
    for (final (k, s) in shellTokens(cmd))
      TextSpan(
        text: s,
        style: TextStyle(
          color: color(k),
          fontWeight: k == ShTok.command || k == ShTok.keyword ? FontWeight.w600 : null,
          fontStyle: k == ShTok.comment ? FontStyle.italic : null,
        ),
      ),
  ]);
}

/// Phông của chat với trợ lý (đóng gói trong app, OFL): chữ đọc câu trả lời và chữ đơn cách cho lệnh / code.
const kReadingFont = 'Source Serif 4';
const kMonoFont = 'JetBrains Mono';
const kMonoFallback = ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'monospace'];
/// Tắt chữ ghép của JetBrains Mono ("--" thành một nét, "!=" thành "≠"): lệnh phải hiện đúng từng ký tự.
const kNoLigatures = [FontFeature.disable('calt'), FontFeature.disable('liga')];
const kMono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontFeatures: kNoLigatures);

/// Kiểu chữ câu trả lời của trợ lý: chữ có chân dễ đọc, 16 px, giãn dòng 1.6.
TextStyle aiAnswerStyle(Color color) =>
    TextStyle(fontFamily: kReadingFont, fontFamilyFallback: const ['Noto Serif', 'Georgia', 'Noto Color Emoji'], fontSize: 16, height: 1.6, color: color);

/// Giấy phép OFL của hai phông trên (trang Giấy phép của app).
void registerAiFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in [('Source Serif 4', 'OFL-SourceSerif4.txt'), ('JetBrains Mono', 'OFL-JetBrainsMono.txt')]) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

/// Khối lệnh shell: nhãn ngôn ngữ nhỏ + lệnh đã tô màu.
class ShellBlock extends StatelessWidget {
  final String command;
  final String lang;
  final int? maxLines;
  final bool selectable;
  final double fontSize;
  const ShellBlock(this.command, {super.key, this.lang = 'bash', this.maxLines = 6, this.selectable = false, this.fontSize = 12.5});

  @override
  Widget build(BuildContext context) {
    final c = CodeColors.of(context);
    final span = shellSpan(command, c, kMono.copyWith(fontSize: fontSize, height: 1.4));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(r'$', style: kMono.copyWith(fontSize: 10.5, color: c.path, fontWeight: FontWeight.w700)),
          const SizedBox(width: 5),
          Text(lang, style: TextStyle(fontSize: 10, color: c.dim, fontWeight: FontWeight.w600, letterSpacing: .5)),
        ]),
        const SizedBox(height: 3),
        selectable
            ? SelectableText.rich(span, maxLines: maxLines)
            : Text.rich(span, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
      ]),
    );
  }
}

final _errLine = RegExp(r'(\berror\b|\bfatal\b|\bfailed\b|\bexception\b|traceback|panic:|permission denied|no such file|not found|command not found|exit (code|status) [1-9]|exited with)',
    caseSensitive: false);
final _warnLine = RegExp(r'\b(warn(ing)?|deprecated)\b', caseSensitive: false);

/// Kết quả chạy lệnh: chữ đơn cách mờ; bước lỗi thì đỏ (nền đỏ nhạt), dòng có "error / fatal / …" đỏ, "warning" vàng.
/// Dài quá [maxLines] dòng thì gập, bấm "Hiện thêm" để mở hết.
class ShellOutput extends StatefulWidget {
  final String text;
  final bool error;
  final int maxLines;
  const ShellOutput(this.text, {super.key, this.error = false, this.maxLines = 12});
  @override
  State<ShellOutput> createState() => _ShellOutputState();
}

class _ShellOutputState extends State<ShellOutput> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = CodeColors.of(context);
    final pal = Pal.of(context);
    final lines = widget.text.split('\n');
    final fold = !_all && lines.length > widget.maxLines;
    final shown = fold ? lines.sublist(lines.length - widget.maxLines) : lines; // lỗi thường ở cuối: giữ phần cuối
    final base = kMono.copyWith(fontSize: 12, height: 1.35, color: widget.error ? c.error : c.dim);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: widget.error ? c.error.withValues(alpha: .08) : c.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.error ? c.error.withValues(alpha: .35) : c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (fold)
          InkWell(
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(tr('… {0} dòng phía trên · Hiện hết', [lines.length - widget.maxLines]),
                  style: TextStyle(fontSize: 11.5, color: pal.accentText, fontWeight: FontWeight.w600)),
            ),
          ),
        SelectableText.rich(TextSpan(style: base, children: [
          for (final (i, l) in shown.indexed)
            TextSpan(
              text: i == shown.length - 1 ? l : '$l\n',
              style: _errLine.hasMatch(l)
                  ? TextStyle(color: c.error)
                  : _warnLine.hasMatch(l)
                      ? TextStyle(color: c.warn)
                      : null,
            ),
        ])),
        if (_all && lines.length > widget.maxLines)
          InkWell(
            onTap: () => setState(() => _all = false),
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(tr('Thu gọn'), style: TextStyle(fontSize: 11.5, color: pal.accentText, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}
