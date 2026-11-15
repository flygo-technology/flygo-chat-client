// Wiki: hiển thị trang Markdown bằng widget native: tiêu đề, đoạn, danh sách (cả ô tick), trích dẫn, khối mã, bảng,
// đường kẻ, ảnh và tệp đính kèm của wiki (file:<id>), link tới trang khác (wiki:<id>) và link thường.
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../common.dart' show fileSize;
import '../theme.dart';
import 'api.dart';
import 'model.dart';

class WikiMarkdown extends StatelessWidget {
  const WikiMarkdown({super.key, required this.text, this.api, this.files = const [], this.onWikiLink, this.onFile, this.fontSize = 15.5});
  final String text;
  final WikiApi? api;
  /// Thông tin tệp mà trang nhắc tới (tên, kiểu, cỡ).
  final List<WFile> files;
  final void Function(String pageId)? onWikiLink;
  final void Function(WFile file)? onFile;
  final double fontSize;

  static final _doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);

  WFile _file(String id, String name) => files.firstWhere((f) => f.id == id, orElse: () => WFile({'id': id, 'name': name, 'mime': '', 'size': 0}));

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final base = TextStyle(fontSize: fontSize, height: 1.65, color: pal.text);
    final nodes = _doc.parse(text.replaceAll('\r\n', '\n'));
    final blocks = <Widget>[for (final n in nodes) ?_block(context, pal, n, base, 0)];
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < blocks.length; i++) ...[if (i > 0) const SizedBox(height: 12), blocks[i]],
      ]),
    );
  }

  Widget? _block(BuildContext context, Pal pal, md.Node node, TextStyle st, int depth) {
    if (node is md.Text) return Text.rich(TextSpan(children: _inline(context, pal, [node], st)));
    if (node is! md.Element) return null;
    final kids = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final size = const {'h1': 1.65, 'h2': 1.38, 'h3': 1.14, 'h4': 1.04, 'h5': 1.0, 'h6': .95}[node.tag]!;
        return Padding(
          padding: EdgeInsets.only(top: node.tag == 'h1' || node.tag == 'h2' ? 10 : 4),
          child: Text.rich(TextSpan(children: _inline(context, pal, kids, st.copyWith(fontSize: st.fontSize! * size, fontWeight: FontWeight.w700, height: 1.3)))),
        );
      case 'p':
        // Đoạn chỉ có một ảnh / một tệp đính kèm: hiện thành khối.
        final only = kids.where((k) => !(k is md.Text && k.text.trim().isEmpty)).toList();
        if (only.length == 1 && only.first is md.Element) {
          final e = only.first as md.Element;
          final src = e.tag == 'img' ? e.attributes['src'] ?? '' : e.tag == 'a' ? e.attributes['href'] ?? '' : '';
          if (src.startsWith('file:')) {
            final f = _file(src.substring(5), e.tag == 'img' ? e.attributes['alt'] ?? '' : e.textContent);
            return e.tag == 'img' || f.isImage ? _image(context, pal, f) : _fileCard(pal, f);
          }
        }
        return Text.rich(TextSpan(children: _inline(context, pal, kids, st)));
      case 'ul' || 'ol':
        return _list(context, pal, node, st, depth);
      case 'blockquote':
        return Container(
          decoration: BoxDecoration(color: pal.surface, border: Border(left: BorderSide(color: pal.accent, width: 3)), borderRadius: const BorderRadius.horizontal(right: Radius.circular(8))),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final k in kids) ?_block(context, pal, k, st.copyWith(color: pal.sub), depth),
          ]),
        );
      case 'pre':
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(node.textContent.replaceAll(RegExp(r'\n$'), ''), style: st.copyWith(fontFamily: 'monospace', fontSize: st.fontSize! * .87, height: 1.5)),
          ),
        );
      case 'hr':
        return Divider(height: 8, thickness: 1, color: pal.divider);
      case 'table':
        return _table(context, pal, node, st);
      default:
        return Text.rich(TextSpan(children: _inline(context, pal, kids, st)));
    }
  }

  Widget _list(BuildContext context, Pal pal, md.Element list, TextStyle st, int depth) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = (list.children ?? const <md.Node>[]).whereType<md.Element>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 26,
              child: _marker(pal, items[i], ordered ? '${start + i}.' : (depth == 0 ? '•' : '◦'), st),
            ),
            Expanded(child: _item(context, pal, items[i], st, depth)),
          ]),
        ),
    ]);
  }

  Widget _marker(Pal pal, md.Element li, String bullet, TextStyle st) {
    final box = (li.children ?? const []).whereType<md.Element>().where((e) => e.tag == 'input').firstOrNull;
    if (box != null) {
      final done = box.attributes.containsKey('checked');
      return Padding(
        padding: EdgeInsets.only(top: (st.fontSize! * st.height! - 18) / 2),
        child: Icon(done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18, color: done ? pal.accent : pal.sub),
      );
    }
    return Text(bullet, style: st.copyWith(color: pal.sub));
  }

  Widget _item(BuildContext context, Pal pal, md.Element li, TextStyle st, int depth) {
    final inline = <md.Node>[], blocks = <Widget>[];
    void flush() {
      if (inline.isEmpty) return;
      blocks.add(Text.rich(TextSpan(children: _inline(context, pal, [...inline], st))));
      inline.clear();
    }

    for (final k in li.children ?? const <md.Node>[]) {
      if (k is md.Element && k.tag == 'input') continue;
      if (k is md.Element && (k.tag == 'ul' || k.tag == 'ol')) {
        flush();
        blocks.add(_list(context, pal, k, st, depth + 1));
      } else if (k is md.Element && const {'p', 'pre', 'blockquote', 'table', 'h1', 'h2', 'h3'}.contains(k.tag)) {
        flush();
        final w = _block(context, pal, k, st, depth);
        if (w != null) blocks.add(w);
      } else {
        inline.add(k);
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks);
  }

  Widget _table(BuildContext context, Pal pal, md.Element table, TextStyle st) {
    final rows = <(bool, List<md.Element>)>[];
    for (final sec in (table.children ?? const <md.Node>[]).whereType<md.Element>()) {
      for (final tr in (sec.children ?? const <md.Node>[]).whereType<md.Element>()) {
        rows.add((sec.tag == 'thead', (tr.children ?? const <md.Node>[]).whereType<md.Element>().toList()));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.map((r) => r.$2.length).reduce((a, b) => a > b ? a : b);
    final cell = st.copyWith(fontSize: st.fontSize! * .92, height: 1.45);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: pal.divider),
        children: [
          for (final (head, r) in rows)
            TableRow(
              decoration: head ? BoxDecoration(color: pal.surface) : null,
              children: [
                for (var c = 0; c < cols; c++)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60, maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: c < r.length
                          ? Text.rich(TextSpan(children: _inline(context, pal, r[c].children ?? const [], head ? cell.copyWith(fontWeight: FontWeight.w700) : cell)))
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _inline(BuildContext context, Pal pal, List<md.Node> nodes, TextStyle st) {
    final out = <InlineSpan>[];
    for (final n in nodes) {
      if (n is md.Text) {
        out.add(TextSpan(text: n.text.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"'), style: st));
        continue;
      }
      if (n is! md.Element) continue;
      final kids = n.children ?? const <md.Node>[];
      switch (n.tag) {
        case 'strong':
          out.addAll(_inline(context, pal, kids, st.copyWith(fontWeight: FontWeight.w700)));
        case 'em':
          out.addAll(_inline(context, pal, kids, st.copyWith(fontStyle: FontStyle.italic)));
        case 'del':
          out.addAll(_inline(context, pal, kids, st.copyWith(decoration: TextDecoration.lineThrough)));
        case 'code':
          out.add(TextSpan(text: n.textContent, style: st.copyWith(fontFamily: 'monospace', fontSize: st.fontSize! * .88, backgroundColor: pal.surface)));
        case 'br':
          out.add(const TextSpan(text: '\n'));
        case 'a':
          final href = n.attributes['href'] ?? '';
          final link = st.copyWith(color: pal.accentText, decoration: TextDecoration.underline, decorationColor: pal.accentText.withValues(alpha: .5));
          final rec = TapGestureRecognizer()
            ..onTap = () {
              if (href.startsWith('wiki:')) {
                onWikiLink?.call(href.substring(5));
              } else if (href.startsWith('file:')) {
                onFile?.call(_file(href.substring(5), n.textContent));
              } else {
                final u = Uri.tryParse(href);
                if (u != null && (u.scheme == 'http' || u.scheme == 'https' || u.scheme == 'mailto' || u.scheme == 'tel')) launchUrl(u, mode: LaunchMode.externalApplication);
              }
            };
          if (href.startsWith('file:')) out.add(TextSpan(text: '📎 ', style: st));
          for (final s in _inline(context, pal, kids, link)) {
            out.add(s is TextSpan ? TextSpan(text: s.text, style: s.style, children: s.children, recognizer: rec, mouseCursor: SystemMouseCursors.click) : s);
          }
        case 'img':
          final src = n.attributes['src'] ?? '';
          if (src.startsWith('file:')) {
            out.add(WidgetSpan(child: SizedBox(height: 140, child: _image(context, pal, _file(src.substring(5), n.attributes['alt'] ?? ''), inline: true))));
          } else {
            out.add(TextSpan(text: n.attributes['alt'] ?? '', style: st.copyWith(color: pal.sub)));
          }
        default:
          out.addAll(_inline(context, pal, kids, st));
      }
    }
    return out;
  }

  Widget _image(BuildContext context, Pal pal, WFile f, {bool inline = false}) {
    final a = api;
    final ph = Container(
      height: inline ? 140 : 180,
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: pal.sub, size: 36),
    );
    if (a == null) return ph;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => onFile?.call(f),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: inline ? 140 : 480, maxWidth: inline ? 260 : double.infinity),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<Uint8List>(
                future: a.bytes(f.id),
                builder: (c, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.contain, errorBuilder: (_, _, _) => ph) : ph,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileCard(Pal pal, WFile f) {
    final ext = f.name.contains('.') ? f.name.split('.').last.toUpperCase() : 'TỆP';
    final color = switch (ext) { 'PDF' => const Color(0xFFE5484D), 'DOC' || 'DOCX' => const Color(0xFF2F6FDE), 'XLS' || 'XLSX' || 'CSV' => const Color(0xFF1E9C5A), 'PPT' || 'PPTX' => const Color(0xFFE07A2E), _ => pal.sub };
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onFile?.call(f),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Text(ext.length > 4 ? ext.substring(0, 4) : ext, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: pal.text)),
                if (f.size > 0) Text(fileSize(f.size), style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
            ),
            Icon(Icons.download_rounded, color: pal.sub),
          ]),
        ),
      ),
    );
  }
}
