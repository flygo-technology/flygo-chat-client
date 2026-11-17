// TeamWork: "AI của dự án". Máy tính: khung bên phải kéo dãn được; điện thoại: bảng kéo lên từ dưới. Chọn agent của mình
// (nhớ theo máy), nút nhanh, cuộc trò chuyện (lời mình + lượt chạy của agent với tiến độ trực tiếp và câu trả lời), ô hỏi có #việc,
// lịch sử cuộc trò chuyện. Agent làm thẳng dưới tên người hỏi; mỗi thao tác hiện trong "Đã làm" kèm nút Hoàn tác.
import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart' show TwException;
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'run_progress.dart';
import 'store.dart';
import 'task_page.dart';

/// Lời hỏi hiện trong bong bóng: lời người dùng, hoặc tên nút nhanh khi lời hỏi trống.
String promptText(String prompt, String? action) {
  if (prompt.trim().isNotEmpty) return prompt.trim();
  for (final (k, _, label) in kAiActions) {
    if (k == action) return label;
  }
  return action == null || action.isEmpty ? 'Hỏi AI' : action;
}

const kAiActions = [
  ('summary', Icons.insights_outlined, 'Tóm tắt tiến độ'),
  ('plan', Icons.account_tree_outlined, 'Lập kế hoạch & chia việc'),
  ('update', Icons.campaign_outlined, 'Soạn cập nhật cho nhóm'),
  ('risks', Icons.warning_amber_rounded, 'Rủi ro & việc trễ'),
  ('chat_group', Icons.forum_outlined, 'Tạo nhóm chat'),
];

/// Điện thoại: bảng kéo lên từ dưới.
Future<void> showProjectAiSheet(BuildContext context, TwStore store, TwProjectFull project) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        minChildSize: .4,
        maxChildSize: .97,
        builder: (c, scroll) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: TwProjectAiPanel(store: store, project: project, sheet: true, onClose: () => Navigator.pop(c)),
        ),
      ),
    );

class TwProjectAiPanel extends StatefulWidget {
  const TwProjectAiPanel({super.key, required this.store, required this.project, this.onClose, this.sheet = false, this.initialThread});
  final TwStore store;
  final TwProjectFull project;
  final VoidCallback? onClose;
  final bool sheet;
  final String? initialThread;
  @override
  State<TwProjectAiPanel> createState() => _TwProjectAiPanelState();
}

