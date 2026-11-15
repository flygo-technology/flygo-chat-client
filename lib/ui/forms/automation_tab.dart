// Biểu mẫu: tab Tự động hoá — tạo quy trình Flows ngay từ biểu mẫu (Sếp, 2026-11-15). Mỗi quy trình là một quy trình Flows
// thật gắn với biểu mẫu (bước Bắt đầu "form"): mỗi câu trả lời tạo một luồng, câu hỏi thành form.<mã câu hỏi>. Trình soạn
// gọn ở đây dựng các bước hay dùng (điều kiện, nhắn chat, duyệt, giao việc kèm form); bước khác sửa trong app Quy trình.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../flows/flows_page.dart' show openFlowsHome;
import '../theme.dart';
import 'api.dart';
import 'model.dart';
import 'widgets.dart';

class AutomationTab extends StatefulWidget {
  const AutomationTab({super.key, required this.api, required this.form, required this.canEdit, required this.onForm});
  final FormsApi api;
  final Json form;
  final bool canEdit;
  final ValueChanged<Json> onForm;
  @override
  State<AutomationTab> createState() => _AutomationTabState();
}

class _AutomationTabState extends State<AutomationTab> {
  List<Json>? _flows;
  Object? _error;
  String? _open;

  String get _id => '${widget.form['id']}';
  Json get _schema => Map<String, dynamic>.from(widget.form['schema'] as Map);
  bool get _public => (widget.form['settings'] as Map?)?['access'] == 'public';

  @override
  void initState() {
    super.initState();
    if (widget.canEdit) _load();
  }

  Future<void> _load() async {
    try {
      final f = await widget.api.flows(_id);
      if (mounted) setState(() => (_flows = f, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Biểu mẫu cần một hook "form" (gửi câu trả lời sang Flows) để các quy trình gắn biểu mẫu chạy.
  Future<void> _ensureHook() async {
    final hooks = [for (final h in ((widget.form['settings'] as Map?)?['flows'] as List? ?? const [])) Map<String, dynamic>.from(h as Map)];
    if (hooks.any((h) => h['mode'] == 'form' && h['flow_id'] == null && h['enabled'] != false)) return;
    final j = await widget.api.put('/api/forms/$_id/settings', {'flows': [...hooks, {'mode': 'form', 'name': 'Quy trình gắn biểu mẫu'}]});
    widget.onForm(Map<String, dynamic>.from(j['form'] as Map));
  }

  void _new(String template) {
    final steps = switch (template) {
      'approve' => [FlowStep.approval(), FlowStep.send(text: 'Đơn của bạn đã được duyệt.')],
      'assign' => [FlowStep.task(), FlowStep.send(text: 'Đã xử lý câu trả lời.')],
      'urgent' => [FlowStep.condition(questionsOf(_schema)), FlowStep.send(text: 'Có câu trả lời cần xử lý gấp.')],
      _ => [FlowStep.send()],
    };
    setState(() {
      _flows = [..._flows ?? const [], {'id': '', 'name': 'Quy trình ${(_flows?.length ?? 0) + 1}', 'active': true, '_steps': steps, '_new': true}];
      _open = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (!widget.canEdit) return FormBackdrop(child: FCard(child: Text('Chỉ người sửa biểu mẫu mới xem và soạn được tự động hoá.', style: TextStyle(color: p.sub))));
    return RefreshIndicator(
      onRefresh: _load,
      child: FormBackdrop(
        max: 820,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tự động hoá', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Mỗi câu trả lời tạo một luồng trong Quy trình (Flows). Câu hỏi thành dữ liệu form.<mã câu hỏi> của luồng.', style: TextStyle(color: p.sub, fontSize: 13)),
              if (_public) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0x1FE4A11B), borderRadius: BorderRadius.circular(8)),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFE4A11B), size: 20),
                    SizedBox(width: 8),
                    Expanded(child: Text('Biểu mẫu đang công khai: khách gửi thì luồng chạy dưới tên chủ biểu mẫu, mọi bước ghi dữ liệu dùng quyền của chủ biểu mẫu.', style: TextStyle(fontSize: 12.5))),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill('Thêm quy trình mới', icon: Icons.add, bg: p.chipSelBg, fg: p.chipSelFg, onTap: () => _new('blank')),
                Pill('Mẫu: Duyệt đơn', icon: Icons.how_to_reg_outlined, onTap: () => _new('approve')),
                Pill('Mẫu: Giao việc xử lý', icon: Icons.person_pin_circle_outlined, onTap: () => _new('assign')),
                Pill('Mẫu: Báo khẩn theo điều kiện', icon: Icons.priority_high, onTap: () => _new('urgent')),
                Pill('Mở Quy trình (nâng cao)', icon: Icons.open_in_new, onTap: () => openFlowsHome(context, context.read<AppState>())),
              ]),
            ]),
          ),
          if (_error != null)
            FCard(child: Text('Không tải được quy trình: $_error', style: TextStyle(color: p.sub)))
          else if (_flows == null)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (_flows!.isEmpty)
            FCard(child: Text('Chưa có quy trình nào gắn với biểu mẫu này.', style: TextStyle(color: p.sub)))
          else
            for (final f in _flows!)
              _FlowCard(
                key: ValueKey(f['id'] == '' ? 'new-${_flows!.indexOf(f)}' : f['id']),
                api: widget.api,
                formId: _id,
                owner: '${(widget.form['owner'] as Map?)?['id'] ?? ''}',
                schema: _schema,
                flow: f,
                expanded: _open == f['id'] || f['_new'] == true,
                onToggle: () => setState(() => _open = _open == f['id'] ? null : '${f['id']}'),
                onSaved: () async {
                  await _ensureHook();
                  await _load();
                },
                onDiscard: () => setState(() => _flows!.remove(f)),
              ),
        ]),
      ),
    );
  }
}

