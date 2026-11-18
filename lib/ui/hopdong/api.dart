// Hợp đồng (vn.flygo.hopdong): gọi backend hopdong (flygo-chat-server hopdong/) bằng vé Flygo ID.
// Đặc tả API: hopdong/src/server.ts — danh sách, soạn, gửi ký, theo dõi tiến độ ký và nhật ký của từng hợp đồng.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'model.dart';

const kHopdongApp = 'vn.flygo.hopdong';
const kHopdongScreen = 'hopdong';

class HopdongException implements Exception {
  HopdongException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class HopdongApi {
  HopdongApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (vd https://chat.example.com/__apps/hopdong).
  final String base;
  final FlygoId id;
  final http.Client _http;

  Future<Map<String, String>> auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await id.ticket(kHopdongApp, refresh: refresh).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

  Uri uri(String path, [Map<String, String>? q]) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path').replace(queryParameters: q == null || q.isEmpty ? null : q);

  Future<http.Response> _send(String method, String path, {Object? body, Map<String, String>? query, bool retried = false, Duration timeout = const Duration(seconds: 40)}) async {
    final req = http.Request(method, uri(path, query))..headers.addAll(await auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(timeout);
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, query: query, retried: true, timeout: timeout);
    return res;
  }

  Json _json(http.Response res) {
    Json j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw HopdongException(res.statusCode, '${j['error'] ?? 'Hợp đồng trả lỗi ${res.statusCode}'}');
    return j;
  }

  Future<Json> get(String path, [Map<String, String>? q]) async => _json(await _send('GET', path, query: q));
  Future<Json> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Json> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Json> delete(String path) async => _json(await _send('DELETE', path));

  // ---------------------------------------------------------------- hợp đồng
  Future<HdMe> me() async => HdMe.fromJson(await get('/api/me'));
  Future<HdCounts> counts() async => HdCounts.fromJson(await get('/api/counts'));

  /// [status]: draft | sending | signed | rejected | cancelled | overdue | expiring (null = tất cả).
  Future<List<Contract>> contracts({String? status, String? q}) async {
    final j = await get('/api/contracts', {'status': ?status, if (q != null && q.trim().isNotEmpty) 'q': q.trim()});
    return [for (final c in (j['contracts'] as List? ?? const [])) Contract.fromJson(Map<String, dynamic>.from(c as Map))];
  }

  Contract _c(Json j) => Contract.fromJson(Map<String, dynamic>.from(j['contract'] as Map));

  Future<Contract> contract(String id) async => _c(await get('/api/contracts/$id'));
  Future<Contract> create(Json body) async => _c(await post('/api/contracts', body));
  Future<Contract> update(String id, Json body) async => _c(await put('/api/contracts/$id', body));
  Future<Contract> send(String id) async => _c(await post('/api/contracts/$id/send'));
  Future<Contract> cancel(String id, String reason) async => _c(await post('/api/contracts/$id/cancel', {'reason': reason}));
  Future<void> remove(String id) => delete('/api/contracts/$id');

  /// [action]: extend (gia hạn link, [until] ms) | revoke (thu hồi link) | remind (gửi nhắc).
  Future<Contract> partyAction(String id, String pid, String action, {int? until}) async =>
      _c(await post('/api/contracts/$id/parties/$pid/$action', {'until': ?until}));

  /// Gửi một tệp dạng multipart (trường `file`, thêm các trường chữ [fields]); hết vé thì xin vé mới thử lại một lần.
  Future<Json> _multipart(String method, String path, String name, Uint8List bytes, {Map<String, String> fields = const {}}) async {
    Future<http.Response> go(bool refresh) async {
      final req = http.MultipartRequest(method, uri(path))
        ..headers.addAll(await auth(refresh: refresh))
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 5)));
    }

    var res = await go(false);
    if (res.statusCode == 401) res = await go(true);
    return _json(res);
  }

  Future<Uint8List> _bytes(String path, [Map<String, String>? q]) async {
    final res = await _send('GET', path, query: q, timeout: const Duration(minutes: 3));
    if (res.statusCode >= 400) _json(res);
    return res.bodyBytes;
  }

  // ---------------------------------------------------------------- nhiều tài liệu
  /// Thêm một tài liệu từ máy (chỉ khi còn nháp, tối đa 10). [label] trống thì máy chủ tự đặt "Hợp đồng chính" / "Phụ lục 01"…
  Future<Contract> addDoc(String id, String name, Uint8List bytes, {String? label}) async =>
      _c(await _multipart('POST', '/api/contracts/$id/docs', name, bytes, fields: {'label': ?label}));

  /// Máy chủ tự lấy PDF từ Drive rồi thêm thành một tài liệu ([ticket] như [docFromDrive]).
  Future<Contract> addDocFromDrive(String id, {required String path, required String name, required String ticket, String? label}) async =>
      _c(_json(await _send('POST', '/api/contracts/$id/docs/from-drive',
          body: {'path': path, 'name': name, 'ticket': ticket, 'label': ?label}, timeout: const Duration(minutes: 3))));

  /// Thay tệp PDF của một tài liệu (bản +1).
  Future<Contract> replaceDoc(String id, String did, String name, Uint8List bytes) async => _c(await _multipart('PUT', '/api/contracts/$id/docs/$did', name, bytes));

  /// PDF hiện tại của một tài liệu (đã gồm các chữ ký đã có). Tài liệu của máy chủ cũ (không id) lấy qua /pdf.
  Future<Uint8List> docPdf(String id, HdDoc d, {bool dl = false}) =>
      d.id.isEmpty ? pdf(id) : _bytes('/api/contracts/$id/docs/${d.id}/pdf', dl ? const {'dl': '1'} : null);

  /// Tất cả tài liệu trong một tệp ZIP.
  Future<Uint8List> zip(String id) => _bytes('/api/contracts/$id/zip');

  // ---------------------------------------------------------------- một tài liệu (máy chủ cũ)
  /// Tải PDF lên (chỉ khi còn nháp).
  Future<Contract> uploadDoc(String id, String name, Uint8List bytes) async => _c(await _multipart('PUT', '/api/contracts/$id/doc', name, bytes));

  /// Máy chủ tự lấy PDF từ Drive ([ticket] = vé Flygo ID của app Drive, chuỗi trần không "Bearer").
  /// Máy chủ cũ chưa có đường này trả 404 / 501.
  Future<Contract> docFromDrive(String id, {required String path, required String name, required String ticket}) async =>
      _c(_json(await _send('PUT', '/api/contracts/$id/doc-from-drive', body: {'path': path, 'name': name, 'ticket': ticket}, timeout: const Duration(minutes: 3))));

  /// Bản PDF hiện tại (đã gồm các chữ ký đã có).
  Future<Uint8List> pdf(String id) => _bytes('/api/contracts/$id/pdf');
}
