// Todo (vn.flygo.todo): gọi backend todo (flygo-chat-server) bằng vé Flygo ID (native giữ vé, tự gia hạn).
// Đặc tả API: flygo-chat-server todo/README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';

const kTodoApp = 'vn.flygo.todo';

class TodoException implements Exception {
  TodoException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class TodoApi {
  TodoApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (có thể kèm đường dẫn, vd https://chat.example.com/apps/todo).
  final String base;
  final FlygoId id;
  final http.Client _http;

    Future<Map<String, String>> _auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await id.ticket(kTodoApp, refresh: refresh).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

  Uri _uri(String path) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<http.Response> _send(String method, String path, {Object? body, bool retried = false}) async {
    final req = http.Request(method, _uri(path))..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
        final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    // Vé vừa hết hạn hoặc quyền vừa đổi: xin vé mới và thử lại một lần.
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, retried: true);
    return res;
  }

  Map<String, dynamic> _json(http.Response res) {
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw TodoException(res.statusCode, '${j['error'] ?? 'Todo trả lỗi ${res.statusCode}'}');
    return j;
  }

  Future<Map<String, dynamic>> get(String path) async => _json(await _send('GET', path));
  Future<Map<String, dynamic>> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Map<String, dynamic>> patch(String path, Object body) async => _json(await _send('PATCH', path, body: body));
  Future<Map<String, dynamic>> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Map<String, dynamic>> delete(String path) async => _json(await _send('DELETE', path));

  /// Lỗi mạng (mất kết nối, hết giờ): giữ lệnh lại để gửi sau. Lỗi do máy chủ trả (TodoException) thì không.
  static bool isOffline(Object e) => e is! TodoException || e.status >= 500 || e.status == 408 || e.status == 429;

  /// Tải một tệp lên (chưa gắn vào ghi chú): trả {id, name, mime, size}.
  Future<Map<String, dynamic>> upload(String name, Uint8List bytes) async {
    Future<http.Response> go(bool refresh) async {
      final req = http.MultipartRequest('POST', _uri('/api/files'))
        ..headers.addAll(await _auth(refresh: refresh))
        // Không gửi kiểu tệp (cần gói http_parser): máy chủ tự đoán theo đuôi tên tệp.
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 5)));
    }

    var res = await go(false);
    if (res.statusCode == 401) res = await go(true);
    return Map<String, dynamic>.from(_json(res)['file'] as Map);
  }

  static final _bytes = <String, Uint8List>{};

  /// Nội dung tệp (ảnh, tệp đính kèm). Giữ trong bộ nhớ tối đa 60 tệp gần nhất.
  Future<Uint8List> bytes(String fileId) async {
    final hit = _bytes.remove(fileId);
    if (hit != null) return _bytes[fileId] = hit;
    final res = await _send('GET', '/api/files/$fileId');
    if (res.statusCode >= 400) _json(res);
    _bytes[fileId] = res.bodyBytes;
    if (_bytes.length > 60) _bytes.remove(_bytes.keys.first);
    return res.bodyBytes;
  }

  /// Tải tệp về thư mục tạm để mở bằng app khác.
  Future<String> download(String fileId, String name) async {
    final data = await bytes(fileId);
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}todo');
    await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File('${dir.path}${Platform.pathSeparator}$safe');
    await f.writeAsBytes(data);
    return f.path;
  }

  static String mimeOf(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'gif': 'image/gif',
          'webp': 'image/webp',
          'heic': 'image/heic',
          'pdf': 'application/pdf',
          'doc': 'application/msword',
          'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'xls': 'application/vnd.ms-excel',
          'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'ppt': 'application/vnd.ms-powerpoint',
          'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          'txt': 'text/plain',
          'zip': 'application/zip',
          'mp4': 'video/mp4',
          'mov': 'video/quicktime',
        }[ext] ??
        'application/octet-stream';
  }
}
