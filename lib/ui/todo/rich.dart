// Todo: chữ có định dạng. RichController giữ định dạng từng ký tự của một khối (đoạn / dòng danh sách) và vẽ bằng
// buildTextSpan; blockView vẽ khối chỉ để xem (thẻ trên lưới).
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'look.dart';
import 'model.dart';

/// Ký tự rỗng đầu mỗi ô soạn: xoá được nó = bấm xoá ở đầu dòng (gộp với dòng trên), kể cả với bàn phím ảo
/// (bàn phím ảo không gửi phím Backspace khi ô đã trống).
const kZw = '​';

TextStyle runStyle(TFmt f, TextStyle base, bool dark) {
  var s = base;
  if (f.b) s = s.copyWith(fontWeight: FontWeight.w700);
  if (f.i) s = s.copyWith(fontStyle: FontStyle.italic);
  final deco = <TextDecoration>[if (f.u || f.a != null) TextDecoration.underline, if (f.s) TextDecoration.lineThrough];
  if (deco.isNotEmpty) s = s.copyWith(decoration: TextDecoration.combine(deco));
  if (f.c) s = s.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'], backgroundColor: (dark ? Colors.white : Colors.black).withValues(alpha: .08));
  final fg = kTextColors[f.fg];
  if (fg != null) s = s.copyWith(color: dark ? fg.$2 : fg.$1);
  if (f.a != null && fg == null) s = s.copyWith(color: dark ? const Color(0xFF8AB4F8) : const Color(0xFF1A5FD0));
  final hl = kTextColors[f.hl];
  if (hl != null) s = s.copyWith(backgroundColor: dark ? hl.$4 : hl.$3);
  return s;
}

/// Cỡ / đậm chữ theo kiểu khối.
TextStyle blockStyle(String t, TextStyle base) => switch (t) {
      'h1' => base.copyWith(fontSize: (base.fontSize ?? 15) * 1.5, fontWeight: FontWeight.w700, height: 1.25),
      'h2' => base.copyWith(fontSize: (base.fontSize ?? 15) * 1.28, fontWeight: FontWeight.w700, height: 1.3),
      'h3' => base.copyWith(fontSize: (base.fontSize ?? 15) * 1.1, fontWeight: FontWeight.w700),
      'quote' => base.copyWith(fontStyle: FontStyle.italic, color: base.color?.withValues(alpha: .8)),
      'code' => base.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'], fontSize: (base.fontSize ?? 15) * .92),
      _ => base,
    };

List<TFmt> _fmtsOf(List<TRun> runs) => [for (final r in runs) for (var i = 0; i < r.x.length; i++) r.f];

class RichController extends TextEditingController {
  RichController(List<TRun> runs, {this.dark = false})
      : _fmts = _fmtsOf(runs),
        super(text: kZw + runs.map((r) => r.x).join());

  List<TFmt> _fmts;
  bool dark;
  /// Định dạng cho chữ gõ tiếp (bấm B khi chưa chọn chữ).
  TFmt? pending;
  /// Xoá ký tự rỗng đầu ô (bấm xoá ở đầu dòng).
  VoidCallback? onBackspaceAtStart;
  /// Chữ đã đổi (không tính đổi chỗ con trỏ).
  VoidCallback? onEdited;

  String get body => text.startsWith(kZw) ? text.substring(1) : text;

  List<TRun> get runs {
    final out = <TRun>[];
    final b = body;
    for (var i = 0; i < b.length && i < _fmts.length; i++) {
      if (out.isNotEmpty && out.last.f == _fmts[i]) {
        out.last.x += b[i];
      } else {
        out.add(TRun(b[i], _fmts[i]));
      }
    }
    return out;
  }

  /// Định dạng ở con trỏ (để thanh công cụ sáng nút B / I…).
  TFmt get current {
    final s = selection;
    if (!s.isValid) return pending ?? TFmt.plain;
    if (s.isCollapsed) return pending ?? (s.start - 2 >= 0 && s.start - 2 < _fmts.length ? _fmts[s.start - 2].copyWith(a: null) : TFmt.plain);
    final i = (s.start - 1).clamp(0, _fmts.length);
    return i < _fmts.length ? _fmts[i] : TFmt.plain;
  }

