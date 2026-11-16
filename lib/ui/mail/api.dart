// Thư (vn.flygo.mail): lớp gọi backend thư. Giao diện chỉ dùng MailApi; có hai bản:
// - HttpMailApi: gọi <base_url>/mail/api/* của backend (Worker flygo-inbox) bằng vé Flygo ID (native giữ vé, tự gia hạn);
// - DemoMailApi (demo.dart): dữ liệu mẫu trong bộ nhớ để xem thử / chụp ảnh / test.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'admin_api.dart';
import 'live.dart';
import 'model.dart';

const kMailApp = 'vn.flygo.mail';

class MailException implements Exception {
  MailException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

abstract class MailApi {
  bool get demo => false;
  /// Hộp thư đang xem (người dùng có nhiều hộp: hộp chung / được uỷ quyền); null = hộp mặc định của người dùng.
  String? mailbox;
  Future<MailMe> me();
  Future<List<MailLabel>> labels();
  Future<MailLabel> createLabel(String name, int color);
  Future<MailCounts> counts();
  Future<MailPage> list({String box = 'inbox', String? label, String? category, String? q, int page = 1, int size = 50});
  Future<MailThread> thread(String id);
  Future<MailCounts?> modify(List<String> ids, MailChange change);
  Future<void> remove(List<String> ids);
  Future<List<MailPerson>> contacts(String q);
  Future<MailAttachment> upload(File file, {String? name, String? type});
  Future<String> saveDraft(MailDraft d);
  Future<void> deleteDraft(String id);
  /// [sendAt] = hẹn giờ gửi (máy chủ giữ ở Đã lên lịch và tự gửi đúng giờ).
  Future<void> send(MailDraft d, {String? draftId, DateTime? sendAt});
  /// Huỷ hẹn giờ gửi (thư trở lại Thư nháp).
  Future<void> cancelScheduled(String draftId) => throw MailException(501, 'Máy chủ thư chưa hỗ trợ hẹn giờ gửi');
  /// Tải tệp đính kèm về máy (thư mục tạm), trả đường dẫn tệp.
  Future<File> download(MailAttachment a);
  /// AI đọc cuộc hội thoại: task = summary (tóm tắt + việc cần làm) | draft (thêm bản nháp trả lời theo [instruction] / [tone]).
  /// AI chỉ soạn nháp, không bao giờ tự gửi.
  Future<MailAiResult> ai(String threadId, {String task = 'draft', String instruction = '', String tone = ''}) =>
      throw MailException(501, 'Máy chủ thư chưa hỗ trợ AI');
  /// AI sửa bản nháp đang soạn theo lệnh (không gửi). [threadId] = hội thoại đang trả lời (bối cảnh).
  Future<MailAiResult> aiRevise({String? threadId, required String draft, String instruction = ''}) =>
      throw MailException(501, 'Máy chủ thư chưa hỗ trợ AI');
  /// AI tóm tắt việc cần làm từ các thư chưa đọc của hộp đang xem.
  Future<MailDigest> aiDigest() => throw MailException(501, 'Máy chủ thư chưa hỗ trợ AI');
  /// Kênh realtime (null = backend không có: màn hình tự tải lại định kỳ).
  Future<MailLiveTarget?> liveTarget({bool refresh = false}) async => null;
  /// Bật / tắt báo thư mới của hộp đang xem qua tin nhắn chat khi app Thư đóng.
  Future<void> setNotify(bool on) => throw MailException(501, 'Máy chủ thư chưa hỗ trợ báo qua chat');
  /// Lớp gọi phần Quản trị Thư (chỉ người có quyền admin của vn.flygo.mail dùng được).
  MailAdminApi adminApi() => throw MailException(501, 'Máy chủ thư chưa hỗ trợ quản trị');
}

class HttpMailApi extends MailApi {
  HttpMailApi({required this.base, required this.id, String? mailbox, http.Client? client}) : _http = client ?? http.Client() {
    this.mailbox = mailbox;
  }

  /// base_url của app (vd https://mail.example.com); API ở `<base>/mail/api`.
  final String base;
  final FlygoId id;
  final http.Client _http;

  Future<Map<String, String>> _auth({bool refresh = false}) async => {
        'Authorization': 'Bearer ${await id.ticket(kMailApp, refresh: refresh).timeout(const Duration(seconds: 25))}',
        'User-Agent': kUserAgent,
        'X-Mailbox': ?mailbox,
      };

