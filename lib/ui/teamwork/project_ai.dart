// TeamWork: "AI của dự án". Máy tính: khung bên phải kéo dãn được; điện thoại: bảng kéo lên từ dưới. Mỗi dự án gắn với một
// dự án AI cùng tên (tab Agents › Dự án AI; chưa có thì tự tạo); khung là phiên AI thật của dự án AI đó (mở phiên gần nhất, nút
// chuyển phiên ở đầu, "Phiên mới" chọn agent), chat stream trực tiếp. Mỗi tin gửi từ đây là một lượt TeamWork (vé ký, chạy
// không cần duyệt cho chủ bot); thao tác của agent hiện trong "Đã làm" dưới câu trả lời, kèm nút Hoàn tác.
import 'package:flutter/material.dart';

import 'api.dart' show TwException;
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
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
  /// Mở đúng phiên của cuộc trò chuyện này (nếu đã gắn phiên).
  final String? initialThread;
  @override
  State<TwProjectAiPanel> createState() => _TwProjectAiPanelState();
}

/// Khung AI của dự án = phiên AI thật của dự án AI cùng tên (tab Agents). Mở: phiên gần nhất; đầu khung là nút chuyển phiên
/// (các phiên của dự án AI + "Phiên mới"). Nội dung là khung chat thật của phiên (thẻ tiến trình, chữ stream trực tiếp);
/// mọi tin gửi từ đây (ô nhắn, nút nhanh) đi kèm ngữ cảnh lượt TeamWork (chạy không cần duyệt cho chủ bot, ghi "Đã làm" để hoàn tác).
class _TwProjectAiPanelState extends State<TwProjectAiPanel> {
  final _q = TextEditingController();
  TwAiProjectInfo? _ai;
  String? _error;
  /// Phiên đang mở; null = đang soạn tin đầu tiên của phiên mới.
  String? _sessionId;
  bool _sending = false, _owner = false;
  List<TwAgent> _agents = [];
  String? _agentId;
  TwAiSessions? _listening;

  TwStore get store => widget.store;
  TwProject get project => widget.project.project;
  TwAiSessions? get _sessions => store.aiSessions;
  List<TwAiSession> get _list => _ai == null || _sessions == null ? const [] : _sessions!.sessions(_ai!.channelId);
  TwAiSession? get _current => _list.where((s) => s.id == _sessionId).firstOrNull;
  /// Trợ lý của lượt tới: trợ lý của phiên đang mở, hoặc trợ lý đang chọn cho phiên mới.
  String? get _botId => _sessionId == null ? _agentId : ((_current?.botId ?? '').isNotEmpty ? _current!.botId : _agentId);
  TwAgent? _agentOf(String? id) => store.agents.where((a) => a.id == id).firstOrNull ?? _agents.where((a) => a.id == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    _listening = _sessions?..addListener(_onSessions);
    _loadAgents();
    _bind();
  }

  @override
  void dispose() {
    _listening?.removeListener(_onSessions);
    _q.dispose();
    super.dispose();
  }

  void _onSessions() {
    if (!mounted) return;
    setState(() {});
    _checkOwner();
  }