class _TwProjectAiPanelState extends State<TwProjectAiPanel> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  String? _threadId;
  List<TwAiTurn> _turns = [];
  bool _history = false, _sending = false, _owner = false;
  List<TwAiThread>? _threads;
  List<TwAgent> _agents = [];
  String? _agentId;

  TwStore get store => widget.store;
  TwProject get project => widget.project.project;
  TwAgent? get _agent => _agents.where((a) => a.id == _agentId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _loadAgents();
    if (widget.initialThread != null) _openThread(widget.initialThread!);
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    final l = store.launcher;
    final ok = <TwAgent>[];
    for (final a in store.agents) {
      if (l == null || await l.canUse(a.id)) ok.add(a);
    }
    if (!mounted) return;
    setState(() {
      _agents = ok;
      _agentId = ok.any((a) => a.id == store.aiAgentId) ? store.aiAgentId : ok.firstOrNull?.id;
    });
    _checkOwner();
  }

  Future<void> _checkOwner() async {
    final id = _agentId, l = store.launcher;
    final o = id != null && l != null && await l.isOwnerOf(id);
    if (mounted) setState(() => _owner = o);
  }

  void _pickAgent(String id) {
    setState(() => _agentId = id);
    store.aiAgentId = id;
    store.saveAiAgent?.call(id);
    _checkOwner();
  }

  Future<void> _openThread(String id) async {
    try {
      final (t, turns) = await store.api.aiThread(id);
      if (!mounted) return;
      setState(() {
        _threadId = t.id;
        _turns = turns;
        _history = false;
        if (t.botId.isNotEmpty && _agents.any((a) => a.id == t.botId)) _agentId = t.botId;
      });
      _toBottom();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _loadThreads() async {
    setState(() => _history = true);
    try {
      final l = await store.api.aiThreads(project.id);
      if (mounted) setState(() => _threads = l);
    } catch (e) {
      if (mounted) setState(() => _threads = []);
    }
  }

  void _newThread() => setState(() {
        _threadId = null;
        _turns = [];
        _history = false;
      });

  void _toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _send(String prompt, {String? action}) async {
    final id = _agentId;
    if (id == null) return _toast('Chưa có agent nào bạn dùng được');
    if (prompt.trim().isEmpty) return;
    final turn = TwAiTurn(prompt: prompt.trim(), action: action, at: DateTime.now().millisecondsSinceEpoch, user: store.meId);
    setState(() {
      _turns = [..._turns, turn];
      _sending = true;
      _q.clear();
    });
    _toBottom();
    try {
      final (run, thread) = await store.api.projectAi(project.id, botId: id, prompt: prompt.trim(), action: action, threadId: _threadId);
      if (!mounted) return;
      setState(() {
        turn.run = run;
        _threadId = thread ?? _threadId;
      });
      unawaited(store.checkRuns()); // máy này nhận lượt chạy và gửi vào phiên của agent
    } catch (e) {
      setState(() => _turns = _turns.where((t) => t != turn).toList());
      _toast('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Đăng câu trả lời "Soạn cập nhật" vào nhóm chat của dự án (bằng bot Làm việc nhóm).
  Future<void> _postUpdate(String runId) async {
    try {
      final r = await store.api.run(runId);
      final text = (r.text ?? r.summary ?? '').trim();
      if (text.isEmpty) return _toast('Agent chưa viết xong bản cập nhật');
      await store.api.postToChat(project.id, text);
      _toast('Đã đăng cập nhật vào nhóm chat');
    } on TwException catch (e) {
      _toast(e.code == 'bot_not_member' ? 'Bot Làm việc nhóm chưa ở trong nhóm chat' : (e.code == 'no_channel' ? 'Dự án chưa gắn nhóm chat' : e.message));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _mentionTask() async {
    final t = await pickTask(context, store, projectId: project.id, title: 'Nhắc tới việc');
    if (t == null) return;
    final sel = _q.selection.isValid ? _q.selection : TextSelection.collapsed(offset: _q.text.length);
    var text = _q.text;
    var at = sel.start;
    if (at > 0 && text[at - 1] == '#') {
      text = text.replaceRange(at - 1, at, '');
      at--;
    }
    final ins = '${t.key} ';
    _q.value = TextEditingValue(text: text.replaceRange(at, at, ins), selection: TextSelection.collapsed(offset: at + ins.length));
  }

  // ------------------------------------------------------------ giao diện
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final taskCount = store.tasksOf(project.id).where((t) => t.deletedAt == null).length;
    return Material(
      color: look.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.sheet) Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 2), decoration: BoxDecoration(color: look.divider, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 6),
          child: Row(children: [
            Icon(Icons.auto_awesome, color: look.ai, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI của dự án', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                Text('${project.name} · $taskCount việc', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: look.sub)),
              ]),
            ),
            IconButton(key: const ValueKey('ai-history'), tooltip: 'Lịch sử', visualDensity: VisualDensity.compact, icon: const Icon(Icons.history, size: 20), onPressed: _history ? () => setState(() => _history = false) : _loadThreads),
            IconButton(key: const ValueKey('ai-new'), tooltip: 'Cuộc trò chuyện mới', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_comment_outlined, size: 20), onPressed: _newThread),
            if (widget.onClose != null) IconButton(key: const ValueKey('ai-close'), tooltip: 'Đóng', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 20), onPressed: widget.onClose),
          ]),
        ),
        _agentRow(look),
        Divider(height: 1, color: look.divider),
        Expanded(child: _history ? _historyList(look) : _thread(look)),
        _composer(look),
      ]),
    );
  }

  Widget _agentRow(TwLook look) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(children: [
          PopupMenuButton<String>(
            key: const ValueKey('ai-agent'),
            tooltip: 'Chọn agent · agent làm bằng quyền của bạn',
            onSelected: _pickAgent,
            itemBuilder: (_) => [for (final a in _agents) PopupMenuItem(value: a.id, child: Row(children: [TwAvatar(name: a.name, id: a.id, agent: true, size: 22, border: false), const SizedBox(width: 8), Text(a.label)]))],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_agent != null) TwAvatar(name: _agent!.name, id: _agent!.id, agent: true, size: 18, border: false),
                const SizedBox(width: 6),
                Text(_agent?.label ?? 'Chưa có agent', style: const TextStyle(fontSize: 13)),
                const Icon(Icons.expand_more, size: 16),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          if (_owner)
            Container(
              key: const ValueKey('ai-bypass'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: look.ok.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
              child: Text('🔓 không cần duyệt', style: TextStyle(fontSize: 11.5, color: look.ok, fontWeight: FontWeight.w600)),
            ),
        ]),
      );

  Widget _chips(TwLook look) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, icon, label) in kAiActions)
          ActionChip(
            key: ValueKey('ai-act-$k'),
            avatar: Icon(icon, size: 16, color: look.ai),
            label: Text(label, style: TextStyle(fontSize: 12.5, color: look.ai, fontWeight: FontWeight.w600)),
            backgroundColor: look.aiSoft,
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
            onPressed: _sending ? null : () => _send(label, action: k),
          ),
      ]);

  Widget _thread(TwLook look) => ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(14, 10, 14, 14), children: [
        _chips(look),
        if (_turns.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text('Hỏi AI về dự án này: tiến độ, kế hoạch, rủi ro… Gõ # để nhắc tới một việc. AI làm bằng quyền của bạn; mọi thao tác hiện ở mục "Đã làm" và hoàn tác được.',
                style: TextStyle(fontSize: 12.5, color: look.sub, height: 1.45)),
          ),
        for (final t in _turns) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              key: ValueKey('ai-prompt-${_turns.indexOf(t)}'),
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: look.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(promptText(t.prompt.isNotEmpty ? t.prompt : (t.run?.prompt ?? ''), t.action ?? t.run?.action), style: TextStyle(fontSize: 13, color: look.text)),
            ),
          ),
          if (t.run == null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: look.ai)), const SizedBox(width: 8), Text('Đang gửi…', style: TextStyle(fontSize: 12.5, color: look.sub))]))
          else ...[
            TwRunProgress(key: ValueKey('ai-run-${t.run!.id}'), store: store, runId: t.run!.id, botId: t.run!.botId, botName: t.run!.botName, state: t.run!.state, session: t.run!.sessionChannel, showFinalText: true),
            TwRunActions(key: ValueKey('ai-actions-${t.run!.id}'), store: store, runId: t.run!.id),
            if ((t.action ?? t.run!.action) == 'update' && project.chatChannel != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('ai-post-${t.run!.id}'),
                  onPressed: () => _postUpdate(t.run!.id),
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: Text('Đăng cập nhật vào ${project.chatChannelName ?? 'nhóm chat'}'),
                ),
              ),
          ],
        ],
      ]);

  Widget _historyList(TwLook look) {
    final l = _threads;
    if (l == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (l.isEmpty) return Center(child: Text('Chưa có cuộc trò chuyện nào', style: TextStyle(color: look.sub)));
    return ListView(children: [
      for (final t in l)
        ListTile(
          key: ValueKey('ai-thread-${t.id}'),
          dense: true,
          leading: Icon(Icons.chat_bubble_outline, size: 18, color: look.ai),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([if (t.botName.isNotEmpty) t.botName, if (t.turnCount > 0) '${t.turnCount} lượt', timeAgo(t.updatedAt, store.now)].join(' · '), style: TextStyle(fontSize: 12, color: look.sub)),
          selected: t.id == _threadId,
          onTap: () => _openThread(t.id),
        ),
    ]);
  }

  Widget _composer(TwLook look) => Container(
        padding: EdgeInsets.fromLTRB(12, 8, 8, widget.sheet ? 14 : 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: look.divider))),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ai-input'),
              controller: _q,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: _turns.isEmpty ? 'Hỏi AI về dự án này… (# để nhắc một việc)' : 'Hỏi tiếp…',
                isDense: true,
                filled: true,
                fillColor: look.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onChanged: (v) {
                final i = _q.selection.start;
                if (i > 0 && i <= v.length && v[i - 1] == '#' && (i == 1 || v[i - 2] == ' ')) _mentionTask();
              },
              onSubmitted: (v) => _send(v),
            ),
          ),
          IconButton(key: const ValueKey('ai-send'), tooltip: 'Gửi', icon: Icon(Icons.send, color: look.ai), onPressed: _sending ? null : () => _send(_q.text)),
        ]),
      );
}

