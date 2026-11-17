// TeamWork: kho dữ liệu của màn hình. Giữ danh sách dự án, cấu hình + việc của các dự án đã mở, "Việc của tôi", thông báo
// và danh sách agent. Lưu xuống máy để mất mạng vẫn xem được; sửa khi mất mạng thì áp ngay trên máy và xếp hàng gửi lại
// khi có mạng. Nhận sự kiện realtime qua WebSocket (live.dart) và tải lại phần thay đổi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, Widget;
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

/// Thao tác chat bằng token của chính người dùng (tạo / gắn nhóm chat cho dự án). App cài bằng AppState; kiểm thử dùng bản giả.
/// Thông tin kênh chat gửi lại cho TeamWork.
typedef TwChannelInfo = ({String id, String teamId, String name, String displayName, String url});

abstract class TwChatOps {
  /// Tạo kênh; trả về thông tin kênh.
  Future<TwChannelInfo> createChannel({String? teamId, required String name, required String displayName, bool private = true, String purpose = '', String header = ''});
  Future<void> addMember(String channelId, String userId);
  /// Mình có là thành viên kênh không.
  Future<bool> isMember(String channelId);
  /// Team có nhiều người trong [userIds] nhất (trong các team của mình); null = team đang dùng.
  Future<String?> bestTeam(List<String> userIds);
  /// Kênh mình đang tham gia (để gắn vào dự án): (id, tên).
  Future<List<(String, String)>> myChannels();
  /// Id người dùng theo username (vd bot teamwork-app).
  Future<String?> userIdByUsername(String username);
  /// Kênh theo id / "~tên" / URL (mình phải thấy được); null nếu không có.
  Future<TwChannelInfo?> resolveChannel(String ref);
  void openChannel(String channelId);
}

/// Dự án AI của app chat (tab Agents: kênh `p-<chủ>-…`, phiên = kênh `a-<dự án>-<chủ>-…` có một trợ lý).
typedef TwAiProjectInfo = ({String channelId, String teamId, String name, String displayName});
/// Một phiên AI của dự án AI: [at] = lúc có tin gần nhất (ms), [botId] = trợ lý trong phiên ('' nếu chưa biết).
typedef TwAiSession = ({String id, String title, String botId, int at});

/// Phiên AI thật của app (dùng lại "Dự án AI" + khung chat phiên AI). App cài bằng AppState; kiểm thử dùng bản giả.
/// Báo thay đổi (phiên mới, tin mới) qua [Listenable].
abstract class TwAiSessions implements Listenable {
  /// Dự án AI [channelId] của mình còn dùng được; null nếu không (đã xoá, của người khác, không thấy).
  TwAiProjectInfo? project(String channelId);
  /// Dự án AI của mình có tên hiển thị đúng [name] (mới hoạt động nhất).
  TwAiProjectInfo? projectByName(String name);
  /// Tạo dự án AI [name] bằng đúng đường tạo dự án ở tab Agents (dưới tên người dùng).
  Future<TwAiProjectInfo> createProject(String name);
  /// Các phiên của dự án AI, mới nhất trước.
  List<TwAiSession> sessions(String projectChannelId);
  /// Mở phiên mới với trợ lý [botId] trong dự án AI; trả về id kênh phiên.
  Future<String> createSession(String projectChannelId, String botId, String title);
  /// Khung chat thật của phiên [sessionId] (thẻ tiến trình + câu trả lời stream trực tiếp). Tin chữ gõ ở ô nhắn đi qua [onSend];
  /// [aboveComposer] hiện ngay trên ô nhắn; [runFooter] hiện dưới câu trả lời của agent cho lượt TeamWork (theo run_id).
  Widget sessionView(BuildContext context, String sessionId,
      {required Future<void> Function(String text) onSend, Widget? aboveComposer, Widget? Function(String runId)? runFooter});
}

class TwStore extends ChangeNotifier {
  TwStore(this.api, {this.cacheKey, DateTime Function()? clock, this.live = true}) : _clock = clock ?? DateTime.now;

