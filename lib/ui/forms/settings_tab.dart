// Biểu mẫu: tab Cài đặt — khi có câu trả lời mới (báo trong chat, tạo việc Todo), câu trả lời (ghi tên, xáo câu hỏi…),
// trình bày (màu chủ đề, thanh tiến độ, lời cảm ơn, lời báo khi đóng).
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';
import 'model.dart';
import 'widgets.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.api, required this.form, required this.canEdit, required this.onForm});
  final FormsApi api;
  final Json form;
  final bool canEdit;
  final ValueChanged<Json> onForm;
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  List<Json>? _channels;
  Json _features = const {};
  final Map<String, Timer> _debounce = {};
  String? _todoName;

  Json get _s => Map<String, dynamic>.from(widget.form['settings'] as Map? ?? const {});
  String get _id => '${widget.form['id']}';

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/me').then((j) => mounted ? setState(() => _features = Map<String, dynamic>.from(j['features'] as Map? ?? const {})) : null).catchError((_) {});
    widget.api.get('/api/channels').then((j) => mounted ? setState(() => _channels = [for (final c in (j['channels'] as List)) Map<String, dynamic>.from(c as Map)]) : null).catchError((_) {});
  }

  @override
  void dispose() {
    for (final t in _debounce.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _save(Json patch) async {
    try {
      final j = await widget.api.put('/api/forms/$_id/settings', patch);
      widget.onForm(Map<String, dynamic>.from(j['form'] as Map));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  void _saveLater(String key, Json patch) {
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(milliseconds: 700), () => _save(patch));
  }

  Future<void> _pickAssignee() async {
    final picked = await showDialog<Json>(context: context, builder: (c) => _PersonPicker(api: widget.api));
    if (picked == null) return;
    setState(() => _todoName = '${picked['name']}');
    await _save({'todo': {..._todo, 'assignee': picked['id'], 'enabled': true}});
  }

  Json get _todo => Map<String, dynamic>.from(_s['todo'] as Map? ?? const {});
  Json get _notify => Map<String, dynamic>.from(_s['notify'] as Map? ?? const {});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = _s, ed = widget.canEdit;
    Widget sec(String title, List<Widget> kids) => FCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 6), ...kids]));
    final channel = _notify['channel'] as String?;
    return FormBackdrop(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sec('Khi có câu trả lời mới', [
          SwitchRow(label: 'Báo trong chat', help: 'Bot "Biểu mẫu" nhắn riêng cho chủ và người cùng sửa; gom tối đa 1 tin / 10 phút', value: _notify['dm'] != false,
              onChanged: ed ? (v) => _save({'notify': {..._notify, 'dm': v}}) : null),
          Row(children: [
            const Expanded(child: Text('Đăng vào nhóm')),
            DropdownButton<String>(
              value: _channels?.any((c) => c['id'] == channel) == true ? channel : '',
              onChanged: !ed ? null : (v) => _save({'notify': {..._notify, 'channel': v == '' ? null : v}}),
              items: [const DropdownMenuItem(value: '', child: Text('Không')), for (final c in _channels ?? const <Json>[]) DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}${c['team'] == null ? '' : ' · ${c['team']}'}'))],
            ),
          ]),
          if (_channels != null && _channels!.isEmpty) Text('Thêm bot "Biểu mẫu" (forms-app) vào nhóm để chọn được ở đây.', style: TextStyle(color: p.sub, fontSize: 12)),
          const SizedBox(height: 6),
          Divider(height: 1, color: p.divider),
          SwitchRow(
            label: 'Tạo việc Todo',
            help: _features['todo'] == false ? 'Máy chủ chưa nối với Todo' : 'Giao cho một người; tiêu đề lấy câu trả lời bằng {{mã câu hỏi}}',
            value: _todo['enabled'] == true,
            onChanged: !ed || _features['todo'] == false ? null : (v) => v && _todo['assignee'] == null ? _pickAssignee() : _save({'todo': {..._todo, 'enabled': v}}),
          ),
          if (_todo['enabled'] == true) ...[
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('Giao cho'), subtitle: Text(_todoName ?? '${widget.form['todo_assignee_name'] ?? (_todo['assignee'] == null ? 'Chưa chọn' : 'Đã chọn')}'), trailing: const Icon(Icons.person_search), onTap: ed ? _pickAssignee : null),
            TextFormField(
              initialValue: '${_todo['title'] ?? ''}',
              enabled: ed,
              decoration: InputDecoration(labelText: 'Tiêu đề việc', hintText: 'vd: Gọi lại {{${questionsOf(Map<String, dynamic>.from(widget.form['schema'] as Map)).firstOrNull?['key'] ?? 'ho_ten'}}}'),
              onChanged: (v) => _saveLater('todo', {'todo': {..._todo, 'title': v}}),
            ),
          ],
          const SizedBox(height: 8),
          Text('Bắt đầu quy trình khi có câu trả lời: xem tab Tự động hoá.', style: TextStyle(color: p.sub, fontSize: 12.5)),
        ]),
        sec('Câu trả lời', [
          SwitchRow(label: 'Ghi tên và email người điền (nội bộ)', value: s['collect_identity'] != false, onChanged: ed ? (v) => _save({'collect_identity': v}) : null),
          SwitchRow(label: 'Xáo thứ tự câu hỏi', help: 'Trong từng mục', value: s['shuffle'] == true, onChanged: ed ? (v) => _save({'shuffle': v}) : null),
          SwitchRow(label: 'Thanh tiến độ', value: s['progress'] != false, onChanged: ed ? (v) => _save({'progress': v}) : null),
        ]),
        sec('Lời nhắn', [
          TextFormField(initialValue: '${s['confirmation'] ?? ''}', enabled: ed, maxLines: null, decoration: const InputDecoration(labelText: 'Sau khi gửi'), onChanged: (v) => _saveLater('confirmation', {'confirmation': v})),
          const SizedBox(height: 10),
          TextFormField(initialValue: '${s['closed_message'] ?? ''}', enabled: ed, maxLines: null, decoration: const InputDecoration(labelText: 'Khi đã ngừng nhận'), onChanged: (v) => _saveLater('closed', {'closed_message': v})),
        ]),
        sec('Chống spam (link công khai)', [
          Row(children: [
            const Expanded(child: Text('Tạm ngừng khi quá số câu trả lời / giờ')),
            DropdownButton<int>(
              value: [100, 300, 1000, 5000].contains(s['per_hour']) ? s['per_hour'] as int : 300,
              onChanged: !ed ? null : (v) => _save({'per_hour': v}),
              items: [for (final n in const [100, 300, 1000, 5000]) DropdownMenuItem(value: n, child: Text('$n'))],
            ),
          ]),
          Text('Mỗi IP tối đa 5 lần / phút. Vượt trần thì biểu mẫu tự ngừng nhận và báo bạn trong chat.', style: TextStyle(color: p.sub, fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _PersonPicker extends StatefulWidget {
  const _PersonPicker({required this.api});
  final FormsApi api;
  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  List<Json> _people = [];
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tìm người', prefixIcon: Icon(Icons.search)),
          onChanged: (q) async {
            if (q.trim().length < 2) return;
            final j = await widget.api.get('/api/people', {'q': q});
            if (mounted) setState(() => _people = [for (final x in (j['people'] as List)) Map<String, dynamic>.from(x as Map)]);
          },
        ),
        content: SizedBox(
          width: 380,
          height: 320,
          child: ListView(children: [for (final u in _people) ListTile(leading: const Icon(Icons.person_outline), title: Text('${u['name']}'), subtitle: Text('@${u['username']}'), onTap: () => Navigator.pop(context, u))]),
        ),
      );
}