  Future<void> _bind() async {
    setState(() => _error = null);
    try {
      final ai = await store.ensureAiProject(project.id);
      if (!mounted) return;
      var sid = _sessions!.sessions(ai.channelId).firstOrNull?.id;
      final th = widget.initialThread;
      if (th != null) {
        try {
          final (t, _) = await store.api.aiThread(th);
          if (t.sessionChannel != null && _sessions!.sessions(ai.channelId).any((s) => s.id == t.sessionChannel)) sid = t.sessionChannel;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _ai = ai;
        _sessionId = sid;
      });
      _checkOwner();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
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
    final id = _botId, l = store.launcher;
    final o = id != null && l != null && await l.isOwnerOf(id);
    if (mounted && o != _owner) setState(() => _owner = o);
  }

  void _pickAgent(String id) {
    setState(() => _agentId = id);
    store.aiAgentId = id;
    store.saveAiAgent?.call(id);
    _checkOwner();
  }

  void _pickSession(String id) {
    setState(() => _sessionId = id == '+' ? null : id);
    _checkOwner();
  }

  void _toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  /// Gửi một lượt vào phiên đang mở (phiên mới thì tạo phiên trước, trong dự án AI, với trợ lý đang chọn).
  Future<void> _send(String prompt, {String? action}) async {
    final ai = _ai, sessions = _sessions;
    if (ai == null || sessions == null) return _toast(_error ?? 'Đang mở dự án AI…');
    final bot = _botId;
    if (bot == null) return _toast('Chưa có agent nào bạn dùng được');
    if (prompt.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      var sid = _sessionId;
      if (sid == null) {
        var title = promptText(prompt, action).replaceAll('\n', ' ');
        if (title.length > 40) title = '${title.substring(0, 40)}…';
        sid = await sessions.createSession(ai.channelId, bot, title);
        _q.clear();
        if (mounted) setState(() => _sessionId = sid);
      }
      await store.askAi(project.id, sessionId: sid, botId: bot, prompt: prompt.trim(), action: action);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
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
    final sessions = _sessions;
    final Widget body;
    if (sessions == null) {
      body = _notice(look, 'App này chưa có Dự án AI.');
    } else if (_error != null) {
      body = _notice(look, 'Không mở được dự án AI: $_error', retry: true);
    } else if (_ai == null) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_sessionId != null) {
      body = KeyedSubtree(
        key: ValueKey('ai-session-view-$_sessionId'),
        child: sessions.sessionView(context, _sessionId!,
            onSend: (t) => _send(t), aboveComposer: _chips(look, bar: true), runFooter: (runId) => TwRunFooter(store: store, project: widget.project, runId: runId)),
      );
    } else {
      body = _newSession(look);
    }
    return Material(
      color: look.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.sheet) Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 2), decoration: BoxDecoration(color: look.divider, borderRadius: BorderRadius.circular(2)))),
        _header(look),
        Divider(height: 1, color: look.divider),
        Expanded(child: body),
      ]),
    );
  }

  Widget _notice(TwLook look, String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: look.sub)),
            if (retry) TextButton(onPressed: _bind, child: const Text('Thử lại')),
          ]),
        ),
      );

  Widget _header(TwLook look) {
    final list = _list, cur = _current;
    final bot = _agentOf(_botId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(children: [
        Icon(Icons.auto_awesome, color: look.ai, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            PopupMenuButton<String>(
              key: const ValueKey('ai-session-switch'),
              tooltip: 'Chuyển phiên',
              enabled: _ai != null,
              position: PopupMenuPosition.under,
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              onSelected: _pickSession,
              itemBuilder: (_) => [
                for (final s in list)
                  PopupMenuItem<String>(
                    key: ValueKey('ai-session-${s.id}'),
                    value: s.id,
                    child: Row(children: [
                      SizedBox(width: 22, child: s.id == _sessionId ? Icon(Icons.check, size: 18, color: look.ai) : null),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.title.isEmpty ? 'Phiên chưa đặt tên' : s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                          Text([if (_agentOf(s.botId) != null) _agentOf(s.botId)!.label, if (s.at > 0) timeAgo(s.at, store.now)].join(' · '),
                              style: TextStyle(fontSize: 11.5, color: look.sub)),
                        ]),
                      ),
                    ]),
                  ),
                if (list.isNotEmpty) const PopupMenuDivider(),
                PopupMenuItem<String>(
                  key: const ValueKey('ai-session-new'),
                  value: '+',
                  child: Row(children: [
                    Icon(Icons.add_comment_outlined, size: 18, color: look.ai),
                    const SizedBox(width: 12),
                    Text('Phiên mới', style: TextStyle(fontWeight: FontWeight.w600, color: look.ai)),
                  ]),
                ),
              ],
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    _sessionId == null ? 'Phiên mới' : (cur?.title.isNotEmpty ?? false) ? cur!.title : 'AI của dự án',
                    key: const ValueKey('ai-session-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
                if (list.length > 1)
                  Container(
                    key: const ValueKey('ai-session-count'),
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: look.aiSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text('${list.length} phiên', style: TextStyle(fontSize: 11, color: look.ai, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            Row(children: [
              Flexible(
                child: Text(
                  ['Dự án AI: ${_ai?.displayName ?? project.name}', if (_sessionId != null && bot != null) bot.label, if (cur != null && cur.at > 0) timeAgo(cur.at, store.now)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: look.sub),
                ),
              ),
              if (_owner) ...[
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey('ai-bypass'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: look.ok.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
                  child: Text('🔓 không cần duyệt', style: TextStyle(fontSize: 11, color: look.ok, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ]),
        ),
        IconButton(key: const ValueKey('ai-new'), tooltip: 'Phiên mới', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_comment_outlined, size: 20), onPressed: _ai == null ? null : () => _pickSession('+')),
        if (widget.onClose != null) IconButton(key: const ValueKey('ai-close'), tooltip: 'Đóng', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 20), onPressed: widget.onClose),
      ]),
    );
  }

  /// Nút nhanh: gửi lời hỏi vào phiên đang mở. [bar]: một hàng cuộn ngang ngay trên ô nhắn của khung chat.
  Widget _chips(TwLook look, {bool bar = false}) {
    final chips = [
      for (final (k, icon, label) in kAiActions)
        Padding(
          padding: EdgeInsets.only(right: bar ? 6 : 0),
          child: ActionChip(
            key: ValueKey('ai-act-$k'),
            avatar: Icon(icon, size: 16, color: look.ai),
            label: Text(label, style: TextStyle(fontSize: 12.5, color: look.ai, fontWeight: FontWeight.w600)),
            backgroundColor: look.aiSoft,
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
            onPressed: _sending ? null : () => _send(label, action: k),
          ),
        ),
    ];
    if (!bar) return Wrap(spacing: 6, runSpacing: 6, children: chips);
    return Container(
      key: const ValueKey('ai-chips'),
      height: 44,
      padding: const EdgeInsets.only(top: 6),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: chips)),
    );
  }

  Widget _newSession(TwLook look) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 14), children: [
            Row(children: [
              Text('Agent', style: TextStyle(fontSize: 12.5, color: look.sub)),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                key: const ValueKey('ai-agent'),
                tooltip: 'Chọn agent · agent làm bằng quyền của bạn',
                onSelected: _pickAgent,
                itemBuilder: (_) => [for (final a in _agents) PopupMenuItem(value: a.id, child: Row(children: [TwAvatar(name: a.name, id: a.id, agent: true, size: 22, border: false), const SizedBox(width: 8), Text(a.label)]))],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_agentOf(_agentId) case final a?) TwAvatar(name: a.name, id: a.id, agent: true, size: 18, border: false),
                    const SizedBox(width: 6),
                    Text(_agentOf(_agentId)?.label ?? 'Chưa có agent', style: const TextStyle(fontSize: 13)),
                    const Icon(Icons.expand_more, size: 16),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _chips(look),
            const SizedBox(height: 16),
            Text(
                _list.isEmpty
                    ? 'Phiên đầu tiên của dự án AI "${_ai?.displayName ?? project.name}". Hỏi về tiến độ, kế hoạch, rủi ro… Gõ # để nhắc tới một việc. '
                        'AI làm bằng quyền của bạn; mọi thao tác hiện ở mục "Đã làm" và hoàn tác được. Phiên cũng có ở tab Agents › Dự án AI.'
                    : 'Phiên mới trong dự án AI "${_ai?.displayName ?? project.name}". Tin đầu tiên gửi kèm bức tranh đầy đủ của dự án.',
                style: TextStyle(fontSize: 12.5, color: look.sub, height: 1.45)),
          ]),
        ),
        Container(
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
                  hintText: 'Hỏi AI về dự án này… (# để nhắc một việc)',
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
            IconButton(
              key: const ValueKey('ai-send'),
              tooltip: 'Gửi',
              icon: _sending ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: look.ai)) : Icon(Icons.send, color: look.ai),
              onPressed: _sending ? null : () => _send(_q.text),
            ),
          ]),
        ),
      ]);
}

