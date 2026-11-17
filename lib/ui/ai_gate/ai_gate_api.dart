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
  /// "Hạng Cơ bản": luôn có chữ Hạng để không lẫn với mức AI ("Mức Cơ bản").
  String get tierLabel => aiTierLabel(tierName);
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
  /// Từng mức AI (Cơ bản / Nâng cao / Chuyên gia; mã flygo-fast / smart / agent không đổi). Trang của nhân viên chỉ nhận %, không có tiền.
  List<AiModel> get models => [for (final m in (j['models'] as List? ?? const [])) if (m is Map) AiModel(m.cast<String, dynamic>())];
  /// Chỉnh riêng từng model của người này (trang quản trị): alias -> {enabled, month_usd, day_usd}.
  Map<String, Map<String, dynamic>> get modelOverrides => {
        for (final e in ((custom['models'] as Map?) ?? const {}).entries) '${e.key}': ((e.value as Map?) ?? const {}).cast<String, dynamic>(),
      };
}

/// Một mức AI của một người.
class AiModel {
  AiModel(this.j);
  final Map<String, dynamic> j;
  String get alias => '${j['alias'] ?? ''}';
  bool get allowed => j['allowed'] == true;
  bool get custom => j['custom'] == true;
  bool get exhausted => j['exhausted'] == true;
  int? get usedPct => (j['used_pct'] as num?)?.toInt();
  int? get dayPct => (j['day_used_pct'] as num?)?.toInt();
  double? get monthCap => (j['month_cap'] as num?)?.toDouble();
  double? get dayCap => (j['day_cap'] as num?)?.toDouble();
  double get usedUsd => (j['used_usd'] as num?)?.toDouble() ?? 0;
}

/// Tên hiển thị của mức AI.
/// Tên hạng luôn kèm chữ "Hạng" (Sếp 2026-11-17: hạng và mức AI trùng tên Cơ bản / Nâng cao).
String aiTierLabel(Object? name) {
  final n = '${name ?? ''}';
  return n.isEmpty || n.startsWith('Hạng') ? n : 'Hạng $n';
}

/// Tên mức AI luôn kèm chữ "Mức" (Mức Cơ bản / Mức Nâng cao / Mức Chuyên gia).
String aiModelName(String alias) => switch (alias) { 'flygo-fast' => 'Mức Cơ bản', 'flygo-smart' => 'Mức Nâng cao', 'flygo-agent' => 'Mức Chuyên gia', _ => alias };

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
  /// Sửa hàng loạt: filter {tier | dept | users}, patch như setUser (tier, models…). Trả {count, users}.
  Future<Map<String, dynamic>> bulkUsers(Map<String, dynamic> filter, Map<String, dynamic> patch) async =>
      Map<String, dynamic>.from(await _call('POST', '/admin/api/users/bulk', {'filter': filter, 'patch': patch}) as Map);
  Future<List<Map<String, dynamic>>> extras() async => [for (final e in await _call('GET', '/admin/api/extras') as List) Map<String, dynamic>.from(e as Map)];
  Future<void> addExtra({required String scope, required String target, required double usd, int? days, String reason = ''}) =>
      _call('POST', '/admin/api/extras', {'scope': scope, 'target': target, 'usd': usd, 'days': ?days, 'reason': reason});
  Future<void> removeExtra(int id) => _call('DELETE', '/admin/api/extras/$id');
  Future<Map<String, dynamic>> usage({String group = 'user', String? month}) async =>
      Map<String, dynamic>.from(await _call('GET', '/admin/api/usage?group=$group${month == null ? '' : '&month=$month'}') as Map);
  Future<List<Map<String, dynamic>>> log({int limit = 100}) async => [for (final e in await _call('GET', '/admin/api/log?limit=$limit') as List) Map<String, dynamic>.from(e as Map)];

  // ---- Nhà cung cấp (khoá CHỈ NHẬP: không API nào trả khoá về, chỉ 4 ký tự cuối)
  Future<List<Map<String, dynamic>>> providers() async => [for (final e in await _call('GET', '/admin/api/providers') as List) Map<String, dynamic>.from(e as Map)];
  Future<void> updateProvider(String id, Map<String, dynamic> v) => _call('PUT', '/admin/api/providers/$id', v);
  /// Thêm / thay khoá: máy chủ gọi thử trước rồi mới mã hoá và lưu. Trả {test:{ok,ms,msg}, models:[…]}.
  Future<Map<String, dynamic>> setProviderKey(String id, String key, {bool force = false}) async =>
      Map<String, dynamic>.from(await _call('PUT', '/admin/api/providers/$id/key', {'key': key, if (force) 'force': true}) as Map);
  Future<void> removeProviderKey(String id) => _call('DELETE', '/admin/api/providers/$id/key');
  Future<void> removeProvider(String id) => _call('DELETE', '/admin/api/providers/$id');
  Future<Map<String, dynamic>> testProvider(String id) async => Map<String, dynamic>.from(await _call('POST', '/admin/api/providers/$id/test') as Map);
  Future<List<String>> providerModels(String id) async => [for (final m in ((await _call('GET', '/admin/api/providers/$id/models') as Map)['models'] as List? ?? const [])) '$m'];

  // ---- Mức AI → nhà cung cấp + model + chuỗi dự phòng
  Future<List<Map<String, dynamic>>> aliases() async => [for (final e in await _call('GET', '/admin/api/aliases') as List) Map<String, dynamic>.from(e as Map)];
  Future<void> setAlias(String id, Map<String, dynamic> v) => _call('PUT', '/admin/api/aliases/$id', v);
}