const _actionIcons = <String, IconData>{
  'task_create': Icons.add_task,
  'task_update': Icons.edit_outlined,
  'task_move': Icons.swap_horiz,
  'task_assign': Icons.person_add_alt,
  'task_delete': Icons.delete_outline,
  'comment_add': Icons.chat_bubble_outline,
  'project_update': Icons.tune,
  'member_set': Icons.group_add_outlined,
  'member_remove': Icons.person_remove_outlined,
  'project_delete': Icons.delete_forever_outlined,
  'chat_create': Icons.forum_outlined,
  'chat_post': Icons.campaign_outlined,
};

/// "Đã làm": các thao tác agent đã làm trong lượt chạy, mỗi dòng có Hoàn tác; nút "Hoàn tác cả lượt". Tải lại theo run_action.
class TwRunActions extends StatefulWidget {
  const TwRunActions({super.key, required this.store, required this.runId});
  final TwStore store;
  final String runId;
  @override
  State<TwRunActions> createState() => _TwRunActionsState();
}

class _TwRunActionsState extends State<TwRunActions> {
  List<TwAiAction> _list = [];
  int _rev = -1, _progRev = -1;
  final Set<String> _busy = {};
  bool _busyAll = false;

  TwStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
    _load();
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    final a = store.actionRev[widget.runId] ?? 0, p = store.runRev[widget.runId] ?? 0;
    if (a != _rev || p != _progRev) _load();
  }

  Future<void> _load() async {
    _rev = store.actionRev[widget.runId] ?? 0;
    _progRev = store.runRev[widget.runId] ?? 0;
    try {
      final l = await store.api.runActions(widget.runId);
      if (mounted) setState(() => _list = l);
    } catch (_) {}
  }

  Future<void> _undo(TwAiAction a) async {
    setState(() => _busy.add(a.id));
    try {
      final r = await store.api.undoAction(a.runId.isNotEmpty ? a.runId : widget.runId, a.id);
      setState(() {
        if (r.conflict != null) {
          a.conflict = r.conflict;
        } else {
          a.undone = true;
          a.conflict = null;
        }
      });
    } catch (e) {
      setState(() => a.conflict = '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  Future<void> _undoAll() async {
    setState(() => _busyAll = true);
    try {
      await store.api.undoRun(widget.runId);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const SizedBox();
    final look = TwLook.of(context);
    final open = _list.where((a) => !a.undone && a.undoable).length;
    return Container(
      key: ValueKey('actions-${widget.runId}'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 2),
          child: Row(children: [
            Icon(Icons.task_alt, size: 16, color: look.ok),
            const SizedBox(width: 6),
            Text('Đã làm · ${_list.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            if (open > 0)
              TextButton.icon(
                key: ValueKey('run-undo-all-${widget.runId}'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: look.red),
                onPressed: _busyAll ? null : _undoAll,
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Hoàn tác cả lượt', style: TextStyle(fontSize: 12.5)),
              ),
          ]),
        ),
        for (final a in _list)
          Container(
            key: ValueKey('action-${a.id}'),
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: look.divider))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(_actionIcons[a.kind] ?? Icons.bolt, size: 16, color: a.high ? look.red : look.sub)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: a.summary, style: TextStyle(color: a.high ? look.red : look.text, fontWeight: a.high ? FontWeight.w700 : null, decoration: a.undone ? TextDecoration.lineThrough : null)),
                      if (a.targetKey.isNotEmpty) const TextSpan(text: '  '),
                    ]),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (a.targetKey.isNotEmpty || a.targetTitle.isNotEmpty)
                    InkWell(
                      key: ValueKey('action-target-${a.id}'),
                      onTap: a.targetType == 'task' || a.targetKey.contains('-') ? () => openTask(context, store, a.targetKey.isNotEmpty ? a.targetKey : a.targetId) : null,
                      child: Text([a.targetKey, a.targetTitle].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: look.accent)),
                    ),
                  Text(a.undone ? 'đã hoàn tác' : timeAgo(a.at, store.now), style: TextStyle(fontSize: 11, color: look.sub)),
                  if (a.conflict != null) Text(a.conflict!, key: ValueKey('action-conflict-${a.id}'), style: TextStyle(fontSize: 11.5, color: look.warn)),
                ]),
              ),
              if (!a.undone && a.undoable)
                TextButton(
                  key: ValueKey('action-undo-${a.id}'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: _busy.contains(a.id) ? null : () => _undo(a),
                  child: const Text('Hoàn tác', style: TextStyle(fontSize: 12)),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Khung AI bên phải (máy tính) kéo mép trái để đổi độ rộng (nhớ theo máy).
class TwProjectAiSide extends StatefulWidget {
  const TwProjectAiSide({super.key, required this.store, required this.project, required this.onClose});
  final TwStore store;
  final TwProjectFull project;
  final VoidCallback onClose;
  @override
  State<TwProjectAiSide> createState() => _TwProjectAiSideState();
}

class _TwProjectAiSideState extends State<TwProjectAiSide> {
  double? _w;
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final full = MediaQuery.sizeOf(context).width;
    final w = (_w ?? widget.store.aiPanelWidth ?? 420).clamp(340.0, full * .6);
    return Container(
      key: const ValueKey('ai-panel'),
      width: w,
      decoration: BoxDecoration(border: Border(left: BorderSide(color: look.divider))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            key: const ValueKey('ai-panel-resize'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() => _w = (w - d.delta.dx).clamp(340.0, full * .6)),
            onHorizontalDragEnd: (_) {
              if (_w == null) return;
              widget.store.aiPanelWidth = _w;
              widget.store.saveAiPanelWidth?.call(_w!);
            },
            child: Container(width: 8, color: look.surface, alignment: Alignment.center, child: Container(width: 3, height: 36, decoration: BoxDecoration(color: look.divider, borderRadius: BorderRadius.circular(2)))),
          ),
        ),
        Expanded(child: TwProjectAiPanel(store: widget.store, project: widget.project, onClose: widget.onClose)),
      ]),
    );
  }
}

