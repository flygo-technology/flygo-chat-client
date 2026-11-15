// Biểu mẫu: thẻ một câu hỏi trong trình soạn — thu gọn (xem như người điền) hoặc đang chọn (sửa tiêu đề, loại, lựa chọn,
// rẽ nhánh, thang đo, lưới, kiểm tra dữ liệu, tệp, bắt buộc).
import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';
import 'fill_page.dart' show FormImage;
import 'model.dart';
import 'widgets.dart';

class QuestionEditor extends StatefulWidget {
  const QuestionEditor({super.key, required this.item, required this.selected, required this.sections, required this.onChanged, required this.onAction, this.onTap, this.api, this.compact = false});
  final Json item;
  final bool selected, compact;
  final List<Json> sections;
  final ValueChanged<Json> onChanged;
  final ValueChanged<String> onAction;
  final VoidCallback? onTap;
  final FormsApi? api;
  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late bool _showDesc = '${widget.item['description'] ?? ''}'.isNotEmpty;
  late bool _branching = (widget.item['options'] as List? ?? const []).any((o) => (o as Map)['goto'] != null);
  late bool _showValidation = widget.item['validation'] != null;

  Json get it => widget.item;
  void _set(void Function(Json x) f) {
    final x = deepCopy(it);
    f(x);
    widget.onChanged(x);
  }

  @override
  Widget build(BuildContext context) {
    final color = FormTheme.of(context);
    if (!widget.selected) return FCard(onTap: widget.onTap, child: _collapsed());
    return FCard(left: color, child: _editing());
  }

