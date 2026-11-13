import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'theme.dart';
import 'package:flygo_chat/ui/app_route.dart';

/// Tin "Việc cần làm" (props.flygo_checklist): tiêu đề, mô tả, danh sách việc có ô tick, để nhắc việc cá nhân / ghi chú.
///   { v: 2, title, desc, allow_edit, tick: "me" | "all" | "some", tickers: [user_id], created_by,
///     items: [{id, text, done, done_by?, done_at?}] }
/// Người gửi luôn tick được (sửa tin của mình); người khác tick theo luật [tick] qua trạm đẩy (flygo-chat-server relay/checklist.mjs).

Map<String, dynamic>? checklistOf(MmPost post) {
  final c = post.props['flygo_checklist'];
  return c is Map && c['items'] is List ? c.cast<String, dynamic>() : null;
}

List<Map<String, dynamic>> checklistItems(Map<String, dynamic> c) =>
    [for (final x in (c['items'] as List? ?? const [])) if (x is Map && '${x['text'] ?? ''}'.trim().isNotEmpty) x.cast<String, dynamic>()];

String _id() => Random().nextInt(1 << 32).toRadixString(36).padLeft(6, '0');

/// Người [userId] có được tick danh sách [c] của tin do [author] gửi không (giống luật của trạm).
bool canTickChecklist(Map<String, dynamic> c, String author, String? userId) {
  if (userId == null) return false;
  if (userId == author) return true;
  return switch ('${c['tick'] ?? 'me'}') {
    'all' => true,
    'some' => (c['tickers'] as List? ?? const []).contains(userId),
    _ => false,
  };
}

/// Dựng props. [old]: danh sách cũ (khi sửa) để giữ trạng thái tick của việc có cùng nội dung.
Map<String, dynamic> buildChecklist({
  required String title,
  String desc = '',
  required List<String> lines,
  required String me,
  bool allowEdit = true,
  String tick = 'me',
  List<String> tickers = const [],
  Map<String, dynamic>? old,
}) {
  final prev = {for (final it in old == null ? const <Map<String, dynamic>>[] : checklistItems(old)) '${it['text']}'.trim(): it};
  return {
    'v': 2,
    'title': title.trim(),
    'desc': desc.trim(),
    'allow_edit': allowEdit,
    'tick': tick,
    'tickers': tick == 'some' ? tickers : const <String>[],
    'items': [
      for (final l in lines.map((e) => e.trim()).where((e) => e.isNotEmpty))
        prev[l] != null ? {...prev[l]!, 'text': l} : {'id': _id(), 'text': l, 'done': false},
    ],
    'created_by': old?['created_by'] ?? me,
  };
}

/// Chữ dự phòng cho app khác: tiêu đề, mô tả, "☐ việc / ☑ việc".
String checklistText(Map<String, dynamic> c) {
  final title = '${c['title'] ?? ''}'.trim();
  final desc = '${c['desc'] ?? ''}'.trim();
  final lines = [for (final it in checklistItems(c)) '${it['done'] == true ? '☑' : '☐'} ${it['text']}'];
  return ['📝 ${title.isEmpty ? tr('Việc cần làm') : title}', if (desc.isNotEmpty) desc, ...lines].join('\n');
}

/// Trang soạn việc cần làm: tiêu đề, mô tả, cho phép sửa sau khi gửi, danh sách việc (mỗi việc một dòng có ô tick),
/// ai được tick (chỉ tôi / mọi người trong chat / một số người, có Chọn tất cả). Trả về props mới hoặc null.
Future<Map<String, dynamic>?> showChecklistEditor(BuildContext context, {required AppState app, required String channelId, Map<String, dynamic>? initial}) =>
    Navigator.of(context).push<Map<String, dynamic>>(
        AppPageRoute(fullscreenDialog: true, builder: (_) => ChecklistEditorPage(app: app, channelId: channelId, initial: initial)));

class ChecklistEditorPage extends StatefulWidget {
  final AppState app;
  final String channelId;
  final Map<String, dynamic>? initial;
  const ChecklistEditorPage({super.key, required this.app, required this.channelId, this.initial});
  @override
  State<ChecklistEditorPage> createState() => _ChecklistEditorPageState();
}

