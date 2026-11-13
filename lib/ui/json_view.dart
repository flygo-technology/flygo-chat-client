import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';
import 'theme.dart';

/// JSON (object / mảng) trong chuỗi, hoặc null nếu chuỗi không phải JSON hợp lệ.
Object? tryParseJson(String text) {
  final t = text.trim();
  if (t.length < 2 || !((t.startsWith('{') && t.endsWith('}')) || (t.startsWith('[') && t.endsWith(']')))) return null;
  try {
    final v = jsonDecode(t);
    return v is Map || v is List ? v : null;
  } catch (_) {
    return null;
  }
}

enum JsonTok { key, string, number, literal, punct, space, more }

/// Một mẩu của JSON đã định dạng (thụt 2 dấu cách, giữ nguyên thứ tự khoá).
typedef JsonPiece = ({JsonTok kind, String text});

/// Các mẩu JSON đã định dạng. [maxDepth]: object / mảng sâu hơn mức này thu thành `{…}` / `[…]` (null = mở hết).
List<JsonPiece> jsonPieces(Object? v, {int? maxDepth}) {
  final out = <JsonPiece>[];
  void add(JsonTok k, String s) => out.add((kind: k, text: s));
  void walk(Object? x, int depth) {
    final pad = '  ' * depth;
    if (x is Map) {
      if (x.isEmpty) return add(JsonTok.punct, '{}');
      if (maxDepth != null && depth >= maxDepth) return add(JsonTok.more, '{…${x.length}}');
      add(JsonTok.punct, '{');
      var i = 0;
      for (final e in x.entries) {
        add(JsonTok.space, '\n$pad  ');
        add(JsonTok.key, jsonEncode('${e.key}'));
        add(JsonTok.punct, ': ');
        walk(e.value, depth + 1);
        if (++i < x.length) add(JsonTok.punct, ',');
      }
      add(JsonTok.space, '\n$pad');
      add(JsonTok.punct, '}');
    } else if (x is List) {
      if (x.isEmpty) return add(JsonTok.punct, '[]');
      if (maxDepth != null && depth >= maxDepth) return add(JsonTok.more, '[…${x.length}]');
      add(JsonTok.punct, '[');
      for (var i = 0; i < x.length; i++) {
        add(JsonTok.space, '\n$pad  ');
        walk(x[i], depth + 1);
        if (i < x.length - 1) add(JsonTok.punct, ',');
      }
      add(JsonTok.space, '\n$pad');
      add(JsonTok.punct, ']');
    } else if (x is String) {
      add(JsonTok.string, jsonEncode(x));
    } else if (x is num) {
      add(JsonTok.number, '$x');
    } else {
      add(JsonTok.literal, '$x'); // true / false / null
    }
  }

  walk(v, 0);
  return out;
}

/// Cắt còn [maxLines] dòng (thêm "…" ở cuối nếu bị cắt).
List<JsonPiece> limitLines(List<JsonPiece> ps, int maxLines) {
  final out = <JsonPiece>[];
  var lines = 1;
  for (final p in ps) {
    if (p.kind == JsonTok.space && p.text.startsWith('\n')) {
      if (++lines > maxLines) {
        out.add((kind: JsonTok.more, text: '\n…'));
        return out;
      }
    }
    out.add(p);
  }
  return out;
}

/// Màu tô của từng loại mẩu (khoá, chuỗi, số, true/false/null, dấu) theo nền sáng / tối.
Color jsonColor(JsonTok k, Brightness b, Pal pal) {
  final dark = b == Brightness.dark;
  return switch (k) {
    JsonTok.key => dark ? const Color(0xFF9CDCFE) : const Color(0xFF0451A5),
    JsonTok.string => dark ? const Color(0xFFCE9178) : const Color(0xFFA31515),
    JsonTok.number => dark ? const Color(0xFFB5CEA8) : const Color(0xFF098658),
    JsonTok.literal => dark ? const Color(0xFF569CD6) : const Color(0xFF0000FF),
    JsonTok.more => pal.accentText,
    _ => pal.sub,
  };
}

/// Khối JSON: định dạng đẹp, tô màu, chữ đơn cách, chọn được, nút sao chép; sâu quá 2 mức hoặc dài quá ~30 dòng
/// thì thu gọn kèm nút "Xem thêm". Chuỗi không phải JSON: dùng [JsonView.orPlain] để hiện chữ đơn cách thường.
class JsonView extends StatefulWidget {
  final Object? value;
  final double fontSize;
  final int collapseDepth;
  final int collapseLines;
  final Color? background;
  const JsonView({super.key, required this.value, this.fontSize = 12, this.collapseDepth = 2, this.collapseLines = 30, this.background});

  /// JSON hợp lệ → [JsonView]; không thì chữ đơn cách thường (chọn được).
  static Widget orPlain(String text, {double fontSize = 12, Color? color, int? maxLines, Color? background, EdgeInsets? padding}) {
    final v = tryParseJson(text);
    if (v != null) return JsonView(value: v, fontSize: fontSize, background: background);
    return Builder(builder: (context) {
      final pal = Pal.of(context);
      final style = TextStyle(fontFamily: 'monospace', fontSize: fontSize, color: color ?? pal.sub, height: 1.3);
      return Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: background ?? pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(6)),
        child: maxLines != null
            ? Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style)
            : SelectableText(text, style: style),
      );
    });
  }

  @override
  State<JsonView> createState() => _JsonViewState();
}

class _JsonViewState extends State<JsonView> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final b = Theme.of(context).brightness;
    final full = jsonPieces(widget.value);
    final short = limitLines(jsonPieces(widget.value, maxDepth: widget.collapseDepth), widget.collapseLines);
    final collapsible = short.length != full.length || short.any((p) => p.kind == JsonTok.more);
    final shown = _all || !collapsible ? full : short;
    final base = TextStyle(fontFamily: 'monospace', fontSize: widget.fontSize, height: 1.35, color: pal.text);
    final text = full.map((p) => p.text).join();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(color: widget.background ?? pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(6)),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 30, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            SelectableText.rich(
              TextSpan(style: base, children: [
                for (final p in shown) TextSpan(text: p.text, style: TextStyle(color: jsonColor(p.kind, b, pal))),
              ]),
            ),
            if (collapsible)
              InkWell(
                onTap: () => setState(() => _all = !_all),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_all ? tr('Thu gọn') : tr('Xem thêm'),
                      style: TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w600, color: pal.accentText)),
                ),
              ),
          ]),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: tr('Sao chép'),
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            icon: Icon(Icons.copy_rounded, color: pal.sub),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(tr('Đã sao chép'))));
            },
          ),
        ),
      ]),
    );
  }
}
