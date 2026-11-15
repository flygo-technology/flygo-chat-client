// Thư: soạn thư có định dạng. Dựa trên RichController của Todo (định dạng từng ký tự), thêm kiểu dòng đánh dấu bằng
// tiền tố ngay trong chữ: "• " danh sách, "1. " danh sách số, "> " trích dẫn. Chuyển sang HTML + chữ thuần khi gửi,
// đọc lại HTML khi dán / mở bản nháp. Không dùng thư viện soạn thảo ngoài: app đã có sẵn bộ này, đủ cho thư công việc.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as hp;
import 'package:pasteboard/pasteboard.dart';

import '../todo/look.dart' show kTextColors;
import '../todo/model.dart' show TFmt, TRun;
import '../todo/rich.dart' show RichController, kZw;

const kBullet = '• ', kQuote = '> ';
final _olRe = RegExp(r'^(\d{1,3})\. ');

/// Kiểu dòng theo tiền tố: ul | ol | quote | p.
String lineKind(String line) {
  if (line.startsWith(kBullet)) return 'ul';
  if (line.startsWith(kQuote)) return 'quote';
  if (_olRe.hasMatch(line)) return 'ol';
  return 'p';
}

/// Độ dài tiền tố của dòng (0 = đoạn thường).
int prefixLen(String line) => switch (lineKind(line)) {
      'ul' => kBullet.length,
      'quote' => kQuote.length,
      'ol' => _olRe.firstMatch(line)!.group(0)!.length,
      _ => 0,
    };

/// Các dòng (mỗi dòng là danh sách run), giữ định dạng.
List<List<TRun>> runLines(List<TRun> runs) {
  final lines = <List<TRun>>[[]];
  for (final r in runs) {
    final parts = r.x.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) lines.add([]);
      if (parts[i].isNotEmpty) lines.last.add(TRun(parts[i], r.f));
    }
  }
  return lines;
}

