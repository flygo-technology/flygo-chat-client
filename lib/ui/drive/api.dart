// Drive (Nextcloud): gọi cổng drive-gw (flygo-chat-server drive-gw/) bằng vé Flygo ID của app Drive. Máy không giữ mật
// khẩu Nextcloud nào; cổng gọi Nextcloud thay người dùng. Đặc tả API: flygo-chat-server drive-gw/README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../browser/flygo_id.dart';
import '../../config.dart';

const kDriveApp = 'vn.flygo.web.drive';
const kDriveScreen = 'drive';

class DriveException implements Exception {
  DriveException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class DriveItem {
  DriveItem({
    required this.path,
    required this.name,
    required this.dir,
    this.size = 0,
    this.mime = '',
    this.mtime = 0,
    this.etag = '',
    this.id = 0,
    this.fav = false,
    this.perms = '',
    this.owner = '',
    this.ownerName = '',
    this.shared = false,
    this.mount = '',
    this.preview = false,
  });

  final String path, name, mime, etag, perms, owner, ownerName, mount;
  final bool dir, shared, preview;
  bool fav;
  final int size, mtime, id;

  factory DriveItem.fromJson(Map j) => DriveItem(
        path: '${j['path'] ?? '/'}',
        name: '${j['name'] ?? ''}',
        dir: j['dir'] == true,
        size: _int(j['size']),
        mime: '${j['mime'] ?? ''}',
        mtime: _int(j['mtime']),
        etag: '${j['etag'] ?? ''}',
        id: _int(j['id']),
        fav: j['fav'] == true,
        perms: '${j['perms'] ?? ''}',
        owner: '${j['owner'] ?? ''}',
        ownerName: '${j['owner_name'] ?? ''}',
        shared: j['shared'] == true,
        mount: '${j['mount'] ?? ''}',
        preview: j['preview'] == true,
      );

  Map<String, Object?> toJson() => {
        'path': path, 'name': name, 'dir': dir, 'size': size, 'mime': mime, 'mtime': mtime, 'etag': etag, 'id': id, 'fav': fav,
        'perms': perms, 'owner': owner, 'owner_name': ownerName, 'shared': shared, 'mount': mount, 'preview': preview,
      };

  DateTime get modified => DateTime.fromMillisecondsSinceEpoch(mtime * 1000);
  String get parent => parentOf(path);
  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get canWrite => perms.isEmpty || perms.contains('W') || perms.contains('C') || perms.contains('K');
  bool get canDelete => perms.isEmpty || perms.contains('D');
  bool get canShare => perms.isEmpty || perms.contains('R');
}

String parentOf(String path) {
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '/';
  parts.removeLast();
  return '/${parts.join('/')}';
}

String joinPath(String dir, String name) => dir == '/' ? '/$name' : '$dir/$name';

class DriveTrashItem extends DriveItem {
  DriveTrashItem(Map j)
      : trashId = '${j['trash_id'] ?? ''}',
        original = '${j['original'] ?? ''}',
        deleted = _int(j['deleted']),
        super(
          path: '${j['path'] ?? ''}',
          name: '${j['name'] ?? ''}',
          dir: j['dir'] == true,
          size: _int(j['size']),
          mime: '${j['mime'] ?? ''}',
          mtime: _int(j['mtime']),
          id: _int(j['id']),
        );
  final String trashId, original;
  final int deleted;
}

class DriveShare {
  DriveShare(Map j)
      : id = '${j['id']}',
        type = '${j['type'] ?? ''}',
        withId = j['with'] == null ? null : '${j['with']}',
        withName = '${j['with_name'] ?? j['with'] ?? ''}',
        canEdit = j['can_edit'] == true,
        expires = j['expires'] == null ? null : '${j['expires']}',
        url = j['url'] == null ? null : '${j['url']}',
        hasPassword = j['has_password'] == true,
        note = '${j['note'] ?? ''}',
        ownerName = '${j['owner_name'] ?? ''}';
  final String id, type, withName, note, ownerName;
  final String? withId, expires, url;
  final bool canEdit, hasPassword;
}

class DrivePerson {
  DrivePerson(Map j)
      : type = '${j['type'] ?? 'user'}',
        id = '${j['id'] ?? ''}',
        label = '${j['label'] ?? j['id'] ?? ''}',
        sub = '${j['sub'] ?? ''}';
  final String type, id, label, sub;
}

class DriveActivity {
  DriveActivity(Map j)
      : subject = '${j['subject'] ?? ''}',
        user = '${j['user'] ?? ''}',
        time = _int(j['time']),
        type = '${j['type'] ?? ''}';
  final String subject, user, type;
  final int time;
}

class DriveMe {
  DriveMe(Map j)
      : uid = '${j['uid'] ?? ''}',
        name = '${(j['user'] as Map?)?['name'] ?? ''}',
        used = _int((j['quota'] as Map?)?['used']),
        total = _int((j['quota'] as Map?)?['total']),
        webUrl = '${j['web_url'] ?? ''}',
        chunkSize = _int(j['chunk_size']) > 0 ? _int(j['chunk_size']) : 10 * 1024 * 1024,
        office = j['office'] == true;
  final String uid, name, webUrl;
  final int used, total, chunkSize;
  final bool office;
}

class DriveApi {
  DriveApi({required this.base, this.id, http.Client? client, this.ticketFn}) : _http = client ?? http.Client();

