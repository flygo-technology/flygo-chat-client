// TeamWork: kho dữ liệu của màn hình. Giữ danh sách dự án, cấu hình + việc của các dự án đã mở, "Việc của tôi", thông báo
// và danh sách agent. Lưu xuống máy để mất mạng vẫn xem được; sửa khi mất mạng thì áp ngay trên máy và xếp hàng gửi lại
// khi có mạng. Nhận sự kiện realtime qua WebSocket (live.dart) và tải lại phần thay đổi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../todo/model.dart';
import 'api.dart';
import 'live.dart';
import 'model.dart';

/// Mở phiên agent (cài bằng agent_runs.dart; kiểm thử dùng bản giả).
abstract class TwAgentLauncher {
  /// Người dùng hiện tại có được dùng agent [botId] không.
  Future<bool> canUse(String botId);

  /// Mở phiên mới với agent [botId] dưới tên người dùng, gửi [brief] (kèm [props]); trả về id kênh phiên.
  Future<String> launch(String botId, String title, String brief, {Map<String, dynamic> props = const {}});

  /// Người dùng hiện tại là chủ bot [botId].
  Future<bool> isOwnerOf(String botId);

  /// Gửi lời dừng vào phiên [channelId] (nếu phiên ở máy này).
  Future<void> stop(String channelId);

  /// Phiên [channelId] còn dùng được (còn tồn tại, mình là chủ, có agent [botId]).
  Future<bool> sessionUsable(String channelId, String botId);

  /// Gửi [text] vào phiên sẵn có [channelId] (kèm [props]).
  Future<void> post(String channelId, String text, {Map<String, dynamic> props = const {}});

  /// Mở phiên trong chat.
  void open(String channelId);
}

class TwStore extends ChangeNotifier {
  TwStore(this.api, {this.cacheKey, DateTime Function()? clock, this.live = true}) : _clock = clock ?? DateTime.now;

  final TwApi api;
  final String? cacheKey;
  final DateTime Function() _clock;
  /// Bật WebSocket (kiểm thử tắt).
  final bool live;
  TwAgentLauncher? launcher;

  String meId = '', meName = '';
  bool isAdmin = false;
  Map<String, dynamic> prefs = {};
  List<TwProject> projects = [];
  final Map<String, TwProjectFull> full = {};
  final Map<String, List<TwTask>> _tasks = {};
  final Map<String, List<TwTask>> mine = {};
  List<TwNotification> notifications = [];
  int unread = 0;
  List<TwAgent> agents = [];
  bool loaded = false, offline = false;
  String? error;
  /// Tăng khi một việc đổi từ ngoài (WebSocket): trang chi tiết đang mở tải lại.
  final Map<String, int> taskRev = {};
  /// Tăng khi một lượt chạy agent có tiến độ mới (run_progress): khối tiến độ tải lại.
  final Map<String, int> runRev = {};
  /// Cột bình luận / hoạt động của trang việc đang thu gọn (nhớ trên máy) + cách lưu.
  bool commentsCollapsed = false;
  Future<void> Function(bool collapsed)? saveCommentsCollapsed;
  /// Độ rộng khung việc bên phải đã chọn (null = 40% cửa sổ) + cách lưu lại trên máy.
  double? panelWidth;
  Future<void> Function(double width)? savePanelWidth;
  /// Bản nháp mô tả đang sửa theo id việc (đóng trang không mất).
  final Map<String, List<TBlock>> descDrafts = {};
  /// Lệnh chờ gửi lại khi có mạng: {m, p, b}.
  final List<Map<String, dynamic>> queue = [];

  bool _disposed = false;
  Timer? _save, _reload;
  TwLive? _live;
  final Set<String> _dirtyProjects = {};
  final Set<String> _claiming = {};
  /// Tên máy khi nhận lượt chạy (máy chủ chỉ cho một máy nhận).
  final String device = 'app-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  DateTime get now => _clock();
  DateTime get today => dayOnly(_clock().toUtc().add(const Duration(hours: 7)));

