import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange, kFlowRed;
import 'flow_cond.dart';
import 'flow_editor_expr.dart';

/// Bước Soạn nội dung (`compose`): ô soạn có thanh nút định dạng (sinh HTML an toàn như máy chủ cho phép), chèn thông
/// tin `{{…}}`, khối Nếu / Lặp, và bản xem trước dựng bằng dữ liệu mẫu. Dựng mẫu giống `flows_engine::compose`.

// ---------------------------------------------------------------------------------------------- dựng mẫu

sealed class _Part {}

class _Text extends _Part {
  final String t;
  _Text(this.t);
}

class _Slot extends _Part {
  final String e;
  _Slot(this.e);
}

class _If extends _Part {
  final String e;
  final List<_Part> then, other;
  _If(this.e, this.then, this.other);
}

class _Each extends _Part {
  final String e;
  final List<_Part> body;
  _Each(this.e, this.body);
}

/// Lỗi cấu trúc khối của mẫu (như máy chủ): null = đúng.
String? composeError(String src) {
  try {
    _parse(src);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

List<_Part> _parse(String src) {
  final top = <_Part>[];
  // (loại, biểu thức, then, else)
  final stack = <(String, String, List<_Part>, List<_Part>?)>[];
  List<_Part> cur() => stack.isEmpty ? top : (stack.last.$4 ?? stack.last.$3);
  var rest = src;
  while (true) {
    final a = rest.indexOf('{{');
    if (a < 0) break;
    if (a > 0) cur().add(_Text(rest.substring(0, a)));
    final after = rest.substring(a + 2);
    final b = after.indexOf('}}');
    if (b < 0) throw FormatException(tr('có "{{" chưa đóng bằng "}}"'));
    final inner = after.substring(0, b).trim();
    rest = after.substring(b + 2);
    if (inner.startsWith('#if ')) {
      stack.add(('if', inner.substring(4).trim(), <_Part>[], null));
    } else if (inner.startsWith('#each ')) {
      stack.add(('each', inner.substring(6).trim(), <_Part>[], null));
    } else if (inner == 'else') {
      if (stack.isEmpty || stack.last.$1 != 'if' || stack.last.$4 != null) throw FormatException(tr('{{else}} không nằm trong {{#if}}'));
      final l = stack.removeLast();
      stack.add((l.$1, l.$2, l.$3, <_Part>[]));
    } else if (inner == '/if' || inner == '/each') {
      final want = inner.substring(1);
      if (stack.isEmpty) throw FormatException(tr('{{/{0}}} không có khối mở', [want]));
      final l = stack.removeLast();
      if (l.$1 != want) throw FormatException(tr('{{/{0}}} đóng nhầm khối {{#{1}}}', [want, l.$1]));
      cur().add(want == 'if' ? _If(l.$2, l.$3, l.$4 ?? []) : _Each(l.$2, l.$3));
    } else if (inner.startsWith('#') || inner.startsWith('/')) {
      throw FormatException(tr('khối "{{{0}}}" không hỗ trợ (dùng #if, #each)', [inner]));
    } else {
      cur().add(_Slot(inner));
    }
  }
  if (rest.isNotEmpty) cur().add(_Text(rest));
  if (stack.isNotEmpty) throw FormatException(tr('khối {{#{0} {1}}} chưa đóng', [stack.last.$1, stack.last.$2]));
  return top;
}

String escapeHtml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');

/// Chữ hiện của giá trị (như `template::show` của máy chủ): số lớn có chấm hàng nghìn, đúng / sai = có / không.
String showValue(Object? v) {
  if (v == null) return '';
  if (v is bool) return v ? 'có' : 'không';
  if (v is num && v == v.roundToDouble() && v.abs() >= 10000) return vnInt(v.round());
  if (v is num) return v == v.roundToDouble() ? '${v.round()}' : '$v';
  return exprText(v);
}

String vnInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

Object? _value(String e, Map<String, dynamic> ctx) => evalExprText(e, ctx);

/// Dựng mẫu với [ctx]: (kết quả, các chỗ chèn ra trống). [html]: mã hoá giá trị.
(String, List<String>) renderCompose(String src, Map<String, dynamic> ctx, {bool html = true}) {
  final missing = <String>[];
  final out = StringBuffer();
  void walk(List<_Part> parts, Map<String, dynamic> c) {
    for (final p in parts) {
      switch (p) {
        case _Text t:
          out.write(t.t);
        case _Slot s:
          final v = _value(s.e, c);
          if ((v == null || (v is String && v.trim().isEmpty)) && !missing.contains(s.e)) missing.add(s.e);
          out.write(html ? escapeHtml(showValue(v)) : showValue(v));
        case _If i:
          walk(exprTruthy(_value(i.e, c)) ? i.then : i.other, c);
        case _Each e:
          final v = _value(e.e, c);
          final rows = v is List ? v : (v == null ? const [] : [v]);
          for (var k = 0; k < rows.length; k++) {
            walk(e.body, {...c, 'item': rows[k], 'loop': {'index': k + 1, 'count': rows.length}});
          }
      }
    }
  }

  walk(_parse(src), ctx);
  return (out.toString(), missing);
}

/// Các đường dẫn `item.<cột>` dùng trong khối Lặp (để dựng dòng mẫu).
Set<String> _itemCols(String src) => {for (final m in RegExp(r'item\.([A-Za-z0-9_]+)').allMatches(src)) m[1]!};

/// Dữ liệu mẫu cho xem trước: mỗi thông tin một giá trị theo kiểu, mỗi bảng trong {{#each}} hai dòng mẫu.
Map<String, dynamic> sampleCtx(List<CondVar> vars, String src) {
  final ctx = <String, dynamic>{};
  void put(List<String> path, Object v) {
    Map<String, dynamic> m = ctx;
    for (final k in path.sublist(0, path.length - 1)) {
      m = (m[k] ??= <String, dynamic>{}) as Map<String, dynamic>;
    }
    m[path.last] = v;
  }

  for (final v in vars) {
    if (v.path.startsWith('item') || v.path.startsWith('loop')) continue;
    final sample = switch (v.type) {
      'number' || 'money' => 1080000,
      'date' => '2026-11-10',
      'bool' => true,
      'select' when v.options.isNotEmpty => v.options.first,
      _ => '‹${v.label.split(' › ').last}›',
    };
    try {
      put(v.path.split('.'), sample);
    } catch (_) {}
  }
  final cols = _itemCols(src);
  for (final m in RegExp(r'\{\{#each\s+([^}]+)\}\}').allMatches(src)) {
    final path = m[1]!.trim();
    if (!RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(path)) continue;
    try {
      put(path.split('.'), [
        for (var i = 1; i <= 2; i++) {for (final c in cols) c: '‹$c $i›'},
      ]);
    } catch (_) {}
  }
  return ctx;
}

// ---------------------------------------------------------------------------------------------- xem trước HTML

const _allowed = {'p', 'br', 'b', 'strong', 'i', 'em', 'u', 's', 'span', 'h1', 'h2', 'h3', 'ul', 'ol', 'li', 'blockquote', 'a', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'img', 'hr'};

class HtmlNode {
  final String tag;
  final Map<String, String> attrs;
  final List<Object> kids = []; // HtmlNode hoặc String
  HtmlNode(this.tag, [this.attrs = const {}]);
}

String _decode(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

/// Đọc HTML (mẫu đã dựng) thành cây, chỉ giữ thẻ cho phép (thẻ khác: bỏ thẻ, giữ chữ; script / style: bỏ hẳn).
HtmlNode parseHtml(String html) {
  final root = HtmlNode('root');
  final stack = [root];
  final re = RegExp(r'<(/?)([a-zA-Z0-9]+)([^>]*)>|<!--.*?-->', dotAll: true);
  var at = 0;
  var skip = 0;
  for (final m in re.allMatches(html)) {
    if (m.start > at && skip == 0) stack.last.kids.add(_decode(html.substring(at, m.start)));
    at = m.end;
    if (m[2] == null) continue;
    final tag = m[2]!.toLowerCase();
    final closing = m[1] == '/';
    if (tag == 'script' || tag == 'style') {
      skip += closing ? -1 : 1;
      if (skip < 0) skip = 0;
      continue;
    }
    if (skip > 0 || !_allowed.contains(tag)) continue;
    if (closing) {
      final i = stack.lastIndexWhere((n) => n.tag == tag);
      if (i > 0) stack.removeRange(i, stack.length);
      continue;
    }
    final attrs = <String, String>{
      for (final a in RegExp(r'''([a-zA-Z-]+)\s*=\s*("([^"]*)"|'([^']*)')''').allMatches(m[3] ?? ''))
        if (!a[1]!.toLowerCase().startsWith('on')) a[1]!.toLowerCase(): _decode(a[3] ?? a[4] ?? ''),
    };
    final n = HtmlNode(tag, attrs);
    stack.last.kids.add(n);
    if (!const {'br', 'img', 'hr'}.contains(tag) && !(m[3] ?? '').trimRight().endsWith('/')) stack.add(n);
  }
  if (at < html.length && skip == 0) stack.last.kids.add(_decode(html.substring(at)));
  return root;
}

Color? _cssColor(String? v) {
  if (v == null) return null;
  final s = v.trim().toLowerCase();
  const named = {'red': 0xFFE53935, 'green': 0xFF2E7D32, 'blue': 0xFF1565C0, 'orange': 0xFFEF6C00, 'black': 0xFF000000, 'gray': 0xFF757575, 'grey': 0xFF757575, 'purple': 0xFF6A1B9A};
  if (named[s] != null) return Color(named[s]!);
  final h = RegExp(r'^#([0-9a-f]{6}|[0-9a-f]{3})$').firstMatch(s);
  if (h == null) return null;
  var hex = h[1]!;
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  return Color(int.parse('FF$hex', radix: 16));
}

Map<String, String> _style(Map<String, String> attrs) => {
      for (final d in (attrs['style'] ?? '').split(';'))
        if (d.contains(':')) d.split(':').first.trim().toLowerCase(): d.split(':').skip(1).join(':').trim(),
    };

/// Bản xem trước: HTML (đã dựng) thành widget, chỉ thẻ cho phép.
class HtmlPreview extends StatelessWidget {
  final String html;
  const HtmlPreview({super.key, required this.html});

  TextStyle _inline(TextStyle base, HtmlNode n) {
    final st = _style(n.attrs);
    var s = switch (n.tag) {
      'b' || 'strong' => base.copyWith(fontWeight: FontWeight.w700),
      'i' || 'em' => base.copyWith(fontStyle: FontStyle.italic),
      'u' => base.copyWith(decoration: TextDecoration.underline),
      's' => base.copyWith(decoration: TextDecoration.lineThrough),
      'a' => base.copyWith(color: const Color(0xFF1565C0), decoration: TextDecoration.underline),
      _ => base,
    };
    final c = _cssColor(st['color']);
    if (c != null) s = s.copyWith(color: c);
    final bg = _cssColor(st['background'] ?? st['background-color']);
    if (bg != null) s = s.copyWith(backgroundColor: bg.withValues(alpha: 0.35));
    if (st['font-weight'] == 'bold' || st['font-weight'] == '700') s = s.copyWith(fontWeight: FontWeight.w700);
    return s;
  }

  static const _blocks = {'p', 'h1', 'h2', 'h3', 'ul', 'ol', 'li', 'blockquote', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'hr', 'img'};

  List<InlineSpan> _spans(List<Object> kids, TextStyle style) => [
        for (final k in kids)
          if (k is String)
            TextSpan(text: k.replaceAll(RegExp(r'\s+'), ' '), style: style)
          else if (k is HtmlNode && k.tag == 'br')
            const TextSpan(text: '\n')
          else if (k is HtmlNode && k.tag == 'img')
            WidgetSpan(child: _img(k))
          else if (k is HtmlNode)
            TextSpan(children: _spans(k.kids, _inline(style, k))),
      ];

  Widget _img(HtmlNode n) => Container(
        padding: const EdgeInsets.all(6),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.image_outlined, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text(n.attrs['alt']?.isNotEmpty == true ? n.attrs['alt']! : (n.attrs['src'] ?? ''), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        ]),
      );

  List<Widget> _blocksOf(List<Object> kids, TextStyle base, {int depth = 0, String? list}) {
    final out = <Widget>[];
    var inline = <Object>[];
    void flush() {
      final txt = inline.where((k) => k is! String || k.trim().isNotEmpty).toList();
      if (txt.isNotEmpty) out.add(Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text.rich(TextSpan(children: _spans(inline, base)))));
      inline = [];
    }

    var no = 0;
    for (final k in kids) {
      if (k is HtmlNode && _blocks.contains(k.tag)) {
        flush();
        out.add(_block(k, base, depth, list, ++no));
      } else {
        inline.add(k);
      }
    }
    flush();
    return out;
  }

  Widget _block(HtmlNode n, TextStyle base, int depth, String? list, int no) {
    final align = switch (_style(n.attrs)['text-align']) { 'center' => TextAlign.center, 'right' => TextAlign.right, _ => TextAlign.left };
    Widget para(TextStyle s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(width: double.infinity, child: Text.rich(TextSpan(children: _spans(n.kids, _inline(s, n))), textAlign: align)),
        );
    switch (n.tag) {
      case 'h1':
        return para(base.copyWith(fontSize: 22, fontWeight: FontWeight.w700));
      case 'h2':
        return para(base.copyWith(fontSize: 19, fontWeight: FontWeight.w700));
      case 'h3':
        return para(base.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700));
      case 'p':
        return para(base);
      case 'hr':
        return const Divider();
      case 'img':
        return _img(n);
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.grey, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _blocksOf(n.kids, base.copyWith(color: Colors.grey.shade700), depth: depth)),
        );
      case 'ul' || 'ol':
        return Padding(
          padding: EdgeInsets.only(left: 12.0 + depth * 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _blocksOf(n.kids, base, depth: depth + 1, list: n.tag)),
        );
      case 'li':
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 22, child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(list == 'ol' ? '$no.' : '•', style: base))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _blocksOf(n.kids, base, depth: depth))),
        ]);
      case 'table' || 'thead' || 'tbody' || 'tfoot':
        final rows = <HtmlNode>[];
        void collect(HtmlNode x) {
          for (final k in x.kids.whereType<HtmlNode>()) {
            k.tag == 'tr' ? rows.add(k) : collect(k);
          }
        }

        collect(n);
        if (rows.isEmpty) return const SizedBox.shrink();
        final cols = rows.map((r) => r.kids.whereType<HtmlNode>().where((c) => c.tag == 'td' || c.tag == 'th').length).fold<int>(0, (a, b) => b > a ? b : a);
        if (cols == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade400),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (final r in rows)
                TableRow(children: [
                  for (var i = 0; i < cols; i++)
                    Builder(builder: (_) {
                      final cells = r.kids.whereType<HtmlNode>().where((c) => c.tag == 'td' || c.tag == 'th').toList();
                      if (i >= cells.length) return const SizedBox.shrink();
                      final c = cells[i];
                      return Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text.rich(TextSpan(children: _spans(c.kids, c.tag == 'th' ? base.copyWith(fontWeight: FontWeight.w700) : base))),
                      );
                    }),
                ]),
            ],
          ),
        );
      default:
        return Text.rich(TextSpan(children: _spans(n.kids, base)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.copyWith(fontSize: 14, color: Pal.of(context).text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _blocksOf(parseHtml(html).kids, base));
  }
}

