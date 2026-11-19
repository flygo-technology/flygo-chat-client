import '../i18n/i18n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import 'common.dart';
import 'json_view.dart';
import 'links.dart';
import 'shell_highlight.dart' show CodeColors, kMonoFallback, kMonoFont, kNoLigatures, kReadingFont, shellSpan;
import 'theme.dart';

/// Hiển thị markdown của máy chủ chat thành widget: đoạn văn, tiêu đề, danh sách,
/// khối mã, trích dẫn, bảng, đường kẻ; trong dòng có đậm, nghiêng, gạch,
/// mã, link, @nhắc tên và :emoji:.
class MarkdownView extends StatelessWidget {
  final String text;
  final TextStyle style;
  /// Khoảng trống chừa ở cuối đoạn cuối cùng để đặt giờ gửi.
  final double trailingSpace;
  /// Bấm vào @tên.
  final void Function(String username)? onMention;
  /// Nội dung do người khác viết (Bảng tin): chỉ link http(s) / mailto / tel bấm được; đường dẫn tệp trên máy, file:,
  /// javascript:… hiện thành chữ thường.
  final bool safeLinks;
  const MarkdownView({super.key, required this.text, required this.style, this.trailingSpace = 0, this.onMention, this.safeLinks = false});

  static bool _safeHref(String href) {
    final u = Uri.tryParse(href.trim());
    return u != null && const {'http', 'https', 'mailto', 'tel'}.contains(u.scheme.toLowerCase());
  }

  /// Chữ thô của markdown (bỏ dấu định dạng, giữ xuống dòng giữa các khối và mục danh sách): đo / thu gọn nội dung.
  static String plain(String text) {
    final out = StringBuffer();
    void walk(md.Node n) {
      if (n is md.Text) {
        out.write(n.text);
        return;
      }
      if (n is! md.Element) return;
      const blocks = {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'pre', 'blockquote', 'tr', 'hr'};
      if (n.tag == 'br') out.write('\n');
      if (n.tag == 'input') out.write(n.attributes['checked'] != null ? '☑ ' : '☐ ');
      for (final c in n.children ?? const <md.Node>[]) {
        walk(c);
      }
      if (blocks.contains(n.tag) && !out.toString().endsWith('\n')) out.write('\n');
    }

    for (final n in _parse(text)) {
      walk(n);
    }
    return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Câu trả lời của trợ lý (kiểu chữ [aiAnswerStyle]): đoạn cách nhau rộng hơn, tiêu đề vừa phải, danh sách thụt
  /// thoáng, code dùng phông đơn cách đóng gói trong app.
  bool get _reading => style.fontFamily == kReadingFont;
  String get _mono => _reading ? kMonoFont : 'monospace';

  static final _mdLink = RegExp(r'\[[^\]\n]+\]\([^)\s]+\)');

  static final _doc = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );

  /// Kết quả phân tích markdown theo nội dung (danh sách chat dựng lại liên tục khi có tin mới / trợ lý sửa tin:
  /// không phân tích lại từng bong bóng mỗi lần). Giữ tối đa 400 nội dung gần nhất.
  static final _cache = <String, List<md.Node>>{};
  static List<md.Node> _parse(String text) {
    final hit = _cache.remove(text);
    if (hit != null) return _cache[text] = hit;
    final nodes = _doc.parse(replaceShortcodes(text));
    _cache[text] = nodes;
    if (_cache.length > 400) _cache.remove(_cache.keys.first);
    return nodes;
  }

  /// Tin chỉ có một đoạn văn bình thường (không có khối) thì hiển thị gọn trong dòng.
  static bool isSimple(String text) {
    // Có link markdown [tên](đường dẫn) thì dùng bộ hiển thị đầy đủ để chỉ hiện tên link.
    if (_mdLink.hasMatch(text)) return false;
    final nodes = _parse(text);
    return nodes.length == 1 && nodes.first is md.Element && (nodes.first as md.Element).tag == 'p';
  }