  final TwApi api;
  final String? cacheKey;
  final DateTime Function() _clock;
  /// Bật WebSocket (kiểm thử tắt).
  final bool live;
  TwAgentLauncher? launcher;
  TwChatOps? chatOps;
  /// Phiên AI thật (dự án AI + khung chat phiên); null = app không có (khung AI dự án báo không dùng được).
  TwAiSessions? aiSessions;
  /// Thông báo ngắn (vd "Đã tạo nhóm chat …"); app gắn vào SnackBar.
  void Function(String text)? onToast;
  /// Id bot teamwork-app trên máy chủ chat (thêm vào nhóm chat của dự án để đăng cập nhật).
  String botUserId = '';
  /// Agent đã chọn ở khung AI dự án (nhớ trên máy) + độ rộng khung.
  String? aiAgentId;
  Future<void> Function(String botId)? saveAiAgent;
  double? aiPanelWidth;
  Future<void> Function(double width)? saveAiPanelWidth;
  /// Tăng khi một lượt chạy có thao tác mới / được hoàn tác (run_action).
  final Map<String, int> actionRev = {};
  final Set<String> _doingOps = {};

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
  /// Lượt đã nhận và gửi xong trên máy này (hai lần checkRuns chồng nhau không gửi trùng).
  final Set<String> _handledRuns = {};
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
      final bot = me['bot'] is Map ? me['bot'] as Map : const {};
      botUserId = '${me['bot_user_id'] ?? bot['id'] ?? botUserId}';
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
      unawaited(runUserOps());
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
    if (type == 'run_action') {
      final id = ev['id'] as String? ?? ev['run_id'] as String?;
      if (id != null) actionRev[id] = (actionRev[id] ?? 0) + 1;
      _changed(persist: false);
      return;
    }
    if (type == 'user_op') {
      unawaited(runUserOps());
      return;
    }
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
      if (_handledRuns.contains(r.id) || !_claiming.add(r.id)) continue;
      try {
        final claimed = await api.claim(r.id, device, attestOwner: await l.isOwnerOf(r.botId));
        if (claimed == null) continue;
        if (!await l.canUse(r.botId)) {
          await api.reportRun(r.id, 'blocked', error: 'Người bắt đầu không được dùng agent ${r.botName.isEmpty ? r.botId : r.botName}');
          continue;
        }
        // Lượt "project" (khung AI dự án): không gắn với việc nào, bản giao việc do máy chủ soạn.
        final project = r.kind == 'project' || claimed.$1.kind == 'project';
        final d = project ? null : await api.task(r.taskId.isNotEmpty ? r.taskId : r.taskKey);
        final pname = claimed.$4 ?? projectById(claimed.$1.projectId.isNotEmpty ? claimed.$1.projectId : r.projectId)?.name ?? 'dự án';
        final brief = claimed.$2 ?? (d == null ? '' : briefOf(d, api.taskLink(d.task.key)));
        final title = d == null ? 'AI · $pname' : '${d.task.key} · ${d.task.title}';
        // @nhắc agent: tiếp tục trong phiên sẵn có của việc này nếu còn dùng được, không thì mở phiên mới.
        final hint = claimed.$1.sessionHint ?? r.sessionHint;
        // run_token: runner kiểm bằng khoá của TeamWork rồi mới đẩy tiến độ / chạy không cần duyệt.
        final props = <String, dynamic>{if (claimed.$3 != null) 'flygo_teamwork': {'run_token': claimed.$3, 'run_id': r.id}};
        String ch;
        if (hint != null && await l.sessionUsable(hint, r.botId)) {
          await l.post(hint, brief, props: props);
          ch = hint;
        } else {
          ch = await l.launch(r.botId, title, brief, props: props);
        }
        _handledRuns.add(r.id);
        await api.reportRun(r.id, 'running', sessionChannel: ch);
        if (d != null) taskRev[d.task.id] = (taskRev[d.task.id] ?? 0) + 1;
        runRev[r.id] = (runRev[r.id] ?? 0) + 1;
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

  // ------------------------------------------------------------ AI của dự án = dự án AI cùng tên + phiên AI thật
  /// Dự án AI gắn với dự án [pid]: dùng bản đã gắn nếu mình mở được; không thì tìm dự án AI cùng tên của mình, chưa có thì tạo
  /// (đường tạo dự án ở tab Agents), rồi gắn lên máy chủ. Bản gắn của người khác (mình không mở được) giữ nguyên, mình dùng dự án
  /// AI cùng tên của chính mình.
  Future<TwAiProjectInfo> ensureAiProject(String pid) async {
    final ai = aiSessions;
    if (ai == null) throw StateError('App này chưa có Dự án AI');
    final p = projectById(pid);
    if (p == null) throw StateError('Không thấy dự án');
    final link = p.aiProject;
    if (link != null) {
      final mine = ai.project(link.channelId);
      if (mine != null) return mine;
    }
    final info = ai.projectByName(p.name) ?? await ai.createProject(p.name);
    if (link == null || link.boundBy == meId || link.boundBy.isEmpty) {
      try {
        final np = await api.setAiProject(pid, {'channel_id': info.channelId, 'team_id': info.teamId, 'name': info.name, 'display_name': info.displayName});
        _replaceProject(np);
      } catch (e) {
        debugPrint('[teamwork] không gắn được dự án AI: $e');
      }
    }
    return info;
  }

  void _replaceProject(TwProject np) {
    final i = projects.indexWhere((x) => x.id == np.id);
    if (i >= 0) projects[i] = np;
    full[np.id]?.project = np;
    _changed();
  }

  /// Gửi một lượt AI dự án vào phiên [sessionId] (bot [botId] của phiên): tạo lượt chạy kèm cuộc trò chuyện gắn với phiên
  /// (lượt tiếp trong phiên → brief ngắn), rồi nhận lượt và gửi tin có props flygo_teamwork vào đúng phiên đó.
  Future<TwRun> askAi(String pid, {required String sessionId, required String botId, required String prompt, String? action}) async {
    final threads = await api.aiThreads(pid, session: sessionId);
    final th = threads.where((t) => t.sessionChannel == null || t.sessionChannel == sessionId).firstOrNull;
    final (run, _) = await api.projectAi(pid,
        botId: botId, prompt: prompt, action: action, threadId: th?.id, sessionChannel: sessionId, continuation: th != null && th.turnCount > 0);
    await checkRuns();
    return run;
  }

  // ------------------------------------------------------------ lệnh của người dùng (nhóm chat)
  /// Làm các lệnh đang chờ của CHÍNH người dùng này bằng token của họ (tạo / gắn nhóm chat), rồi báo kết quả.
  /// Lệnh của người khác không bao giờ làm.
  Future<void> runUserOps() async {
    final ops = chatOps;
    if (ops == null || meId.isEmpty) return;
    List<TwUserOp> list;
    try {
      list = await api.userOps();
    } catch (_) {
      return;
    }
    for (final op in list) {
      if (op.userId != meId || !_doingOps.add(op.id)) continue;
      try {
        final p = op.params;
        final bot = '${p['bot_user_id'] ?? p['bot_id'] ?? ''}'.isNotEmpty ? '${p['bot_user_id'] ?? p['bot_id']}' : botUserId;
        if (op.kind == 'channel_create') {
          final members = [for (final m in p['members'] as List? ?? const []) '$m'];
          final team = '${p['team_id'] ?? ''}'.isNotEmpty ? '${p['team_id']}' : await ops.bestTeam(members);
          final display = '${p['display_name'] ?? p['name'] ?? 'Dự án'}';
          final info = await ops.createChannel(
            teamId: team,
            name: '${p['name'] ?? ''}'.isNotEmpty ? '${p['name']}' : _slug(display),
            displayName: display,
            private: p['private'] != false,
            purpose: '${p['purpose'] ?? ''}',
            header: '${p['header'] ?? ''}',
          );
          for (final m in members) {
            if (m == meId) continue;
            try {
              await ops.addMember(info.id, m);
            } catch (_) {}
          }
          if (bot.isNotEmpty) await ops.addMember(info.id, bot);
          await api.reportUserOp(op.id, 'done', result: _infoJson(info));
          onToast?.call('Đã tạo nhóm chat "${info.displayName}"');
        } else if (op.kind == 'channel_link') {
          final ref = '${p['channel'] ?? p['channel_id'] ?? ''}';
          final info = ref.isEmpty ? null : await ops.resolveChannel(ref);
          if (info == null || !await ops.isMember(info.id)) {
            await api.reportUserOp(op.id, 'failed', error: 'Bạn không ở trong kênh này');
            continue;
          }
          if (bot.isNotEmpty) await ops.addMember(info.id, bot);
          await api.reportUserOp(op.id, 'done', result: _infoJson(info));
          onToast?.call('Đã gắn nhóm chat "${info.displayName}" vào dự án');
        } else {
          await api.reportUserOp(op.id, 'failed', error: 'Không hỗ trợ ${op.kind}');
          continue;
        }
        if (op.projectId.isNotEmpty && full.containsKey(op.projectId)) unawaited(openProject(op.projectId));
      } catch (e) {
        try {
          await api.reportUserOp(op.id, 'failed', error: '$e');
        } catch (_) {}
      } finally {
        _doingOps.remove(op.id);
      }
    }
  }

  static Map<String, dynamic> _infoJson(TwChannelInfo i) => {'channel_id': i.id, 'team_id': i.teamId, 'name': i.name, 'display_name': i.displayName, 'url': i.url};
  static Map<String, dynamic> channelJson(TwChannelInfo i) => {'id': i.id, 'team_id': i.teamId, 'name': i.name, 'display_name': i.displayName, 'url': i.url};

  /// Tên kỹ thuật của kênh từ tên hiển thị (chữ thường, không dấu, gạch nối) + đuôi ngẫu nhiên ngắn.
  static String _slug(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = s.toLowerCase().split('').map((c) {
      final i = from.indexOf(c);
      return i < 0 ? c : to[i];
    }).join().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final tail = DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(4);
    return '${b.isEmpty ? 'du-an' : (b.length > 40 ? b.substring(0, 40) : b)}-$tail';
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