// ---------------------------------------------------------------------------------------------- ô soạn

/// Bộ điều khiển ô soạn: chỗ chèn `{{…}}` hiện như chip (nền màu), khối {{#if}} / {{#each}} màu khác.
class ComposeController extends TextEditingController {
  ComposeController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\{\{[^}]*\}\}');
    var at = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start), style: style));
      final t = m[0]!;
      final block = t.startsWith('{{#') || t.startsWith('{{/') || t == '{{else}}';
      spans.add(TextSpan(
        text: t,
        style: (style ?? const TextStyle()).copyWith(
          backgroundColor: (block ? kFlowOrange : Theme.of(context).colorScheme.primary).withValues(alpha: 0.14),
          color: block ? kFlowOrange : Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at), style: style));
    return TextSpan(children: spans, style: style);
  }
}

/// Cấu hình bước Soạn nội dung. Sửa trực tiếp [n].
class ComposeConfig extends StatefulWidget {
  final Map<String, dynamic> n;
  final List<CondVar> vars;
  final VoidCallback? onChanged;
  const ComposeConfig({super.key, required this.n, required this.vars, this.onChanged});
  @override
  State<ComposeConfig> createState() => _ComposeConfigState();
}

class _ComposeConfigState extends State<ComposeConfig> {
  Map<String, dynamic> get n => widget.n;
  late final subject = ComposeController(text: '${n['subject'] ?? ''}');
  late final body = ComposeController(text: '${n['body'] ?? ''}');
  late TextEditingController _focus = body;
  bool _preview = false;