  Widget _collapsed() {
    final p = Pal.of(context);
    if (!isQuestion(it)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ('${it['title'] ?? ''}'.isNotEmpty) Text('${it['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        if ('${it['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${it['description']}', style: TextStyle(color: p.sub))),
        if (it['type'] == 'image' && it['image'] != null && widget.api != null) FormImage(api: widget.api!, fileId: '${it['image']}'),
      ]);
    }
    final v = it['validation'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      reqTitle(context, '${it['title'] ?? ''}', it['required'] == true),
      if ('${it['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${it['description']}', style: TextStyle(color: p.sub, fontSize: 12.5))),
      const SizedBox(height: 8),
      IgnorePointer(child: QuestionPreview(item: it)),
      if (v != null || (it['options'] as List? ?? const []).any((o) => (o as Map)['goto'] != null))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if (v != null) Pill('Kiểm tra: ${_validationName(v)}', icon: Icons.rule),
            if ((it['options'] as List? ?? const []).any((o) => (o as Map)['goto'] != null)) const Pill('Rẽ nhánh theo câu trả lời', icon: Icons.alt_route),
          ]),
        ),
    ]);
  }

  String _validationName(Map v) => switch (v['kind']) {
        'email' => 'email',
        'phone' => 'số điện thoại Việt Nam',
        'url' => 'đường dẫn',
        'length' => 'độ dài',
        'regex' => 'biểu thức',
        'range' => 'khoảng số',
        'count' => 'số lựa chọn',
        _ => '${v['kind']}',
      };

  Widget _editing() {
    final p = Pal.of(context);
    final color = FormTheme.of(context);
    final type = '${it['type']}';
    final typePicker = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(border: Border.all(color: p.divider), borderRadius: BorderRadius.circular(6)),
      child: DropdownButton<String>(
        value: type,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [
          for (final t in [...kQuestionTypes, 'text', 'image'])
            if (t != 'image' || type == 'image')
              DropdownMenuItem(value: t, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(kTypeInfo[t]!.$2, size: 18, color: p.sub), const SizedBox(width: 8), Text(kTypeInfo[t]!.$1, style: const TextStyle(fontSize: 13.5))])),
        ],
        onChanged: (t) => t == null || t == type ? null : widget.onChanged(changeType(it, t)),
      ),
    );
    final title = TextFormField(
      key: ValueKey('t-${it['id']}'),
      initialValue: '${it['title'] ?? ''}',
      autofocus: '${it['title'] ?? ''}'.isEmpty,
      maxLines: null,
      style: TextStyle(fontSize: isQuestion(it) ? 15 : 18, fontWeight: isQuestion(it) ? FontWeight.w400 : FontWeight.w500),
      decoration: InputDecoration(
        hintText: isQuestion(it) ? 'Câu hỏi' : 'Tiêu đề',
        filled: true,
        fillColor: p.surface,
        border: UnderlineInputBorder(borderSide: BorderSide(color: color, width: 2)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: color, width: 2)),
      ),
      onChanged: (v) => _set((x) => x['title'] = v),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.compact) ...[title, const SizedBox(height: 10), typePicker] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: title), const SizedBox(width: 12), typePicker]),
      if (_showDesc || !isQuestion(it))
        TextFormField(
          key: ValueKey('d-${it['id']}'),
          initialValue: '${it['description'] ?? ''}',
          maxLines: null,
          style: TextStyle(fontSize: 13, color: p.sub),
          decoration: const InputDecoration(hintText: 'Mô tả', isDense: true),
          onChanged: (v) => _set((x) => v.isEmpty ? x.remove('description') : x['description'] = v),
        ),
      const SizedBox(height: 12),
      ..._body(),
      if (_showValidation && it['validation'] is! Map && _validationKinds().isNotEmpty) _validationEditor(),
      if (it['validation'] is Map) _validationEditor(),
      if (isQuestion(it) && it['key'] != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text('Mã câu hỏi: ${it['key']} (dùng trong Tự động hoá và khi xuất)', style: TextStyle(color: p.sub, fontSize: 11.5))),
      const SizedBox(height: 10),
      Divider(height: 1, color: p.divider),
      Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(tooltip: 'Chuyển lên', onPressed: () => widget.onAction('up'), icon: Icon(Icons.arrow_upward, color: p.sub)),
        IconButton(tooltip: 'Chuyển xuống', onPressed: () => widget.onAction('down'), icon: Icon(Icons.arrow_downward, color: p.sub)),
        IconButton(tooltip: 'Nhân bản', onPressed: () => widget.onAction('copy'), icon: Icon(Icons.content_copy_outlined, color: p.sub)),
        IconButton(tooltip: 'Xoá', onPressed: () => widget.onAction('delete'), icon: Icon(Icons.delete_outline, color: p.sub)),
        if (isQuestion(it)) ...[
          Container(width: 1, height: 26, color: p.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
          const Text('Bắt buộc', style: TextStyle(fontSize: 13.5)),
          Switch(value: it['required'] == true, activeTrackColor: color, onChanged: (v) => _set((x) => v ? x['required'] = true : x.remove('required'))),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: p.sub),
            onSelected: (a) => setState(() {
              if (a == 'desc') _showDesc = !_showDesc;
              if (a == 'branch') {
                _branching = !_branching;
                if (!_branching) _set((x) => [for (final o in (x['options'] as List? ?? const [])) (o as Map).remove('goto')]);
              }
              if (a == 'valid') {
                _showValidation = !_showValidation;
                if (!_showValidation) _set((x) => x.remove('validation'));
              }
              if (a == 'shuffle') _set((x) => x['shuffle'] == true ? x.remove('shuffle') : x['shuffle'] = true);
            }),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'desc', checked: _showDesc, child: const Text('Mô tả')),
              if (_validationKinds().isNotEmpty) CheckedPopupMenuItem(value: 'valid', checked: _showValidation || it['validation'] != null, child: const Text('Kiểm tra câu trả lời')),
              if ((type == 'choice' || type == 'dropdown') && widget.sections.length > 1)
                CheckedPopupMenuItem(value: 'branch', checked: _branching, child: const Text('Chuyển đến mục dựa trên câu trả lời')),
              if (type == 'choice' || type == 'checkbox' || type == 'dropdown') CheckedPopupMenuItem(value: 'shuffle', checked: it['shuffle'] == true, child: const Text('Xáo trộn thứ tự lựa chọn')),
            ],
          ),
        ],
      ]),
    ]);
  }

  List<String> _validationKinds() => switch (it['type']) {
        'short' => ['email', 'phone', 'url', 'length', 'regex', 'range'],
        'paragraph' => ['length', 'regex'],
        'number' => ['range'],
        'checkbox' => ['count'],
        _ => const [],
      };

  Widget _validationEditor() {
    final p = Pal.of(context);
    final v = Map<String, dynamic>.from(it['validation'] as Map? ?? {'kind': _validationKinds().first});
    void put(String k, Object? x) => _set((it) {
          final nv = Map<String, dynamic>.from(it['validation'] as Map? ?? v);
          if (x == null || x == '') {
            nv.remove(k);
          } else {
            nv[k] = x;
          }
          it['validation'] = nv;
        });
    Widget num(String k, String hint) => SizedBox(
          width: 90,
          child: TextFormField(
            key: ValueKey('v$k-${it['id']}'),
            initialValue: v[k] == null ? '' : '${v[k]}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(hintText: hint, isDense: true),
            onChanged: (s) => put(k, s.isEmpty ? null : double.tryParse(s.replaceAll(',', '.'))),
          ),
        );
    const names = {'email': 'Email', 'phone': 'Số điện thoại VN', 'url': 'Đường dẫn', 'length': 'Độ dài', 'regex': 'Biểu thức chính quy', 'range': 'Khoảng số', 'count': 'Số lựa chọn'};
    if (it['validation'] == null) WidgetsBinding.instance.addPostFrameCallback((_) => put('kind', v['kind']));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<String>(
          value: v['kind'] as String?,
          isDense: true,
          items: [for (final k in _validationKinds()) DropdownMenuItem(value: k, child: Text(names[k]!))],
          onChanged: (k) => _set((x) => x['validation'] = {'kind': k}),
        ),
        if (v['kind'] == 'length' || v['kind'] == 'range' || v['kind'] == 'count') ...[num('min', 'Tối thiểu'), num('max', 'Tối đa')],
        if (it['type'] == 'number' || v['kind'] == 'range')
          FilterChip(label: const Text('Số nguyên'), selected: v['integer'] == true, onSelected: (b) => put('integer', b ? true : null)),
        if (v['kind'] == 'regex')
          SizedBox(width: 200, child: TextFormField(key: ValueKey('vp-${it['id']}'), initialValue: '${v['pattern'] ?? ''}', decoration: const InputDecoration(hintText: 'Mẫu, vd ^NV\\d{3}\$', isDense: true), onChanged: (s) => put('pattern', s))),
        SizedBox(width: 220, child: TextFormField(key: ValueKey('vm-${it['id']}'), initialValue: '${v['message'] ?? ''}', decoration: const InputDecoration(hintText: 'Câu báo lỗi (không bắt buộc)', isDense: true), onChanged: (s) => put('message', s))),
      ]),
    );
  }

  List<Widget> _body() {
    final p = Pal.of(context);
    final type = '${it['type']}';
    switch (type) {
      case 'choice' || 'checkbox' || 'dropdown':
        final opts = (it['options'] as List? ?? const []).map((o) => Map<String, dynamic>.from(o as Map)).toList();
        final icon = type == 'checkbox' ? Icons.check_box_outline_blank : type == 'choice' ? Icons.radio_button_off : null;
        return [
          for (var i = 0; i < opts.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                if (icon != null) Icon(icon, size: 20, color: p.sub) else SizedBox(width: 20, child: Text('${i + 1}.', style: TextStyle(color: p.sub))),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('o-${opts[i]['id']}'),
                    initialValue: '${opts[i]['label']}',
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                    onChanged: (v) => _set((x) => (x['options'] as List)[i] = {...opts[i], 'label': v}),
                  ),
                ),
                if (_branching && type != 'checkbox') _gotoPicker(opts[i], i),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: opts.length <= 1 ? null : () => _set((x) => (x['options'] as List).removeAt(i)),
                  icon: Icon(Icons.close, size: 18, color: p.sub),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 4),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton(onPressed: () => _set((x) => (x['options'] as List).add({'id': newId(), 'label': 'Lựa chọn ${opts.length + 1}'})), child: const Text('Thêm lựa chọn')),
              if (type != 'dropdown' && it['other'] != true) ...[
                Text('hoặc', style: TextStyle(color: p.sub)),
                TextButton(onPressed: () => _set((x) => x['other'] = true), child: const Text('thêm "Khác"')),
              ],
              if (it['other'] == true) Pill('Có lựa chọn "Khác"', icon: Icons.close, onTap: () => _set((x) => x.remove('other'))),
            ]),
          ),
        ];
      case 'scale':
        final sc = Map<String, dynamic>.from(it['scale'] as Map? ?? {'min': 1, 'max': 5});
        return [
          Row(children: [
            DropdownButton<int>(value: sc['min'] as int? ?? 1, items: const [DropdownMenuItem(value: 0, child: Text('0')), DropdownMenuItem(value: 1, child: Text('1'))], onChanged: (v) => _set((x) => x['scale'] = {...sc, 'min': v})),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('đến')),
            DropdownButton<int>(value: sc['max'] as int? ?? 5, items: [for (var i = 2; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))], onChanged: (v) => _set((x) => x['scale'] = {...sc, 'max': v})),
          ]),
          for (final k in const [('min_label', 'Nhãn đầu thấp (không bắt buộc)'), ('max_label', 'Nhãn đầu cao (không bắt buộc)')])
            TextFormField(key: ValueKey('${k.$1}-${it['id']}'), initialValue: '${sc[k.$1] ?? ''}', decoration: InputDecoration(hintText: k.$2, isDense: true), onChanged: (v) => _set((x) => x['scale'] = {...Map<String, dynamic>.from(x['scale'] as Map), k.$1: v})),
        ];
      case 'grid_choice' || 'grid_checkbox':
        Widget lines(String key, String label) {
          final ls = (it[key] as List? ?? const []).map((o) => Map<String, dynamic>.from(o as Map)).toList();
          return Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              for (var i = 0; i < ls.length; i++)
                Row(children: [
                  Text('${i + 1}.', style: TextStyle(color: p.sub)),
                  const SizedBox(width: 6),
                  Expanded(child: TextFormField(key: ValueKey('$key-${ls[i]['id']}'), initialValue: '${ls[i]['label']}', decoration: const InputDecoration(isDense: true, border: InputBorder.none), onChanged: (v) => _set((x) => (x[key] as List)[i] = {...ls[i], 'label': v}))),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: ls.length <= 1 ? null : () => _set((x) => (x[key] as List).removeAt(i)), icon: Icon(Icons.close, size: 16, color: p.sub)),
                ]),
              TextButton(onPressed: () => _set((x) => (x[key] as List).add({'id': newId(), 'label': '${key == 'rows' ? 'Hàng' : 'Cột'} ${ls.length + 1}'})), child: Text('Thêm ${key == 'rows' ? 'hàng' : 'cột'}')),
            ]),
          );
        }
        return [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [lines('rows', 'Hàng'), const SizedBox(width: 16), lines('cols', 'Cột')])];
      case 'file':
        final fo = Map<String, dynamic>.from(it['file'] as Map? ?? {'max_files': 1, 'max_mb': 10});
        final types = [for (final t in (fo['types'] as List? ?? const [])) '$t'];
        return [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in kFileTypes.entries)
              FilterChip(
                label: Text(t.value),
                selected: types.contains(t.key),
                onSelected: (b) => _set((x) => x['file'] = {...fo, 'types': b ? [...types, t.key] : types.where((y) => y != t.key).toList()}),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Số tệp tối đa '),
            DropdownButton<int>(value: fo['max_files'] as int? ?? 1, items: [for (final n in const [1, 3, 5, 10]) DropdownMenuItem(value: n, child: Text('$n'))], onChanged: (v) => _set((x) => x['file'] = {...fo, 'max_files': v})),
            const SizedBox(width: 16),
            const Text('Dung lượng '),
            DropdownButton<int>(value: fo['max_mb'] as int? ?? 10, items: [for (final n in const [1, 10, 25, 100]) DropdownMenuItem(value: n, child: Text('$n MB'))], onChanged: (v) => _set((x) => x['file'] = {...fo, 'max_mb': v})),
          ]),
          Text(types.isEmpty ? 'Cho phép mọi loại tệp' : 'Chỉ nhận: ${types.map((t) => kFileTypes[t]).join(', ')}', style: TextStyle(color: p.sub, fontSize: 12)),
        ];
      case 'text' || 'image':
        return [if (type == 'image' && it['image'] != null && widget.api != null) FormImage(api: widget.api!, fileId: '${it['image']}')];
      default:
        return [IgnorePointer(child: QuestionPreview(item: it))];
    }
  }

  Widget _gotoPicker(Json o, int i) {
    final secs = widget.sections;
    final cur = '${o['goto'] ?? ''}';
    return DropdownButton<String>(
      value: cur.isEmpty || cur == 'submit' || secs.any((s) => s['id'] == cur) ? cur : '',
      isDense: true,
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12.5, color: Pal.of(context).text),
      items: [
        const DropdownMenuItem(value: '', child: Text('Tiếp tục mục kế')),
        for (var k = 0; k < secs.length; k++) DropdownMenuItem(value: '${secs[k]['id']}', child: Text('Đến mục ${k + 1}')),
        const DropdownMenuItem(value: 'submit', child: Text('Gửi biểu mẫu')),
      ],
      onChanged: (v) => _set((x) {
        final opt = Map<String, dynamic>.from((x['options'] as List)[i] as Map);
        if (v == null || v.isEmpty) {
          opt.remove('goto');
        } else {
          opt['goto'] = v;
        }
        (x['options'] as List)[i] = opt;
      }),
    );
  }
}