/// Gắn nhóm chat cho dự án: tạo nhóm mới (bằng token của mình) hoặc chọn kênh mình đang tham gia; thêm bot teamwork-app.
Future<void> linkProjectChat(BuildContext context, TwStore store, TwProjectFull f) async {
  final ops = store.chatOps;
  if (ops == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final channels = await ops.myChannels();
  if (!context.mounted) return;
  final pick = await twSheet<String>(
    context,
    width: 440,
    builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(c, 'Gắn nhóm chat cho dự án'),
      ListTile(key: const ValueKey('chat-create'), leading: Icon(Icons.add_circle_outline, color: TwLook.of(c).accent), title: const Text('Tạo nhóm chat mới'), subtitle: const Text('Nhóm riêng tư, thêm thành viên dự án'), onTap: () => Navigator.pop(c, '+')),
      groupLabel(c, 'Hoặc chọn kênh bạn đang tham gia'),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
          for (final (id, name) in channels) ListTile(key: ValueKey('chat-pick-$id'), dense: true, leading: const Icon(Icons.tag, size: 18), title: Text(name), onTap: () => Navigator.pop(c, id)),
        ]),
      ),
    ]),
  );
  if (pick == null) return;
  try {
    final pr = f.project;
    final bot = store.botUserId.isNotEmpty ? store.botUserId : await ops.userIdByUsername('teamwork-app') ?? '';
    TwChannelInfo? ch;
    if (pick == '+') {
      final members = [for (final m in f.members) if (m.subjectType == 'user') m.subjectId];
      final link = store.api.taskLink('').replaceFirst(RegExp(r'/t/$'), '/p/${pr.key}');
      ch = await ops.createChannel(
        teamId: await ops.bestTeam(members),
        name: '${pr.key.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4)}',
        displayName: pr.name,
        purpose: 'Nhóm chat của dự án ${pr.name} trên Làm việc nhóm: $link',
        header: '[Mở dự án ${pr.key}]($link)',
      );
      for (final m in members) {
        if (m == store.meId) continue;
        try {
          await ops.addMember(ch.id, m);
        } catch (_) {}
      }
    } else {
      ch = await ops.resolveChannel(pick);
      if (ch == null) throw StateError('Không đọc được kênh này');
    }
    if (bot.isNotEmpty) await ops.addMember(ch.id, bot);
    await store.api.setChatChannel(pr.id, TwStore.channelJson(ch));
    await store.openProject(pr.id);
    await store.refresh();
    messenger.showSnackBar(SnackBar(content: Text(pick == '+' ? 'Đã tạo nhóm chat "${pr.name}"' : 'Đã gắn nhóm chat vào dự án')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