  @override
  void dispose() {
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  void _sync() {
    n['subject'] = subject.text;
    n['body'] = body.text;
    setState(() {});
    widget.onChanged?.call();
  }

  /// Bọc phần đang chọn bằng [open] / [close] (không chọn gì thì chèn cả hai, con trỏ ở giữa).
  void _wrap(String open, String close, {TextEditingController? ctl}) {
    final c = ctl ?? body;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: c.text.length);
    final inner = c.text.substring(sel.start, sel.end);
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, '$open$inner$close'),
      selection: inner.isEmpty ? TextSelection.collapsed(offset: sel.start + open.length) : TextSelection(baseOffset: sel.start, extentOffset: sel.start + open.length + inner.length + close.length),
    );
    _sync();
  }

  void _insert(String t, {TextEditingController? ctl}) => _wrap(t, '', ctl: ctl);

  Future<String?> _ask(String title, String label, {String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: Text(tr('Chèn'))),
        ],
      ),
    );
  }

  Future<void> _link() async {
    final url = await _ask(tr('Chèn link'), tr('Địa chỉ (https://…, mailto:… hoặc {{thông tin}})'));
    if (url == null || url.isEmpty) return;
    _wrap('<a href="${url.replaceAll('"', '&quot;')}">', '</a>');
  }

  Future<void> _image() async {
    final url = await _ask(tr('Chèn ảnh'), tr('Địa chỉ ảnh (https://…)'));
    if (url == null || url.isEmpty) return;
    _insert('<img src="${url.replaceAll('"', '&quot;')}" alt="">');
  }

  Future<void> _each() async {
    final lists = [for (final v in widget.vars) if (v.type == 'table' || v.path.endsWith('.rows') || v.path.endsWith('.groups')) v];
    final path = await _ask(tr('Lặp theo bảng'), tr('Bảng (vd steps.mail.output.dong)'), initial: lists.firstOrNull?.path ?? '');
    if (path == null || path.isEmpty) return;
    _wrap('{{#each $path}}', '{{/each}}');
  }

  Future<void> _if() async {
    final cond = await _ask(tr('Chỉ hiện khi'), tr('Điều kiện (vd steps.mail.output.ma)'));
    if (cond == null || cond.isEmpty) return;
    _wrap('{{#if $cond}}', '{{/if}}');
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {Key? key}) => IconButton(key: key, icon: Icon(icon, size: 20), tooltip: tip, onPressed: onTap, visualDensity: VisualDensity.compact);

  Widget _toolbar() => Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        _btn(Icons.format_bold_rounded, tr('Đậm'), () => _wrap('<b>', '</b>'), key: const ValueKey('c-bold')),
        _btn(Icons.format_italic_rounded, tr('Nghiêng'), () => _wrap('<i>', '</i>')),
        _btn(Icons.format_underlined_rounded, tr('Gạch chân'), () => _wrap('<u>', '</u>')),
        PopupMenuButton<String>(
          tooltip: tr('Màu chữ'),
          icon: const Icon(Icons.format_color_text_rounded, size: 20),
          onSelected: (c) => _wrap('<span style="color: $c">', '</span>'),
          itemBuilder: (_) => [
            for (final (c, l) in const [('#e53935', 'Đỏ'), ('#2e7d32', 'Xanh lá'), ('#1565c0', 'Xanh dương'), ('#ef6c00', 'Cam'), ('#757575', 'Xám')])
              PopupMenuItem(value: c, child: Row(children: [Icon(Icons.circle, color: _cssColor(c), size: 16), const SizedBox(width: 8), Text(tr(l))])),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: tr('Tiêu đề'),
          icon: const Icon(Icons.title_rounded, size: 20),
          onSelected: (h) => _wrap('<$h>', '</$h>'),
          itemBuilder: (_) => [for (final (h, l) in const [('h1', 'Tiêu đề lớn'), ('h2', 'Tiêu đề vừa'), ('h3', 'Tiêu đề nhỏ'), ('p', 'Đoạn thường')]) PopupMenuItem(value: h, child: Text(tr(l)))],
        ),
        _btn(Icons.format_list_bulleted_rounded, tr('Danh sách'), () => _wrap('<ul><li>', '</li></ul>')),
        _btn(Icons.format_list_numbered_rounded, tr('Danh sách đánh số'), () => _wrap('<ol><li>', '</li></ol>')),
        _btn(Icons.link_rounded, tr('Link'), _link),
        _btn(Icons.table_chart_outlined, tr('Bảng (mỗi dòng của một bảng dữ liệu)'), () async {
          final lists = [for (final v in widget.vars) if (v.path.endsWith('.rows') || v.path.endsWith('.groups') || v.type == 'table') v];
          final path = await _ask(tr('Chèn bảng'), tr('Lặp dòng theo bảng (bỏ trống = bảng 2 cột tự điền)'), initial: lists.firstOrNull?.path ?? '');
          if (path == null) return;
          _insert(path.isEmpty
              ? '<table><tr><th>Cột 1</th><th>Cột 2</th></tr><tr><td></td><td></td></tr></table>'
              : '<table><tr><th>STT</th><th>Tên</th></tr>{{#each $path}}<tr><td>{{loop.index}}</td><td>{{item.ten}}</td></tr>{{/each}}</table>');
        }),
        _btn(Icons.image_outlined, tr('Ảnh'), _image),
        _btn(Icons.horizontal_rule_rounded, tr('Đường kẻ'), () => _insert('<hr>')),
        const SizedBox(width: 6),
        ActionChip(key: const ValueKey('c-if'), avatar: const Icon(Icons.call_split_rounded, size: 16), label: Text(tr('Nếu')), onPressed: _if),
        const SizedBox(width: 6),
        ActionChip(key: const ValueKey('c-each'), avatar: const Icon(Icons.repeat_rounded, size: 16), label: Text(tr('Lặp')), onPressed: _each),
        const SizedBox(width: 6),
        PopupMenuButton<CondVar>(
          key: const ValueKey('c-data'),
          tooltip: tr('Chèn dữ liệu'),
          onSelected: (v) => _insert('{{${v.path}}}', ctl: _focus),
          itemBuilder: (_) => [for (final v in widget.vars) PopupMenuItem(value: v, child: Text(v.label))],
          child: Chip(avatar: const Icon(Icons.add_box_outlined, size: 16), label: Text(tr('Chèn dữ liệu'))),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final err = composeError(body.text) ?? composeError(subject.text);
    String? html, subj;
    var missing = <String>[];
    if (err == null) {
      final ctx = sampleCtx(widget.vars, '${subject.text}${body.text}');
      final (h, m1) = renderCompose(body.text, ctx);
      final (s, m2) = renderCompose(subject.text, ctx, html: false);
      html = h;
      subj = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      missing = {...m1, ...m2}.toList();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Focus(
        onFocusChange: (f) => f ? _focus = subject : null,
        child: TextField(
          key: const ValueKey('c-subject'),
          controller: subject,
          decoration: InputDecoration(labelText: tr('Tiêu đề'), isDense: true, border: const OutlineInputBorder()),
          onChanged: (_) => _sync(),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text(tr('Nội dung'), style: Theme.of(context).textTheme.labelLarge)),
        SegmentedButton<bool>(
          segments: [ButtonSegment(value: false, label: Text(tr('Soạn'))), ButtonSegment(value: true, label: Text(tr('Xem trước')))],
          selected: {_preview},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _preview = s.first),
        ),
      ]),
      const SizedBox(height: 6),
      if (!_preview) ...[
        _toolbar(),
        Focus(
          onFocusChange: (f) => f ? _focus = body : null,
          child: TextField(
            key: const ValueKey('c-body'),
            controller: body,
            minLines: 8,
            maxLines: 24,
            style: const TextStyle(fontSize: 13.5, height: 1.4),
            decoration: InputDecoration(hintText: tr('Gõ nội dung, dùng các nút để định dạng và chèn dữ liệu'), border: const OutlineInputBorder()),
            onChanged: (_) => _sync(),
          ),
        ),
      ] else
        Container(
          key: const ValueKey('c-preview'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.divider)),
          child: html == null
              ? Text(tr('Chưa xem trước được: {0}', [err ?? '']), style: const TextStyle(color: kFlowRed))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(subj ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: pal.text)),
                  const Divider(),
                  HtmlPreview(html: html),
                ]),
        ),
      if (err != null)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: const TextStyle(color: kFlowRed, fontSize: 12.5)))
      else if (missing.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Dữ liệu mẫu thiếu: {0}', [missing.join(', ')]), style: const TextStyle(color: kFlowOrange, fontSize: 12.5)),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(tr('Kết quả: Nội dung HTML, Nội dung chữ thường, Tiêu đề (dùng cho gửi thư / gửi tin). Xem trước dùng dữ liệu mẫu.'),
            style: TextStyle(color: pal.sub, fontSize: 12.5)),
      ),
    ]);
  }
}
