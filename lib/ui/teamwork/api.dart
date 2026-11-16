// TeamWork (vn.flygo.teamwork): gọi backend teamwork (flygo-chat-server teamwork/) bằng vé Flygo ID, giống Lịch / Todo.
// Đặc tả API: flygo-chat-server teamwork/README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'model.dart';

const kTwApp = 'vn.flygo.teamwork';
const kTwScreen = 'teamwork';

class TwException implements Exception {
  TwException(this.status, this.message, {this.code});
  final int status;
  final String message;
  final String? code;
  @override
  String toString() => message;
}

class TwApi {
  TwApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (vd https://chat.example.com/__apps/teamwork).
  final String base;
  final FlygoId id;
  final http.Client _http;

  Future<String> ticket({bool refresh = false}) => id.ticket(kTwApp, refresh: refresh).timeout(const Duration(seconds: 25));

  Future<Map<String, String>> _auth({bool refresh = false}) async => {'Authorization': 'Bearer ${await ticket(refresh: refresh)}', 'User-Agent': kUserAgent};

  String get _root => base.replaceAll(RegExp(r'/+$'), '');
  Uri _uri(String path) => Uri.parse('$_root$path');

  /// Địa chỉ WebSocket (vé trong query vì không phải client nào cũng đặt được header).
  Future<Uri> wsUri() async {
    final u = Uri.parse('$_root/ws');
    return u.replace(scheme: u.scheme == 'http' ? 'ws' : 'wss', queryParameters: {'ticket': await ticket()});
  }

  /// Link mở việc (để chép / chia sẻ).
  String taskLink(String key) => '$_root/t/$key';

  Future<http.Response> _send(String method, String path, {Object? body, bool retried = false}) async {
    final req = http.Request(method, _uri(path))..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 45));
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, retried: true);
    return res;
  }

  Map<String, dynamic> _json(http.Response res) {
    Map<String, dynamic> j = const {};
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      j = d is Map ? Map<String, dynamic>.from(d) : {'items': d};
    } catch (_) {}
    if (res.statusCode >= 400) throw TwException(res.statusCode, '${j['error'] ?? 'TeamWork trả lỗi ${res.statusCode}'}', code: j['code'] as String?);
    return j;
  }

  Future<Map<String, dynamic>> get(String path) async => _json(await _send('GET', path));
  Future<Map<String, dynamic>> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Map<String, dynamic>> patch(String path, Object body) async => _json(await _send('PATCH', path, body: body));
  Future<Map<String, dynamic>> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Map<String, dynamic>> delete(String path, [Object? body]) async => _json(await _send('DELETE', path, body: body));

  /// Gửi lại một lệnh đã xếp hàng khi mất mạng.
  Future<Map<String, dynamic>> raw(String method, String path, Object? body) async => _json(await _send(method, path, body: body));

  /// Lỗi mạng (mất kết nối, hết giờ, máy chủ quá tải) → coi là mất mạng. Lỗi máy chủ trả (4xx) thì không.
  static bool isOffline(Object e) => e is! TwException || e.status >= 500 || e.status == 408 || e.status == 429;

  static String q(Map<String, Object?> p) {
    final e = p.entries.where((x) => x.value != null && '${x.value}'.isNotEmpty);
    return e.isEmpty ? '' : '?${e.map((x) => '${x.key}=${Uri.encodeQueryComponent('${x.value}')}').join('&')}';
  }

  static List<Map> _list(Map j, String key) => [for (final x in (j[key] ?? j['items']) as List? ?? const []) if (x is Map) x];
  static Map _one(Map j, String key) => (j[key] is Map ? j[key] : j) as Map;

  // ------------------------------------------------------------ người dùng
  Future<Map<String, dynamic>> me() => get('/api/me');
  Future<Map<String, dynamic>> putPrefs(Map<String, dynamic> prefs) => put('/api/me/prefs', prefs);

  // ------------------------------------------------------------ dự án
  Future<List<TwProject>> projects({String? status, bool archived = false}) async =>
      [for (final p in _list(await get('/api/projects${q({'status': status, 'archived': archived ? '1' : null})}'), 'projects')) TwProject.fromJson(p)];
  Future<TwProjectFull> project(String id) async => TwProjectFull.fromJson(await get('/api/projects/$id'));
  Future<TwProjectFull> createProject(Map<String, dynamic> body) async => TwProjectFull.fromJson(await post('/api/projects', body));
  Future<TwProject> updateProject(String id, Map<String, dynamic> body) async => TwProject.fromJson(_one(await patch('/api/projects/$id', body), 'project'));
  Future<void> deleteProject(String id) => delete('/api/projects/$id');
  Future<void> star(String id, bool on) => post('/api/projects/$id/star', {'on': on});
  Future<TwProjectFull> copyProject(String id, String name, String key) async => TwProjectFull.fromJson(await post('/api/projects/$id/copy', {'name': name, 'key': key}));

  // ------------------------------------------------------------ thành viên
  Future<List<TwMember>> members(String pid) async => [for (final m in _list(await get('/api/projects/$pid/members'), 'members')) TwMember.fromJson(m)];
  Future<void> setMember(String pid, String type, String id, String role) => put('/api/projects/$pid/members', {'subject_type': type, 'subject_id': id, 'role': role});
  Future<void> removeMember(String pid, String type, String id) => delete('/api/projects/$pid/members', {'subject_type': type, 'subject_id': id});
  Future<List<TwSubject>> subjects(String query) async {
    final j = await get('/api/subjects${q({'q': query})}');
    if (j['subjects'] is List) return [for (final s in _list(j, 'subjects')) TwSubject.fromJson(s)];
    return [
      for (final s in _list(j, 'users')) TwSubject.fromJson(s, 'user'),
      for (final s in _list(j, 'depts')) TwSubject.fromJson(s, 'dept'),
      for (final s in _list(j, 'roles')) TwSubject.fromJson(s, 'role'),
      if (j['everyone'] == true) const TwSubject('everyone', '*', 'Mọi người'),
    ];
  }

  Future<List<TwAgent>> agents() async => [for (final a in _list(await get('/api/agents'), 'agents')) TwAgent.fromJson(a)];

  // ------------------------------------------------------------ trạng thái, nhãn
  Future<TwStatus> createStatus(String pid, Map<String, dynamic> body) async => TwStatus.fromJson(_one(await post('/api/projects/$pid/statuses', body), 'status'));
  Future<TwStatus> updateStatus(String id, Map<String, dynamic> body) async => TwStatus.fromJson(_one(await patch('/api/statuses/$id', body), 'status'));
  Future<void> deleteStatus(String id, String moveTo) => delete('/api/statuses/$id${q({'move_to': moveTo})}');
  Future<void> reorderStatuses(String pid, List<String> ids) => put('/api/projects/$pid/statuses/order', {'ids': ids});
  Future<TwLabel> createLabel(String pid, String name, String color) async => TwLabel.fromJson(_one(await post('/api/projects/$pid/labels', {'name': name, 'color': color}), 'label'));
  Future<TwLabel> updateLabel(String id, Map<String, dynamic> body) async => TwLabel.fromJson(_one(await patch('/api/labels/$id', body), 'label'));
  Future<void> deleteLabel(String id) => delete('/api/labels/$id');

  // ------------------------------------------------------------ việc
  Future<List<TwTask>> tasks(String pid, {bool includeDone = true, String? q2}) async =>
      [for (final t in _list(await get('/api/projects/$pid/tasks${q({'include_done': includeDone ? '1' : '0', 'q': q2, 'limit': 2000})}'), 'tasks')) TwTask.fromJson(t)];
  Future<List<TwTask>> mine(String tab) async => (await mineWithProjects(tab)).$1;
  /// "Việc của tôi" kèm thông tin ngắn các dự án ({id: {key, name, color, my_role}}).
  Future<(List<TwTask>, List<TwProject>)> mineWithProjects(String tab) async {
    final j = await get('/api/tasks/mine${q({'tab': tab})}');
    final projs = <TwProject>[];
    final pm = j['projects'];
    if (pm is Map) {
      pm.forEach((k, v) {
        if (v is Map) projs.add(TwProject.fromJson({'id': k, ...v}));
      });
    }
    return ([for (final t in _list(j, 'tasks')) TwTask.fromJson(t)], projs);
  }
  Future<TwTaskDetail> task(String idOrKey) async => TwTaskDetail.fromJson(await get('/api/tasks/${Uri.encodeComponent(idOrKey)}'));
  Future<TwTask> createTask(String pid, Map<String, dynamic> body) async => TwTask.fromJson(_one(await post('/api/projects/$pid/tasks', body), 'task'));
  Future<TwTask> updateTask(String id, Map<String, dynamic> body) async => TwTask.fromJson(_one(await patch('/api/tasks/$id', body), 'task'));
  Future<TwTask> moveTask(String id, {String? statusId, String? beforeId, String? afterId}) async =>
      TwTask.fromJson(_one(await post('/api/tasks/$id/move', {'status_id': ?statusId, 'before_id': ?beforeId, 'after_id': ?afterId}), 'task'));
  Future<void> bulk(List<String> ids, Map<String, dynamic> patch) => post('/api/tasks/bulk', {'ids': ids, 'patch': patch});
  Future<void> deleteTask(String id) => delete('/api/tasks/$id');
  Future<void> restoreTask(String id) => post('/api/tasks/$id/restore');
  Future<List<TwTask>> trash(String pid) async => [for (final t in _list(await get('/api/projects/$pid/trash'), 'items')) TwTask.fromJson(t)];

  /// Việc phụ thuộc sẽ bị dời nếu đổi ngày việc [id] (id, key, title, start, due, new_start, new_due).
  Future<List<TwTask>> schedulePreview(String id, DateTime? start, DateTime? due) async {
    final j = await get('/api/tasks/$id/schedule-preview${q({'start': start == null ? null : dayStr(start), 'due': due == null ? null : dayStr(due)})}');
    return [for (final t in (j['dependents'] ?? j['tasks']) as List? ?? const []) if (t is Map) TwTask.fromJson(t)];
  }

  Future<List<TwTask>> schedule(String id, DateTime? start, DateTime? due, {bool shiftDependents = false}) async {
    final j = await post('/api/tasks/$id/schedule', {'start': start == null ? null : dayStr(start), 'due': due == null ? null : dayStr(due), 'shift_dependents': shiftDependents});
    return [for (final t in (j['changed'] ?? j['tasks']) as List? ?? const []) if (t is Map) TwTask.fromJson(t)];
  }

  Future<TwTask> setAssignees(String id, List<TwAssignee> a) async => TwTask.fromJson(_one(await put('/api/tasks/$id/assignees', {'assignees': [for (final x in a) x.toJson()]}), 'task'));
  Future<void> watch(String id, bool on) => post('/api/tasks/$id/watch', {'on': on});
  Future<void> addLink(String id, String to, String type) => post('/api/tasks/$id/links', {'to': to, 'type': type});
  Future<void> removeLink(String linkId) => delete('/api/links/$linkId');

  // ------------------------------------------------------------ bình luận, cảm xúc
  Future<List<TwComment>> comments(String taskId) async => [for (final c in _list(await get('/api/tasks/$taskId/comments'), 'comments')) TwComment.fromJson(c)];
  Future<TwComment> addComment(String taskId, List<Map<String, dynamic>> blocks, {String? parentId, List<String> attachmentIds = const []}) async =>
      TwComment.fromJson(_one(await post('/api/tasks/$taskId/comments', {'blocks': blocks, 'parent_id': ?parentId, if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds}), 'comment'));
  Future<TwComment> editComment(String id, List<Map<String, dynamic>> blocks) async => TwComment.fromJson(_one(await patch('/api/comments/$id', {'blocks': blocks}), 'comment'));
  Future<void> deleteComment(String id) => delete('/api/comments/$id');
  Future<void> react(String target, String id, String emoji) => post('/api/reactions', {'target': target, 'id': id, 'emoji': emoji});

  // ------------------------------------------------------------ tệp
  Future<TwAttachment> upload(String taskId, String name, Uint8List bytes, {String? mime, bool forComment = false}) async {
    Future<http.Response> go(bool refresh) async {
      final req = http.Request('POST', _uri('/api/tasks/$taskId/attachments${q({'name': name, 'for': forComment ? 'comment' : null})}'))
        ..headers.addAll(await _auth(refresh: refresh))
        ..headers['Content-Type'] = mime ?? 'application/octet-stream'
        ..bodyBytes = bytes;
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 5)));
    }

    var res = await go(false);
    if (res.statusCode == 401) res = await go(true);
    return TwAttachment.fromJson(_one(_json(res), 'attachment'));
  }

  Future<TwAttachment> attachDrive(String taskId, String name, String url) async => TwAttachment.fromJson(_one(await post('/api/tasks/$taskId/attachments/drive', {'name': name, 'url': url}), 'attachment'));
  Future<void> deleteAttachment(String id) => delete('/api/attachments/$id');

  /// Tải tệp về thư mục tạm để mở bằng app khác.
  Future<String> download(TwAttachment a) async {
    final res = await _send('GET', '/api/attachments/${a.id}');
    if (res.statusCode >= 400) _json(res);
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}teamwork');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  /// Ảnh xem trước (byte) của tệp ảnh.
  Future<Uint8List> bytes(TwAttachment a) async {
    final res = await _send('GET', '/api/attachments/${a.id}');
    if (res.statusCode >= 400) _json(res);
    return res.bodyBytes;
  }

  // ------------------------------------------------------------ hoạt động, agent
  Future<List<TwActivity>> activity(String taskId) async => [for (final a in _list(await get('/api/tasks/$taskId/activity'), 'activity')) TwActivity.fromJson(a)];
  Future<List<TwRun>> start(String taskId) async {
    final j = await post('/api/tasks/$taskId/start');
    return [for (final r in _list(j, 'runs')) TwRun.fromJson(r)];
  }

  Future<List<TwRun>> runs({bool mine = true, String? state}) async => [for (final r in _list(await get('/api/runs${q({'mine': mine ? '1' : null, 'state': state})}'), 'runs')) TwRun.fromJson(r)];
  /// Nhận lượt chạy cho máy [device]: (lượt chạy, bản giao việc máy chủ soạn, run_token); null nếu máy khác đã nhận.
  /// [attestOwner]: người dùng hiện tại là chủ bot (máy chủ chỉ cho chạy không cần duyệt khi có xác nhận này).
  Future<(TwRun, String?, String?)?> claim(String runId, String device, {bool attestOwner = false}) async {
    try {
      final j = await post('/api/runs/$runId/claim', {'device': device, if (attestOwner) 'attest_owner': true});
      return (TwRun.fromJson(_one(j, 'run')), j['brief'] as String?, j['run_token'] as String?);
    } on TwException catch (e) {
      if (e.code == 'claimed' || e.code == 'not_queued') return null;
      rethrow;
    }
  }

  /// Một lượt chạy kèm tiến độ (các bước + chữ đang viết).
  Future<TwRun> run(String runId) async => TwRun.fromJson(_one(await get('/api/runs/$runId'), 'run'));
  Future<void> reportRun(String runId, String state, {String? sessionChannel, String? error}) => post('/api/runs/$runId', {'state': state, 'session_channel': ?sessionChannel, 'error': ?error});
  Future<void> cancelRun(String runId) => post('/api/runs/$runId/cancel');

  // ------------------------------------------------------------ bộ lọc, thông báo, tìm kiếm
  Future<List<TwView>> views(String pid) async => [for (final v in _list(await get('/api/projects/$pid/views'), 'views')) TwView.fromJson(v)];
  Future<TwView> saveView(String pid, String name, Map<String, dynamic> query, {bool shared = false}) async =>
      TwView.fromJson(_one(await post('/api/projects/$pid/views', {'name': name, 'query': query, 'shared': shared}), 'view'));
  Future<void> deleteView(String id) => delete('/api/views/$id');
  Future<(List<TwNotification>, int)> notifications() async {
    final j = await get('/api/notifications');
    return ([for (final n in (j['notifications'] ?? j['items']) as List? ?? const []) if (n is Map) TwNotification.fromJson(n)], (j['unread'] as num?)?.toInt() ?? -1);
  }

  Future<void> markRead({List<String>? ids}) => post('/api/notifications/read', ids == null ? {'all': true} : {'ids': ids});
  Future<List<TwTask>> search(String query) async {
    final j = await get('/api/search${q({'q': query})}');
    return [for (final t in (j['results'] ?? j['tasks']) as List? ?? const []) if (t is Map) TwTask.fromJson(t)];
  }
}