List<TRun> _dropPrefix(List<TRun> l, int n) {
  final out = <TRun>[];
  for (final r in l) {
    if (n >= r.x.length) {
      n -= r.x.length;
      continue;
    }
    out.add(TRun(r.x.substring(n), r.f));
    n = 0;
  }
  return out;
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// HTML thư từ chữ có định dạng của khung soạn.
String composeHtml(List<TRun> runs) {
  String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
  String attr(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);
  String inline(List<TRun> rs) => rs.map((r) {
        var s = esc(r.x);
        if (r.f.c) s = '<code>$s</code>';
        if (r.f.b) s = '<b>$s</b>';
        if (r.f.i) s = '<i>$s</i>';
        if (r.f.u) s = '<u>$s</u>';
        if (r.f.s) s = '<s>$s</s>';
        final fg = kTextColors[r.f.fg];
        if (fg != null) s = '<span style="color:${_hex(fg.$1)}">$s</span>';
        if (r.f.a != null) s = '<a href="${attr(r.f.a!)}">$s</a>';
        return s;
      }).join();
  final out = StringBuffer();
  String? open;
  void close() {
    if (open != null) out.write('</$open>');
    open = null;
  }

  for (final l in runLines(runs)) {
    final text = l.map((r) => r.x).join();
    final k = lineKind(text);
    final tag = switch (k) { 'ul' => 'ul', 'ol' => 'ol', 'quote' => 'blockquote', _ => null };
    if (tag != open) {
      close();
      if (tag == 'blockquote') {
        out.write('<blockquote style="margin:0 0 0 .8ex;border-left:2px solid #ccc;padding-left:1ex">');
      } else if (tag != null) {
        out.write('<$tag>');
      }
      open = tag;
    }
    final rest = _dropPrefix(l, prefixLen(text));
    final empty = rest.every((r) => r.x.isEmpty);
    if (k == 'ul' || k == 'ol') {
      out.write('<li>${inline(rest)}</li>');
    } else {
      out.write(empty ? '<div><br></div>' : '<div>${inline(rest)}</div>');
    }
  }
  close();
  return out.toString();
}

/// Bản chữ thuần gửi kèm (multipart/alternative): giữ gạch đầu dòng, số, "> " trích dẫn, link ghi kèm địa chỉ.
String composeText(List<TRun> runs) => runLines(runs).map((l) {
      final text = l.map((r) => r.x).join();
      final k = lineKind(text);
      final rest = _dropPrefix(l, prefixLen(text)).map((r) => r.f.a != null && r.f.a != r.x ? '${r.x} <${r.f.a}>' : r.x).join();
      return switch (k) {
        'ul' => '- $rest',
        'ol' => '${_olRe.firstMatch(text)!.group(1)}. $rest',
        'quote' => '> $rest',
        _ => rest,
      };
    }).join('\n');

/// Màu gần nhất trong bảng màu chữ (null = màu mặc định / đen / xám đậm).
String? _nearColor(String css) {
  final m = RegExp(r'#([0-9a-f]{6}|[0-9a-f]{3})\b', caseSensitive: false).firstMatch(css);
  final rgb = RegExp(r'rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)').firstMatch(css);
  int r, g, b;
  if (m != null) {
    var h = m.group(1)!;
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    final v = int.parse(h, radix: 16);
    (r, g, b) = ((v >> 16) & 255, (v >> 8) & 255, v & 255);
  } else if (rgb != null) {
    (r, g, b) = (int.parse(rgb.group(1)!), int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
  } else {
    return null;
  }
  // Gần đen / trắng / xám: coi như màu mặc định (chữ dán từ trang web hay có màu #222).
  final mx = [r, g, b].reduce((a, c) => a > c ? a : c), mn = [r, g, b].reduce((a, c) => a < c ? a : c);
  if (mx - mn < 40) return null;
  String? best;
  var bestD = 1 << 30;
  kTextColors.forEach((k, v) {
    final c = v.$1;
    final dr = r - (c.r * 255).round(), dg = g - (c.g * 255).round(), db = b - (c.b * 255).round();
    final d = dr * dr + dg * dg + db * db;
    if (d < bestD) (bestD, best) = (d, k);
  });
  return best;
}

/// Chữ có định dạng từ HTML (dán, mở bản nháp). Giữ đậm / nghiêng / gạch chân / gạch ngang / link / màu, danh sách,
/// trích dẫn; bỏ phần còn lại (bảng thành dòng, ảnh bỏ qua).
List<TRun> htmlToRuns(String html) {
  final doc = hp.parse(html);
  doc.querySelectorAll('style,script,head,title,meta').forEach((e) => e.remove());
  var out = <TRun>[];
  var lineOpen = false; // dòng hiện tại đã có chữ
  void write(String s, TFmt f) {
    if (s.isEmpty) return;
    if (out.isNotEmpty && out.last.f == f) {
      out.last.x += s;
    } else {
      out.add(TRun(s, f));
    }
    lineOpen = true;
  }

  void newline() {
    write('\n', TFmt.plain);
    lineOpen = false;
  }

  void breakBlock() {
    if (lineOpen) newline();
  }

  const blocks = {'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'tr', 'table', 'pre', 'section', 'article', 'header', 'footer'};
  void walk(dom.Node n, TFmt f, String? list, int quote) {
    if (n is dom.Text) {
      final t = n.text.replaceAll(RegExp(r'[\r\n\t ]+'), ' ');
      if (t.trim().isEmpty && !lineOpen) return;
      write(lineOpen ? t : t.trimLeft(), f);
      return;
    }
    if (n is! dom.Element) return;
    final t = n.localName;
    if (t == 'br') return newline();
    var g = f;
    switch (t) {
      case 'b' || 'strong':
        g = g.copyWith(b: true);
      case 'i' || 'em':
        g = g.copyWith(i: true);
      case 'u' || 'ins':
        g = g.copyWith(u: true);
      case 's' || 'strike' || 'del':
        g = g.copyWith(s: true);
      case 'code':
        g = g.copyWith(c: true);
      case 'a':
        final href = n.attributes['href'];
        if (href != null && RegExp(r'^(https?:|mailto:)', caseSensitive: false).hasMatch(href)) g = g.copyWith(a: href);
      case 'h1' || 'h2' || 'h3':
        g = g.copyWith(b: true);
    }
    final style = n.attributes['style'] ?? '';
    if (RegExp(r'font-weight\s*:\s*(bold|[6-9]00)').hasMatch(style)) g = g.copyWith(b: true);
    if (RegExp(r'font-style\s*:\s*italic').hasMatch(style)) g = g.copyWith(i: true);
    if (RegExp(r'text-decoration[^;]*underline').hasMatch(style)) g = g.copyWith(u: true);
    if (RegExp(r'text-decoration[^;]*line-through').hasMatch(style)) g = g.copyWith(s: true);
    final color = RegExp(r'(?:^|;)\s*color\s*:\s*([^;]+)').firstMatch(style)?.group(1) ?? n.attributes['color'];
    if (color != null) g = g.copyWith(fg: _nearColor(color));
    if (t == 'ul' || t == 'ol') {
      breakBlock();
      var i = 0;
      for (final c in n.children) {
        if (c.localName != 'li') continue;
        i++;
        breakBlock();
        write(t == 'ul' ? kBullet : '$i. ', TFmt.plain);
        for (final x in c.nodes) {
          // Danh sách lồng nhau: làm phẳng thành dòng cùng cấp.
          walk(x, g, t, quote);
        }
      }
      breakBlock();
      return;
    }
    if (t == 'blockquote') {
      breakBlock();
      // Gom phần trích dẫn riêng rồi đánh dấu "> " đầu mỗi dòng.
      final saved = out;
      out = [];
      lineOpen = false;
      for (final c in n.nodes) {
        walk(c, g, list, quote + 1);
      }
      final seg = out;
      out = saved;
      lineOpen = false;
      var atStart = true;
      for (final r in seg) {
        final parts = r.x.split('\n');
        for (var p = 0; p < parts.length; p++) {
          if (p > 0) {
            write('\n', TFmt.plain);
            atStart = true;
          }
          if (parts[p].isEmpty) continue;
          if (atStart) write(lineKind(parts[p]) == 'p' ? kQuote : '', TFmt.plain);
          atStart = false;
          write(parts[p], r.f);
        }
      }
      lineOpen = out.isNotEmpty && !out.last.x.endsWith('\n');
      return;
    }
    final block = blocks.contains(t) || t == 'li';
    if (block) breakBlock();
    for (final c in n.nodes) {
      walk(c, g, list, quote);
    }
    if (block) breakBlock();
    if (t == 'td' || t == 'th') write(' ', TFmt.plain);
  }

  walk(doc.body ?? doc.documentElement!, TFmt.plain, null, 0);
  // Bỏ dòng trống thừa ở cuối, gộp nhiều dòng trống.
  final joined = <TRun>[];
  for (final r in out) {
    final x = r.x.replaceAll(RegExp(r' +\n'), '\n');
    if (joined.isNotEmpty && joined.last.f == r.f) {
      joined.last.x += x;
    } else {
      joined.add(TRun(x, r.f));
    }
  }
  while (joined.isNotEmpty && joined.last.x.trimRight().isEmpty) {
    joined.removeLast();
  }
  if (joined.isNotEmpty) joined.last.x = joined.last.x.trimRight();
  for (final r in joined) {
    r.x = r.x.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
  return joined;
}

/// HTML trong bộ nhớ tạm (null = không có / nền tảng không hỗ trợ). Windows trả dạng CF_HTML có phần đầu
/// "Version:… StartFragment:…", chỉ lấy đoạn giữa hai dấu StartFragment / EndFragment.
Future<String?> readClipboardHtml() async {
  String? h;
  try {
    if (Platform.isWindows || Platform.isAndroid) {
      h = await Pasteboard.html;
    } else if (Platform.isLinux) {
      for (final cmd in [
        ['wl-paste', '-n', '-t', 'text/html'],
        ['xclip', '-o', '-selection', 'clipboard', '-t', 'text/html'],
      ]) {
        try {
          final r = await Process.run(cmd.first, cmd.sublist(1), stdoutEncoding: utf8);
          if (r.exitCode == 0 && '${r.stdout}'.trim().isNotEmpty) {
            h = '${r.stdout}';
            break;
          }
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      final r = await Process.run('osascript', ['-e', 'the clipboard as «class HTML»']);
      final m = RegExp(r'«data HTML([0-9A-Fa-f]+)»').firstMatch('${r.stdout}');
      if (m != null) {
        final hex = m.group(1)!;
        h = utf8.decode([for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)], allowMalformed: true);
      }
    }
  } catch (_) {
    return null;
  }
  if (h == null || h.trim().isEmpty) return null;
  final a = h.indexOf('<!--StartFragment-->'), b = h.indexOf('<!--EndFragment-->');
  if (a >= 0 && b > a) return h.substring(a + '<!--StartFragment-->'.length, b);
  final i = h.indexOf('<');
  return i > 0 ? h.substring(i) : h;
}

/// Bộ soạn thân thư: RichController + kiểu dòng (danh sách, trích dẫn), Enter nối tiếp danh sách, dán giữ định dạng.
class MailRichController extends RichController {
  MailRichController(super.runs, {super.dark});

  /// Màu tiền tố / vạch trích dẫn (đặt theo theme lúc vẽ).
  Color accent = const Color(0xFF1A73E8), muted = const Color(0xFF5F6368);

  (int, int) _lineAt(String t, int at) {
    final s = t.lastIndexOf('\n', at - 1) + 1;
    final e = t.indexOf('\n', at);
    return (s == 0 ? 1 : s, e < 0 ? t.length : e);
  }

  @override
  set value(TextEditingValue v) {
    final old = text;
    final sel = v.selection;
    // Gõ Enter trong danh sách: dòng mới có tiền tố tiếp theo; Enter ở mục trống: thoát danh sách.
    if (sel.isValid && sel.isCollapsed && v.text.length == old.length + 1 && sel.start >= 2 && v.text[sel.start - 1] == '\n' &&
        v.text.substring(0, sel.start - 1) + v.text.substring(sel.start) == old) {
      final (ls, _) = _lineAt(v.text, sel.start - 1);
      final line = v.text.substring(ls, sel.start - 1);
      final k = lineKind(line);
      if (k != 'p') {
        final pre = line.substring(0, prefixLen(line));
        if (line.length == pre.length) {
          final t = old.replaceRange(ls, ls + pre.length, '');
          super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: ls));
          return;
        }
        final next = k == 'ol' ? '${int.parse(_olRe.firstMatch(line)!.group(1)!) + 1}. ' : pre;
        final t = v.text.replaceRange(sel.start, sel.start, next);
        super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: sel.start + next.length));
        return;
      }
    }
    super.value = v;
  }

  /// Đổi kiểu các dòng đang chọn sang [kind] (ul | ol | quote); đã cùng kiểu hết thì bỏ về đoạn thường.
  void setLineKind(String kind) {
    var t = text;
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: t.length);
    final (first, _) = _lineAt(t, sel.start);
    final (_, last) = _lineAt(t, sel.end);
    final starts = <int>[first];
    for (var i = t.indexOf('\n', first); i >= 0 && i < last; i = t.indexOf('\n', i + 1)) {
      starts.add(i + 1);
    }
    String lineOf(int s) {
      final e = t.indexOf('\n', s);
      return t.substring(s, e < 0 ? t.length : e);
    }

    final off = starts.every((s) => lineKind(lineOf(s)) == kind);
    // Đánh số tiếp theo dòng ngay phía trên nếu nó cũng là danh sách số.
    var n = 1;
    if (kind == 'ol' && first > 1) {
      final (ps, pe) = _lineAt(t, first - 1);
      final m = _olRe.firstMatch(t.substring(ps, pe));
      if (m != null) n = int.parse(m.group(1)!) + 1;
    }
    final pres = [for (var i = 0; i < starts.length; i++) off ? '' : (kind == 'ul' ? kBullet : kind == 'quote' ? kQuote : '${n + i}. ')];
    var delta = 0;
    // Sửa từ dưới lên để vị trí các dòng trên không đổi.
    for (var i = starts.length - 1; i >= 0; i--) {
      final s = starts[i], old = prefixLen(lineOf(s));
      t = t.replaceRange(s, s + old, pres[i]);
      value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: s));
      delta += pres[i].length - old;
    }
    final end = (sel.end + delta).clamp(1, text.length);
    value = value.copyWith(selection: sel.isCollapsed ? TextSelection.collapsed(offset: end) : TextSelection(baseOffset: first, extentOffset: end));
  }

  /// Kiểu dòng ở con trỏ (để sáng nút trên thanh công cụ).
  String get currentKind {
    final t = text;
    final at = selection.isValid ? selection.start : t.length;
    final (s, e) = _lineAt(t, at);
    return lineKind(t.substring(s, e));
  }

  /// Chèn chữ có định dạng vào chỗ đang chọn.
  void insertRuns(List<TRun> ins) {
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final a = (sel.start - 1).clamp(0, body.length), b = (sel.end - 1).clamp(0, body.length);
    final before = <TRun>[], after = <TRun>[];
    var pos = 0;
    for (final r in runs) {
      final end = pos + r.x.length;
      if (pos < a) before.add(TRun(r.x.substring(0, (a - pos).clamp(0, r.x.length)), r.f));
      if (end > b) after.add(TRun(r.x.substring((b - pos).clamp(0, r.x.length)), r.f));
      pos = end;
    }
    final len = ins.fold<int>(0, (s, r) => s + r.x.length);
    setBody([...before, ...ins, ...after], cursor: sel.start + len);
    onEdited?.call();
  }

  /// Dán: có HTML trong bộ nhớ tạm thì giữ định dạng cơ bản, không thì dán chữ thuần.
  Future<void> paste() async {
    final h = await readClipboardHtml();
    if (h != null) {
      final r = htmlToRuns(h);
      if (r.isNotEmpty) return insertRuns(r);
    }
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null && d!.text!.isNotEmpty) insert(d.text!.replaceAll('\r\n', '\n'));
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    final span = super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final kids = span.children ?? const <InlineSpan>[];
    // Tô lại theo dòng: tiền tố (màu nhấn) và dòng trích dẫn (chữ nhạt). Giữ nguyên chữ (TextField cần chữ khớp
    // từng ký tự với controller). cls: 0 = thường, 1 = tiền tố, 2 = chữ trích dẫn.
    final b = body;
    final cls = List<int>.filled(b.length, 0);
    var ls = 0;
    while (ls <= b.length) {
      final nl = b.indexOf('\n', ls);
      final le = nl < 0 ? b.length : nl;
      final line = b.substring(ls, le);
      final p = prefixLen(line), q = lineKind(line) == 'quote';
      for (var x = ls; x < le; x++) {
        cls[x] = x < ls + p ? 1 : (q ? 2 : 0);
      }
      if (nl < 0) break;
      ls = nl + 1;
    }
    final out = <InlineSpan>[];
    var pos = 0;
    for (final k in kids) {
      final txt = (k as TextSpan).text ?? '';
      if (txt == kZw && out.isEmpty) {
        out.add(k);
        continue;
      }
      final s = k.style ?? base;
      var j = 0;
      while (j < txt.length) {
        final c = pos + j < cls.length ? cls[pos + j] : 0;
        var e = j + 1;
        while (e < txt.length && (pos + e < cls.length ? cls[pos + e] : 0) == c) {
          e++;
        }
        final st = switch (c) {
          1 => s.copyWith(color: accent, fontWeight: FontWeight.w700, fontStyle: FontStyle.normal),
          2 => s.copyWith(color: muted),
          _ => s,
        };
        out.add(TextSpan(text: txt.substring(j, e), style: st, recognizer: k.recognizer));
        j = e;
      }
      pos += txt.length;
    }
    return TextSpan(style: span.style, children: out);
  }
}