/// Một bước trong trình soạn gọn.
class FlowStep {
  FlowStep(this.kind, [Json? data]) : data = data ?? {};
  final String kind; // condition | send | approval | task | advanced
  final Json data;

  factory FlowStep.send({String text = 'Có câu trả lời mới cho biểu mẫu {{form._form_title}}'}) => FlowStep('send', {'to': r'$owner', 'text': text});
  factory FlowStep.approval() => FlowStep('approval', {'title': 'Duyệt câu trả lời', 'approver': null});
  factory FlowStep.task() => FlowStep('task', {'title': 'Xử lý câu trả lời', 'assignee': null, 'fields': [{'key': 'ket_qua', 'label': 'Kết quả xử lý', 'type': 'textarea', 'required': true}]});
  factory FlowStep.condition(List<Json> qs) {
    final q = qs.where((x) => x['type'] == 'scale' || x['type'] == 'number').firstOrNull ?? qs.firstOrNull;
    return FlowStep('condition', {'key': q?['key'], 'op': q != null && (q['type'] == 'scale' || q['type'] == 'number') ? '<=' : '==', 'value': q?['type'] == 'scale' ? '2' : ''});
  }

  static const kinds = {
    'condition': ('Điều kiện (chỉ chạy tiếp khi…)', Icons.call_split, Color(0xFF5B6CC4)),
    'send': ('Nhắn chat', Icons.chat_bubble_outline, Color(0xFFE4A11B)),
    'approval': ('Duyệt', Icons.how_to_reg_outlined, Color(0xFF2E7D32)),
    'task': ('Giao việc kèm form', Icons.person_pin_circle_outlined, Color(0xFFD9534F)),
    'advanced': ('Bước nâng cao', Icons.extension_outlined, Color(0xFF8E9AAF)),
  };
}

/// Người nhận / người duyệt: "$requester" (người điền), "$owner" (chủ biểu mẫu = người đứng tên luồng khi khách gửi),
/// {user, name}.
Object? _who(Object? v, String owner) {
  if (v == r'$requester') return r'$requester';
  if (v == r'$owner') return {'user': owner};
  if (v is Map && v['user'] != null) return {'user': v['user']};
  return null;
}

