import 'dart:typed_data';
// Thư: vẽ nội dung HTML của thư bằng widget (không dùng WebView, không chạy script, không tải ảnh ngoài khi chưa cho phép).
// Hỗ trợ phần hay gặp trong thư công việc: đoạn, xuống dòng, đậm/nghiêng/gạch chân, link, tiêu đề, danh sách,
// trích dẫn, bảng đơn giản, ảnh. Phần trích dẫn thư cũ (.gq / .gmail_quote / blockquote cite) thu gọn sau nút "…".
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as hp;
import '../links.dart' show openInSystem;

/// Chữ thuần của HTML (đoạn trích, trích dẫn khi trả lời).
String htmlToText(String html) {
  final doc = hp.parse(html);
  doc.querySelectorAll('style,script,head').forEach((e) => e.remove());
  final b = StringBuffer();
  void walk(dom.Node n) {
    if (n is dom.Text) {
      b.write(n.text.replaceAll(RegExp(r'\s+'), ' '));
    } else if (n is dom.Element) {
      final t = n.localName;
      if (t == 'br') b.write('\n');
      for (final c in n.nodes) {
        walk(c);
      }
      if (const {'p', 'div', 'li', 'tr', 'h1', 'h2', 'h3', 'h4', 'blockquote'}.contains(t)) b.write('\n');
    }
  }

  walk(doc.body ?? doc.documentElement!);
  return b.toString().replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Ảnh trong thân thư mở được bằng trình xem (đúng thứ tự trong thư): ảnh dán trong thư (/mail/api/attachments/...),
/// ảnh từ mạng khi [loadImages]. Bỏ ảnh theo dõi / biểu tượng nhỏ (rộng hoặc cao ≤ 48px).
List<String> mailBodyImages(String html, {bool loadImages = false}) {
  final out = <String>[];
  for (final e in hp.parse(html).querySelectorAll('img')) {
    final src = e.attributes['src'] ?? '';
    if (!_viewable(e) || out.contains(src)) continue;
    if (src.startsWith('/mail/api/attachments/') || (loadImages && (src.startsWith('https://') || src.startsWith('http://')))) out.add(src);
  }
  return out;
}

bool _viewable(dom.Element e) {
  final w = double.tryParse(e.attributes['width'] ?? ''), h = double.tryParse(e.attributes['height'] ?? '');
  return !((w != null && w <= 48) || (h != null && h <= 48));
}

/// href của link trong thư thành Uri mở được: http(s), mailto, tel; "www.…" không có giao thức thì thêm https.
/// Link khác (javascript:, file:, đường dẫn tương đối…) bỏ qua.
Uri? mailLinkUri(String href) {
  var h = href.trim();
  if (h.toLowerCase().startsWith('www.')) h = 'https://$h';
  final u = Uri.tryParse(h);
  if (u == null || !(u.isScheme('http') || u.isScheme('https') || u.isScheme('mailto') || u.isScheme('tel'))) return null;
  return u;
}

bool _isQuote(dom.Element e) =>
    e.classes.contains('gq') || e.classes.contains('gmail_quote') || (e.localName == 'blockquote' && e.attributes['type'] == 'cite');

class MailHtml extends StatefulWidget {
  const MailHtml(this.html, {super.key, this.style, this.loadImages = false, this.onLink, this.inlineImage, this.onImageTap});
  final String html;
  /// Bấm một ảnh xem được (xem [mailBodyImages]): mở trình xem ảnh tại ảnh [src].
  final void Function(String src)? onImageTap;
  /// Tải ảnh dán trong thư (đường dẫn /mail/api/attachments/..., có đăng nhập). Luôn hiện, vì là tệp của chính thư.
  final Future<Uint8List?> Function(String path)? inlineImage;
  final TextStyle? style;
  /// Cho tải ảnh từ mạng (mặc định tắt để không bị theo dõi mở thư).
  final bool loadImages;
  final void Function(Uri url)? onLink;

  @override
  State<MailHtml> createState() => _MailHtmlState();
}

class _MailHtmlState extends State<MailHtml> {
  bool _showQuote = false;
  final _inline = <String, Future<Uint8List?>>{};
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _open(String href) {
    final u = mailLinkUri(href);
    if (u == null) return;
    if (widget.onLink != null) {
      widget.onLink!(u);
    } else {
      openInSystem(u);
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final base = widget.style ?? DefaultTextStyle.of(context).style.copyWith(fontSize: 14.5, height: 1.5);
    final doc = hp.parse(widget.html);
    doc.querySelectorAll('style,script,head,title,meta').forEach((e) => e.remove());
    final body = doc.body ?? doc.documentElement!;
    final quotes = body.querySelectorAll('*').where(_isQuote).toList();
    final hasQuote = quotes.isNotEmpty;
    if (hasQuote && !_showQuote) {
      for (final q in quotes) {
        q.remove();
      }
    }
    final blocks = _Builder(context, base, _open, _recognizers, widget.loadImages, widget.inlineImage, _inline, widget.onImageTap).blocks(body.nodes);
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...blocks,
        if (hasQuote)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Tooltip(
              message: _showQuote ? 'Ẩn nội dung đã cắt bớt' : 'Hiện nội dung đã cắt bớt',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showQuote = !_showQuote),
                child: Container(
                  width: 30,
                  height: 18,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.more_horiz, size: 16),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Builder {
  _Builder(this.context, this.base, this.open, this.recognizers, this.loadImages, [this.inlineImage, this.inlineCache = const {}, this.onImageTap]);
  final void Function(String src)? onImageTap;
  final Future<Uint8List?> Function(String path)? inlineImage;
  final Map<String, Future<Uint8List?>> inlineCache;
  final BuildContext context;
  final TextStyle base;
  final void Function(String href) open;
  final List<TapGestureRecognizer> recognizers;

  /// Link đang bao quanh (thẻ <a>): mọi chữ bên trong mang recognizer này (Flutter chỉ nhận chạm ở đoạn chữ lá,
  /// recognizer đặt ở TextSpan cha thì chữ con không bấm được, nên trước đây bấm link trong thư không làm gì);
  /// ảnh bên trong mở link thay vì trình xem ảnh.
  TapGestureRecognizer? _rec;
  String? _href;
  final bool loadImages;

  static const _blockTags = {'p', 'div', 'section', 'article', 'header', 'footer', 'main', 'center', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'blockquote', 'table', 'hr', 'pre', 'img', 'tbody', 'thead', 'tr'};

  Color get _link => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8AB4F8) : const Color(0xFF1A5FD0);

  List<Widget> blocks(List<dom.Node> nodes, {TextStyle? style}) {
    final st = style ?? base;
    final out = <Widget>[];
    var inline = <InlineSpan>[];
    void flush() {
      // bỏ khoảng trắng thừa đầu / cuối đoạn
      if (inline.isEmpty) return;
      final text = TextSpan(style: st, children: inline);
      if (text.toPlainText().trim().isNotEmpty || inline.any((s) => s is WidgetSpan)) {
        out.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: Text.rich(text)));
      }
      inline = [];
    }

    for (final n in nodes) {
      if (n is dom.Element && _blockTags.contains(n.localName)) {
        flush();
        final w = block(n, st);
        if (w != null) out.add(w);
      } else {
        final s = span(n, st);
        if (s != null) inline.add(s);
      }
    }
    flush();
    return out;
  }

  Widget? block(dom.Element e, TextStyle st) {
    final tag = e.localName;
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final size = {'h1': 22.0, 'h2': 20.0, 'h3': 18.0}[tag] ?? 16.0;
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text.rich(TextSpan(children: [for (final c in e.nodes) ?span(c, st)], style: st.copyWith(fontSize: size, fontWeight: FontWeight.w600))));
      case 'hr':
        return const Divider(height: 24);
      case 'img':
        return _img(e);
      case 'pre':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(e.text, style: st.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'], fontSize: 13)),
        );
      case 'ul' || 'ol':
        var i = 0;
        final items = e.children.where((c) => c.localName == 'li').map((li) {
          i++;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 22, child: Text(tag == 'ol' ? '$i.' : '•', style: st)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _trimBottom(blocks(li.nodes, style: st)))),
            ]),
          );
        }).toList();
        return Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: items));
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.only(bottom: 10, left: 2),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks(e.nodes, style: st.copyWith(color: st.color?.withValues(alpha: .75)))),
        );
      case 'table' || 'tbody' || 'thead':
        // Only this table's own rows (nested tables are drawn by their cell, not again here).
        final rows = [
          for (final c in e.children)
            if (c.localName == 'tr') c else if (c.localName == 'tbody' || c.localName == 'thead' || c.localName == 'tfoot') ...c.children.where((r) => r.localName == 'tr'),
        ];
        // Bảng dàn trang của thư quảng cáo: vẽ từng ô thành khối dọc cho dễ đọc trên điện thoại.
        // Ô rộng 1-2px chỉ là đường kẻ (chữ trong đó vốn bị che), bỏ qua.
        final cells = rows.expand((r) => r.children.where((c) => (c.localName == 'td' || c.localName == 'th') && !_hairline(c))).toList();
        if (cells.isEmpty) return null;
        final simple = rows.every((r) => r.children.length <= 4) && cells.every((c) => c.querySelector('table') == null) && rows.length > 1 && rows.first.children.length > 1;
        if (simple) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(color: Theme.of(context).dividerColor),
                children: [
                  for (final r in rows)
                    TableRow(children: [
                      for (var i = 0; i < rows.map((x) => x.children.length).reduce((a, b) => a > b ? a : b); i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: i < r.children.length ? Text.rich(TextSpan(children: [for (final c in r.children[i].nodes) ?span(c, st)], style: r.children[i].localName == 'th' ? st.copyWith(fontWeight: FontWeight.w600) : st)) : const SizedBox(),
                        ),
                    ]),
                ],
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in cells) ...blocks(c.nodes, style: st)]);
      case 'tr':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in e.children) ...blocks(c.nodes, style: st)]);
      default:
        final kids = blocks(e.nodes, style: _styled(e, st));
        if (kids.isEmpty) return null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids);
    }
  }

  List<Widget> _trimBottom(List<Widget> ws) => [
        for (final w in ws) w is Padding && w.padding == const EdgeInsets.only(bottom: 10) ? Padding(padding: EdgeInsets.zero, child: w.child) : w,
      ];

  TextStyle _styled(dom.Element e, TextStyle st) {
    var s = st;
    final css = (e.attributes['style'] ?? '').toLowerCase();
    if (css.contains('font-weight:bold') || css.contains('font-weight: bold') || RegExp(r'font-weight:\s*[6-9]00').hasMatch(css)) s = s.copyWith(fontWeight: FontWeight.w700);
    if (css.contains('italic')) s = s.copyWith(fontStyle: FontStyle.italic);
    final fs = RegExp(r'font-size:\s*(\d+)px').firstMatch(css);
    if (fs != null) {
      final px = double.parse(fs.group(1)!);
      if (px >= 9 && px <= 28) s = s.copyWith(fontSize: px);
    }
    if (css.contains('color:#888') || css.contains('color: #888') || css.contains('color:gray') || css.contains('color:grey')) s = s.copyWith(color: s.color?.withValues(alpha: .6));
    return s;
  }

  InlineSpan? span(dom.Node n, TextStyle st) {
    if (n is dom.Text) {
      final t = n.text.replaceAll(RegExp(r'\s+'), ' ');
      return t.isEmpty ? null : TextSpan(text: t, recognizer: _rec, mouseCursor: _rec == null ? null : SystemMouseCursors.click);
    }
    if (n is! dom.Element) return null;
    final tag = n.localName;
    if (tag == 'br') return const TextSpan(text: '\n');
    if (tag == 'img') return WidgetSpan(child: _img(n) ?? const SizedBox());
    if (_blockTags.contains(tag)) {
      // khối lồng trong chữ (thư viết tay lộn xộn): xuống dòng rồi vẽ chữ của nó.
      return TextSpan(children: [const TextSpan(text: '\n'), for (final c in n.nodes) ?span(c, st), const TextSpan(text: '\n')]);
    }
    var s = _styled(n, const TextStyle());
    TapGestureRecognizer? rec;
    switch (tag) {
      case 'b' || 'strong':
        s = s.copyWith(fontWeight: FontWeight.w700);
      case 'i' || 'em':
        s = s.copyWith(fontStyle: FontStyle.italic);
      case 'u' || 'ins':
        s = s.copyWith(decoration: TextDecoration.underline);
      case 's' || 'strike' || 'del':
        s = s.copyWith(decoration: TextDecoration.lineThrough);
      case 'code' || 'kbd':
        s = s.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono']);
      case 'small':
        s = s.copyWith(fontSize: (st.fontSize ?? 14) * .85);
      case 'a':
        final href = n.attributes['href'];
        if (href != null && href.trim().isNotEmpty && mailLinkUri(href) != null) {
          s = s.copyWith(color: _link, decoration: TextDecoration.underline, decorationColor: _link);
          rec = TapGestureRecognizer()..onTap = () => open(href);
          recognizers.add(rec);
        }
    }
    if (rec == null) return TextSpan(style: s, children: [for (final c in n.nodes) ?span(c, st)]);
    final (prevRec, prevHref) = (_rec, _href);
    _rec = rec;
    _href = n.attributes['href'];
    try {
      return TextSpan(style: s, recognizer: rec, mouseCursor: SystemMouseCursors.click, children: [for (final c in n.nodes) ?span(c, st)]);
    } finally {
      _rec = prevRec;
      _href = prevHref;
    }
  }

  static bool _hairline(dom.Element c) {
    final w = double.tryParse(c.attributes['width'] ?? '');
    final st = (c.attributes['style'] ?? '').replaceAll(' ', '');
    return (w != null && w <= 2) || RegExp(r'(^|;)width:[0-2](\.\d+)?px').hasMatch(st);
  }

  Widget? _img(dom.Element e) {
    final src = e.attributes['src'] ?? '';
    final alt = e.attributes['alt'] ?? '';
    final w = double.tryParse(e.attributes['width'] ?? '');
    if (w != null && w <= 2) return null; // ảnh theo dõi 1x1
    final tap = onImageTap, href = _href;
    // Ảnh nằm trong link (banner, nút bản tin): bấm mở link. Ảnh thường, không phải biểu tượng nhỏ: bấm để xem phóng to.
    Widget tappable(Widget img) => href != null
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(key: ValueKey('mail-img-link-$src'), behavior: HitTestBehavior.opaque, onTap: () => open(href), child: img),
          )
        : tap == null || !_viewable(e)
            ? img
            : MouseRegion(
                cursor: SystemMouseCursors.zoomIn,
                child: GestureDetector(key: ValueKey('mail-img-$src'), behavior: HitTestBehavior.opaque, onTap: () => tap(src), child: img),
              );
    final load = inlineImage;
    if (load != null && src.startsWith('/mail/api/attachments/')) {
      return tappable(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: w ?? 600),
          child: FutureBuilder<Uint8List?>(
            future: inlineCache.putIfAbsent(src, () => load(src)),
            builder: (context, snap) => snap.data != null
                ? Image.memory(snap.data!, errorBuilder: (_, _, _) => _altBox(alt.isEmpty ? 'Ảnh' : alt))
                : snap.connectionState == ConnectionState.done
                    ? _altBox(alt.isEmpty ? 'Ảnh' : alt)
                    : const SizedBox(width: 48, height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ),
      ));
    }
    if (loadImages && (src.startsWith('https://') || src.startsWith('http://'))) {
      return tappable(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: w ?? 600), child: Image.network(src, errorBuilder: (_, _, _) => _altBox(alt))),
      ));
    }
    // Ảnh ngoài chưa cho tải: ảnh nhỏ (biểu tượng chữ ký) không chiếm chỗ; ảnh lớn để một ô thay thế.
    final h = double.tryParse(e.attributes['height'] ?? '');
    if ((w != null && w <= 48) || (h != null && h <= 48)) return null;
    return alt.isEmpty && !src.startsWith('http') ? null : _altBox(alt.isEmpty ? 'Ảnh' : alt);
  }

  Widget _altBox(String alt) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_outlined, size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: 6),
          Flexible(child: Text(alt, style: base.copyWith(fontSize: 12.5, color: Theme.of(context).hintColor), overflow: TextOverflow.ellipsis)),
        ]),
      );
}