  List<TwTask> tasksOf(String pid) => _tasks[pid] ?? const [];
  TwProject? projectById(String id) => projects.where((p) => p.id == id).firstOrNull ?? full[id]?.project;
  TwProjectFull? fullOf(String? pid) => pid == null ? null : full[pid];
  TwTask? taskById(String id) {
    for (final l in _tasks.values) {
      for (final t in l) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  TwStatus? statusOf(TwTask t) => full[t.projectId]?.status(t.statusId) ?? t.statusInfo;
  TwAgent? agent(String id) => agents.where((a) => a.id == id).firstOrNull;

  void _changed({bool persist = true}) {
    if (_disposed) return;
    notifyListeners();
    if (persist) _persist();
  }

  void _netError(Object e) {
    if (TwApi.isOffline(e)) {
      offline = true;
    } else {
      error = '$e';
    }
  }

  // ------------------------------------------------------------ khởi động
  Future<void> start() async {
    await _restore();
    if (loaded) _changed(persist: false);
    await refresh();
    if (live && !_disposed) {
      _live = TwLive(api, onEvent: _onEvent, onState: (up) {
        if (up && offline) refresh();
      });
      _live!.connect();
      _live!.subscribe(full.keys.toList());
    }
  }

  Future<void> refresh() async {
    try {
      final me = await api.me();
      final u = me['user'] is Map ? me['user'] as Map : const {};
      meId = '${u['id'] ?? ''}';
      meName = '${u['name'] ?? u['username'] ?? ''}';
      isAdmin = me['is_admin'] == true;
      prefs = me['prefs'] is Map ? (me['prefs'] as Map).cast<String, dynamic>() : {};
      offline = false;
      error = null;
      await _flush();
      projects = await api.projects();
      loaded = true;
      _changed();
      unawaited(loadAgents());
      unawaited(loadNotifications());
      for (final pid in full.keys.toList()) {
        unawaited(openProject(pid));
      }
      unawaited(checkRuns());
    } catch (e) {
      _netError(e);
      loaded = true;
      _changed(persist: false);
    }
  }

  Future<void> loadAgents() async {
    try {
      agents = await api.agents();
      _changed();
    } catch (_) {}
  }

  /// Tải cấu hình + việc của dự án [pid].
  Future<void> openProject(String pid) async {
    try {
      final f = await api.project(pid);
      full[pid] = f;
      final i = projects.indexWhere((p) => p.id == pid);
      if (i >= 0) projects[i] = f.project;
      _tasks[pid] = await api.tasks(pid);
      _live?.subscribe(full.keys.toList());
      _changed();
    } catch (e) {
      _netError(e);
      _changed(persist: false);
    }
  }

  Future<void> loadMine(String tab) async {
    try {
      final (tasks, projs) = await api.mineWithProjects(tab);
      for (final p in projs) {
        if (!projects.any((x) => x.id == p.id)) projects.add(p);
      }
      mine[tab] = tasks;
      _changed();
    } catch (e) {
      _netError(e);
      _changed(persist: false);
    }
  }

  Future<void> loadNotifications() async {
    try {
      final (list, n) = await api.notifications();
      notifications = list;
      unread = n >= 0 ? n : list.where((x) => !x.read).length;
      _changed();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    for (final n in notifications) {
      n.read = true;
    }
    unread = 0;
    _changed();
    try {
      await api.markRead();
    } catch (_) {}
  }

  // ------------------------------------------------------------ realtime
  void _onEvent(Map ev) {
    final type = '${ev['type'] ?? ''}';
    final pid = ev['project_id'] as String?;
    final tid = ev['task_id'] as String?;
    if (type == 'run_progress') {
      final id = ev['id'] as String?;
      if (id != null) runRev[id] = (runRev[id] ?? 0) + 1;
      _changed(persist: false);
      return;
    }
    if (type == 'run') {
      unawaited(checkRuns());
      final id = ev['id'] as String?;
      if (id != null) runRev[id] = (runRev[id] ?? 0) + 1;
    }
    if (type == 'notification') {
      unawaited(loadNotifications());
      return;
    }
    if (tid != null) taskRev[tid] = (taskRev[tid] ?? 0) + 1;
    if (pid != null && full.containsKey(pid)) {
      _dirtyProjects.add(pid);
      _reload?.cancel();
      _reload = Timer(const Duration(milliseconds: 300), () {
        final l = _dirtyProjects.toList();
        _dirtyProjects.clear();
        for (final p in l) {
          unawaited(openProject(p));
        }
      });
    } else if (type == 'project' || type == 'member') {
      unawaited(refresh());
    }
    _changed(persist: false);
  }

  /// Gọi khi WebSocket không có (kiểm thử) để giả lập sự kiện.
  @visibleForTesting
  void debugEvent(Map ev) => _onEvent(ev);

  // ------------------------------------------------------------ dự án
  Future<TwProjectFull> createProject(Map<String, dynamic> body) async {
    final f = await api.createProject(body);
    full[f.project.id] = f;
    projects = [f.project, ...projects.where((p) => p.id != f.project.id)];
    _tasks[f.project.id] = [];
    _changed();
    return f;
  }

  Future<void> updateProject(String pid, Map<String, dynamic> patch) async {
    final p = await api.updateProject(pid, patch);
    final i = projects.indexWhere((x) => x.id == pid);
    if (i >= 0) projects[i] = p;
    full[pid]?.project = p;
    _changed();
  }

  Future<void> star(TwProject p) async {
    p.starred = !p.starred;
    _changed();
    try {
      await api.star(p.id, p.starred);
    } catch (e) {
      p.starred = !p.starred;
      _changed();
      rethrow;
    }
  }

  Future<void> deleteProject(String pid) async {
    await api.deleteProject(pid);
    projects.removeWhere((p) => p.id == pid);
    full.remove(pid);
    _tasks.remove(pid);
    _changed();
  }

  // ------------------------------------------------------------ cấu hình dự án
  Future<void> saveStatus(String pid, TwStatus s, {bool create = false}) async {
    if (create) {
      await api.createStatus(pid, s.toJson()..remove('id'));
    } else {
      await api.updateStatus(s.id, s.toJson()..remove('id'));
    }
    await openProject(pid);
  }

  Future<void> deleteStatus(String pid, String id, String moveTo) async {
    await api.deleteStatus(id, moveTo);
    await openProject(pid);
  }

  Future<void> reorderStatuses(String pid, List<String> ids) async {
    final f = full[pid];
    if (f != null) {
      for (var i = 0; i < ids.length; i++) {
        f.status(ids[i])?.pos = i;
      }
      f.statuses.sort((a, b) => a.pos.compareTo(b.pos));
      _changed();
    }
    await api.reorderStatuses(pid, ids);
  }

  /// Đặt trạng thái "bắt đầu" (luôn đúng một trạng thái).
  Future<void> setStartStatus(String pid, String id) async {
    final f = full[pid];
    if (f == null) return;
    for (final s in f.statuses) {
      s.isStart = s.id == id;
    }
    _changed();
    await api.updateStatus(id, {'is_start': true});
    await openProject(pid);
  }

  Future<void> saveLabel(String pid, {String? id, required String name, required String color}) async {
    if (id == null) {
      await api.createLabel(pid, name, color);
    } else {
      await api.updateLabel(id, {'name': name, 'color': color});
    }
    await openProject(pid);
  }

  Future<void> deleteLabel(String pid, String id) async {
    await api.deleteLabel(id);
    await openProject(pid);
  }

  Future<void> setMember(String pid, String type, String id, String role) async {
    await api.setMember(pid, type, id, role);
    await openProject(pid);
  }

  Future<void> removeMember(String pid, String type, String id) async {
    await api.removeMember(pid, type, id);
    await openProject(pid);
  }

  // ------------------------------------------------------------ việc
  void _put(TwTask t) {
    final l = _tasks.putIfAbsent(t.projectId, () => []);
    final i = l.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      l[i] = t;
    } else {
      l.add(t);
    }
    for (final m in mine.values) {
      final j = m.indexWhere((x) => x.id == t.id);
      if (j >= 0) m[j] = t;
    }
    // Đếm lại việc con của việc cha.
    if (t.parentId != null) {
      final p = l.where((x) => x.id == t.parentId).firstOrNull;
      if (p != null) {
        final kids = l.where((x) => x.parentId == p.id && x.deletedAt == null).toList();
        p.subTotal = kids.length;
        p.subDone = kids.where((k) => full[p.projectId]?.status(k.statusId)?.isDone ?? false).length;
      }
    }
  }

  Future<TwTask> createTask(String pid, Map<String, dynamic> body) async {
    final t = await api.createTask(pid, body);
    _put(t);
    _changed();
    return t;
  }

  /// Sửa trường của việc: áp ngay trên máy; mất mạng thì xếp hàng gửi lại.
  Future<void> updateTask(TwTask t, Map<String, dynamic> patch) async {
    final local = TwTask.fromJson({...t.toJson(), ...patch});
    _put(local);
    _changed();
    try {
      final r = await api.updateTask(t.id, patch);
      _put(r);
      _changed();
      if (patch.containsKey('status_id')) unawaited(checkRuns());
    } catch (e) {
      if (TwApi.isOffline(e)) {
        offline = true;
        _enqueue('PATCH', '/api/tasks/${t.id}', patch);
        _changed();
        return;
      }
      _put(t);
      _changed();
      rethrow;
    }
  }

  /// Chuyển việc sang trạng thái [statusId] và đặt giữa [before] / [after] (thứ tự Kanban).
  Future<void> moveTask(TwTask t, {String? statusId, TwTask? before, TwTask? after}) async {
    final old = t.copy();
    if (statusId != null) t.statusId = statusId;
    t.rank = rankBetween(after?.rank ?? '', before?.rank ?? '');
    _put(t);
    _changed();
    try {
      final r = await api.moveTask(t.id, statusId: statusId, beforeId: before?.id, afterId: after?.id);
      _put(r);
      _changed();
      unawaited(checkRuns());
    } catch (e) {
      if (TwApi.isOffline(e)) {
        offline = true;
        _enqueue('POST', '/api/tasks/${t.id}/move', {'status_id': ?statusId, 'before_id': ?before?.id, 'after_id': ?after?.id});
        _changed();
        return;
      }
      _put(old);
      _changed();
      rethrow;
    }
  }

  Future<void> setAssignees(TwTask t, List<TwAssignee> a) async {
    final old = t.assignees;
    t.assignees = a;
    _put(t);
    _changed();
    try {
      _put(await api.setAssignees(t.id, a));
      _changed();
    } catch (e) {
      t.assignees = old;
      _put(t);
      _changed();
      rethrow;
    }
  }

  Future<List<TwTask>> schedule(TwTask t, DateTime? start, DateTime? due, {bool shift = false}) async {
    t.start = start;
    t.due = due;
    _put(t);
    _changed();
    final changed = await api.schedule(t.id, start, due, shiftDependents: shift);
    for (final c in changed) {
      _put(c);
    }
    _changed();
    return changed;
  }

  Future<void> deleteTask(TwTask t) async {
    await api.deleteTask(t.id);
    _tasks[t.projectId]?.removeWhere((x) => x.id == t.id);
    for (final m in mine.values) {
      m.removeWhere((x) => x.id == t.id);
    }
    _changed();
  }

  /// Bấm "Bắt đầu": máy chủ tạo lượt chạy cho các agent đang được giao; máy này nhận và mở phiên.
  Future<List<TwRun>> startAgents(TwTask t) async {
    final runs = await api.start(t.id);
    if (runs.isNotEmpty) t.run = runs.first;
    _put(t);
    _changed();
    await checkRuns();
    return runs;
  }

  Future<void> cancelRun(TwRun r) async {
    await api.cancelRun(r.id);
    final ch = r.sessionChannel;
    if (ch != null) {
      try {
        await launcher?.stop(ch);
      } catch (_) {}
    }
    r.state = 'cancelled';
    _changed();
  }

  /// Nhận các lượt chạy đang chờ của mình: mở phiên với agent và gửi bản giao việc.
  Future<void> checkRuns() async {
    final l = launcher;
    if (l == null) return;
    List<TwRun> runs;
    try {
      runs = await api.runs(state: 'queued');
    } catch (_) {
      return;
    }
    for (final r in runs) {
      if (!_claiming.add(r.id)) continue;
      try {
        final claimed = await api.claim(r.id, device, attestOwner: await l.isOwnerOf(r.botId));
        if (claimed == null) continue;
        if (!await l.canUse(r.botId)) {
          await api.reportRun(r.id, 'blocked', error: 'Người bắt đầu không được dùng agent ${r.botName.isEmpty ? r.botId : r.botName}');
          continue;
        }
        final d = await api.task(r.taskId.isNotEmpty ? r.taskId : r.taskKey);
        final brief = claimed.$2 ?? briefOf(d, api.taskLink(d.task.key));
        // @nhắc agent: tiếp tục trong phiên sẵn có của việc này nếu còn dùng được, không thì mở phiên mới.
        final hint = claimed.$1.sessionHint ?? r.sessionHint;
        // run_token: runner kiểm bằng khoá của TeamWork rồi mới đẩy tiến độ / chạy không cần duyệt.
        final props = <String, dynamic>{if (claimed.$3 != null) 'flygo_teamwork': {'run_token': claimed.$3, 'run_id': r.id}};
        String ch;
        if (hint != null && await l.sessionUsable(hint, r.botId)) {
          await l.post(hint, brief, props: props);
          ch = hint;
        } else {
          ch = await l.launch(r.botId, '${d.task.key} · ${d.task.title}', brief, props: props);
        }
        await api.reportRun(r.id, 'running', sessionChannel: ch);
        taskRev[d.task.id] = (taskRev[d.task.id] ?? 0) + 1;
      } catch (e) {
        try {
          await api.reportRun(r.id, 'failed', error: '$e');
        } catch (_) {}
      } finally {
        _claiming.remove(r.id);
      }
    }
    _changed(persist: false);
  }

  // ------------------------------------------------------------ hàng đợi khi mất mạng
  void _enqueue(String m, String p, Object? b) {
    queue.add({'m': m, 'p': p, 'b': b});
    _persist();
  }

  Future<void> _flush() async {
    while (queue.isNotEmpty) {
      final op = queue.first;
      try {
        await api.raw('${op['m']}', '${op['p']}', op['b']);
      } catch (e) {
        if (TwApi.isOffline(e)) rethrow;
        debugPrint('[teamwork] bỏ lệnh lỗi khi gửi lại: $e');
      }
      queue.removeAt(0);
    }
  }

  // ------------------------------------------------------------ bộ nhớ đệm
  Future<File?> _file() async {
    if (cacheKey == null) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}teamwork_$cacheKey.json');
  }

  Future<void> _restore() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map;
      meId = '${j['me'] ?? ''}';
      meName = '${j['me_name'] ?? ''}';
      isAdmin = j['admin'] == true;
      projects = [for (final p in j['projects'] as List? ?? const []) TwProject.fromJson(p as Map)];
      (j['full'] as Map? ?? const {}).forEach((k, v) => full['$k'] = TwProjectFull.fromJson(v as Map));
      (j['tasks'] as Map? ?? const {}).forEach((k, v) => _tasks['$k'] = [for (final t in v as List) TwTask.fromJson(t as Map)]);
      (j['mine'] as Map? ?? const {}).forEach((k, v) => mine['$k'] = [for (final t in v as List) TwTask.fromJson(t as Map)]);
      notifications = [for (final n in j['notifications'] as List? ?? const []) TwNotification.fromJson(n as Map)];
      agents = [for (final a in j['agents'] as List? ?? const []) TwAgent.fromJson(a as Map)];
      queue.addAll([for (final q in j['queue'] as List? ?? const []) (q as Map).cast<String, dynamic>()]);
      loaded = projects.isNotEmpty;
    } catch (e) {
      debugPrint('[teamwork] bộ nhớ đệm hỏng, bỏ qua: $e');
    }
  }

  void _persist() {
    if (cacheKey == null) return;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 800), () async {
      try {
        final f = await _file();
        if (f == null) return;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode({
          'me': meId,
          'me_name': meName,
          'admin': isAdmin,
          'projects': [for (final p in projects) p.toJson()],
          'full': {for (final e in full.entries) e.key: e.value.toJson()},
          'tasks': {for (final e in _tasks.entries) e.key: [for (final t in e.value) t.toJson()]},
          'mine': {for (final e in mine.entries) e.key: [for (final t in e.value) t.toJson()]},
          'notifications': [for (final n in notifications.take(100)) n.toJson()],
          'agents': [for (final a in agents) a.toJson()],
          'queue': queue,
        }));
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('[teamwork] không lưu được bộ nhớ đệm: $e');
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _save?.cancel();
    _reload?.cancel();
    _live?.close();
    super.dispose();
  }
}