/// Bước → định nghĩa quy trình Flows (đi thẳng; điều kiện sai / từ chối thì kết thúc).
Json buildDef({required String id, required String name, required List<FlowStep> steps, required Json schema, required String owner}) {
  final nodes = <Json>[{'id': 'start', 'type': 'start'}];
  final edges = <List<String>>[];
  final ids = [for (var i = 0; i < steps.length; i++) 'b${i + 1}'];
  String? prev = 'start';
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i], d = s.data, nid = ids[i], next = i + 1 < steps.length ? ids[i + 1] : 'end';
    if (prev != null) edges.add([prev, nid]);
    prev = nid;
    switch (s.kind) {
      case 'condition':
        final v = '${d['value'] ?? ''}';
        final lit = num.tryParse(v.replaceAll(',', '.')) != null && (d['op'] != '==' && d['op'] != '!=' || RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(v)) ? v.replaceAll(',', '.') : "'${v.replaceAll("'", "\\'")}'";
        final expr = d['op'] == 'in' ? "$lit in form.${d['key']}" : 'form.${d['key']} ${d['op']} $lit';
        nodes.add({'id': nid, 'type': 'condition', 'name': 'Điều kiện', 'rules': [{'if': expr, 'to': next}], 'else': 'end'});
        prev = null;
      case 'send':
        final to = d['to'] == 'channel' ? null : _who(d['to'], owner);
        nodes.add({'id': nid, 'type': 'send', 'name': 'Nhắn chat', if (to != null) 'to': [to], if (d['to'] == 'channel' && d['channel'] != null) 'channels': [d['channel']], 'text': d['text'] ?? ''});
      case 'approval':
        nodes.add({'id': nid, 'type': 'approval_request', 'name': d['title'] ?? 'Duyệt', 'title': d['title'] ?? 'Duyệt', 'approver': _who(d['approver'], owner) ?? {'user': owner}, 'approve_to': next});
        prev = null;
      case 'task':
        nodes.add({'id': nid, 'type': 'form_task', 'name': d['title'] ?? 'Giao việc', 'assignee': _who(d['assignee'], owner) ?? {'user': owner}, 'fields': d['fields'] ?? const []});
      case 'advanced':
        nodes.add({...Map<String, dynamic>.from(d['node'] as Map), 'id': nid});
    }
  }
  if (prev != null) edges.add([prev, 'end']);
  nodes.add({'id': 'end', 'type': 'end'});
  return {
    'id': id,
    'name': name,
    'form': [for (final q in questionsOf(schema)) flowsField(q)],
    'nodes': nodes,
    'edges': edges,
  };
}

