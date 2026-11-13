import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowRed;
import 'flow_cond.dart';

/// Nút / nhãn / tệp thêm trên thẻ chat (`card_extra` của bước, hoặc của quy trình cho thẻ trạng thái): như
/// `flows_engine::card_extra` của máy chủ.

/// Loại bước gửi thẻ chat (thẻ luồng).
const cardSendingTypes = {'notify', 'send', 'approval', 'approval_request', 'form_task', 'claim', 'wait_button', 'wait_choice'};

/// Loại bước gửi / tạo thẻ tiến trình (nút, nhãn dựng lại theo tiến trình).
bool processCardStep(Map n) => n['type'] == 'process_create' || n['type'] == 'process_send' || (n['type'] == 'send' && n['process'] != null);

const cardTagColors = {'red': 'Đỏ', 'orange': 'Cam', 'green': 'Xanh lá', 'blue': 'Xanh dương', 'gray': 'Xám'};
const _actions = {'url': 'Mở link', 'open': 'Mở tiến trình / tệp', 'copy': 'Sao chép', 'reply': 'Trả lời vào thẻ'};

Color tagColor(String? c) => switch (c) {
      'red' => const Color(0xFFE53935),
      'orange' => const Color(0xFFEF6C00),
      'green' => const Color(0xFF2E7D32),
      'blue' => const Color(0xFF1565C0),
      _ => const Color(0xFF757575),
    };

/// Lỗi của một nút (như lint máy chủ): null = được.
String? buttonError(Map b) {
  if ('${b['label'] ?? ''}'.trim().isEmpty) return tr('Chưa có chữ trên nút');
  final acts = _actions.keys.where((k) => b[k] != null).length;
  if (acts != 1) return tr('Chọn đúng một hành động');
  final u = b['url'];
  if (u is String && !u.trim().startsWith('https://') && !u.trim().startsWith('{{')) return tr('Link phải bắt đầu bằng https://');
  if (b['open'] != null && '${(b['open'] as Map?)?['process'] ?? ''}'.trim().isEmpty) return tr('Mở tiến trình cần mã tiến trình');
  return null;
}

/// Ô soạn nút / nhãn / tệp thêm. Sửa trực tiếp [owner] (`card_extra`). [process]: thẻ tiến trình (chỉ thông tin
/// `process.*`, không có tệp).
class CardExtraField extends StatefulWidget {
  final Map<String, dynamic> owner;
  final List<CondVar> vars;
  final bool process;
  final VoidCallback? onChanged;
  const CardExtraField({super.key, required this.owner, required this.vars, this.process = false, this.onChanged});
  @override
  State<CardExtraField> createState() => _CardExtraFieldState();
}

class _CardExtraFieldState extends State<CardExtraField> {
  Map<String, dynamic> get x => ((widget.owner['card_extra'] as Map?) ?? <String, dynamic>{}).cast<String, dynamic>();

  List<Map<String, dynamic>> _list(String k) => [for (final v in (x[k] as List? ?? const [])) if (v is Map) v.cast<String, dynamic>()];

  void _save(String k, List<Map<String, dynamic>> l) {
    final m = x;
    l.isEmpty ? m.remove(k) : m[k] = l;
    m.isEmpty ? widget.owner.remove('card_extra') : widget.owner['card_extra'] = m;
    setState(() {});
    widget.onChanged?.call();
  }

  List<CondVar> get _vars => widget.process ? [for (final v in widget.vars) if (v.path.startsWith('process.')) v] : widget.vars;

  Widget _text(String label, String value, ValueChanged<String> on, {Key? key, String? hint}) => TextFormField(
        key: key,
        initialValue: value,
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
        onChanged: on,
      );

  Widget _insert(ValueChanged<String> put) => PopupMenuButton<CondVar>(
        tooltip: tr('Chèn thông tin'),
        icon: const Icon(Icons.add_box_outlined, size: 18),
        onSelected: (v) => put('{{${v.path}}}'),
        itemBuilder: (_) => [for (final v in _vars) PopupMenuItem(value: v, child: Text(v.label))],
      );

