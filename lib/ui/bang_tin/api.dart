// Bảng tin (vn.flygo.bangtin): gọi backend bang-tin (flygo-chat-server) bằng vé Flygo ID (native giữ vé, tự gia hạn).
// Đặc tả API: flygo-chat-server bang-tin/README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';
import '../../data/image_disk_cache.dart';

const kBangTinApp = 'vn.flygo.bangtin';

class BangTinException implements Exception {
  BangTinException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class BangTinApi {
  BangTinApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (có thể kèm đường dẫn, vd https://chat.flygo.vn/apps/bang-tin).
  final String base;
  final FlygoId id;
  final http.Client _http;

    Future<Map<String, String>> _auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await id.ticket(kBangTinApp, refresh: refresh).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

    /// Địa chỉ và header (vé Flygo ID) để trình xem ảnh tải ảnh của Bảng tin.
  String fileUrl(String fileId) => _uri('/api/files/$fileId').toString();
  Future<Map<String, String>> imageHeaders() => _auth();

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
    if (res.statusCode >= 400) throw BangTinException(res.statusCode, '${j['error'] ?? 'Bảng tin trả lỗi ${res.statusCode}'}');
    return j;
  }

  Future<Map<String, dynamic>> get(String path) async => _json(await _send('GET', path));
  Future<Map<String, dynamic>> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Map<String, dynamic>> patch(String path, Object body) async => _json(await _send('PATCH', path, body: body));
  Future<Map<String, dynamic>> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Map<String, dynamic>> delete(String path) async => _json(await _send('DELETE', path));

  /// Tải một tệp lên (chưa gắn vào bài): trả {id, name, mime, size}.
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

  /// Khoá đệm ổn định của tệp (máy chủ Bảng tin + mã tệp; không chứa vé).
  String imageKey(String fileId) => 'bt:${Uri.tryParse(base)?.host ?? base}:$fileId';

  Future<Uint8List> _fetch(String fileId) async {
    final res = await _send('GET', '/api/files/$fileId');
    if (res.statusCode >= 400) _json(res);
    return res.bodyBytes;
  }

  /// Ảnh của tệp, đọc qua bộ nhớ đệm trên đĩa (đã xem thì không tải lại, kể cả sau khi mở lại app).
  DiskCachedImage image(String fileId) => DiskCachedImage(imageKey(fileId), () => _fetch(fileId));

  /// Nội dung tệp (ảnh bìa, ảnh đính kèm), dùng chung bộ nhớ đệm trên đĩa với [image].
  Future<Uint8List> bytes(String fileId) => ImageDiskCache.instance.get(imageKey(fileId), () => _fetch(fileId));

  /// Tải tệp về thư mục tạm để mở bằng app khác.
  Future<String> download(String fileId, String name) async {
    final data = await bytes(fileId);
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}bang-tin');
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