/// Định nghĩa Flows → bước (đi theo cạnh / approve_to / rules từ start). Bước lạ giữ nguyên dạng "nâng cao".
List<FlowStep> parseDef(Json def, String owner) {
  final nodes = {for (final n in (def['nodes'] as List? ?? const [])) '${(n as Map)['id']}': Map<String, dynamic>.from(n)};
  final edges = [for (final e in (def['edges'] as List? ?? const [])) [for (final x in e as List) '$x']];
  String? nextOf(String id) {
    final n = nodes[id];
    if (n == null) return null;
    if (n['approve_to'] != null) return '${n['approve_to']}';
    if (n['type'] == 'condition') return '${((n['rules'] as List?)?.firstOrNull as Map?)?['to'] ?? n['else']}';
    return edges.where((e) => e.length == 2 && e[0] == id).firstOrNull?[1];
  }

  Object? whoBack(Object? w) {
    if (w is List) w = w.firstOrNull;
    if (w == r'$requester') return r'$requester';
    if (w is Map && w['user'] == owner) return r'$owner';
    if (w is Map && w['user'] != null) return {'user': w['user']};
    return null;
  }

  final out = <FlowStep>[];
  var cur = nextOf('start');
  final seen = <String>{};
  while (cur != null && cur != 'end' && !seen.contains(cur) && nodes[cur] != null) {
    seen.add(cur);
    final n = nodes[cur]!;
    switch (n['type']) {
      case 'condition':
        final m = RegExp(r'''^form\.([a-z0-9_]+)\s*(==|!=|<=|>=|<|>)\s*'?(.*?)'?$''').firstMatch('${((n['rules'] as List?)?.firstOrNull as Map?)?['if'] ?? ''}');
        final mi = RegExp(r'''^'(.*)' in form\.([a-z0-9_]+)$''').firstMatch('${((n['rules'] as List?)?.firstOrNull as Map?)?['if'] ?? ''}');
        if (m != null) {
          out.add(FlowStep('condition', {'key': m[1], 'op': m[2], 'value': m[3]}));
        } else if (mi != null) {
          out.add(FlowStep('condition', {'key': mi[2], 'op': 'in', 'value': mi[1]}));
        } else {
          out.add(FlowStep('advanced', {'node': n}));
        }
      case 'send' || 'notify':
        final ch = (n['channels'] as List?)?.firstOrNull;
        out.add(FlowStep('send', {'to': ch != null ? 'channel' : whoBack(n['to']) ?? r'$owner', 'channel': ch, 'text': n['text'] ?? ''}));
      case 'approval_request':
        out.add(FlowStep('approval', {'title': n['title'] ?? n['name'], 'approver': whoBack(n['approver'])}));
      case 'form_task':
        out.add(FlowStep('task', {'title': n['name'], 'assignee': whoBack(n['assignee']), 'fields': n['fields'] ?? const []}));
      default:
        out.add(FlowStep('advanced', {'node': n}));
    }
    cur = nextOf(cur);
  }
  return out;
}

