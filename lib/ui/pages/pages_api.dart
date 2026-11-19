import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../calls/call_service.dart';
import '../../config.dart';

// Trang họp (Họp mới) trên relay: /meet/pages (kho trang), /meet/stage/<cuộc họp> (sân khấu, qua CallService.stageAct).

class PagesError implements Exception {
  final int status;
  final String message;
  PagesError(this.status, this.message);
  @override
  String toString() => message;
}

/// Một trang (phần chung, không có trạng thái riêng của loại trang).
class MeetPage {
  final String id, type, title, owner, ownerName, visibility;
  final String? meeting;
  final int order, seconds, rev, updatedAt;
  final Map<String, dynamic> content;
  final Map<String, dynamic>? file;
  MeetPage(Map m)
    : id = '${m['id'] ?? ''}',
      type = '${m['type'] ?? ''}',
      title = '${m['title'] ?? ''}',
      owner = '${m['owner'] ?? ''}',
      ownerName = '${m['owner_name'] ?? ''}',
      visibility = '${m['visibility'] ?? 'private'}',
      meeting = m['meeting'] as String?,
      order = (m['order'] as num?)?.toInt() ?? 0,
      seconds = (m['seconds'] as num?)?.toInt() ?? 0,
      rev = (m['rev'] as num?)?.toInt() ?? 0,
      updatedAt = (m['updated_at'] as num?)?.toInt() ?? 0,
      content = m['content'] is Map ? (m['content'] as Map).cast<String, dynamic>() : const {},
      file = m['content'] is Map && (m['content'] as Map)['file'] is Map
          ? ((m['content'] as Map)['file'] as Map).cast<String, dynamic>()
          : m['file'] is Map
              ? (m['file'] as Map).cast<String, dynamic>()
              : null;
  bool get public => visibility != 'private';
}

/// Trang kèm phần xem của mình (view do loại trang tính theo quyền) và vai trò owner | manager | member | viewer.
class PageData {
  final MeetPage page;
  final Map<String, dynamic> view;
  final String role;
  final int rev;
  PageData(this.page, this.view, this.role, this.rev);
  factory PageData.from(Map j) => PageData(
        MeetPage(j['page'] as Map),
        j['view'] is Map ? (j['view'] as Map).cast<String, dynamic>() : const {},
        '${j['role'] ?? 'owner'}',
        (j['rev'] as num?)?.toInt() ?? 0,
      );
  bool get manage => role == 'owner' || role == 'manager';
  PageData withView(Map<String, dynamic> v, int rev) => PageData(page, v, role, rev);
}

class PagesApi {
  final CallService call;
  PagesApi(this.call);

  Future<Map<String, dynamic>> _req(String method, String path, {Object? body, Map<String, String>? query, Map<String, String>? headers, Duration timeout = const Duration(seconds: 15)}) async {
    final req = http.Request(method, Uri.parse('$kPushUrl$path').replace(queryParameters: query))..headers.addAll({...call.pushHeaders, ...?headers});
    if (body is List<int>) {
      req.bodyBytes = body;
    } else if (body != null) {
      req.body = jsonEncode(body);
    }
    final r = await http.Response.fromStream(await req.send().timeout(timeout));
    Map<String, dynamic> j;
    try {
      j = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      j = const {};
    }
    if (r.statusCode != 200) throw PagesError(r.statusCode, (j['error'] as String?) ?? 'HTTP ${r.statusCode}');
    return j;
  }

  /// scope: mine | public | all (trang trong cuộc họp hiện tại).
  Future<List<MeetPage>> list(String scope) async {
    final m = call.pagesMeeting;
    if (m == null) return const [];
    final j = await _req('GET', '/meet/pages', query: {'meeting': m, 'scope': scope});
    return [for (final x in (j['pages'] as List? ?? const [])) MeetPage(x as Map)];
  }

  Future<PageData> get(String id) async => PageData.from(await _req('GET', '/meet/pages/$id'));

  /// Trang đang lên sân khấu, đọc bằng khoá sân khấu (khi mình không có quyền đọc theo id).
  Future<PageData> byKey(String key) async => PageData.from(await _req('GET', '/meet/pages/stage/$key'));

  Future<PageData> create({required String type, required String title, String visibility = 'private', Map<String, dynamic> content = const {}, int seconds = 0, Map<String, dynamic> init = const {}}) async {
    final j = await _req('POST', '/meet/pages', body: {
      'type': type, 'title': title, 'meeting': call.pagesMeeting, 'visibility': visibility, 'content': content, 'seconds': seconds, 'init': init,
    });
    return PageData.from({...j, 'role': 'owner'});
  }

  Future<MeetPage> patch(String id, Map<String, dynamic> b) async => MeetPage((await _req('PATCH', '/meet/pages/$id', body: b))['page'] as Map);

  Future<void> delete(String id) => _req('DELETE', '/meet/pages/$id');

  /// Một hành động của loại trang -> phần xem mới.
  Future<(Map<String, dynamic>, int)> act(String id, String action, [Map<String, dynamic> body = const {}]) async {
    final j = await _req('POST', '/meet/pages/$id/act/$action', body: body);
    return ((j['view'] as Map? ?? const {}).cast<String, dynamic>(), (j['rev'] as num?)?.toInt() ?? 0);
  }

  Future<void> export(String id) => _req('POST', '/meet/pages/$id/export');

  /// Gửi bản PDF cho trang tài liệu.
  Future<Map<String, dynamic>> upload(String id, File pdf, String name, int pages) async {
    final j = await _req('POST', '/meet/pages/$id/file',
        query: {'name': name, 'pages': '$pages'}, headers: {'Content-Type': 'application/pdf'}, body: await pdf.readAsBytes(), timeout: const Duration(minutes: 3));
    return (j['file'] as Map).cast<String, dynamic>();
  }
}
