// TeamWork: chi tiết một việc. Máy tính: cột nội dung (tiêu đề, mô tả có định dạng, agent, việc con, tệp, bình luận /
// hoạt động) + cột thuộc tính + khung AI hỗ trợ. Điện thoại: một cột, thuộc tính thành hàng chip, AI mở bảng trượt.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart' show pickFilesOrReport;
import '../todo/model.dart';
import 'ai_panel.dart';
import 'comments.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'rich_mentions.dart';
import 'store.dart';

/// Mở trang chi tiết việc [idOrKey].
Future<void> openTask(BuildContext context, TwStore store, String idOrKey) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TwTaskPage(store: store, idOrKey: idOrKey)));

class TwTaskPage extends StatefulWidget {
  const TwTaskPage({super.key, required this.store, required this.idOrKey, this.showAi});
  final TwStore store;
  final String idOrKey;
  /// Kiểm thử / ảnh chụp: mở sẵn khung AI.
  final bool? showAi;
  @override
  State<TwTaskPage> createState() => _TwTaskPageState();
}

class _TwTaskPageState extends State<TwTaskPage> {
  TwTaskDetail? _d;
  String? _err;
  int _rev = -1, _descRev = 0;
  late bool _ai = widget.showAi ?? true;
  String _tab = 'comments';
  List<TwActivity>? _activity;
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  final _comments = GlobalKey<TwCommentsState>();
  Timer? _descSave;
  List<TBlock>? _descPending;
  String? _addingSubFor;
  final _subCtl = TextEditingController();

