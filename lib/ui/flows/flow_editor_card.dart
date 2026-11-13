import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../flygo_card.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowRed;
import 'flow_cond.dart';
import 'flow_editor.dart' show TemplateField;
import 'magic_sign_hooks.dart' show FlowSignEditor;

/// Soạn thẻ dữ liệu `flygo_card` cho các bước Gửi thẻ / Sửa thẻ: mọi chuỗi chèn được thông tin của việc, xem trước
/// ngay bằng chính widget thẻ của app với giá trị mẫu.

/// Biểu tượng của thẻ (khoá trong spec) → tên hiển thị.
const cardIcons = {
  'invoice': 'Hoá đơn',
  'debt': 'Công nợ',
  'incident': 'Sự cố',
  'sign': 'Ký số',
  'report': 'Báo cáo',
  'order': 'Đơn hàng',
  'attendance': 'Chấm công',
  'event': 'Lịch hẹn',
  'task': 'Công việc',
  'info': 'Thông báo',
};

/// Màu của thẻ / trạng thái (khoá trong spec) → tên và màu hiển thị.
const cardTones = {
  'green': ('Xanh lá', Color(0xFF16A34A)),
  'red': ('Đỏ', Color(0xFFDC2626)),
  'orange': ('Cam', Color(0xFFEA7A0C)),
  'blue': ('Xanh dương', Color(0xFF2563EB)),
  'purple': ('Tím', Color(0xFF7C3AED)),
  'gray': ('Xám', Color(0xFF6B7280)),
};

const cardStepStates = {'done': 'Xong', 'active': 'Đang làm', 'pending': 'Chưa tới', 'failed': 'Lỗi', 'skipped': 'Bỏ qua'};

const _fieldKinds = {'text': 'Chữ', 'money': 'Số tiền (đậm)', 'copy': 'Sao chép được', 'phone': 'Số điện thoại'};

/// Giá trị mẫu cho xem trước, theo kiểu thông tin.
String sampleValue(CondVar v) => switch (v.type) {
      'money' => '12.500.000 ₫',
      'number' => '12',
      'date' => '07/11/2026',
      'bool' => tr('Có'),
      'user' => 'Nguyễn An',
      'select' when v.options.isNotEmpty => v.options.first,
      _ => v.label.split(' › ').last,
    };

/// Thay mọi "{{...}}" trong [v] (chuỗi, danh sách, map lồng nhau) bằng giá trị mẫu.
Object? sampleCard(Object? v, List<CondVar> vars) {
  if (v is String) {
    return v.replaceAllMapped(RegExp(r'\{\{\s*([^}]*?)\s*\}\}'), (m) {
      final x = vars.where((x) => x.path == m.group(1)).firstOrNull;
      return x == null ? '…' : sampleValue(x);
    });
  }
  if (v is List) return [for (final x in v) sampleCard(x, vars)];
  if (v is Map) return {for (final e in v.entries) '${e.key}': sampleCard(e.value, vars)};
  return v;
}

/// Xem trước thẻ với giá trị mẫu. [card] thiếu tiêu đề thì hiện chữ "(chưa có tiêu đề)".
class CardPreview extends StatelessWidget {
  final Map<String, dynamic> card;
  final List<CondVar> vars;
  const CardPreview({super.key, required this.card, required this.vars});

  @override
  Widget build(BuildContext context) {
    final m = (sampleCard(card, vars) as Map).cast<String, dynamic>();
    m['v'] = 1;
    if ('${m['title'] ?? ''}'.trim().isEmpty) m['title'] = tr('(chưa có tiêu đề)');
    final pal = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.visibility_outlined, size: 16, color: pal.sub),
        const SizedBox(width: 6),
        Text(tr('Xem trước (giá trị mẫu)'), style: TextStyle(fontSize: 12.5, color: pal.sub, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 6),
      Center(child: FlygoCard(data: FlygoCardData(m), width: 320)),
    ]);
  }
}

/// Soạn thẻ: sửa trực tiếp [card] (map của node), gọi [onChanged] sau mỗi thay đổi. [partial]: dùng cho phần sửa
/// của bước Sửa thẻ (không bắt buộc tiêu đề; ô trống = giữ nguyên). [base]: thẻ gốc để xem trước khi sửa một phần.
class CardTemplateEditor extends StatefulWidget {
  final Map<String, dynamic> card;
  final List<CondVar> vars;
  final VoidCallback? onChanged;
  final bool partial;
  final Map<String, dynamic>? base;
  const CardTemplateEditor({super.key, required this.card, required this.vars, this.onChanged, this.partial = false, this.base});
  @override
  State<CardTemplateEditor> createState() => _CardTemplateEditorState();
}

class _CardTemplateEditorState extends State<CardTemplateEditor> {
  Map<String, dynamic> get c => widget.card;

