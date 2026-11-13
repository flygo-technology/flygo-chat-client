import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange;
import 'flow_cond.dart';
import 'flow_editor_expr.dart';

/// Ô gõ biểu thức (điều kiện, Tính toán, Đặt biến): chèn thông tin (đường dẫn biến), chèn hàm, kiểm ngay khi gõ và
/// báo lỗi tiếng Việt; dưới ô hiện câu đọc được với tên thông tin.
class ExprField extends StatefulWidget {
  final String label;
  final String value;
  final List<CondVar> vars;
  final ValueChanged<String> onChanged;
  final int lines;
  final String? hint;
  const ExprField({super.key, required this.label, required this.value, required this.vars, required this.onChanged, this.lines = 2, this.hint});
  @override
  State<ExprField> createState() => _ExprFieldState();
}

class _ExprFieldState extends State<ExprField> {
  late final ctl = TextEditingController(text: widget.value);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _insert(String text) {
    final sel = ctl.selection;
    final at = sel.isValid ? sel.start : ctl.text.length;
    final end = sel.isValid ? sel.end : ctl.text.length;
    final before = ctl.text.substring(0, at);
    // Tách khỏi chữ đứng trước bằng dấu cách (tên biến được chứa "-", phép trừ cần dấu cách).
    final pad = before.isNotEmpty && !RegExp(r'[\s(\[,]$').hasMatch(before) ? ' ' : '';
    final t = '$pad$text';
    ctl.value = TextEditingValue(text: ctl.text.replaceRange(at, end, t), selection: TextSelection.collapsed(offset: at + t.length));
    widget.onChanged(ctl.text);
    setState(() {});
  }

  Widget _menuButton<T>(IconData icon, String label, List<PopupMenuEntry<T>> Function(BuildContext) items, ValueChanged<T> onPick) {
    final c = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onPick,
      itemBuilder: items,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final src = ctl.text;
    final check = src.trim().isEmpty ? null : checkExpr(src, known: [for (final v in widget.vars) v.path]);
    final shown = check != null && check.ok ? exprDisplay(src.trim(), (p) => widget.vars.where((v) => v.path == p).firstOrNull?.label ?? p) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: ctl,
        minLines: widget.lines,
        maxLines: widget.lines + 4,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint ?? tr('Vd form.so_tien * 1.08 > 50000000'),
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          errorText: check?.error,
          errorMaxLines: 3,
        ),
        onChanged: (v) {
          widget.onChanged(v);
          setState(() {});
        },
      ),
      if (check != null && check.ok)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(check.warning == null ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, size: 15, color: check.warning == null ? kFlowGreen : kFlowOrange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(check.warning ?? (shown == src.trim() ? tr('Biểu thức hợp lệ') : shown!),
                  style: TextStyle(fontSize: 12.5, color: check.warning == null ? pal.sub : kFlowOrange)),
            ),
          ]),
        ),
      Wrap(spacing: 14, children: [
        if (widget.vars.isNotEmpty)
          _menuButton<CondVar>(
            Icons.add_box_outlined,
            tr('Chèn thông tin'),
            (_) => [
              for (final v in widget.vars)
                PopupMenuItem(value: v, child: ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(v.label), subtitle: Text(v.path, style: const TextStyle(fontSize: 11)))),
            ],
            (v) => _insert(v.path),
          ),
        _menuButton<ExprFunc>(
          Icons.functions_rounded,
          tr('Hàm'),
          (_) => [
            for (final f in exprFuncs)
              PopupMenuItem(
                value: f,
                child: ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(f.template, style: const TextStyle(fontFamily: 'monospace')), subtitle: Text(tr(f.hint))),
              ),
          ],
          (f) => _insert(f.template),
        ),
      ]),
      Text(tr('Phép tính + - * / %, so sánh == != > >= < <=, and / or / not. Phép trừ cần dấu cách hai bên (a - b); chữ đặt trong dấu nháy.'),
          style: TextStyle(fontSize: 11.5, color: pal.sub)),
    ]);
  }
}