class _FlowCard extends StatefulWidget {
  const _FlowCard({super.key, required this.api, required this.formId, required this.owner, required this.schema, required this.flow, required this.expanded, required this.onToggle, required this.onSaved, required this.onDiscard});
  final FormsApi api;
  final String formId, owner;
  final Json schema, flow;
  final bool expanded;
  final VoidCallback onToggle, onDiscard;
  final Future<void> Function() onSaved;
  @override
  State<_FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends State<_FlowCard> {
  late final TextEditingController _name = TextEditingController(text: '${widget.flow['name'] ?? ''}');
  late List<FlowStep> _steps;
  bool _busy = false, _dirty = false;
  List<String> _issues = [];
  String? _checkResult;
  final Map<String, String> _names = {};

  bool get _isNew => widget.flow['_new'] == true;
  String get _owner => widget.owner;

  @override
  void initState() {
    super.initState();
    final def = widget.flow['def'];
    _steps = widget.flow['_steps'] as List<FlowStep>? ?? (def is Map ? parseDef(Map<String, dynamic>.from(def), widget.owner) : []);
    _dirty = _isNew;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Json _def() => buildDef(id: _isNew ? '' : '${widget.flow['id']}', name: _name.text.trim().isEmpty ? 'Quy trình' : _name.text.trim(), steps: _steps, schema: widget.schema, owner: _owner);

  List<String> _issueTexts(Json j) => [for (final i in (j['issues'] as List? ?? const [])) i is Map ? '${i['message'] ?? i['msg'] ?? i['code'] ?? i}' : '$i'];

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final j = await widget.api.saveFlow(widget.formId, _def());
      _issues = _issueTexts(j);
      _dirty = false;
      await widget.onSaved();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(_issues.isEmpty ? 'Đã lưu quy trình' : 'Đã lưu, còn ${_issues.length} lưu ý')));
    } on FormsException catch (e) {
      setState(() => _issues = _issueTexts(e.body).isEmpty ? [e.message] : _issueTexts(e.body));
    } catch (e) {
      setState(() => _issues = ['$e']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      Json? sample;
      try {
        final r = await widget.api.get('/api/forms/${widget.formId}/responses', {'limit': '1'});
        final list = r['responses'] as List? ?? const [];
        if (list.isNotEmpty) sample = Map<String, dynamic>.from((list.first as Map)['answers'] as Map);
      } catch (_) {}
      final j = await widget.api.checkFlow(widget.formId, _def(), answers: sample);
      setState(() {
        _issues = _issueTexts(j);
        final traces = j['traces'] as List? ?? const [];
        _checkResult = j['ok'] == true
            ? 'Chạy thử ${sample == null ? 'với các tình huống tự sinh' : 'với câu trả lời mới nhất'}: ổn${traces.isEmpty ? '' : ' (${traces.length} tình huống)'}'
            : 'Chạy thử có lỗi';
      });
    } catch (e) {
      setState(() => _checkResult = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActive(bool v) async {
    try {
      await widget.api.setFlowActive(widget.formId, '${widget.flow['id']}', v);
      await widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  void _change(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  Future<Json?> _pickPerson() => showDialog<Json>(
        context: context,
        builder: (c) {
          var people = <Json>[];
          return StatefulBuilder(
            builder: (c, set) => AlertDialog(
              title: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Tìm người', prefixIcon: Icon(Icons.search)),
                onChanged: (q) async {
                  if (q.trim().length < 2) return;
                  final j = await widget.api.get('/api/people', {'q': q});
                  set(() => people = [for (final x in (j['people'] as List)) Map<String, dynamic>.from(x as Map)]);
                },
              ),
              content: SizedBox(width: 360, height: 300, child: ListView(children: [for (final u in people) ListTile(title: Text('${u['name']}'), subtitle: Text('@${u['username']}'), onTap: () => Navigator.pop(c, u))])),
            ),
          );
        },
      );

  Widget _whoPicker(Object? value, ValueChanged<Object?> onChanged, {bool allowChannel = false}) {
    final label = value == r'$requester'
        ? 'Người điền'
        : value == r'$owner'
            ? 'Chủ biểu mẫu'
            : value == 'channel'
                ? 'Một nhóm chat'
                : value is Map
                    ? (_names['${value['user']}'] ?? 'Người đã chọn')
                    : 'Chọn người';
    return PopupMenuButton<String>(
      onSelected: (v) async {
        if (v == 'pick') {
          final u = await _pickPerson();
          if (u != null) {
            _names['${u['id']}'] = '${u['name']}';
            onChanged({'user': u['id']});
          }
        } else {
          onChanged(v);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: r'$requester', child: Text('Người điền (nội bộ)')),
        const PopupMenuItem(value: r'$owner', child: Text('Chủ biểu mẫu')),
        const PopupMenuItem(value: 'pick', child: Text('Chọn người…')),
        if (allowChannel) const PopupMenuItem(value: 'channel', child: Text('Một nhóm chat…')),
      ],
      child: Pill(label, icon: Icons.person_outline),
    );
  }

  Widget _stepCard(int i) {
    final p = Pal.of(context);
    final s = _steps[i];
    final info = FlowStep.kinds[s.kind]!;
    final qs = questionsOf(widget.schema);
    Widget body;
    switch (s.kind) {
      case 'condition':
        final q = qs.where((x) => x['key'] == s.data['key']).firstOrNull;
        body = Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 230,
            child: DropdownButton<String>(
              value: q == null ? null : '${q['key']}',
              hint: const Text('Câu hỏi'),
              isDense: true,
              isExpanded: true,
              items: [for (final x in qs) DropdownMenuItem(value: '${x['key']}', child: Text('${x['title']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => _change(() => s.data['key'] = v),
            ),
          ),
          DropdownButton<String>(
            value: '${s.data['op'] ?? '=='}',
            isDense: true,
            items: const [
              DropdownMenuItem(value: '==', child: Text('bằng')),
              DropdownMenuItem(value: '!=', child: Text('khác')),
              DropdownMenuItem(value: '<=', child: Text('≤')),
              DropdownMenuItem(value: '<', child: Text('<')),
              DropdownMenuItem(value: '>=', child: Text('≥')),
              DropdownMenuItem(value: '>', child: Text('>')),
              DropdownMenuItem(value: 'in', child: Text('có chọn')),
            ],
            onChanged: (v) => _change(() => s.data['op'] = v),
          ),
          if (q != null && (q['type'] == 'choice' || q['type'] == 'dropdown' || q['type'] == 'checkbox'))
            DropdownButton<String>(
              value: optionLabels(q).contains(s.data['value']) ? '${s.data['value']}' : null,
              hint: const Text('Giá trị'),
              isDense: true,
              items: [for (final l in optionLabels(q)) DropdownMenuItem(value: l, child: Text(l))],
              onChanged: (v) => _change(() => s.data['value'] = v),
            )
          else
            SizedBox(width: 120, child: TextFormField(initialValue: '${s.data['value'] ?? ''}', decoration: const InputDecoration(hintText: 'Giá trị', isDense: true), onChanged: (v) => _change(() => s.data['value'] = v))),
          Text('· sai thì dừng', style: TextStyle(color: p.sub, fontSize: 12)),
        ]);
      case 'send':
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, children: [
            Text('Gửi cho ', style: TextStyle(color: p.sub)),
            _whoPicker(s.data['to'], (v) => _change(() => s.data['to'] = v), allowChannel: true),
            if (s.data['to'] == 'channel')
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(width: 160, child: TextFormField(initialValue: '${s.data['channel'] ?? ''}', decoration: const InputDecoration(hintText: 'Mã nhóm (Flow Bot ở trong)', isDense: true), onChanged: (v) => _change(() => s.data['channel'] = v.trim()))),
              ),
          ]),
          TextFormField(
            initialValue: '${s.data['text'] ?? ''}',
            maxLines: null,
            decoration: InputDecoration(hintText: 'Nội dung, chèn câu trả lời bằng {{form.<mã>}}', helperText: qs.isEmpty ? null : 'Mã: ${qs.map((q) => q['key']).join(', ')}', helperMaxLines: 3),
            onChanged: (v) => _change(() => s.data['text'] = v),
          ),
        ]);
      case 'approval':
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(initialValue: '${s.data['title'] ?? ''}', decoration: const InputDecoration(labelText: 'Tiêu đề', isDense: true), onChanged: (v) => _change(() => s.data['title'] = v)),
          const SizedBox(height: 8),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [Text('Người duyệt ', style: TextStyle(color: p.sub)), _whoPicker(s.data['approver'], (v) => _change(() => s.data['approver'] = v))]),
          Text('Duyệt thì đi tiếp; từ chối thì kết thúc luồng.', style: TextStyle(color: p.sub, fontSize: 12)),
        ]);
      case 'task':
        final fields = [for (final f in (s.data['fields'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)];
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(initialValue: '${s.data['title'] ?? ''}', decoration: const InputDecoration(labelText: 'Tên việc', isDense: true), onChanged: (v) => _change(() => s.data['title'] = v)),
          const SizedBox(height: 8),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [Text('Giao cho ', style: TextStyle(color: p.sub)), _whoPicker(s.data['assignee'], (v) => _change(() => s.data['assignee'] = v))]),
          const SizedBox(height: 6),
          Text('Người được giao điền:', style: TextStyle(color: p.sub, fontSize: 12.5)),
          for (var k = 0; k < fields.length; k++)
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: '${fields[k]['label']}',
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) => _change(() => (s.data['fields'] as List)[k] = {...fields[k], 'label': v, 'key': slugKey(v)}),
                ),
              ),
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => _change(() => (s.data['fields'] as List).removeAt(k)), icon: const Icon(Icons.close, size: 16)),
            ]),
          TextButton(onPressed: () => _change(() => s.data['fields'] = [...fields, {'key': 'truong_${fields.length + 1}', 'label': 'Trường ${fields.length + 1}', 'type': 'text'}]), child: const Text('Thêm trường')),
        ]);
      default:
        body = Text('Bước "${(s.data['node'] as Map?)?['name'] ?? (s.data['node'] as Map?)?['type']}" — sửa trong app Quy trình.', style: TextStyle(color: p.sub));
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.divider)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: tintOf(info.$3, isDark(context)), borderRadius: BorderRadius.circular(9)), child: Icon(info.$2, size: 19, color: info.$3)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(info.$1, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 6), body])),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 18, color: p.sub),
            onSelected: (a) => _change(() {
              if (a == 'del') _steps.removeAt(i);
              if (a == 'up' && i > 0) _steps.insert(i - 1, _steps.removeAt(i));
              if (a == 'down' && i < _steps.length - 1) _steps.insert(i + 1, _steps.removeAt(i));
            }),
            itemBuilder: (_) => const [PopupMenuItem(value: 'up', child: Text('Chuyển lên')), PopupMenuItem(value: 'down', child: Text('Chuyển xuống')), PopupMenuItem(value: 'del', child: Text('Xoá bước'))],
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.only(left: 30), child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: 16, color: p.divider))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = FormTheme.of(context);
    final f = widget.flow;
    final active = f['active'] != false;
    return FCard(
      left: widget.expanded ? color : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: _isNew ? null : widget.onToggle,
          child: Row(children: [
            Icon(Icons.account_tree_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: widget.expanded
                  ? TextField(controller: _name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600), decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Tên quy trình'), onChanged: (_) => _change(() {}))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${f['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('${f['runs'] ?? 0} luồng · lỗi ${f['errors'] ?? 0} · ${_steps.length} bước', style: TextStyle(color: p.sub, fontSize: 12.5)),
                    ]),
            ),
            if (!_isNew) Switch(value: active, activeTrackColor: color, onChanged: _setActive),
            if (!_isNew) Icon(widget.expanded ? Icons.expand_less : Icons.expand_more, color: p.sub),
          ]),
        ),
        if (widget.expanded) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.divider)),
            child: Row(children: [
              Container(width: 34, height: 34, decoration: BoxDecoration(color: tintOf(color, isDark(context)), borderRadius: BorderRadius.circular(9)), child: Icon(Icons.assignment_outlined, size: 19, color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Khi có câu trả lời', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Mỗi câu trả lời tạo 1 luồng; dữ liệu: ${questionsOf(widget.schema).take(4).map((q) => 'form.${q['key']}').join(', ')}${questionsOf(widget.schema).length > 4 ? '…' : ''}', style: TextStyle(color: p.sub, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(left: 30), child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: 16, color: p.divider))),
          for (var i = 0; i < _steps.length; i++) _stepCard(i),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              onSelected: (k) => _change(() => _steps.add(switch (k) {
                    'condition' => FlowStep.condition(questionsOf(widget.schema)),
                    'approval' => FlowStep.approval(),
                    'task' => FlowStep.task(),
                    _ => FlowStep.send(),
                  })),
              itemBuilder: (_) => [
                for (final k in const ['condition', 'send', 'approval', 'task'])
                  PopupMenuItem(value: k, child: Row(children: [Icon(FlowStep.kinds[k]!.$2, size: 18, color: FlowStep.kinds[k]!.$3), const SizedBox(width: 10), Text(FlowStep.kinds[k]!.$1)])),
              ],
              child: Padding(
                padding: const EdgeInsets.only(left: 18, top: 2, bottom: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_circle, size: 26, color: color), const SizedBox(width: 8), Text('Thêm bước', style: TextStyle(color: color, fontWeight: FontWeight.w600))]),
              ),
            ),
          ),
          if (_issues.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0x14D93025), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final s in _issues) Text('• $s', style: const TextStyle(fontSize: 12.5))]),
            ),
          if (_checkResult != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_checkResult!, style: TextStyle(color: p.sub, fontSize: 12.5))),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            if (_isNew) TextButton(onPressed: widget.onDiscard, child: const Text('Bỏ')),
            OutlinedButton.icon(onPressed: _busy || _steps.isEmpty ? null : _check, icon: const Icon(Icons.play_arrow_outlined, size: 18), label: const Text('Chạy thử')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _busy || !_dirty || _steps.isEmpty ? null : _save,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined, size: 18),
              label: Text(_isNew ? 'Tạo quy trình' : 'Lưu'),
            ),
          ]),
        ],
      ]),
    );
  }
}