  void setBody(List<TRun> runs, {int? cursor}) {
    _fmts = _fmtsOf(runs);
    final t = kZw + runs.map((r) => r.x).join();
    super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: (cursor ?? t.length).clamp(1, t.length)));
  }

  @override
  set value(TextEditingValue v) {
    final old = super.value.text;
    if (!v.text.startsWith(kZw)) {
      if (old.startsWith(kZw) && v.text == old.substring(1)) {
        // Chỉ xoá ký tự rỗng đầu ô: báo lên trên (gộp dòng / bỏ thụt lề), giữ nguyên chữ.
        super.value = TextEditingValue(text: old, selection: const TextSelection.collapsed(offset: 1));
        notifyListeners();
        scheduleMicrotask(() => onBackspaceAtStart?.call());
        return;
      }
      // Thay cả nội dung (chọn hết rồi gõ / xoá): thêm lại ký tự rỗng đầu.
      v = TextEditingValue(
        text: kZw + v.text,
        selection: v.selection.isValid ? TextSelection(baseOffset: v.selection.baseOffset + 1, extentOffset: v.selection.extentOffset + 1) : v.selection,
        composing: v.composing.isValid ? TextRange(start: v.composing.start + 1, end: v.composing.end + 1) : TextRange.empty,
      );
    }
    // Con trỏ không đứng trước ký tự rỗng.
    if (v.selection.isValid && (v.selection.start < 1 || v.selection.end < 1)) {
      v = v.copyWith(selection: TextSelection(baseOffset: v.selection.baseOffset < 1 ? 1 : v.selection.baseOffset, extentOffset: v.selection.extentOffset < 1 ? 1 : v.selection.extentOffset));
    }
    final changed = v.text != old;
    if (changed) _adjust(old, v.text);
    super.value = v;
    if (changed) onEdited?.call();
  }

  /// Cập nhật định dạng theo phần chữ đổi (tiền tố / hậu tố chung). Chữ mới lấy định dạng chờ hoặc của ký tự đứng trước.
  void _adjust(String old, String nw) {
    var p = 0;
    final minLen = old.length < nw.length ? old.length : nw.length;
    while (p < minLen && old.codeUnitAt(p) == nw.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < minLen - p && old.codeUnitAt(old.length - 1 - s) == nw.codeUnitAt(nw.length - 1 - s)) {
      s++;
    }
    final start = (p - 1).clamp(0, _fmts.length);
    final removed = (old.length - s - p).clamp(0, _fmts.length - start);
    final added = nw.length - s - p;
    final inherit = pending ?? (start > 0 ? _fmts[start - 1].copyWith(a: null) : (start < _fmts.length ? _fmts[start].copyWith(a: null) : TFmt.plain));
    _fmts = [..._fmts.sublist(0, start), for (var i = 0; i < added; i++) inherit, ..._fmts.sublist(start + removed)];
    if (added > 0) pending = null;
  }

  void _apply(TFmt Function(TFmt) f) {
    final s = selection;
    if (!s.isValid) return;
    if (s.isCollapsed) {
      pending = f(current);
    } else {
      final a = (s.start - 1).clamp(0, _fmts.length), b = (s.end - 1).clamp(0, _fmts.length);
      for (var i = a; i < b; i++) {
        _fmts[i] = f(_fmts[i]);
      }
    }
    notifyListeners();
    onEdited?.call();
  }

  bool _all(bool Function(TFmt) has) {
    final s = selection;
    if (!s.isValid || s.isCollapsed) return has(current);
    final a = (s.start - 1).clamp(0, _fmts.length), b = (s.end - 1).clamp(0, _fmts.length);
    for (var i = a; i < b; i++) {
      if (!has(_fmts[i])) return false;
    }
    return b > a;
  }

  /// Bật / tắt b, i, u, s, c trên phần chọn (hoặc cho chữ gõ tiếp).
  void toggle(String k) {
    final on = !_all((f) => switch (k) { 'b' => f.b, 'i' => f.i, 'u' => f.u, 's' => f.s, _ => f.c });
    _apply((f) => switch (k) { 'b' => f.copyWith(b: on), 'i' => f.copyWith(i: on), 'u' => f.copyWith(u: on), 's' => f.copyWith(s: on), _ => f.copyWith(c: on) });
  }

  void setColor(String? fg) => _apply((f) => f.copyWith(fg: fg));
  void setHighlight(String? hl) => _apply((f) => f.copyWith(hl: hl));
  void setLink(String? url) => _apply((f) => f.copyWith(a: url));
  void clearFormat() => _apply((_) => TFmt.plain);

  /// Thay phần đang chọn bằng [s] (dán chữ thủ công).
  void insert(String s) {
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    final t = text.replaceRange(sel.start, sel.end, s);
    value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: sel.start + s.length));
  }

  /// Tách chữ tại các ký tự xuống dòng: trả về các đoạn (đoạn đầu ở lại ô này).
  List<List<TRun>> splitLines() {
    final b = body, out = <List<TRun>>[];
    var start = 0;
    for (var i = 0; i <= b.length; i++) {
      if (i == b.length || b[i] == '\n') {
        final seg = <TRun>[];
        for (var j = start; j < i && j < _fmts.length; j++) {
          if (seg.isNotEmpty && seg.last.f == _fmts[j]) {
            seg.last.x += b[j];
          } else {
            seg.add(TRun(b[j], _fmts[j]));
          }
        }
        out.add(seg);
        start = i + 1;
      }
    }
    return out;
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    return TextSpan(style: base, children: [
      const TextSpan(text: kZw),
      for (final r in runs) TextSpan(text: r.x, style: runStyle(r.f, base, dark)),
    ]);
  }
}

/// Chữ của một khối để xem (link bấm được).
InlineSpan runsSpan(List<TRun> runs, TextStyle base, bool dark, {bool links = true}) => TextSpan(style: base, children: [
      for (final r in runs)
        TextSpan(
          text: r.x,
          style: runStyle(r.f, base, dark),
          recognizer: links && r.f.a != null ? (TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(r.f.a!), mode: LaunchMode.externalApplication)) : null,
        ),
    ]);

/// Số thứ tự của khối "ol" thứ [i] trong [blocks] (đếm lại khi gặp khối khác hoặc thụt lề khác).
int olNumber(List<TBlock> blocks, int i) {
  var n = 1;
  for (var j = i - 1; j >= 0; j--) {
    final b = blocks[j];
    if (b.t == 'ol' && b.ind == blocks[i].ind) {
      n++;
    } else if (b.t == 'ol' && b.ind > blocks[i].ind) {
      continue;
    } else {
      break;
    }
  }
  return n;
}

/// Ký hiệu đầu dòng (gạch đầu dòng, số) — ô tick vẽ riêng vì bấm được.
Widget? bulletOf(List<TBlock> blocks, int i, TextStyle style) {
  final b = blocks[i];
  if (b.t == 'ul') return SizedBox(width: 22, child: Text(const ['•', '◦', '▪'][b.ind % 3], textAlign: TextAlign.center, style: style.copyWith(fontWeight: FontWeight.w700)));
  if (b.t == 'ol') return SizedBox(width: 26, child: Text('${olNumber(blocks, i)}.', textAlign: TextAlign.right, style: style));
  return null;
}
