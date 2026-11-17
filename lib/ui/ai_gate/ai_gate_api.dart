// Cổng AI (vn.flygo.ai): hạn mức dùng AI của công ty. Máy chủ: <chat>/__apps/ai (flygo-chat-server ai/, MODE=admin).
//   GET  /api/me/quota                 hạn mức của chính mình (vé cần quyền use)
//   /admin/api/*                       quản trị (vé cần quyền admin của Cổng AI trong Flygo ID)
// Gọi bằng vé Flygo ID (aud = vn.flygo.ai), không dùng cookie.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../browser/flygo_id.dart';
import '../../config.dart';

const kAiGateApp = 'vn.flygo.ai';

/// Địa chỉ Cổng AI của máy chủ chat hiện tại (chuẩn `/__apps/<tên>`).
String aiGateBase([String? server]) => '${(server ?? kServerUrl).replaceAll(RegExp(r'/+$'), '')}/__apps/ai';

class AiGateException implements Exception {
  AiGateException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Trạng thái hạn mức một người (dùng chung cho trang quản trị và trang "Hạn mức AI").
class AiQuota {
  AiQuota(this.j);
  final Map<String, dynamic> j;
  String get user => '${j['user'] ?? ''}';
  String get tier => '${j['tier'] ?? ''}';
  String get tierName => '${j['tier_name'] ?? j['tier'] ?? ''}';
  /// ok | warn (≥80%) | degraded (hết, đang dùng model rẻ) | blocked
  String get state => '${j['state'] ?? 'ok'}';
  int get usedPct => (j['used_pct'] as num?)?.toInt() ?? 0;
  int get dayPct => (j['day_used_pct'] as num?)?.toInt() ?? 0;
  double get monthUsd => (j['month_usd'] as num?)?.toDouble() ?? 0;
  double get usedUsd => (j['used_usd'] as num?)?.toDouble() ?? 0;
  double get dayUsd => (j['day_usd'] as num?)?.toDouble() ?? 0;
  double get daySpentUsd => (j['day_spent_usd'] as num?)?.toDouble() ?? 0;
  int? get smartLeft => (j['smart_left'] as num?)?.toInt();
  /// Mốc làm mới theo giờ Việt Nam (UTC+7), đọc bằng .day/.month/.hour.
  DateTime? get resetsAt => j['resets_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['resets_at'] as num).toInt(), isUtc: true).add(const Duration(hours: 7)) : null;
  bool get blocked => j['blocked'] == true;
  bool get access => j['access'] != false;
  double get extraUsd => (j['extra_usd'] as num?)?.toDouble() ?? 0;
  Map get custom => (j['custom'] as Map?) ?? const {};
  double? get customDay => (custom['day_usd'] as num?)?.toDouble();
  double? get customMonth => (custom['month_usd'] as num?)?.toDouble();
  String? get customTier => custom['tier'] as String?;
}

class AiGateApi {
  AiGateApi({required this.base, required this.ticket, http.Client? client}) : _http = client ?? http.Client();
  final String base;
  /// Vé Flygo ID aud = vn.flygo.ai (FlygoId.ticket).
  final Future<String> Function() ticket;
  final http.Client _http;

  static Future<AiGateApi?> current(String chatToken) async {
    final id = await FlygoId.current(chatToken);
    if (id == null) return null;
    return AiGateApi(base: aiGateBase(), ticket: () => id.ticket(kAiGateApp));
  }

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$base$path'))..headers['authorization'] = 'Bearer ${await ticket()}';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final r = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      j = null;
    }
    if (r.statusCode >= 400) throw AiGateException(r.statusCode, j is Map && j['error'] != null ? '${j['error']}' : 'Lỗi Cổng AI (${r.statusCode})');
    return j;
  }

  Future<AiQuota> myQuota() async => AiQuota(Map<String, dynamic>.from(await _call('GET', '/api/me/quota') as Map));

  /// Mức dùng của chính mình theo ứng dụng / trợ lý (hôm nay + tháng này): {day:{rows}, month:{rows}}, mỗi dòng
  /// {k, n, tok_in, tok_out, usd}. null = máy chủ Cổng AI chưa có (bản cũ trả 404).
  Future<Map<String, dynamic>?> myUsage() async {
    try {
      return Map<String, dynamic>.from(await _call('GET', '/api/me/usage?group=app') as Map);
    } on AiGateException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> overview() async => Map<String, dynamic>.from(await _call('GET', '/admin/api/overview') as Map);
  Future<List<AiQuota>> users() async => [for (final u in await _call('GET', '/admin/api/users') as List) AiQuota(Map<String, dynamic>.from(u as Map))];
  Future<AiQuota> setUser(String user, Map<String, dynamic> patch) async =>
      AiQuota(Map<String, dynamic>.from(await _call('PUT', '/admin/api/user', {'user': user, ...patch}) as Map));
  Future<Map<String, dynamic>> tiers() async => Map<String, dynamic>.from(await _call('GET', '/admin/api/tiers') as Map);
  Future<void> setTier(String id, Map<String, dynamic> v) => _call('PUT', '/admin/api/tiers/$id', v);
  Future<void> setCompany({double? monthUsd, double? dayUsd}) => _call('PUT', '/admin/api/company', {'month_usd': ?monthUsd, 'day_usd': ?dayUsd});
  Future<void> setAccessAll(bool all) => _call('PUT', '/admin/api/access', {'all': all});
  Future<List<Map<String, dynamic>>> extras() async => [for (final e in await _call('GET', '/admin/api/extras') as List) Map<String, dynamic>.from(e as Map)];
  Future<void> addExtra({required String scope, required String target, required double usd, int? days, String reason = ''}) =>
      _call('POST', '/admin/api/extras', {'scope': scope, 'target': target, 'usd': usd, 'days': ?days, 'reason': reason});
  Future<void> removeExtra(int id) => _call('DELETE', '/admin/api/extras/$id');
  Future<Map<String, dynamic>> usage({String group = 'user', String? month}) async =>
      Map<String, dynamic>.from(await _call('GET', '/admin/api/usage?group=$group${month == null ? '' : '&month=$month'}') as Map);
  Future<List<Map<String, dynamic>>> log() async => [for (final e in await _call('GET', '/admin/api/log') as List) Map<String, dynamic>.from(e as Map)];
}