  /// Địa chỉ cổng drive-gw, vd https://chat.example.com/__apps/drive.
  final String base;
  final FlygoId? id;
  final http.Client _http;
  /// Thay cho xin vé Flygo ID (test).
  final Future<String> Function(bool refresh)? ticketFn;

  /// Cổng drive-gw của máy chủ chat [server] (chuẩn `<chat>/__apps/<app>`).
  static String baseFor(String server) => '${server.replaceAll(RegExp(r'/+$'), '')}/__apps/drive';

  Future<Map<String, String>> auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await (ticketFn?.call(refresh) ?? id!.ticket(kDriveApp, refresh: refresh)).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

  Uri uri(String path, [Map<String, String>? q]) {
    final u = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');
    return q == null ? u : u.replace(queryParameters: q);
  }

  Future<http.Response> _send(String method, String path, {Map<String, String>? q, Object? body, bool retried = false, Duration? timeout}) async {
    final req = http.Request(method, uri(path, q))..headers.addAll(await auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(timeout ?? const Duration(seconds: 60));
    // Vé hết hạn hoặc quyền vừa đổi: xin vé mới, thử lại một lần.
    if (res.statusCode == 401 && !retried) return _send(method, path, q: q, body: body, retried: true, timeout: timeout);
    return res;
  }

  Map<String, dynamic> _json(http.Response res) {
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw DriveException(res.statusCode, '${j['error'] ?? 'Drive trả lỗi ${res.statusCode}'}');
    return j;
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? q]) async => _json(await _send('GET', path, q: q));
  Future<Map<String, dynamic>> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Map<String, dynamic>> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Map<String, dynamic>> delete(String path) async => _json(await _send('DELETE', path));

  /// Lỗi mạng / máy chủ tạm thời (thử lại sau được).
  static bool isTransient(Object e) =>
      e is SocketException || e is TimeoutException || e is HttpException || e is http.ClientException || (e is DriveException && (e.status >= 500 || e.status == 408 || e.status == 429));

  List<DriveItem> _items(Map j) => [for (final x in (j['items'] as List? ?? const [])) DriveItem.fromJson(x as Map)];