/// Dưới câu trả lời của agent cho một lượt TeamWork: "Đã làm" (+ Hoàn tác) và, với lượt "Soạn cập nhật", nút đăng vào nhóm chat.
class TwRunFooter extends StatefulWidget {
  const TwRunFooter({super.key, required this.store, required this.project, required this.runId});
  final TwStore store;
  final TwProjectFull project;
  final String runId;
  @override
  State<TwRunFooter> createState() => _TwRunFooterState();
}

class _TwRunFooterState extends State<TwRunFooter> {
  String? _action;
  TwStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    if (widget.project.project.chatChannel != null) {
      store.api.run(widget.runId).then((r) {
        if (mounted) setState(() => _action = r.action);
      }, onError: (_) {});
    }
  }

  void _toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  /// Đăng câu trả lời "Soạn cập nhật" vào nhóm chat của dự án (bằng bot Làm việc nhóm).
  Future<void> _postUpdate() async {
    final pid = widget.project.project.id;
    try {
      final r = await store.api.run(widget.runId);
      final text = (r.text ?? r.summary ?? '').trim();
      if (text.isEmpty) return _toast('Agent chưa viết xong bản cập nhật');
      await store.api.postToChat(pid, text);
      _toast('Đã đăng cập nhật vào nhóm chat');
    } on TwException catch (e) {
      _toast(e.code == 'bot_not_member' ? 'Bot Làm việc nhóm chưa ở trong nhóm chat' : (e.code == 'no_channel' ? 'Dự án chưa gắn nhóm chat' : e.message));
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        key: ValueKey('run-footer-${widget.runId}'),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          TwRunActions(key: ValueKey('ai-actions-${widget.runId}'), store: store, runId: widget.runId),
          if (_action == 'update' && widget.project.project.chatChannel != null)
            TextButton.icon(
              key: ValueKey('ai-post-${widget.runId}'),
              onPressed: _postUpdate,
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: Text('Đăng cập nhật vào ${widget.project.project.chatChannelName ?? 'nhóm chat'}'),
            ),
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