  static Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
  static List<Map<String, dynamic>> _maps(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) _map(x)];

  // Phần con giữ cố định trong lúc soạn; phần rỗng không ghi vào thẻ (thẻ không hiện khung trống).
  late final status = _map(c['status']), hero = _map(c['hero']), stepsM = _map(c['steps']);
  late final fields = _maps(c['fields']), actions = _maps(c['actions']), rows = _maps(stepsM['rows']);

  @override
  void initState() {
    super.initState();
    if (!widget.partial) c['v'] = 1;
    _sync();
  }

  static bool _empty(Map m) => m.values.every((v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty));

  void _sync() {
    rows.isEmpty ? stepsM.remove('rows') : stepsM['rows'] = rows;
    for (final (k, m) in [('status', status), ('hero', hero), ('steps', stepsM)]) {
      _empty(m) ? c.remove(k) : c[k] = m;
    }
    for (final (k, l) in [('fields', fields), ('actions', actions)]) {
      l.isEmpty ? c.remove(k) : c[k] = l;
    }
  }

  void _changed([VoidCallback? f]) {
    setState(() {
      f?.call();
      _sync();
    });
    widget.onChanged?.call();
  }

  /// Đặt chuỗi [v] vào [m][k]; trống thì bỏ khoá.
  void _put(Map<String, dynamic> m, String k, String v) => _changed(() => v.trim().isEmpty ? m.remove(k) : m[k] = v);

  Widget _tpl(String label, Map<String, dynamic> m, String k, {int lines = 1, Key? key}) =>
      TemplateField(key: key, label: label, raw: '${m[k] ?? ''}', vars: widget.vars, lines: lines, onChanged: (v) => _put(m, k, v));

  Widget _tones(String? cur, ValueChanged<String?> pick, {bool allowNone = true}) => Wrap(spacing: 6, runSpacing: 6, children: [
        if (allowNone) ChoiceChip(label: Text(tr('Mặc định')), selected: cur == null || cur.isEmpty, onSelected: (_) => pick(null)),
        for (final e in cardTones.entries)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: e.value.$2, radius: 6),
            label: Text(tr(e.value.$1)),
            selected: cur == e.key,
            onSelected: (_) => pick(e.key),
          ),
      ]);

  Widget _section(String title, List<Widget> children, {bool open = false, String? sub}) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(top: 8),
        color: Pal.of(context).surface2,
        child: ExpansionTile(
          initiallyExpanded: open,
          shape: const Border(),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null || sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: children,
        ),
      );

  Widget _row(List<Widget> children, VoidCallback onDelete, {Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 6),
        decoration: BoxDecoration(border: Border.all(color: Pal.of(context).divider), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.close_rounded, size: 18), tooltip: tr('Xoá')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final preview = widget.base == null ? Map<String, dynamic>.of(c) : _merge(widget.base!, c);
    final children = <Widget>[
      _tpl(widget.partial ? tr('Tiêu đề (trống = giữ nguyên)') : tr('Tiêu đề thẻ *'), c, 'title'),
      const SizedBox(height: 10),
      _tpl(tr('Dòng phụ'), c, 'subtitle'),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: cardIcons.containsKey(c['icon']) ? '${c['icon']}' : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Biểu tượng thẻ'), border: const OutlineInputBorder()),
        items: [for (final e in cardIcons.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
        onChanged: (v) => _changed(() => c['icon'] = v),
      ),
      const SizedBox(height: 10),
      Text(tr('Màu chủ đạo'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      _tones(c['accent'] as String?, (v) => _changed(() => v == null ? c.remove('accent') : c['accent'] = v)),
      _section(tr('Trạng thái'), [
        _tpl(tr('Nhãn trạng thái (vd Chờ kế toán ký)'), status, 'label'),
        const SizedBox(height: 8),
        _tones(status['tone'] as String?, (v) => _changed(() => v == null ? status.remove('tone') : status['tone'] = v)),
      ], sub: '${status['label'] ?? ''}'),
      _section(tr('Số lớn'), [
        _tpl(tr('Giá trị (vd tổng tiền)'), hero, 'value'),
        const SizedBox(height: 8),
        _tpl(tr('Chú thích'), hero, 'label'),
      ], sub: '${hero['value'] ?? ''}'),
      _section(tr('Dòng thông tin'), [
        for (final f in fields)
          _row([
            _tpl(tr('Nhãn'), f, 'label'),
            const SizedBox(height: 6),
            _tpl(tr('Giá trị'), f, 'value'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _fieldKinds.containsKey(f['kind']) ? '${f['kind']}' : 'text',
              isDense: true,
              decoration: InputDecoration(labelText: tr('Kiểu'), isDense: true, border: const OutlineInputBorder()),
              items: [for (final e in _fieldKinds.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
              onChanged: (v) => _changed(() => v == 'text' ? f.remove('kind') : f['kind'] = v),
            ),
          ], () => _changed(() => fields.remove(f)), key: ObjectKey(f)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => _changed(() => fields.add({'label': '', 'value': ''})), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm dòng'))),
        ),
      ], sub: fields.isEmpty ? null : tr('{0} dòng', [fields.length])),
      _section(tr('Các bước'), [
        _tpl(tr('Tiêu đề khung bước (vd Tiến độ công việc)'), stepsM, 'title'),
        for (final r in rows)
          _row([
            _tpl(tr('Tên bước'), r, 'title'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: cardStepStates.containsKey(r['state']) ? '${r['state']}' : 'pending',
              isDense: true,
              decoration: InputDecoration(labelText: tr('Trạng thái'), isDense: true, border: const OutlineInputBorder()),
              items: [for (final e in cardStepStates.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
              onChanged: (v) => _changed(() => r['state'] = v),
            ),
            const SizedBox(height: 6),
            _tpl(tr('Dòng phụ (người, giờ)'), r, 'sub'),
          ], () => _changed(() => rows.remove(r)), key: ObjectKey(r)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _changed(() => rows.add({'title': '', 'state': rows.isEmpty ? 'active' : 'pending'})),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Thêm bước')),
          ),
        ),
      ], sub: rows.isEmpty ? null : tr('{0} bước', [rows.length])),
      _section(tr('Nút bấm'), [
        for (final a in actions)
          _row([
            TextFormField(
              initialValue: '${a['label'] ?? ''}',
              decoration: InputDecoration(labelText: tr('Chữ trên nút'), isDense: true, border: const OutlineInputBorder()),
              onChanged: (v) => _changed(() => a['label'] = v),
            ),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(tr('Chờ người bấm'))), ButtonSegment(value: true, label: Text(tr('Mở link')))],
              selected: {a.containsKey('url')},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _changed(() {
                if (v.first) {
                  a.remove('id');
                  a['url'] = '';
                } else {
                  a.remove('url');
                  a.remove('sign');
                  a['id'] = 'nut${actions.indexOf(a) + 1}';
                }
              }),
            ),
            const SizedBox(height: 6),
            if (a.containsKey('url')) ...[
              _tpl(tr('Link'), a, 'url', key: ValueKey('url-${identityHashCode(a)}')),
              FlowSignEditor(key: ValueKey('sign-${identityHashCode(a)}'), button: a, vars: widget.vars, onChanged: () => _changed(() {})),
            ] else
              TextFormField(
                key: ValueKey('id-${identityHashCode(a)}'),
                initialValue: '${a['id'] ?? ''}',
                decoration: InputDecoration(
                  labelText: tr('Mã nút'),
                  helperText: tr('Bước "Chờ bấm nút trên thẻ" nhận nút theo mã này'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => _changed(() => a['id'] = v.trim()),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(tr('Nút chính (nền màu)')),
              value: a['style'] == 'primary',
              onChanged: (v) => _changed(() => v == true ? a['style'] = 'primary' : a.remove('style')),
            ),
          ], () => _changed(() => actions.remove(a)), key: ObjectKey(a)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _changed(() => actions.add({'label': '', 'id': 'nut${actions.length + 1}'})),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Thêm nút')),
          ),
        ),
      ], sub: actions.isEmpty ? null : [for (final a in actions) '${a['label'] ?? ''}'].join(' · ')),
      _section(tr('Ghi chú và chân thẻ'), [
        _tpl(tr('Đoạn chữ tự do'), c, 'note', lines: 2),
        const SizedBox(height: 8),
        _tpl(tr('Chân thẻ (nguồn, mã phiếu)'), c, 'footer'),
      ]),
      if (!widget.partial && '${c['title'] ?? ''}'.trim().isEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('Thẻ cần có tiêu đề.'), style: const TextStyle(color: kFlowRed, fontSize: 12.5))),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
        child: CardPreview(card: preview, vars: widget.vars),
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Gộp sâu [patch] vào [base] (như máy chủ làm với bước Sửa thẻ): map gộp từng khoá, danh sách thay nguyên,
/// null xoá khoá.
Map<String, dynamic> _merge(Map<String, dynamic> base, Map<String, dynamic> patch) {
  final out = Map<String, dynamic>.of(base);
  for (final e in patch.entries) {
    if (e.value == null) {
      out.remove(e.key);
    } else if (e.value is Map && out[e.key] is Map) {
      out[e.key] = _merge((out[e.key] as Map).cast<String, dynamic>(), (e.value as Map).cast<String, dynamic>());
    } else {
      out[e.key] = e.value;
    }
  }
  return out;
}

/// Gộp phần sửa vào thẻ gốc (dùng chung cho xem trước và tóm tắt).
Map<String, dynamic> mergeCardPatch(Map<String, dynamic> base, Map<String, dynamic> patch) => _merge(base, patch);