/// Câu hỏi hiển thị như người điền thấy (chỉ xem, trong trình soạn).
class QuestionPreview extends StatelessWidget {
  const QuestionPreview({super.key, required this.item});
  final Json item;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget line(String hint, [double w = 320]) => Container(
          width: w,
          padding: const EdgeInsets.only(bottom: 6, top: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider, width: 1.2))),
          child: Text(hint, style: TextStyle(color: p.sub)),
        );
    switch (item['type']) {
      case 'short':
        return line('Văn bản câu trả lời ngắn');
      case 'paragraph':
        return line('Văn bản câu trả lời dài', 520);
      case 'number':
        return line('Số', 160);
      case 'date':
        return line('Ngày / tháng / năm', 180);
      case 'time':
        return line('Giờ', 120);
      case 'datetime':
        return line('Ngày và giờ', 220);
      case 'file':
        return Row(children: [OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Thêm tệp'))]);
      case 'dropdown':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final (i, l) in optionLabels(item).indexed) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${i + 1}. $l'))]);
      case 'choice' || 'checkbox':
        final multi = item['type'] == 'checkbox';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in [...optionLabels(item), if (item['other'] == true) 'Khác…'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [Icon(multi ? Icons.check_box_outline_blank : Icons.radio_button_off, size: 20, color: p.sub), const SizedBox(width: 10), Flexible(child: Text(l))]),
            ),
        ]);
      case 'scale':
        final sc = item['scale'] as Map? ?? const {'min': 1, 'max': 5};
        return Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (var i = sc['min'] as int; i <= (sc['max'] as int); i++)
              Expanded(child: Column(children: [Text('$i', style: const TextStyle(fontSize: 13)), const SizedBox(height: 6), Icon(Icons.radio_button_off, size: 20, color: p.sub)])),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text('${sc['min_label'] ?? ''}', style: TextStyle(color: p.sub, fontSize: 11.5))),
            Flexible(child: Text('${sc['max_label'] ?? ''}', textAlign: TextAlign.right, style: TextStyle(color: p.sub, fontSize: 11.5))),
          ]),
        ]);
      case 'grid_choice' || 'grid_checkbox':
        final rows = lineLabels(item, 'rows'), cols = lineLabels(item, 'cols');
        return Text('Lưới ${rows.length} hàng × ${cols.length} cột: ${cols.join(' · ')}', style: TextStyle(color: p.sub));
    }
    return const SizedBox.shrink();
  }
}
