import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../theme.dart';

/// Trường "chọn từ danh mục" (vd mã linh kiện, khách hàng trong ERP): gõ thẳng trong ô, gợi ý xổ ngay bên dưới
/// (máy chủ Flows gọi tool MCP qua POST /flows/lookup). Máy tính: ↑ ↓ chọn, Enter nhận, Tab sang ô kế. Ô trống thì gợi
/// ý các mục vừa chọn gần đây; gõ / quét đúng một mã thì tự nhận. [onPicked] nhận {value, label, sub, data} để điền thêm.
class LookupField extends StatefulWidget {
  final FlowsApi api;
  final String flowId;
  /// `khoa`, `bang.cot` hoặc `<id bước>:khoa`.
  final String field;
  final String label;
  final String? value;
  final String hint;
  final String? error;
  final bool dense;
  final ValueChanged<Map<String, dynamic>> onPicked;
  const LookupField({
    super.key,
    required this.api,
    required this.flowId,
    required this.field,
    required this.label,
    required this.value,
    required this.onPicked,
    this.hint = '',
    this.error,
    this.dense = false,
  });

  @override
  State<LookupField> createState() => _LookupFieldState();
}

class _LookupFieldState extends State<LookupField> {
  /// Mục vừa chọn gần đây theo từng trường (trong phiên chạy app), tối đa 8.
  static final _recent = <String, List<Map<String, dynamic>>>{};
  late final _ctl = TextEditingController(text: widget.value ?? '');
  final _focus = FocusNode();
  List<Map<String, dynamic>> _last = const [];
  int _seq = 0;
  bool _loading = false;
  String? _err;

  String get _rk => '${widget.flowId}|${widget.field}';

  @override
  void initState() {
    super.initState();
    // Rời ô mà chưa chọn: trả về giá trị đã chọn (ô danh mục không nhận chữ tự do).
    _focus.addListener(() {
      if (!_focus.hasFocus && _ctl.text != (widget.value ?? '')) _ctl.text = widget.value ?? '';
    });
  }

  @override
  void didUpdateWidget(LookupField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) _ctl.text = widget.value ?? '';
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<Map<String, dynamic>>> _options(TextEditingValue v) async {
    final q = v.text.trim();
    final recent = _recent[_rk] ?? const <Map<String, dynamic>>[];
    if (q.isEmpty && recent.isNotEmpty) return recent;
    if (q.isNotEmpty && q == (widget.value ?? '')) return const [];
    final my = ++_seq;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (my != _seq) return _last;
    if (mounted) setState(() => _loading = true);
    try {
      final r = await widget.api.lookup(widget.flowId, widget.field, q);
      if (my == _seq) {
        _last = r;
        _err = null;
        // Gõ / quét / dán đúng một mã: nhận luôn.
        final exact = r.where((x) => '${x['value']}'.toLowerCase() == q.toLowerCase()).toList();
        if (q.isNotEmpty && exact.length == 1 && r.length == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _pick(exact.first, next: true));
        }
      }
    } catch (e) {
      if (my == _seq) _err = '$e';
    }
    if (mounted && my == _seq) setState(() => _loading = false);
    return _last;
  }

  void _pick(Map<String, dynamic> it, {bool next = false}) {
    final list = [it, ...?_recent[_rk]?.where((x) => x['value'] != it['value'])];
    _recent[_rk] = list.take(8).toList();
    _ctl.value = TextEditingValue(text: '${it['value']}', selection: TextSelection.collapsed(offset: '${it['value']}'.length));
    widget.onPicked(it);
    if (next) _focus.nextFocus();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return LayoutBuilder(
      builder: (context, box) => RawAutocomplete<Map<String, dynamic>>(
        textEditingController: _ctl,
        focusNode: _focus,
        optionsBuilder: _options,
        displayStringForOption: (o) => '${o['value']}',
        onSelected: (o) => _pick(o),
        fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
          controller: ctl,
          focusNode: focus,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: widget.dense ? null : widget.label,
            hintText: widget.hint.isEmpty ? tr('Gõ để tìm') : widget.hint,
            errorText: widget.error ?? _err,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                : const Icon(Icons.search_rounded, size: 20),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        optionsViewBuilder: (context, onSelected, options) {
          final list = options.toList();
          final q = _ctl.text.trim();
          final showingRecent = q.isEmpty && list.isNotEmpty;
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              color: pal.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 300, maxWidth: box.maxWidth < 280 ? 320 : box.maxWidth),
                child: list.isEmpty
                    ? Padding(padding: const EdgeInsets.all(14), child: Text(tr('Không thấy mục nào'), style: TextStyle(color: pal.sub)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: list.length + (showingRecent ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (showingRecent && i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                              child: Text(tr('Vừa chọn gần đây'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pal.sub)),
                            );
                          }
                          final it = list[i - (showingRecent ? 1 : 0)];
                          final hot = AutocompleteHighlightedOption.of(context) == i - (showingRecent ? 1 : 0);
                          final sub = [
                            if ('${it['label']}' != '${it['value']}') '${it['value']}',
                            if ('${it['sub'] ?? ''}'.isNotEmpty) '${it['sub']}',
                          ].join(' · ');
                          return InkWell(
                            onTap: () => onSelected(it),
                            child: Container(
                              color: hot ? pal.accent.withValues(alpha: 0.10) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${it['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
