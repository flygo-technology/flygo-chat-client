// Todo: bộ nhớ đệm trên máy + hàng đợi lệnh để dùng được khi mất mạng.
// Mọi thay đổi áp ngay vào bản trong máy rồi xếp hàng gửi lên; gửi lỗi mạng thì giữ lại thử sau. Đồng bộ bằng
// GET /api/sync?since=<seq>: máy chủ trả ghi chú đổi, ghi chú không còn và toàn bộ nhãn.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'model.dart';

/// Một lệnh chờ gửi. put: sửa ghi chú (gộp nhiều lần sửa liền nhau); del: xoá vĩnh viễn / rời; label / label_del;
/// members: đặt người chia sẻ; empty_trash.
class TodoOp {
  TodoOp(this.kind, this.id, [Map<String, dynamic>? body, Map<String, dynamic>? local]) : body = body ?? {}, local = local ?? {};
  final String kind, id;
  /// Gửi máy chủ (tệp theo id) / áp lên bản trong máy (tệp đủ tên, kiểu).
  final Map<String, dynamic> body, local;
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'body': body, 'local': local};
  factory TodoOp.fromJson(Map m) => TodoOp('${m['kind']}', '${m['id']}', Map<String, dynamic>.from(m['body'] as Map? ?? const {}),
      Map<String, dynamic>.from(m['local'] as Map? ?? const {}));
}

class TodoStore extends ChangeNotifier {
  TodoStore(this.api, {this.cacheKey, this.pollEvery = const Duration(seconds: 20)});

  final TodoApi api;
  /// Tên tệp bộ nhớ đệm (máy chủ + người dùng); null = chỉ trong bộ nhớ (kiểm thử).
  final String? cacheKey;
  final Duration pollEvery;

  final Map<String, TNote> notes = {};
  List<TLabel> labels = [];
  String meId = '', meName = '';
  int seq = 0;
  final List<TodoOp> _ops = [];
  bool loaded = false, offline = false, syncing = false;
  String? error;
  Timer? _poll, _retry, _save;
  bool _flushing = false, _disposed = false;
  TodoOp? _inFlight;

  int get pending => _ops.length;
  bool hasPending(String id) => _ops.any((o) => o.id == id);