/// Bản giao việc gửi agent: tiêu đề, link, mô tả, việc con còn mở, tệp, và cách báo kết quả.
String briefOf(TwTaskDetail d, String link) {
  final t = d.task;
  final b = StringBuffer()
    ..writeln('[teamwork task=${t.key}]')
    ..writeln('Việc được giao: **${t.key} — ${t.title}**')
    ..writeln('Link: $link');
  if (t.due != null) b.writeln('Hạn: ${dayStr(t.due!)}');
  final desc = blocksToMarkdown(t.description).trim();
  if (desc.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Mô tả:')
      ..writeln(desc);
  }
  final open = d.subtasks.where((s) => s.parentId == t.id && s.doneAt == null).toList();
  if (open.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Việc con còn mở:');
    for (final s in open) {
      b.writeln('- ${s.key} ${s.title}');
    }
  }
  if (d.attachments.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Tệp đính kèm: ${d.attachments.map((a) => a.name).join(', ')}');
  }
  b
    ..writeln()
    ..writeln('Cách làm: dùng tool TeamWork (task_get, comment_add, task_update…) để đọc thêm và cập nhật. '
        'Báo kết quả bằng bình luận trên việc. Xong thì gọi agent_report với state "review" (hoặc "failed" nếu không làm được) kèm tóm tắt. '
        'Không tự chuyển việc sang Xong: người giao sẽ duyệt.');
  return b.toString();
}