  Future<DriveMe> me() async => DriveMe(await get('/api/me'));
  Future<List<DriveItem>> list(String path) async => _items(await get('/api/list', {'path': path}));
  Future<DriveItem> info({String? path, int? id}) async =>
      DriveItem.fromJson((await get('/api/info', {if (id != null) 'id': '$id', 'path': ?path}))['item'] as Map);
  Future<List<DriveItem>> search({String q = '', String? type, int? since, String? owner}) async => _items(await get('/api/search', {
        if (q.isNotEmpty) 'q': q,
        'type': ?type,
        if (since != null) 'since': '$since',
        'owner': ?owner,
      }));
  Future<List<DriveItem>> recent() async => _items(await get('/api/recent'));
  Future<List<DriveItem>> starred() async => _items(await get('/api/starred'));
  Future<List<DriveItem>> shared() async => _items(await get('/api/shared'));
  Future<List<DriveTrashItem>> trash() async => [for (final x in ((await get('/api/trash'))['items'] as List? ?? const [])) DriveTrashItem(x as Map)];
  Future<void> restore(List<String> ids) => post('/api/trash/restore', {'ids': ids});
  Future<void> purge(List<String> ids) => post('/api/trash/delete', {'ids': ids});
  Future<void> emptyTrash() => post('/api/trash/empty');
  Future<DriveItem> mkdir(String parent, String name) async => DriveItem.fromJson((await post('/api/mkdir', {'parent': parent, 'name': name}))['item'] as Map);
  Future<DriveItem> rename(String path, String name) async => _items(await post('/api/move', {'from': path, 'name': name})).first;
  Future<List<DriveItem>> move(List<String> items, String to) async => _items(await post('/api/move', {'items': items, 'to': to}));
  Future<List<DriveItem>> copy(List<String> items, String to) async => _items(await post('/api/copy', {'items': items, 'to': to}));
  Future<void> remove(List<String> items) => post('/api/delete', {'items': items});
  Future<void> star(List<String> items, bool on) => post('/api/star', {'items': items, 'on': on});
  Future<List<DriveShare>> shares(String path) async => [for (final x in ((await get('/api/shares', {'path': path}))['shares'] as List? ?? const [])) DriveShare(x as Map)];
  Future<DriveShare> share({required String path, required String type, String? withId, bool canEdit = false, String? expires, String? password, String? note}) async =>
      DriveShare((await post('/api/shares', {
        'path': path,
        'type': type,
        'with': ?withId,
        'can_edit': canEdit,
        'expires': ?expires,
        if (password != null && password.isNotEmpty) 'password': password,
        if (note != null && note.isNotEmpty) 'note': note,
      }))['share'] as Map);
  Future<void> updateShare(String id, Map<String, Object?> patch) => put('/api/shares/$id', patch);
  Future<void> unshare(String id) => delete('/api/shares/$id');
  Future<List<DrivePerson>> sharees(String q) async => [for (final x in ((await get('/api/sharees', {'q': q}))['people'] as List? ?? const [])) DrivePerson(x as Map)];
  Future<List<DriveActivity>> activity(int fileId) async =>
      [for (final x in ((await get('/api/activity', {'id': '$fileId'}))['activity'] as List? ?? const [])) DriveActivity(x as Map)];
  Future<(DriveItem, String)> officeNew(String dir, String kind, {String? name}) async {
    final j = await post('/api/office/new', {'dir': dir, 'kind': kind, 'name': ?name});
    return (DriveItem.fromJson(j['item'] as Map), '${j['open_path']}');
  }

  /// Ảnh thu nhỏ (null nếu không có).
  Future<List<int>?> thumb(int fileId, int size) async {
    final res = await _send('GET', '/api/thumb', q: {'id': '$fileId', 'w': '$size', 'h': '$size', 'crop': '1'});
    return res.statusCode == 200 ? res.bodyBytes : null;
  }