  static bool _isHeading(md.Node n) => n is md.Element && const {'h1', 'h2', 'h3', 'h4'}.contains(n.tag);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final nodes = _parse(text);
    final blocks = <Widget>[];
    final heads = <bool>[];
    for (var i = 0; i < nodes.length; i++) {
      final last = i == nodes.length - 1;
      final w = _block(context, pal, nodes[i], last ? trailingSpace : 0);
      if (w != null) {
        blocks.add(w);
        heads.add(_isHeading(nodes[i]));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < blocks.length; i++) ...[
        // Câu trả lời AI: dãn rộng như app Claude (Sếp, 2026-11-15); tiêu đề cách đoạn trên thêm một chút.
        if (i > 0) SizedBox(height: _reading ? (heads[i] ? 22 : 16) : 6),
        blocks[i],
      ],
    ]);
  }

  Widget? _block(BuildContext context, Pal pal, md.Node node, double trailing) {
    if (node is md.Text) return _para(pal, [node], style, trailing);
    if (node is! md.Element) return null;
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'p':
        return _para(pal, children, style, trailing);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final size = (_reading ? {'h1': 1.3, 'h2': 1.18, 'h3': 1.08} : {'h1': 1.35, 'h2': 1.25, 'h3': 1.15})[node.tag] ?? 1.05;
        return _para(pal, children,
            style.copyWith(fontSize: (style.fontSize ?? 17) * size, fontWeight: _reading ? FontWeight.w600 : FontWeight.w700, height: _reading ? 1.35 : null),
            trailing);
      case 'ul' || 'ol':
        return _list(context, pal, node, 0);
      case 'pre':
        final code = node.textContent.replaceAll(RegExp(r'\n$'), '');
        // Khối ```json (hoặc không ghi ngôn ngữ) chứa JSON hợp lệ: định dạng đẹp, tô màu, thu gọn được.
        final first = children.isNotEmpty ? children.first : null;
        final lang = first is md.Element ? (first.attributes['class'] ?? '').replaceFirst('language-', '').toLowerCase() : '';
        final json = lang.isEmpty || lang == 'json' || lang == 'jsonc' || lang == 'json5' ? tryParseJson(code) : null;
        if (json != null) return JsonView(value: json, fontSize: 13, background: pal.text.withValues(alpha: .07));
        return Stack(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 10, 34, 10),
            decoration: BoxDecoration(color: pal.text.withValues(alpha: _reading ? .05 : .07), borderRadius: BorderRadius.circular(_reading ? 10 : 8)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Builder(builder: (ctx) {
                final codeStyle = style.copyWith(
                    fontFamily: _mono, fontFamilyFallback: kMonoFallback, fontFeatures: kNoLigatures, fontSize: _reading ? 13 : 13.5, height: _reading ? 1.5 : 1.35);
                // Câu trả lời của trợ lý: khối ```bash / sh tô màu như thẻ lệnh.
                if (_reading && const {'bash', 'sh', 'shell', 'zsh', 'console'}.contains(lang)) {
                  return Text.rich(shellSpan(code, CodeColors.of(ctx), codeStyle.copyWith(fontStyle: FontStyle.normal, fontWeight: FontWeight.normal)));
                }
                return Text(code, style: codeStyle);
              }),
            ),
          ),
          // Nút sao chép cả khối code.
          Positioned(
            top: 2,
            right: 2,
            child: Builder(
              builder: (ctx) => IconButton(
                tooltip: tr('Sao chép'),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(Icons.copy_rounded, color: pal.sub),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(ctx).showSnackBar(toast(Text(tr('Đã sao chép'))));
                },
              ),
            ),
          ),
        ]);
      case 'blockquote':
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, decoration: BoxDecoration(color: pal.sub, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final c in children)
                  ?_block(context, pal, c, 0),
              ]),
            ),
          ]),
        );
      case 'hr':
        return Divider(color: pal.divider, height: 12);
      case 'table':
        return _table(pal, node);
      default:
        return _para(pal, children, style, trailing);
    }
  }

  Widget _para(Pal pal, List<md.Node> nodes, TextStyle st, double trailing) => Text.rich(
        TextSpan(children: [
          ..._inline(pal, nodes, st),
          if (trailing > 0) WidgetSpan(child: SizedBox(width: trailing, height: 12)),
        ]),
        style: st,
      );

  /// Dấu đầu dòng theo cấp: chấm đặc, tròn rỗng, vuông nhỏ rồi lặp lại (như app Claude / trình duyệt). Tự vẽ, không
  /// dùng ký tự "◦ ▪": nhiều phông (Roboto) không có, máy sẽ hiện ô vuông.
  Widget _bullet(int depth, Color color) {
    final size = (style.fontSize ?? 17) * .34;
    final kind = depth % 3;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kind == 1 ? null : color,
        shape: kind == 2 ? BoxShape.rectangle : BoxShape.circle,
        border: kind == 1 ? Border.all(color: color, width: 1.2) : null,
      ),
    );
  }

  /// Danh sách: mỗi mục một hàng "dấu | nội dung", dấu thẳng hàng với dòng chữ đầu của mục (căn theo baseline, kể cả
  /// khi mục mở đầu bằng emoji). Danh sách con nằm trong cột nội dung của mục cha nên tự thụt thêm một cấp.
  Widget _list(BuildContext context, Pal pal, md.Element list, int depth) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = (list.children ?? const <md.Node>[]).whereType<md.Element>().toList();
    // Cột dấu rộng đủ cho số có hai chữ số; cấp ngoài cùng thụt nhẹ so với lề đoạn văn.
    final lead = _reading ? (depth == 0 ? 10.0 : 12.0) : (depth == 0 ? 2.0 : 4.0);
    final slot = _reading ? 28.0 : (ordered ? 24.0 : 18.0);
    final last = '${start + items.length - 1}.';
    final numSlot = ordered && last.length > 3 ? slot + (last.length - 3) * 9 : slot;
    return Padding(
      padding: EdgeInsets.only(left: lead),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? (depth > 0 && _reading ? 4 : 0) : (_reading ? 6 : 2)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              SizedBox(
                width: numSlot,
                child: ordered
                    ? Text('${start + i}.', style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))
                    // Dấu vẽ nằm giữa chiều cao chữ của dòng đầu (Text giữ baseline để thẳng hàng với nội dung).
                    : Text.rich(TextSpan(children: [
                        const TextSpan(text: '\u200B'),
                        WidgetSpan(alignment: PlaceholderAlignment.middle, child: _bullet(depth, style.color ?? pal.text)),
                      ]), style: style),
              ),
              Expanded(child: _listItem(context, pal, items[i], depth)),
            ]),
          ),
      ]),
    );
  }

  /// Nội dung một mục: chữ trong dòng gộp thành đoạn; mục "lỏng" (nhiều đoạn), danh sách con, khối code, trích dẫn…
  /// hiện thành các khối riêng theo đúng thứ tự.
  Widget _listItem(BuildContext context, Pal pal, md.Element li, int depth) {
    final parts = <Widget>[];
    var inline = <md.Node>[];
    void flush() {
      if (inline.isEmpty) return;
      parts.add(_para(pal, inline, style, 0));
      inline = <md.Node>[];
    }

    for (final c in li.children ?? const <md.Node>[]) {
      if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) {
        flush();
        parts.add(_list(context, pal, c, depth + 1));
      } else if (c is md.Element && c.tag == 'p') {
        flush();
        inline.addAll(c.children ?? const []);
        flush();
      } else if (c is md.Element && c.tag == 'input') {
        inline.add(md.Text(c.attributes['checked'] != null ? '☑ ' : '☐ '));
      } else if (c is md.Element && const {'pre', 'blockquote', 'table', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(c.tag)) {
        flush();
        final w = _block(context, pal, c, 0);
        if (w != null) parts.add(Padding(padding: EdgeInsets.only(top: _reading ? 6 : 3), child: w));
      } else {
        inline.add(c);
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < parts.length; i++)
        // Các đoạn trong cùng một mục cách nhau như đoạn văn (danh sách con đã tự có khoảng cách).
        if (i > 0 && parts[i] is Text) Padding(padding: EdgeInsets.only(top: _reading ? 8 : 4), child: parts[i]) else parts[i],
    ]);
  }

  Widget _table(Pal pal, md.Element table) {
    final rows = <List<md.Element>>[];
    var header = 0;
    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      for (final tr in section.children ?? const <md.Node>[]) {
        if (tr is md.Element && tr.tag == 'tr') {
          rows.add((tr.children ?? const []).whereType<md.Element>().toList());
          if (section.tag == 'thead') header++;
        }
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: pal.divider, width: .8, borderRadius: BorderRadius.circular(6)),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: BoxDecoration(color: r < header ? pal.text.withValues(alpha: .06) : null),
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: c < rows[r].length
                        ? Text.rich(
                            TextSpan(
                                children: _inline(pal, rows[r][c].children ?? const [],
                                    r < header ? style.copyWith(fontWeight: FontWeight.w600) : style)),
                            style: (r < header ? style.copyWith(fontWeight: FontWeight.w600) : style)
                                .copyWith(fontSize: (style.fontSize ?? 17) - 2),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _inline(Pal pal, List<md.Node> nodes, TextStyle st) {
    final out = <InlineSpan>[];
    for (final n in nodes) {
      if (n is md.Text) {
        out.addAll(_mentions(pal, n.text));
        continue;
      }
      if (n is! md.Element) continue;
      final kids = n.children ?? const <md.Node>[];
      switch (n.tag) {
        case 'strong':
          // Câu trả lời của trợ lý (Inter): đậm vừa (600) như app Claude, Inter Bold quá nặng ở cỡ đọc.
          out.add(TextSpan(children: _inline(pal, kids, st), style: TextStyle(fontWeight: _reading ? FontWeight.w600 : FontWeight.w700)));
        case 'em':
          out.add(TextSpan(children: _inline(pal, kids, st), style: const TextStyle(fontStyle: FontStyle.italic)));
        case 'del':
          out.add(TextSpan(children: _inline(pal, kids, st), style: const TextStyle(decoration: TextDecoration.lineThrough)));
        case 'code':
          out.add(TextSpan(
            text: n.textContent,
            style: TextStyle(fontFamily: _mono, fontFamilyFallback: kMonoFallback, fontFeatures: kNoLigatures, fontSize: (st.fontSize ?? 17) - (_reading ? 2.5 : 2), backgroundColor: pal.text.withValues(alpha: .08)),
          ));
        case 'br':
          out.add(const TextSpan(text: '\n'));
        case 'a' when safeLinks && !_safeHref(n.attributes['href'] ?? ''):
          out.addAll(_inline(pal, kids, st));
        case 'img' when safeLinks && !_safeHref(n.attributes['src'] ?? ''):
          out.add(TextSpan(text: '🖼 ${n.attributes['alt'] ?? ''}'));
        case 'a':
          // Link markdown chỉ hiện tên, kèm nút sao chép / mở.
          final href = n.attributes['href'] ?? '';
          final phone = href.startsWith('tel:');
          final link = FoundLink(phone ? href.substring(4) : href, phone);
          out.add(TextSpan(
            text: n.textContent,
            style: TextStyle(color: pal.tick, decoration: TextDecoration.underline, decorationColor: pal.tick),
            mouseCursor: SystemMouseCursors.click,
            recognizer: TapGestureRecognizer()..onTap = link.open,
          ));
          out.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: InlineLinkButtons(link: link)));
        case 'img':
          final src = n.attributes['src'] ?? '';
          out.add(TextSpan(
            text: '🖼 ${n.attributes['alt']?.isNotEmpty == true ? n.attributes['alt'] : 'ảnh'}',
            style: TextStyle(color: pal.tick),
            recognizer: TapGestureRecognizer()..onTap = () => openInSystem(Uri.parse(src)),
          ));
        default:
          out.addAll(_inline(pal, kids, st));
      }
    }
    return out;
  }

  List<InlineSpan> _mentions(Pal pal, String text) {
    List<InlineSpan> plain(String t) => _reading && t.contains('\uFE0F') ? _emojiSpans(t, pal) : linkSpans(t, pal, (x) => mentionSpans(x, pal, onMention));
    if (!_reading || !_cite.hasMatch(text)) return plain(text);
    // Câu trả lời của trợ lý: trích dẫn [n] (Nghiên cứu sâu) hiện thành huy hiệu nhỏ.
    final out = <InlineSpan>[];
    var i = 0;
    for (final m in _cite.allMatches(text)) {
      if (m.start > i) out.addAll(plain(text.substring(i, m.start)));
      out.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: const Color(0xFFD97757).withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
          child: Text(m.group(1)!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97757))),
        ),
      ));
      i = m.end;
    }
    if (i < text.length) out.addAll(plain(text.substring(i)));
    return out;
  }

  static final _cite = RegExp(r'\[(\d{1,2})\]');

  /// Ký tự + U+FE0F ("↔️", "ℹ️", "1️⃣"): Inter có sẵn nét chữ của "↔", "ℹ"… nên máy vẽ thành chữ đen thay vì emoji.
  /// Ép các cụm này dùng phông emoji của hệ điều hành.
  static final _vs16 = RegExp('[^\uFE0F]\uFE0F\u20E3?');
  static const _emojiStyle = TextStyle(fontFamily: 'Apple Color Emoji', fontFamilyFallback: ['Noto Color Emoji', 'Segoe UI Emoji']);
  List<InlineSpan> _emojiSpans(String text, Pal pal) {
    final out = <InlineSpan>[];
    var i = 0;
    for (final m in _vs16.allMatches(text)) {
      if (m.start > i) out.addAll(linkSpans(text.substring(i, m.start), pal, (x) => mentionSpans(x, pal, onMention)));
      out.add(TextSpan(text: m.group(0), style: _emojiStyle));
      i = m.end;
    }
    if (i < text.length) out.addAll(linkSpans(text.substring(i), pal, (x) => mentionSpans(x, pal, onMention)));
    return out;
  }
}