  Uri _uri(String path, [Map<String, String?> q = const {}]) {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    final u = Uri.parse(path.startsWith('/mail/api') || path.startsWith('/api/') ? '$b$path' : '$b/mail/api$path');
    final qp = {for (final e in q.entries) if (e.value != null && e.value!.isNotEmpty) e.key: e.value!};
    return qp.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...qp});
  }

  Future<http.Response> _send(String method, Uri uri, {Object? body, bool retried = false}) async {
    final req = http.Request(method, uri)..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 45));
    // Vé vừa hết hạn hoặc quyền vừa đổi: xin vé mới và thử lại một lần.
    if (res.statusCode == 401 && !retried) return _send(method, uri, body: body, retried: true);
    return res;
  }

  dynamic _json(http.Response res) {
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    if (res.statusCode >= 400) throw MailException(res.statusCode, '${j is Map ? j['error'] ?? '' : ''}'.isEmpty ? 'Máy chủ thư trả lỗi ${res.statusCode}' : '${(j as Map)['error']}');
    return j;
  }

  Future<dynamic> _get(String path, [Map<String, String?> q = const {}]) async => _json(await _send('GET', _uri(path, q)));
  Future<dynamic> _post(String path, Object body) async => _json(await _send('POST', _uri(path), body: body));

  @override
  Future<MailMe> me() async => MailMe.fromJson(await _get('/me') as Map);
  @override
  Future<List<MailLabel>> labels() async => [for (final l in await _get('/labels') as List) MailLabel.fromJson(l as Map)];
  @override
  Future<MailLabel> createLabel(String name, int color) async => MailLabel.fromJson(await _post('/labels', {'name': name, 'color': hexColor(color)}) as Map);
  @override
  Future<MailCounts> counts() async => MailCounts.fromJson(await _get('/counts') as Map);

  @override
  Future<MailPage> list({String box = 'inbox', String? label, String? category, String? q, int page = 1, int size = 50}) async {
    final j = await _get('/threads', {'box': box, 'label': label, 'category': category, 'q': q, 'page': '$page', 'size': '$size'}) as Map;
    return MailPage([for (final t in j['items'] as List) MailThreadSummary.fromJson(t as Map)], (j['total'] as num?)?.toInt() ?? 0,
        page: page, size: size, counts: j['counts'] is Map ? MailCounts.fromJson(j['counts'] as Map) : null);
  }

  @override
  Future<MailThread> thread(String id) async => MailThread.fromJson(await _get('/threads/${Uri.encodeComponent(id)}') as Map);

  @override
  Future<MailCounts?> modify(List<String> ids, MailChange change) async {
    final j = await _post('/threads/modify', {'ids': ids, ...change.toJson()});
    return j is Map && j['counts'] is Map ? MailCounts.fromJson(j['counts'] as Map) : null;
  }

  @override
  Future<void> remove(List<String> ids) async => _post('/threads/delete', {'ids': ids});

  @override
  Future<List<MailPerson>> contacts(String q) async => [for (final p in await _get('/contacts', {'q': q}) as List) MailPerson.fromJson(p as Map)];

  @override
  Future<MailAttachment> upload(File file, {String? name, String? type}) async {
    Future<http.Response> go(bool retried) async {
      final req = http.MultipartRequest('POST', _uri('/attachments'))
        ..headers.addAll(await _auth(refresh: retried))
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name ?? file.uri.pathSegments.last));
      final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(minutes: 3));
      return res.statusCode == 401 && !retried ? go(true) : res;
    }

    return MailAttachment.fromJson(_json(await go(false)) as Map);
  }

  @override
  Future<String> saveDraft(MailDraft d) async {
    final j = await _json(await _send('PUT', _uri(d.id == null ? '/drafts' : '/drafts/${Uri.encodeComponent(d.id!)}'), body: d.toJson())) as Map;
    return '${j['id']}';
  }

  @override
  Future<void> deleteDraft(String id) async => _json(await _send('DELETE', _uri('/drafts/${Uri.encodeComponent(id)}')));

  @override
  Future<void> send(MailDraft d, {String? draftId, DateTime? sendAt}) async =>
      _post('/send', {...d.toJson(), 'draftId': ?draftId, if (sendAt != null) 'sendAt': sendAt.toUtc().toIso8601String()});

  @override
  Future<void> cancelScheduled(String draftId) async => _json(await _send('DELETE', _uri('/scheduled/${Uri.encodeComponent(draftId)}')));

  @override
  MailAdminApi adminApi() => HttpMailAdminApi(base: base, id: id, client: _http);

  @override
  Future<MailLiveTarget?> liveTarget({bool refresh = false}) async {
    final u = _uri('/live');
    final h = await _auth(refresh: refresh)
      ..remove('X-Mailbox');
    return MailLiveTarget(u.replace(scheme: u.scheme == 'http' ? 'ws' : 'wss'), h);
  }

  @override
  Future<void> setNotify(bool on) async => _json(await _send('PUT', _uri('/notify'), body: {'enabled': on}));

  @override
  Future<MailAiResult> ai(String threadId, {String task = 'draft', String instruction = '', String tone = ''}) async =>
      MailAiResult.fromJson(await _post('/ai', {'threadId': threadId, 'task': task, if (instruction.isNotEmpty) 'instruction': instruction, if (tone.isNotEmpty) 'tone': tone}) as Map);

  @override
  Future<MailAiResult> aiRevise({String? threadId, required String draft, String instruction = ''}) async => MailAiResult.fromJson(
      await _post('/ai', {'task': 'revise', 'draft': draft, 'threadId': ?threadId, if (instruction.isNotEmpty) 'instruction': instruction}) as Map);

  @override
  Future<MailDigest> aiDigest() async => MailDigest.fromJson(await _post('/ai/digest', {}) as Map);

  @override
  Future<File> download(MailAttachment a) async {
    final res = await _send('GET', _uri(a.url));
    if (res.statusCode >= 400) throw MailException(res.statusCode, 'Không tải được "${a.name}"');
    final dir = Directory('${(await getTemporaryDirectory()).path}/mail/${a.id.hashCode.toUnsigned(32)}');
    await dir.create(recursive: true);
    final f = File('${dir.path}/${a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
    await f.writeAsBytes(res.bodyBytes);
    return f;
  }
}
