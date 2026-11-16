// Danh bạ khách (vn.flygo.contacts): gọi backend contacts (flygo-chat-server) bằng vé Flygo ID.
// Đặc tả API: flygo-chat-server contacts/README.md.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart';
import '../../i18n/i18n.dart';

const kContactsApp = 'vn.flygo.contacts';
const kContactsScreen = 'contacts';

class ContactsException implements Exception {
  ContactsException(this.status, this.message, [this.body = const {}]);
  final int status;
  final String message;
  /// Toàn bộ JSON lỗi (vd `duplicates` khi trùng).
  final Map<String, dynamic> body;
  @override
  String toString() => message;
}

class ContactsApi {
  ContactsApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  final String base;
  final FlygoId id;
  final http.Client _http;

  /// API của máy chủ đang đăng nhập (app vn.flygo.contacts có trong danh sách mini app của mình); không có thì null.
  static Future<ContactsApi?> forServer(String token) async {
    final apps = await MiniApps.list(token);
    final app = apps.where((a) => a.id == kContactsApp).firstOrNull;
    if (app == null) return null;
    final fid = await FlygoId.current(token);
    if (fid == null) return null;
    return ContactsApi(base: app.baseUrl, id: fid);
  }

  Future<Map<String, String>> _auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await id.ticket(kContactsApp, refresh: refresh).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

  Uri _uri(String path) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<http.Response> _send(String method, String path, {Object? body, bool retried = false}) async {
    final req = http.Request(method, _uri(path))..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 60));
    // Vé vừa hết hạn hoặc quyền vừa đổi: xin vé mới và thử lại một lần.
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, retried: true);
    return res;
  }

  Map<String, dynamic> _json(http.Response res) {
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw ContactsException(res.statusCode, '${j['error'] ?? 'Danh bạ khách trả lỗi ${res.statusCode}'}', j);
    return j;
  }

  Future<Map<String, dynamic>> get(String path) async => _json(await _send('GET', path));
  Future<Map<String, dynamic>> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Map<String, dynamic>> patch(String path, Object body) async => _json(await _send('PATCH', path, body: body));
  Future<Map<String, dynamic>> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Map<String, dynamic>> delete(String path) async => _json(await _send('DELETE', path));

  /// Văn bản thô (vCard, CSV).
  Future<String> text(String path) async {
    final res = await _send('GET', path);
    if (res.statusCode >= 400) _json(res);
    return utf8.decode(res.bodyBytes);
  }

  // ---------------------------------------------------------------- các lệnh hay dùng
  Map<String, dynamic>? _me;
  Future<Map<String, dynamic>> me({bool refresh = false}) async => !refresh && _me != null ? _me! : (_me = await get('/api/me'));

  Future<Map<String, dynamic>> list({String q = '', String view = 'all', String? type, String? kind, String? tag, int limit = 300}) {
    final qs = <String, String>{'view': view, 'limit': '$limit', if (q.trim().isNotEmpty) 'q': q.trim(), 'type': ?type, 'kind': ?kind, 'tag': ?tag};
    return get('/api/contacts?${Uri(queryParameters: qs).query}');
  }

  Future<Map<String, dynamic>> contact(String id) async => Map<String, dynamic>.from((await get('/api/contacts/$id'))['contact'] as Map);
  Future<Map<String, dynamic>> create(Map<String, dynamic> b) async => Map<String, dynamic>.from((await post('/api/contacts', b))['contact'] as Map);
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> b) async => Map<String, dynamic>.from((await patch('/api/contacts/$id', b))['contact'] as Map);
}

// ------------------------------------------------------------------ nhãn hiển thị
String typeLabel(String t) => switch (t) {
      'customer' => tr('Khách hàng'),
      'lead' => tr('Tiềm năng'),
      'supplier' => tr('Nhà cung cấp'),
      'partner' => tr('Đối tác'),
      'shipping' => tr('Vận chuyển'),
      'agency' => tr('Cơ quan'),
      _ => tr('Khác'),
    };

String scopeLabel(String s) => switch (s) { 'private' => tr('Riêng tôi'), 'company' => tr('Toàn công ty'), _ => tr('Phòng ban') };

String interactionLabel(String k) => switch (k) {
      'call' => tr('Cuộc gọi'),
      'meeting' => tr('Cuộc họp'),
      'mail' => tr('Mail'),
      'chat' => tr('Chat'),
      'flow' => tr('Quy trình'),
      'invoice' => tr('Hoá đơn'),
      'payment' => tr('Báo có'),
      'note' => tr('Ghi chú'),
      _ => tr('Khác'),
    };