  Widget _button(List<Map<String, dynamic>> l, int i) {
    final b = l[i];
    final act = _actions.keys.firstWhere((k) => b[k] != null, orElse: () => 'url');
    final err = buttonError(b);
    final value = act == 'open' ? '${(b['open'] as Map?)?['process'] ?? ''}' : '${b[act] ?? ''}';
    return Container(
      key: ValueKey('cx-b-$i-$act'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: err == null ? Pal.of(context).divider : kFlowRed), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _text(tr('Chữ trên nút'), '${b['label'] ?? ''}', (v) => _save('buttons', l..[i]['label'] = v), key: ValueKey('cx-bl-$i'))),
          IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => _save('buttons', l..removeAt(i))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          DropdownButton<String>(
            value: act,
            items: [for (final e in _actions.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
            onChanged: (v) {
              for (final k in [..._actions.keys, 'id']) {
                b.remove(k);
              }
              b[v ?? 'url'] = v == 'open' ? <String, dynamic>{'process': widget.process ? '{{process.id}}' : ''} : (v == 'url' ? 'https://' : '');
              _save('buttons', l);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _text(
              switch (act) { 'url' => tr('Link https://…'), 'open' => tr('Mã tiến trình'), 'copy' => tr('Chữ sao chép'), _ => tr('Chữ trả lời') },
              value,
              (v) => _save('buttons', l..[i][act] = act == 'open' ? {...?(b['open'] as Map?)?.cast<String, dynamic>(), 'process': v} : v),
              key: ValueKey('cx-bv-$i-$act'),
            ),
          ),
          _insert((t) => _save('buttons', l..[i][act] = act == 'open' ? {'process': t} : '$value$t')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          SegmentedButton<String>(
            segments: [ButtonSegment(value: 'secondary', label: Text(tr('Viền'))), ButtonSegment(value: 'primary', label: Text(tr('Nền màu')))],
            selected: {b['style'] == 'primary' ? 'primary' : 'secondary'},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _save('buttons', l..[i]['style'] = s.first),
          ),
          const SizedBox(width: 8),
          Expanded(child: _text(tr('Hỏi xác nhận (tuỳ chọn)'), '${b['confirm'] ?? ''}', (v) => _save('buttons', l..[i]['confirm'] = v), key: ValueKey('cx-bc-$i'))),
        ]),
        const SizedBox(height: 6),
        _text(tr('Chỉ hiện khi (biểu thức, tuỳ chọn)'), '${b['when'] ?? ''}', (v) => _save('buttons', l..[i]['when'] = v), key: ValueKey('cx-bw-$i'), hint: widget.process ? "process.state == 'running'" : null),
        if (err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(err, style: const TextStyle(color: kFlowRed, fontSize: 12.5))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final buttons = _list('buttons'), tags = _list('tags'), files = _list('files');
    final fileVars = [for (final v in widget.vars) if (v.type == 'files' || v.path.contains('download_url') || v.path.endsWith('.file_id')) v];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Nút, nhãn, tệp trên thẻ chat'), style: Theme.of(context).textTheme.labelLarge),
      Text(
        widget.process ? tr('Thẻ tiến trình tự cập nhật nút và nhãn mỗi khi tiến trình đổi; xong thì bỏ nút trả lời. Chỉ dùng thông tin của tiến trình.') : tr('Thêm vào thẻ mà bước này gửi.'),
        style: TextStyle(color: pal.sub, fontSize: 12.5),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < buttons.length; i++) _button(buttons, i),
      if (buttons.length < 4)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('cx-add-button'),
            onPressed: () => _save('buttons', buttons..add({'label': '', 'url': 'https://'})),
            icon: const Icon(Icons.smart_button_outlined, size: 18),
            label: Text(tr('Thêm nút trên thẻ')),
          ),
        ),
      const SizedBox(height: 4),
      for (var i = 0; i < tags.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.label_rounded, color: tagColor(tags[i]['color'] as String?), size: 20),
            const SizedBox(width: 6),
            Expanded(child: _text(tr('Nhãn'), '${tags[i]['text'] ?? ''}', (v) => _save('tags', tags..[i]['text'] = v), key: ValueKey('cx-t-$i'))),
            _insert((t) => _save('tags', tags..[i]['text'] = '${tags[i]['text'] ?? ''}$t')),
            DropdownButton<String>(
              value: cardTagColors.containsKey(tags[i]['color']) ? '${tags[i]['color']}' : 'gray',
              items: [for (final e in cardTagColors.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
              onChanged: (v) => _save('tags', tags..[i]['color'] = v),
            ),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => _save('tags', tags..removeAt(i))),
          ]),
        ),
      if (tags.length < 5)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('cx-add-tag'),
            onPressed: () => _save('tags', tags..add({'text': '', 'color': 'blue'})),
            icon: const Icon(Icons.label_outline_rounded, size: 18),
            label: Text(tr('Thêm nhãn trên thẻ')),
          ),
        ),
      if (!widget.process) ...[
        for (var i = 0; i < files.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.attach_file_rounded, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('cx-f-$i'),
                  initialValue: fileVars.any((v) => v.path == files[i]['from']) ? '${files[i]['from']}' : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Tệp đính kèm'), isDense: true, border: const OutlineInputBorder()),
                  items: [for (final v in fileVars) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => _save('files', files..[i] = {'from': v}),
                ),
              ),
              IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => _save('files', files..removeAt(i))),
            ]),
          ),
        if (fileVars.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('cx-add-file'),
              onPressed: () => _save('files', files..add({'from': fileVars.first.path})),
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(tr('Đính kèm tệp vào thẻ')),
            ),
          ),
      ],
    ]);
  }
}