class _ChecklistEditorPageState extends State<ChecklistEditorPage> {
  late final _title = TextEditingController(text: '${widget.initial?['title'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.initial?['desc'] ?? ''}');
  late bool _allowEdit = widget.initial?['allow_edit'] != false;
  late String _tick = '${widget.initial?['tick'] ?? 'me'}';
  late final Set<String> _tickers = {for (final x in (widget.initial?['tickers'] as List? ?? const [])) '$x'};
  late final List<(TextEditingController, FocusNode)> _rows = [
    for (final it in widget.initial == null ? const <Map<String, dynamic>>[] : checklistItems(widget.initial!)) _row('${it['text']}'),
    if (widget.initial == null) _row(''),
  ];

  bool get _editing => widget.initial != null;

  (TextEditingController, FocusNode) _row(String text) => (TextEditingController(text: text), FocusNode());

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    for (final (c, f) in _rows) {
      c.dispose();
      f.dispose();
    }
    super.dispose();
  }

  List<String> get _lines => [for (final (c, _) in _rows) if (c.text.trim().isNotEmpty) c.text.trim()];

  void _addAfter(int i) {
    final r = _row('');
    setState(() => _rows.insert(i + 1, r));
    WidgetsBinding.instance.addPostFrameCallback((_) => r.$2.requestFocus());
  }

  void _remove(int i) {
    final r = _rows.removeAt(i);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      r.$1.dispose();
      r.$2.dispose();
    });
  }

  Future<void> _pickPeople() async {
    final me = widget.app.me?.id;
    List<MmUser> people;
    try {
      people = (await widget.app.channelUsers(widget.channelId)).where((u) => u.id != me && !u.isBot && u.deleteAt == 0).toList()
        ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    } catch (_) {
      people = const [];
    }
    if (!mounted) return;
    final picked = {..._tickers};
    final r = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (s) => StatefulBuilder(
        builder: (s, set) {
          final all = people.isNotEmpty && people.every((u) => picked.contains(u.id));
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(s).height * .75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                  child: Row(children: [
                    Expanded(child: Text(tr('Ai được tick'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Pal.of(s).text))),
                    TextButton(
                      onPressed: people.isEmpty
                          ? null
                          : () => set(() => all ? picked.removeAll(people.map((u) => u.id)) : picked.addAll(people.map((u) => u.id))),
                      child: Text(all ? tr('Bỏ chọn tất cả') : tr('Chọn tất cả')),
                    ),
                  ]),
                ),
                if (people.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Chat này không có người nào khác.'))),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final u in people)
                      CheckboxListTile(
                        value: picked.contains(u.id),
                        onChanged: (v) => set(() => v == true ? picked.add(u.id) : picked.remove(u.id)),
                        secondary: Avatar(userId: u.id, name: u.displayName, size: 34, status: false),
                        title: Text(u.displayName),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(s, picked), child: Text(tr('Xong ({0})', [picked.length])))),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (r != null) {
      setState(() {
        _tickers
          ..clear()
          ..addAll(r);
      });
    }
  }

  void _submit() {
    Navigator.pop(
      context,
      buildChecklist(
        title: _title.text,
        desc: _desc.text,
        lines: _lines,
        me: widget.app.me?.id ?? '',
        allowEdit: _allowEdit,
        tick: _tick,
        tickers: _tickers.toList(),
        old: widget.initial,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final ok = _lines.isNotEmpty && (_tick != 'some' || _tickers.isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? tr('Sửa việc cần làm') : tr('Việc cần làm')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: ok ? _submit : null, child: Text(_editing ? tr('Lưu') : tr('Gửi'))),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
              // 1. Tiêu đề
              TextField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: tr('Tiêu đề'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              // 2. Mô tả
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(labelText: tr('Nội dung mô tả'), border: const OutlineInputBorder(), alignLabelWithHint: true),
              ),
              // 3. Cho phép sửa sau khi gửi
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Cho phép sửa sau khi gửi')),
                value: _allowEdit,
                onChanged: (v) => setState(() => _allowEdit = v),
              ),
              const Divider(),
              // 4. Danh sách việc: mỗi việc một dòng có ô tick phía trước
              Text(tr('Danh sách việc'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 4),
              for (final (i, (c, f)) in _rows.indexed)
                Row(children: [
                  Icon(Icons.check_box_outline_blank_rounded, color: pal.sub),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: c,
                      focusNode: f,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _addAfter(i),
                      decoration: InputDecoration(hintText: tr('Việc cần làm'), border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Bỏ việc này'),
                    icon: Icon(Icons.close_rounded, size: 18, color: pal.sub),
                    onPressed: _rows.length == 1 ? null : () => _remove(i),
                  ),
                ]),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => _addAfter(_rows.length - 1), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm việc'))),
              ),
              const Divider(),
              // 5. Ai được tick
              Text(tr('Ai được tick'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              RadioGroup<String>(
                groupValue: _tick,
                onChanged: (v) => setState(() => _tick = v ?? 'me'),
                child: Column(children: [
                  RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'me', title: Text(tr('Chỉ mình tôi'))),
                  RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'all', title: Text(tr('Mọi người trong chat'))),
                  RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'some', title: Text(tr('Một số người'))),
                ]),
              ),
              if (_tick == 'some')
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final id in _tickers) Chip(label: Text(widget.app.users[id]?.displayName ?? id), onDeleted: () => setState(() => _tickers.remove(id))),
                    OutlinedButton.icon(onPressed: _pickPeople, icon: const Icon(Icons.group_add_outlined), label: Text(tr('Chọn người'))),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Người khác tick: nhờ trạm đẩy sửa tin của người gửi (theo luật người gửi đặt). Trả về danh sách mới.
Future<Map<String, dynamic>> checklistToggle(AppState app, String postId, String itemId, bool done, {http.Client? client}) async {
  final c = client ?? http.Client();
  final r = await c
      .post(Uri.parse('${pushUrlFor(kServerUrl)}/checklist/toggle'),
          headers: {
            'Authorization': 'Bearer ${app.token}',
            'X-MM-Server': kServerUrl,
            'Content-Type': 'application/json',
            'User-Agent': kUserAgent,
          },
          body: jsonEncode({'post_id': postId, 'item_id': itemId, 'done': done}))
      .timeout(const Duration(seconds: 15));
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  if (r.statusCode != 200 || j['ok'] != true) throw Exception(j['error'] ?? 'checklist ${r.statusCode}');
  return (j['checklist'] as Map).cast<String, dynamic>();
}

/// Thẻ việc cần làm trong khung tin.
class ChecklistCard extends StatefulWidget {
  final AppState app;
  final MmPost post;
  final double width;
  const ChecklistCard({super.key, required this.app, required this.post, required this.width});
  @override
  State<ChecklistCard> createState() => _ChecklistCardState();
}

class _ChecklistCardState extends State<ChecklistCard> {
  /// Trạng thái vừa bấm trên máy này (chờ máy chủ xác nhận).
  Map<String, dynamic>? _local;

  Map<String, dynamic> get _c => _local ?? checklistOf(widget.post) ?? const {};
  bool get _mine => widget.post.userId == widget.app.me?.id;

  @override
  void didUpdateWidget(ChecklistCard old) {
    super.didUpdateWidget(old);
    if (old.post.updateAt != widget.post.updateAt) _local = null;
  }

  Future<void> _toggle(Map<String, dynamic> it) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = it['done'] != true;
    final me = widget.app.me?.id;
    final c = Map<String, dynamic>.of(_c);
    Map<String, dynamic> flip(Map<String, dynamic> x) {
      final y = {...x, 'done': done};
      if (done) {
        y['done_by'] = me;
        y['done_at'] = DateTime.now().millisecondsSinceEpoch;
      } else {
        y
          ..remove('done_by')
          ..remove('done_at');
      }
      return y;
    }

    c['items'] = [for (final x in checklistItems(c)) x['id'] == it['id'] ? flip(x) : x];
    setState(() => _local = c);
    try {
      if (_mine) {
        await widget.app.patchProps(widget.post, {'flygo_checklist': c});
      } else {
        final fresh = await checklistToggle(widget.app, widget.post.id, '${it['id']}', done);
        widget.app.mergeLocalProps(widget.post, {'flygo_checklist': fresh});
        if (mounted) setState(() => _local = fresh);
      }
    } catch (e) {
      if (mounted) setState(() => _local = null);
      messenger.showSnackBar(toast(Text(tr('Không lưu được: {0}', ['$e'.replaceFirst('Exception: ', '')]))));
    }
  }

  Future<void> _edit() async {
    final c = _c;
    final r = await showChecklistEditor(context, app: widget.app, channelId: widget.post.channelId, initial: c);
    if (r == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _local = r);
    try {
      await widget.app.patchProps(widget.post, {'flygo_checklist': r});
    } catch (_) {
      if (mounted) setState(() => _local = null);
      messenger.showSnackBar(toast(Text(tr('Không lưu được. Kiểm tra kết nối mạng.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = _c;
    final items = checklistItems(c);
    final done = items.where((it) => it['done'] == true).length;
    final title = '${c['title'] ?? ''}'.trim();
    final desc = '${c['desc'] ?? ''}'.trim();
    final canTick = canTickChecklist(c, widget.post.userId, widget.app.me?.id);
    final canEdit = _mine && c['allow_edit'] != false;
    const green = Color(0xFF2EAD6B);
    String who(String id) => id == widget.app.me?.id ? tr('Bạn') : (widget.app.users[id]?.displayName ?? '');
    return Container(
      width: widget.width.clamp(220.0, 380.0),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: green.withValues(alpha: .35))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: green.withValues(alpha: .10),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            const Icon(Icons.checklist_rounded, size: 18, color: green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title.isEmpty ? tr('Việc cần làm') : title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: green, fontSize: 14)),
            ),
            Text('$done/${items.length}', style: TextStyle(color: pal.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (canEdit)
              IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Sửa việc cần làm'), icon: Icon(Icons.edit_outlined, size: 18, color: pal.sub), onPressed: _edit)
            else
              const SizedBox(width: 8),
          ]),
        ),
        if (items.isNotEmpty) LinearProgressIndicator(value: done / items.length, minHeight: 3, color: green, backgroundColor: green.withValues(alpha: .12)),
        if (desc.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 2), child: Text(desc, style: TextStyle(color: pal.text, fontSize: 14))),
        for (final it in items)
          InkWell(
            onTap: canTick ? () => _toggle(it) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 12, 2),
              child: Row(children: [
                Checkbox(value: it['done'] == true, activeColor: green, visualDensity: VisualDensity.compact, onChanged: canTick ? (_) => _toggle(it) : null),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${it['text']}',
                        style: TextStyle(
                          color: it['done'] == true ? pal.sub : pal.text,
                          fontSize: 14.5,
                          decoration: it['done'] == true ? TextDecoration.lineThrough : null,
                          decorationColor: pal.sub,
                        )),
                    // Người khác tick: hiện tên người tick.
                    if (it['done'] == true && it['done_by'] != null && it['done_by'] != widget.post.userId && who('${it['done_by']}').isNotEmpty)
                      Row(children: [
                        Icon(Icons.check_rounded, size: 12, color: pal.sub),
                        const SizedBox(width: 3),
                        Text(who('${it['done_by']}'), style: TextStyle(color: pal.sub, fontSize: 11.5)),
                      ]),
                  ]),
                ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            switch ('${c['tick'] ?? 'me'}') {
              'all' => tr('Mọi người trong chat được tick'),
              'some' => tr('{0} người được tick', [(c['tickers'] as List? ?? const []).length + 1]),
              _ => tr('Chỉ người gửi được tick'),
            },
            style: TextStyle(color: pal.sub, fontSize: 11.5),
          ),
        ),
      ]),
    );
  }
}