  /// Tải tệp về [dest] (ghi vào tệp tạm rồi đổi tên). [onProgress] (đã nhận, tổng).
  Future<File> download(String path, File dest, {void Function(int got, int total)? onProgress, bool Function()? cancelled}) async {
    for (var attempt = 0; ; attempt++) {
      final req = http.Request('GET', uri('/api/file', {'path': path}))..headers.addAll(await auth(refresh: attempt > 0));
      final res = await _http.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode == 401 && attempt == 0) {
        await res.stream.drain<void>();
        continue;
      }
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString().catchError((_) => '');
        String msg = 'Tải tệp lỗi ${res.statusCode}';
        try {
          msg = '${(jsonDecode(body) as Map)['error'] ?? msg}';
        } catch (_) {}
        throw DriveException(res.statusCode, msg);
      }
      await dest.parent.create(recursive: true);
      final tmp = File('${dest.path}.part');
      final sink = tmp.openWrite();
      var got = 0;
      final total = res.contentLength ?? 0;
      try {
        await for (final chunk in res.stream) {
          if (cancelled?.call() ?? false) throw DriveException(499, 'Đã huỷ');
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got, total);
        }
        await sink.close();
      } catch (_) {
        await sink.close().catchError((_) {});
        await tmp.delete().catchError((_) => tmp);
        rethrow;
      }
      return tmp.rename(dest.path);
    }
  }

  /// Gửi một đoạn của tệp [file] (offset, length) tới [path] bằng PUT (stream, không nạp cả vào bộ nhớ).
  Future<http.Response> _putFile(String path, Map<String, String> q, File file, int offset, int length, {void Function(int sent)? onSent}) async {
    for (var attempt = 0; ; attempt++) {
      final req = http.StreamedRequest('PUT', uri(path, q))
        ..headers.addAll(await auth(refresh: attempt > 0))
        ..contentLength = length;
      final done = _http.send(req).then(http.Response.fromStream);
      var sent = 0;
      await for (final b in file.openRead(offset, offset + length)) {
        req.sink.add(b);
        sent += b.length;
        onSent?.call(sent);
      }
      await req.sink.close();
      final res = await done.timeout(const Duration(minutes: 10));
      if (res.statusCode == 401 && attempt == 0) continue;
      return res;
    }
  }

  /// Tệp nhỏ: một lần PUT.
  Future<DriveItem> putSmall(String path, File file, {int? mtime, String conflict = 'rename', void Function(int sent)? onSent}) async {
    final len = await file.length();
    final res = await _putFile('/api/file', {'path': path, 'conflict': conflict, if (mtime != null) 'mtime': '$mtime'}, file, 0, len, onSent: onSent);
    return DriveItem.fromJson(_json(res)['item'] as Map);
  }

  Future<({String id, String path, int chunkSize})> uploadStart(String path, int size, {String conflict = 'rename'}) async {
    final j = await post('/api/uploads', {'path': path, 'size': size, 'conflict': conflict});
    return (id: '${j['id']}', path: '${j['path']}', chunkSize: _int(j['chunk_size']));
  }

  /// Khúc đã có trên máy chủ (n -> kích thước). null: phiên không còn (tải lại từ đầu).
  Future<Map<int, int>?> uploadParts(String id) async {
    final res = await _send('GET', '/api/uploads/$id');
    if (res.statusCode == 404) return null;
    final j = _json(res);
    return {for (final p in (j['parts'] as List? ?? const [])) _int((p as Map)['n']): _int(p['size'])};
  }

  Future<void> uploadChunk(String id, int n, String path, int total, File file, int offset, int length, {void Function(int sent)? onSent}) async {
    final res = await _putFile('/api/uploads/$id/$n', {'path': path, 'total': '$total'}, file, offset, length, onSent: onSent);
    _json(res);
  }

  Future<DriveItem> uploadDone(String id, String path, int size, {int? mtime}) async =>
      DriveItem.fromJson((await post('/api/uploads/$id/done', {'path': path, 'size': size, 'mtime': ?mtime}))['item'] as Map);
  Future<void> uploadAbort(String id) async {
    await _send('DELETE', '/api/uploads/$id');
  }
}