  // ------------------------------------------------------------ bộ nhớ đệm
  Future<File?> _file() async {
    if (cacheKey == null) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}todo_$cacheKey.json');
  }

  Future<void> _restore() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map;
      seq = (j['seq'] as num?)?.toInt() ?? 0;
      meId = '${j['me'] ?? ''}';
      labels = [for (final l in j['labels'] as List? ?? const []) TLabel.fromJson(l as Map)];
      for (final n in j['notes'] as List? ?? const []) {
        final x = TNote.fromJson(n as Map);
        notes[x.id] = x;
      }
      _ops.addAll([for (final o in j['ops'] as List? ?? const []) TodoOp.fromJson(o as Map)]);
      loaded = notes.isNotEmpty || seq > 0;
    } catch (e) {
      debugPrint('[todo] bộ nhớ đệm hỏng, tải lại: $e');
      seq = 0;
    }
  }

  void _persist() {
    if (cacheKey == null) return;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), () async {
      try {
        final f = await _file();
        if (f == null) return;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode({
          'seq': seq,
          'me': meId,
          'labels': [for (final l in labels) l.toJson()],
          'notes': [for (final n in notes.values) n.toJson()],
          'ops': [for (final o in _ops) o.toJson()],
        }));
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('[todo] không lưu được bộ nhớ đệm: $e');
      }
    });
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    _persist();
  }

  // ------------------------------------------------------------ đồng bộ
  Future<void> start() async {
    await _restore();
    if (loaded) notifyListeners();
    try {
      final me = await api.get('/api/me');
      final u = me['user'] as Map? ?? const {};
      meId = '${u['id'] ?? meId}';
      meName = '${u['name'] ?? ''}';
    } catch (e) {
      if (!TodoApi.isOffline(e)) error = '$e';
    }
    await sync();
    _poll?.cancel(); // mở lại màn hình với cùng kho: không để hai bộ hẹn giờ
    _poll = Timer.periodic(pollEvery, (_) => sync());
  }

  /// Gửi các lệnh đang chờ rồi lấy thay đổi từ máy chủ.
  Future<void> sync() async {
    if (syncing || _disposed) return;
    syncing = true;
    try {
      await _flush();
      final j = await api.get('/api/sync?since=$seq');
      if (j['full'] == true) notes.removeWhere((id, n) => n.version > 0 && !hasPending(id));
      for (final n in j['notes'] as List? ?? const []) {
        final x = TNote.fromJson(n as Map);
        _applyServer(x);
      }
      for (final id in j['gone'] as List? ?? const []) {
        if (!hasPending('$id')) notes.remove('$id');
      }
      labels = [for (final l in j['labels'] as List? ?? const []) TLabel.fromJson(l as Map)];
      for (final o in _ops.where((o) => o.kind == 'label')) {
        labels = [...labels.where((l) => l.id != o.id), TLabel(o.id, '${o.body['name']}')];
      }
      labels.removeWhere((l) => _ops.any((o) => o.kind == 'label_del' && o.id == l.id));
      seq = (j['seq'] as num?)?.toInt() ?? seq;
      offline = false;
      error = null;
      loaded = true;
    } catch (e) {
      offline = TodoApi.isOffline(e);
      if (!offline) error = '$e';
    } finally {
      syncing = false;
      _changed();
    }
  }

  /// Bản máy chủ mới về: thay bản trong máy, rồi áp lại các thay đổi chưa gửi (để không mất chữ đang gõ).
  void _applyServer(TNote x) {
    for (final o in _ops) {
      if (o.kind == 'put' && o.id == x.id) x.applyPut(o.local);
    }
    if (_ops.any((o) => o.kind == 'del' && o.id == x.id)) return;
    notes[x.id] = x;
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_ops.isNotEmpty && !_disposed) {
        final o = _ops.first;
        try {
          _inFlight = o;
          await _send(o);
          _ops.remove(o);
          offline = false;
        } catch (e) {
          if (TodoApi.isOffline(e)) {
            offline = true;
            _retry?.cancel();
            _retry = Timer(const Duration(seconds: 10), sync);
            return;
          }
          // Máy chủ từ chối (không còn quyền, dữ liệu sai): bỏ lệnh, lần đồng bộ sau lấy lại bản đúng.
          _ops.remove(o);
          error = '$e';
          if (o.kind == 'put') {
            final n = notes[o.id];
            if (n != null && n.version == 0) notes.remove(o.id);
            seq = 0; // tải lại hết cho chắc
          }
        }
      }
    } finally {
      _flushing = false;
      _inFlight = null;
      _changed();
    }
  }

  Future<void> _send(TodoOp o) async {
    switch (o.kind) {
      case 'put':
        final r = await api.put('/api/notes/${o.id}', o.body);
        _applyServer(TNote.fromJson(r['note'] as Map));
      case 'del':
        await api.delete('/api/notes/${o.id}');
        notes.remove(o.id);
      case 'members':
        final r = await api.put('/api/notes/${o.id}/members', o.body);
        _applyServer(TNote.fromJson(r['note'] as Map));
      case 'copy':
        final r = await api.post('/api/notes/${o.body['from']}/copy', {'id': o.id});
        _applyServer(TNote.fromJson(r['note'] as Map));
      case 'label':
        await api.put('/api/labels/${o.id}', {'name': o.body['name']});
      case 'label_del':
        await api.delete('/api/labels/${o.id}');
      case 'empty_trash':
        await api.post('/api/trash/empty');
    }
  }

  void _queue(TodoOp o) {
    // Sửa liền nhau cùng một ghi chú: gộp vào lệnh put cuối (giữ base = version lúc bắt đầu sửa).
    if (o.kind == 'put' && _ops.isNotEmpty && _ops.last.kind == 'put' && _ops.last.id == o.id && !identical(_ops.last, _inFlight)) {
      final b = o.body..remove('base');
      _ops.last.body.addAll(b);
      _ops.last.local.addAll(o.local);
    } else {
      _ops.add(o);
    }
    _changed();
    unawaited(_flush());
  }

  // ------------------------------------------------------------ thao tác
  /// Ghi chú mới (chưa gửi cho tới khi có nội dung).
  TNote draft({String kind = 'note', List<TBlock>? blocks}) {
    final top = notes.values.where((n) => !n.pinned).fold<double>(0, (m, n) => n.sort > m ? n.sort : m);
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    return TNote(id: todoId(), kind: kind, blocks: blocks ?? [TBlock(t: kind == 'list' ? 'check' : 'p')], sort: now > top ? now : top + 1,
        members: [TMember(meId, meName, 'owner')]);
  }

  /// Sửa ghi chú [n]: [body] là các trường đổi (giống PUT /api/notes/:id). Ghi chú mới thì gửi cả nội dung.
  void put(TNote n, Map<String, dynamic> body) {
    final isNew = !notes.containsKey(n.id);
    final cur = notes[n.id] ?? n.clone();
    if (isNew) {
      body = {
        'kind': n.kind,
        'title': n.title,
        'blocks': [for (final b in n.blocks) b.toJson()],
        'color': n.color,
        'bg': n.bg,
        'files': [for (final f in n.files) f.id],
        'sort': n.sort,
        'labels': n.labels,
        if (n.pinned) 'pinned': true,
        if (n.reminder != null) 'reminder': n.reminder!.toJson(),
        ...body,
      };
    }
    final send = {...body};
    if (send['files'] is List) send['files'] = [for (final f in send['files'] as List) f is TFile ? f.id : f is Map ? f['id'] : f];
    final local = {...body};
    if (local['files'] is List) local['files'] = [for (final f in local['files'] as List) f is TFile ? f.toJson() : f];
    cur.applyPut(local);
    cur.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notes[cur.id] = cur;
    if (cur.version > 0 && _hasContent(send)) send['base'] = cur.version;
    _queue(TodoOp('put', cur.id, send, local));
  }

  static bool _hasContent(Map b) => b.keys.any((k) => const {'kind', 'title', 'blocks', 'color', 'bg', 'files'}.contains(k));

  void remove(TNote n) {
    _ops.removeWhere((o) => o.id == n.id && o.kind == 'put' && n.version == 0);
    notes.remove(n.id);
    if (n.version == 0 && !_ops.any((o) => o.id == n.id)) return _changed();
    _queue(TodoOp('del', n.id));
  }

  void setMembers(TNote n, List<TMember> others) {
    n.members = [...n.members.where((m) => m.role == 'owner'), ...others];
    _queue(TodoOp('members', n.id, {'members': [for (final m in others) {'id': m.id, 'role': m.role}]}));
  }

  TNote copy(TNote n) {
    final c = n.clone();
    final x = TNote.fromJson({...c.toJson(), 'id': todoId(), 'version': 0, 'role': 'owner', 'pinned': false, 'reminder': null,
      'sort': DateTime.now().millisecondsSinceEpoch.toDouble(), 'members': [TMember(meId, meName, 'owner').toJson()]});
    notes[x.id] = x;
    _queue(TodoOp('copy', x.id, {'from': n.id}));
    return x;
  }

  TLabel putLabel(String name, {String? id}) {
    final l = TLabel(id ?? todoId(), name.trim());
    labels = [...labels.where((x) => x.id != l.id), l]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _queue(TodoOp('label', l.id, {'name': l.name}));
    return l;
  }

  void deleteLabel(TLabel l) {
    labels = labels.where((x) => x.id != l.id).toList();
    for (final n in notes.values) {
      n.labels.remove(l.id);
    }
    _queue(TodoOp('label_del', l.id));
  }

  void emptyTrash() {
    notes.removeWhere((_, n) => n.trashed);
    _queue(TodoOp('empty_trash', ''));
  }

  /// Kéo thả: đặt [n] ngay trước [before] (hoặc cuối nhóm nếu null) trong danh sách [order] đang hiện.
  void moveBefore(TNote n, TNote? before, List<TNote> order) {
    final list = order.where((x) => x.id != n.id).toList();
    final i = before == null ? list.length : list.indexWhere((x) => x.id == before.id);
    // Danh sách sắp sort giảm dần: lấy giữa hai ghi chú hai bên.
    final hi = i > 0 ? list[i - 1].sort : null, lo = i < list.length ? list[i].sort : null;
    final s = hi != null && lo != null ? (hi + lo) / 2 : hi != null ? hi - 1000 : lo != null ? lo + 1000 : n.sort;
    put(n, {'sort': s});
  }

  // ------------------------------------------------------------ xem
  /// Ghi chú theo mục: notes (đang dùng), reminders, archive, trash, hoặc `label:<id>`; lọc theo chữ [q].
  List<TNote> view(String section, {String q = ''}) {
    final query = q.trim().toLowerCase();
    Iterable<TNote> it = notes.values;
    if (section == 'trash') {
      it = it.where((n) => n.trashed);
    } else {
      it = it.where((n) => !n.trashed);
      if (section == 'archive') it = it.where((n) => n.archived);
      if (section == 'notes') it = it.where((n) => !n.archived);
      if (section == 'reminders') it = it.where((n) => n.reminder != null);
      if (section.startsWith('label:')) it = it.where((n) => n.labels.contains(section.substring(6)));
    }
    if (query.isNotEmpty) {
      it = it.where((n) => n.plain.toLowerCase().contains(query) || n.files.any((f) => f.name.toLowerCase().contains(query)) ||
          n.labels.any((l) => labelName(l).toLowerCase().contains(query)));
    }
    final out = it.where((n) => !n.isEmpty || n.version > 0).toList();
    if (section == 'reminders') {
      out.sort((a, b) => a.reminder!.at.compareTo(b.reminder!.at));
    } else if (section == 'trash') {
      out.sort((a, b) => (b.trashedAt ?? 0).compareTo(a.trashedAt ?? 0));
    } else {
      out.sort((a, b) => b.sort.compareTo(a.sort));
    }
    return out;
  }

  String labelName(String id) => labels.where((l) => l.id == id).firstOrNull?.name ?? '';

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _retry?.cancel();
    if (_save?.isActive ?? false) _persist(); // lần lưu đang chờ vẫn chạy sau khi đóng màn hình
    super.dispose();
  }
}