  TwStore get store => widget.store;
  TwTask get t => _d!.task;
  TwProjectFull? get p => store.fullOf(_d?.task.projectId);
  bool get canEdit => p?.project.canEdit ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    store.addListener(_onStore);
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _saveTitle();
    });
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    _flushDesc();
    _title.dispose();
    _titleFocus.dispose();
    _subCtl.dispose();
    super.dispose();
  }

  void _onStore() {
    final id = _d?.task.id;
    if (id == null) return;
    final r = store.taskRev[id] ?? 0;
    if (r != _rev) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final d = await store.api.task(_d?.task.id ?? widget.idOrKey);
      _rev = store.taskRev[d.task.id] ?? 0;
      if (store.fullOf(d.task.projectId) == null) await store.openProject(d.task.projectId);
      if (!mounted) return;
      setState(() {
        final descChanged = _d == null || _descPending == null && blocksText(_d!.task.description) != blocksText(d.task.description);
        _d = d;
        if (descChanged) _descRev++;
        if (!_titleFocus.hasFocus) _title.text = d.task.title;
        _err = null;
      });
      if (_tab == 'activity') _loadActivity();
    } catch (e) {
      if (mounted && !quiet) setState(() => _err = '$e');
    }
  }

  Future<void> _loadActivity() async {
    try {
      final a = await store.api.activity(t.id);
      if (mounted) setState(() => _activity = a);
    } catch (_) {}
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    try {
      await store.updateTask(t, patch);
      final n = store.taskById(t.id);
      if (n != null && mounted) setState(() => _d!.task = n);
      unawaited(_load(quiet: true));
    } catch (e) {
      _toast('$e');
    }
  }

  void _toast(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _saveTitle() async {
    final v = _title.text.trim();
    if (_d == null || v.isEmpty || v == t.title) return;
    await _patch({'title': v});
  }

  void _descChanged(List<TBlock> b) {
    _descPending = b;
    _descSave?.cancel();
    _descSave = Timer(const Duration(milliseconds: 900), _flushDesc);
  }

  Future<void> _flushDesc() async {
    _descSave?.cancel();
    final b = _descPending;
    if (b == null || _d == null) return;
    _descPending = null;
    try {
      final r = await store.api.updateTask(t.id, {'description': blocksToJson(b), 'base_version': t.version});
      if (mounted) setState(() => _d!.task = r);
    } catch (e) {
      if (e is Exception && e.toString().contains('version')) {
        _toast('Có người vừa sửa mô tả. Đang tải bản mới.');
        unawaited(_load());
      } else {
        _toast('$e');
      }
    }
  }

  void _onMention(String kind, String id) {
    if (kind == 'task') openTask(context, store, id);
  }

  // ------------------------------------------------------------ thao tác
  Future<void> _pickStatus() async {
    final s = await pickStatus(context, p!, current: t.statusId);
    if (s == null || s.id == t.statusId) return;
    if (s.isDone && t.subTotal > t.subDone && s.closeSubtasksPrompt && mounted) {
      if (await confirm(context, 'Còn ${t.subTotal - t.subDone} việc con chưa xong', 'Đóng luôn các việc con còn mở?', ok: 'Đóng luôn')) {
        final kids = _d!.subtasks.where((x) => !(p!.status(x.statusId)?.isClosed ?? false)).map((x) => x.id).toList();
        if (kids.isNotEmpty) await store.api.bulk(kids, {'status_id': s.id});
      }
    }
    await _patch({'status_id': s.id});
    if (s.isStart && t.hasAgent) _toast('Việc vào trạng thái bắt đầu: agent được giao sẽ bắt đầu làm');
  }

  Future<void> _pickAssignees() async {
    final r = await pickAssignees(context, store, current: t.assignees, projectId: t.projectId);
    if (r == null) return;
    final removedAgents = t.assignees.where((a) => a.isAgent && !r.contains(a)).map((a) => a.id).toSet();
    try {
      await store.setAssignees(t, r);
      // Bỏ giao agent đang chạy: dừng lượt chạy.
      for (final run in _d!.runs.where((x) => x.active && removedAgents.contains(x.botId))) {
        await store.cancelRun(run);
      }
      unawaited(_load(quiet: true));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _pickDate(String field) async {
    final cur = field == 'start' ? t.start : t.due;
    final d = await pickDay(context, initial: cur, today: store.today, help: field == 'start' ? 'Ngày bắt đầu' : 'Hạn');
    if (d == null) return;
    await _patch({field: dayStr(d)});
  }

  Future<void> _estimate() async {
    final v = await askText(context, title: 'Ước lượng', initial: t.estimate == null ? '' : '${t.estimate!.value}${t.estimate!.unit}', hint: 'vd 4h hoặc 2d (để trống = bỏ)');
    if (v == null) return;
    if (v.isEmpty) return _patch({'estimate': null});
    final m = RegExp(r'^([\d.,]+)\s*([hd]?)').firstMatch(v.toLowerCase());
    if (m == null) return _toast('Nhập số giờ (h) hoặc ngày (d), vd 4h');
    await _patch({'estimate': {'value': double.parse(m[1]!.replaceAll(',', '.')), 'unit': m[2]!.isEmpty ? 'h' : m[2]}});
  }

  Future<void> _start() async {
    try {
      final runs = await store.startAgents(t);
      _toast(runs.isEmpty ? 'Không có agent nào để bắt đầu' : 'Đang mở phiên cho ${runs.length} agent');
      unawaited(_load(quiet: true));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _addSubtask(String? parentId) async {
    final title = _subCtl.text.trim();
    if (title.isEmpty) return setState(() => _addingSubFor = null);
    _subCtl.clear();
    try {
      await store.createTask(t.projectId, {'title': title, 'parent_id': parentId ?? t.id});
      await _load(quiet: true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _toggleSub(TwTask s) async {
    final f = p!;
    final done = f.status(s.statusId)?.isDone ?? false;
    final target = done ? f.defaultStatus : f.firstDone;
    if (target == null) return;
    try {
      await store.updateTask(s, {'status_id': target.id});
      await _load(quiet: true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _upload() async {
    final files = await pickFilesOrReport(context);
    for (final f in files) {
      try {
        await store.api.upload(t.id, f.name, await f.readAsBytes());
      } catch (e) {
        _toast('$e');
      }
    }
    await _load(quiet: true);
  }

  Future<void> _drive() async {
    final name = TextEditingController(), url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Đính kèm từ Drive'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('drive-url'), controller: url, decoration: const InputDecoration(labelText: 'Link tệp trên Drive')),
          TextField(key: const ValueKey('drive-name'), controller: name, decoration: const InputDecoration(labelText: 'Tên hiển thị')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Huỷ')),
          FilledButton(key: const ValueKey('drive-ok'), onPressed: () => Navigator.pop(d, true), child: const Text('Đính kèm')),
        ],
      ),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    final n = name.text.trim().isEmpty ? Uri.tryParse(url.text.trim())?.pathSegments.lastOrNull ?? 'Tệp Drive' : name.text.trim();
    try {
      await store.api.attachDrive(t.id, n, url.text.trim());
      await _load(quiet: true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _addLink() async {
    final other = await pickTask(context, store, projectId: t.projectId, exclude: {t.id}, title: 'Liên kết tới việc');
    if (other == null || !mounted) return;
    final type = await twSheet<String>(
      context,
      width: 320,
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(c, '${t.key} … ${other.key}'),
        ListTile(key: const ValueKey('link-blocks'), leading: const Icon(Icons.block, color: Color(0xFFE5484D)), title: Text('Chặn ${other.key}'), subtitle: const Text('Việc này xong thì việc kia mới bắt đầu'), onTap: () => Navigator.pop(c, 'blocks')),
        ListTile(key: const ValueKey('link-blocked'), leading: const Icon(Icons.subdirectory_arrow_left), title: Text('Bị ${other.key} chặn'), onTap: () => Navigator.pop(c, 'blocked_by')),
        ListTile(key: const ValueKey('link-relates'), leading: const Icon(Icons.link), title: const Text('Liên quan'), onTap: () => Navigator.pop(c, 'relates')),
        ListTile(leading: const Icon(Icons.content_copy), title: const Text('Trùng'), onTap: () => Navigator.pop(c, 'duplicates')),
        const SizedBox(height: 8),
      ]),
    );
    if (type == null) return;
    try {
      if (type == 'blocked_by') {
        await store.api.addLink(other.id, t.id, 'blocks');
      } else {
        await store.api.addLink(t.id, other.id, type);
      }
      await _load(quiet: true);
      unawaited(store.openProject(t.projectId));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _reactTask(String e) async {
    setState(() => t.reactions = toggleReaction(t.reactions, e, store.meId));
    try {
      await store.api.react('task', t.id, e);
    } catch (_) {
      setState(() => t.reactions = toggleReaction(t.reactions, e, store.meId));
    }
  }

  Future<void> _watch() async {
    final on = !t.watchers.contains(store.meId);
    setState(() => on ? t.watchers = [...t.watchers, store.meId] : t.watchers = t.watchers.where((w) => w != store.meId).toList());
    try {
      await store.api.watch(t.id, on);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: store.api.taskLink(t.key)));
        _toast('Đã chép link ${t.key}');
      case 'delete':
        if (!await confirm(context, 'Xoá ${t.key}?', 'Việc vào thùng rác 30 ngày, Quản trị khôi phục được.', ok: 'Xoá', danger: true)) return;
        try {
          await store.deleteTask(t);
          if (mounted) Navigator.pop(context);
        } catch (e) {
          _toast('$e');
        }
    }
  }

  void _assignAgent() async {
    final r = await pickAssignees(context, store, current: t.assignees, projectId: t.projectId);
    if (r == null) return;
    await store.setAssignees(t, r);
    unawaited(_load(quiet: true));
  }

  void _openAi() => showAiSheet(context, store, _d!, onChanged: () => _load(quiet: true), onDraft: (b) => _comments.currentState?.setDraft(b), onAssignAgent: _assignAgent);

  // ------------------------------------------------------------ giao diện
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final d = _d;
    if (d == null) {
      return Scaffold(
        backgroundColor: look.bg,
        appBar: AppBar(backgroundColor: look.bg, title: Text(widget.idOrKey)),
        body: Center(child: _err == null ? const CircularProgressIndicator() : Text(_err!, style: TextStyle(color: look.red))),
      );
    }
    final wide = w >= 760, huge = w >= 1180;
    final body = _body(look, wide);
    return Scaffold(
      backgroundColor: look.bg,
      appBar: AppBar(
        backgroundColor: look.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(children: [
          if (p != null && wide) ...[ProjectBadge(p!.project), const SizedBox(width: 8), Text(p!.project.name, style: TextStyle(fontSize: 13.5, color: look.sub)), Icon(Icons.chevron_right, size: 18, color: look.sub)],
          if (d.parentKey != null) ...[
            InkWell(onTap: () => openTask(context, store, d.parentKey!), child: Text(d.parentKey!, style: TextStyle(fontSize: 13.5, color: look.sub))),
            Icon(Icons.chevron_right, size: 18, color: look.sub),
          ],
          Text(t.key, style: TextStyle(fontSize: 13.5, color: look.sub)),
        ]),
        actions: [
          if (!huge) IconButton(key: const ValueKey('ai-open'), tooltip: 'AI hỗ trợ', icon: Icon(Icons.auto_awesome, color: look.ai), onPressed: _openAi),
          if (huge && !_ai) IconButton(key: const ValueKey('ai-open'), tooltip: 'AI hỗ trợ', icon: Icon(Icons.auto_awesome, color: look.ai), onPressed: () => setState(() => _ai = true)),
          IconButton(
            key: const ValueKey('watch'),
            tooltip: t.watchers.contains(store.meId) ? 'Bỏ theo dõi' : 'Theo dõi',
            icon: Icon(t.watchers.contains(store.meId) ? Icons.notifications_active : Icons.notifications_none, color: t.watchers.contains(store.meId) ? look.accent : null),
            onPressed: _watch,
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Chép link')),
              if (canEdit) const PopupMenuItem(value: 'delete', child: Text('Xoá việc')),
            ],
          ),
        ],
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: body),
              Container(width: 300, decoration: BoxDecoration(border: Border(left: BorderSide(color: look.divider))), child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: _props(look, true))),
              if (huge && _ai)
                SizedBox(
                  width: 340,
                  child: TwAiPanel(
                    store: store,
                    detail: d,
                    onChanged: () => _load(quiet: true),
                    onDraft: (b) => _comments.currentState?.setDraft(b),
                    onAssignAgent: _assignAgent,
                    onClose: () => setState(() => _ai = false),
                  ),
                ),
            ])
          : body,
    );
  }

  Widget _section(String title, {String? count, List<Widget> actions = const [], Widget? extra}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Row(children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (count != null) ...[const SizedBox(width: 8), Text(count, style: TextStyle(color: TwLook.of(context).sub))],
          if (extra != null) ...[const SizedBox(width: 10), Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: extra))] else const Spacer(),
          if (extra != null) const SizedBox(width: 10),
          ...actions,
        ]),
      );

  Widget _body(TwLook look, bool wide) {
    final d = _d!;
    final sub = d.subtasks;
    final direct = childrenOf(sub, t.id);
    final doneN = direct.where((s) => p?.status(s.statusId)?.isDone ?? false).length;
    return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('task-title'),
        controller: _title,
        focusNode: _titleFocus,
        readOnly: !canEdit,
        maxLines: null,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
        onSubmitted: (_) => _saveTitle(),
      ),
      if (!wide) Padding(padding: const EdgeInsets.only(top: 6), child: _props(look, false)),
      const SizedBox(height: 10),
      if (canEdit)
        TwRichEditor(key: const ValueKey('desc'), blocks: t.description, onChanged: _descChanged, store: store, projectId: t.projectId, revision: _descRev)
      else if (t.description.isNotEmpty)
        TwRichView(t.description, onMention: _onMention),
      Padding(padding: const EdgeInsets.only(top: 8), child: ReactionRow(reactions: t.reactions, me: store.meId, keyPrefix: 'trx', onToggle: _reactTask)),
      if (t.hasAgent) _agentCard(look),
      _section('Việc con',
          count: direct.isEmpty ? null : '$doneN/${direct.length}',
          extra: direct.isEmpty ? null : ThinProgress(doneN / direct.length),
          actions: [
            if (canEdit)
              TextButton.icon(
                key: const ValueKey('ai-breakdown'),
                style: TextButton.styleFrom(foregroundColor: look.ai, backgroundColor: look.aiSoft, visualDensity: VisualDensity.compact),
                onPressed: () => MediaQuery.sizeOf(context).width >= 1180 ? setState(() => _ai = true) : _openAi(),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(wide ? 'AI chia nhỏ' : 'AI'),
              ),
            const SizedBox(width: 6),
            if (canEdit)
              OutlinedButton.icon(
                key: const ValueKey('sub-add'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _addingSubFor = t.id),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Thêm'),
              ),
          ]),
      ..._subtree(t.id, 0, look),
      if (_addingSubFor == t.id) _subInput(t.id),
      _section('Tệp đính kèm', count: d.attachments.isEmpty ? null : '${d.attachments.length}', actions: [
        if (canEdit) OutlinedButton.icon(key: const ValueKey('att-drive'), style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: _drive, icon: const Icon(Icons.add_to_drive, size: 16), label: const Text('Từ Drive')),
        const SizedBox(width: 6),
        if (canEdit) OutlinedButton.icon(key: const ValueKey('att-upload'), style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: _upload, icon: const Icon(Icons.upload, size: 16), label: const Text('Tải lên')),
      ]),
      if (d.attachments.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: [for (final a in d.attachments) _attTile(a, look)]),
      const SizedBox(height: 18),
      Row(children: [
        _tabBtn('comments', 'Bình luận ${t.commentCount > 0 ? t.commentCount : ''}'.trim(), look),
        _tabBtn('activity', 'Hoạt động', look),
      ]),
      Divider(height: 1, color: look.divider),
      if (_tab == 'comments')
        TwComments(key: _comments, store: store, task: t, onMention: _onMention, canComment: p != null)
      else
        _activityList(look),
    ]));
  }

  Widget _tabBtn(String k, String label, TwLook look) => InkWell(
        key: ValueKey('tab-$k'),
        onTap: () {
          setState(() => _tab = k);
          if (k == 'activity') _loadActivity();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == k ? look.accent : Colors.transparent, width: 2))),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: _tab == k ? look.accent : look.sub)),
        ),
      );

  Widget _agentCard(TwLook look) {
    final agents = t.assignees.where((a) => a.isAgent).toList();
    final runs = _d!.runs;
    return Container(
      key: const ValueKey('agent-card'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: look.aiSoft, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final a in agents)
          () {
            final run = runs.where((r) => r.botId == a.id).firstOrNull;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                TwAvatar.of(a, size: 26, border: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      run == null ? 'Chưa bắt đầu. Bấm Bắt đầu hoặc kéo việc vào "${p?.startStatus?.name ?? 'trạng thái bắt đầu'}".' : '${kRunStateNames[run.state] ?? run.state}${run.error == null ? '' : ': ${run.error}'}',
                      style: TextStyle(fontSize: 12, color: look.ai),
                    ),
                  ]),
                ),
                if (run?.sessionChannel != null && store.launcher != null)
                  TextButton(key: ValueKey('run-open-${a.id}'), onPressed: () => store.launcher!.open(run!.sessionChannel!), child: const Text('Mở phiên')),
                if (run != null && run.active)
                  TextButton(
                    key: ValueKey('run-cancel-${a.id}'),
                    onPressed: () async {
                      await store.cancelRun(run);
                      unawaited(_load(quiet: true));
                    },
                    child: const Text('Dừng'),
                  ),
              ]),
            );
          }(),
        if (canEdit && !runs.any((r) => r.active)) ...[
          const SizedBox(height: 6),
          FilledButton.icon(
            key: const ValueKey('agent-start'),
            style: FilledButton.styleFrom(backgroundColor: look.ai),
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Bắt đầu'),
          ),
        ],
      ]),
    );
  }

  List<Widget> _subtree(String parentId, int depth, TwLook look) {
    final out = <Widget>[];
    for (final s in childrenOf(_d!.subtasks, parentId)) {
      final st = p?.status(s.statusId);
      final done = st?.isDone ?? false;
      final kids = childrenOf(_d!.subtasks, s.id);
      out.add(InkWell(
        key: ValueKey('sub-${s.key}'),
        onTap: () => openTask(context, store, s.key),
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: EdgeInsets.only(left: 6.0 + depth * 22, right: 6, top: 5, bottom: 5),
          child: Row(children: [
            InkWell(
              key: ValueKey('subck-${s.key}'),
              onTap: canEdit ? () => _toggleSub(s) : null,
              child: Icon(done ? Icons.check_box : Icons.check_box_outline_blank, size: 19, color: done ? look.ok : look.sub),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(s.title, style: TextStyle(color: done ? look.sub : look.text, decoration: done ? TextDecoration.lineThrough : null))),
            if (kids.isNotEmpty) Text('${kids.where((k) => p?.status(k.statusId)?.isDone ?? false).length}/${kids.length}  ', style: TextStyle(fontSize: 12, color: look.sub)),
            if (s.run?.active ?? false) Padding(padding: const EdgeInsets.only(right: 6), child: Text('đang làm', style: TextStyle(fontSize: 12, color: look.ai, fontWeight: FontWeight.w600))),
            if (s.due != null) Padding(padding: const EdgeInsets.only(right: 6), child: Text(dShort(s.due!), style: TextStyle(fontSize: 12, color: look.sub))),
            TwAvatars(s.assignees, size: 22, max: 2),
            if (canEdit && depth < 2)
              IconButton(tooltip: 'Thêm việc con', visualDensity: VisualDensity.compact, iconSize: 16, onPressed: () => setState(() => _addingSubFor = s.id), icon: Icon(Icons.add, color: look.sub)),
          ]),
        ),
      ));
      out.addAll(_subtree(s.id, depth + 1, look));
      if (_addingSubFor == s.id) out.add(Padding(padding: EdgeInsets.only(left: 22.0 * (depth + 1)), child: _subInput(s.id)));
    }
    return out;
  }

  Widget _subInput(String parentId) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          key: const ValueKey('sub-input'),
          controller: _subCtl,
          autofocus: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tên việc con, Enter để thêm',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _addingSubFor = null)),
          ),
          onSubmitted: (_) => _addSubtask(parentId),
        ),
      );

  Widget _attTile(TwAttachment a, TwLook look) {
    const colors = {'XLS': Color(0xFF2B9348), 'XLSX': Color(0xFF2B9348), 'PDF': Color(0xFFE5484D), 'DOC': Color(0xFF1E7BFF), 'DOCX': Color(0xFF1E7BFF), 'PNG': Color(0xFF7C5CFF), 'JPG': Color(0xFF7C5CFF)};
    return InkWell(
      key: ValueKey('att-${a.id}'),
      onTap: () => openAttachment(context, store, a),
      onLongPress: canEdit
          ? () async {
              if (!await confirm(context, 'Gỡ tệp?', a.name, ok: 'Gỡ', danger: true)) return;
              await store.api.deleteAttachment(a.id);
              await _load(quiet: true);
            }
          : null,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 230,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(9)),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colors[a.ext] ?? look.sub, borderRadius: BorderRadius.circular(7)),
            child: Text(a.ext.isEmpty ? '?' : a.ext.substring(0, a.ext.length.clamp(0, 4)), style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              Text([if (a.size > 0) _size(a.size), if (a.isDrive) 'Drive'].join(' · '), style: TextStyle(fontSize: 11.5, color: look.sub)),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _size(int b) => b < 1024 ? '$b B' : (b < 1048576 ? '${(b / 1024).round()} KB' : '${(b / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB');

  Widget _activityList(TwLook look) {
    final l = _activity;
    if (l == null) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (l.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có hoạt động', style: TextStyle(color: look.sub)));
    String describe(TwActivity a) {
      final dta = a.data;
      String st(Object? id) => p?.status('$id')?.name ?? '${dta['${id}_name'] ?? id ?? ''}';
      return switch (a.type) {
        'created' => 'tạo việc',
        'status' => 'chuyển ${dta['from_name'] ?? st(dta['from'])} → ${dta['to_name'] ?? st(dta['to'])}',
        'assign' => 'đổi người làm',
        'field' => 'sửa ${dta['field'] ?? ''}',
        'comment' => 'bình luận',
        'link' => 'thêm liên kết',
        'attach' => 'đính kèm ${dta['name'] ?? 'tệp'}',
        'run' => 'agent ${kRunStateNames['${dta['state']}'] ?? dta['state'] ?? ''}',
        'deleted' => 'xoá việc',
        'restored' => 'khôi phục việc',
        _ => a.type,
      };
    }

    return Column(children: [
      for (final a in l)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(a.type == 'status' ? Icons.swap_horiz : (a.type == 'run' ? Icons.smart_toy_outlined : Icons.history), size: 16, color: look.sub),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: look.sub), children: [
                TextSpan(text: a.actorName, style: TextStyle(fontWeight: FontWeight.w600, color: look.text)),
                if (a.via.startsWith('agent:') || a.via == 'mcp') TextSpan(text: ' (agent)', style: TextStyle(color: look.ai)),
                TextSpan(text: ' ${describe(a)} · ${timeAgo(a.at, store.now)}'),
              ])),
            ),
          ]),
        ),
    ]);
  }

  /// Thuộc tính: cột phải (máy tính) hoặc hàng chip (điện thoại).
  Widget _props(TwLook look, bool column) {
    final f = p;
    final st = store.statusOf(t);
    final late = t.due != null && t.due!.isBefore(store.today) && !(st?.isClosed ?? false);
    if (!column) {
      Widget chip(Widget child, VoidCallback? onTap, {Key? key}) => TwPill(key: key, onTap: canEdit ? onTap : null, child: child);
      return Wrap(spacing: 6, runSpacing: 6, children: [
        chip(Row(mainAxisSize: MainAxisSize.min, children: [StatusRing(st), const SizedBox(width: 6), Text(st?.name ?? '—')]), _pickStatus, key: const ValueKey('p-status')),
        chip(Row(mainAxisSize: MainAxisSize.min, children: [PriorityIcon(t.priority), const SizedBox(width: 4), Text(kPriorityNames[t.priority]!)]), () async {
          final v = await pickPriority(context, current: t.priority);
          if (v != null) await _patch({'priority': v});
        }),
        chip(Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event_outlined), const SizedBox(width: 4), Text(t.due == null ? 'Hạn' : dShort(t.due!), style: TextStyle(color: late ? look.red : null))]), () => _pickDate('due')),
        chip(t.assignees.isEmpty ? const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.person_add_alt), SizedBox(width: 4), Text('Người làm')]) : TwAvatars(t.assignees, size: 20), _pickAssignees, key: const ValueKey('p-assignees')),
        if (f != null && t.labels.isNotEmpty) for (final l in t.labels) if (f.label(l) != null) LabelChip(f.label(l)!),
      ]);
    }
    Widget row(String label, Widget value, {VoidCallback? onTap, Key? key, bool top = false}) => InkWell(
          key: key,
          onTap: canEdit ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Row(crossAxisAlignment: top ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
              SizedBox(width: 96, child: Text(label, style: TextStyle(color: look.sub, fontSize: 13))),
              Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: value)),
            ]),
          ),
        );
    final links = _d!.links;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Trạng thái', Row(children: [StatusRing(st), const SizedBox(width: 6), Flexible(child: Text(st?.name ?? '—')), const Icon(Icons.expand_more, size: 16)]), onTap: _pickStatus, key: const ValueKey('p-status')),
      row(
        'Người làm',
        t.assignees.isEmpty
            ? Text('Chưa giao', style: TextStyle(color: look.sub))
            : Wrap(spacing: 8, runSpacing: 4, children: [
                for (final a in t.assignees) Row(mainAxisSize: MainAxisSize.min, children: [TwAvatar.of(a, size: 22, border: false), const SizedBox(width: 5), Text(a.name.split(' (').first)]),
              ]),
        onTap: _pickAssignees,
        key: const ValueKey('p-assignees'),
      ),
      row('Ưu tiên', Row(children: [PriorityIcon(t.priority), const SizedBox(width: 4), Text(kPriorityNames[t.priority]!)]), onTap: () async {
        final v = await pickPriority(context, current: t.priority);
        if (v != null) await _patch({'priority': v});
      }, key: const ValueKey('p-priority')),
      row('Bắt đầu', Text(t.start == null ? '—' : dLong(t.start!)), onTap: () => _pickDate('start'), key: const ValueKey('p-start')),
      row('Hạn', Text(t.due == null ? '—' : dLong(t.due!), style: TextStyle(fontWeight: FontWeight.w700, color: late ? look.red : null)), onTap: () => _pickDate('due'), key: const ValueKey('p-due')),
      row('Ước lượng', Text(t.estimate?.label ?? '—'), onTap: _estimate),
      row(
        'Nhãn',
        t.labels.isEmpty || f == null
            ? Text('—', style: TextStyle(color: look.sub))
            : Wrap(spacing: 4, runSpacing: 4, children: [for (final l in t.labels) if (f.label(l) != null) LabelChip(f.label(l)!)]),
        onTap: f == null
            ? null
            : () async {
                final r = await pickLabels(context, f, current: t.labels);
                if (r != null) await _patch({'labels': r});
              },
        key: const ValueKey('p-labels'),
      ),
      row(
        'Liên kết',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in links)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () => openTask(context, store, l.otherKey),
                child: Row(children: [
                  Icon(l.type == 'blocks' ? (l.fromTask == t.id ? Icons.block : Icons.subdirectory_arrow_left) : Icons.link, size: 15, color: l.type == 'blocks' && l.fromTask == t.id ? look.red : look.sub),
                  const SizedBox(width: 4),
                  Text(switch (l.type) { 'blocks' => l.fromTask == t.id ? 'Chặn ' : 'Sau ', 'duplicates' => 'Trùng ', _ => 'Liên quan ' }, style: const TextStyle(fontSize: 12.5)),
                  Flexible(child: Text(l.otherKey, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                  if (canEdit)
                    InkWell(
                      onTap: () async {
                        await store.api.removeLink(l.id);
                        await _load(quiet: true);
                      },
                      child: Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.close, size: 13, color: look.sub)),
                    ),
                ]),
              ),
            ),
          if (canEdit) InkWell(key: const ValueKey('link-add'), onTap: _addLink, child: Text('+ Thêm liên kết', style: TextStyle(color: look.accent, fontSize: 12.5))),
        ]),
        top: true,
      ),
      row('Người theo dõi', t.watchers.isEmpty ? Text('—', style: TextStyle(color: look.sub)) : Text('${t.watchers.length} người${t.watchers.contains(store.meId) ? ' (có bạn)' : ''}')),
      if (t.createdAt > 0) row('Tạo', Text(timeAgo(t.createdAt, store.now), style: TextStyle(color: look.sub))),
    ]);
  }
}
