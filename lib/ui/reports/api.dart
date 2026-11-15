// Báo cáo (vn.flygo.reports): gọi backend reports (flygo-chat-server reports/) bằng vé Flygo ID, kênh realtime WebSocket.
// App chỉ đọc và hiển thị: số liệu do AI đẩy vào qua MCP. Đặc tả API: flygo-chat-server reports/README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';

typedef Json = Map<String, dynamic>;

const kReportsApp = 'vn.flygo.reports';
const kReportsScreen = 'reports';

class ReportsException implements Exception {
  ReportsException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Nguồn dữ liệu cho màn hình: API thật, hoặc dữ liệu cố định khi kiểm thử / chụp mockup.
abstract class ReportsSource {
  Future<Json> get(String path, [Map<String, String>? q]);
  Future<Json> post(String path, [Object? body]);
  Future<Json> put(String path, Object body);
  Future<Json> delete(String path);
  Future<Uint8List> bytes(String path, [Map<String, String>? q]);
  Future<ReportsLive?> live({List<String> reports = const [], bool all = false});
}

class ReportsApi implements ReportsSource {
  ReportsApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (vd https://chat.example.com/__apps/reports).
  final String base;
  final FlygoId id;
  final http.Client _http;

  /// Kiểm thử: tắt kênh realtime.
  static bool liveEnabled = true;

  Future<Map<String, String>> _auth({bool refresh = false}) async => {
    'Authorization': 'Bearer ${await id.ticket(kReportsApp, refresh: refresh).timeout(const Duration(seconds: 25))}',
    'User-Agent': kUserAgent,
  };

  Uri uri(String path, [Map<String, String>? q]) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path').replace(queryParameters: q);

  Future<http.Response> _send(String method, String path, {Object? body, Map<String, String>? query, bool retried = false}) async {
    final req = http.Request(method, uri(path, query))..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 40));
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, query: query, retried: true);
    return res;
  }

  Json _json(http.Response res) {
    Json j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw ReportsException(res.statusCode, '${j['error'] ?? 'Báo cáo trả lỗi ${res.statusCode}'}');
    return j;
  }

  @override
  Future<Json> get(String path, [Map<String, String>? q]) async => _json(await _send('GET', path, query: q));
  @override
  Future<Json> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  @override
  Future<Json> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  @override
  Future<Json> delete(String path) async => _json(await _send('DELETE', path));

  @override
  Future<Uint8List> bytes(String path, [Map<String, String>? q]) async {
    final res = await _send('GET', path, query: q);
    if (res.statusCode >= 400) _json(res);
    return res.bodyBytes;
  }

  @override
  Future<ReportsLive?> live({List<String> reports = const [], bool all = false}) async {
    if (!liveEnabled) return null;
    final t = await id.ticket(kReportsApp);
    final u = uri('/ws', {'ticket': t});
    final ws = WebSocketChannel.connect(u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws'));
    await ws.ready;
    final l = ReportsLive._(ws);
    l.subscribe(reports: reports, all: all);
    return l;
  }
}

/// Kênh realtime: nhận {type: edition | report | comment | deleted, report, edition?}.
class ReportsLive {
  ReportsLive._(this._ws) {
    _sub = _ws.stream.listen(
      (m) {
        try {
          _out.add(Map<String, dynamic>.from(jsonDecode('$m') as Map));
        } catch (_) {}
      },
      onError: (_) => _out.close(),
      onDone: () => _out.close(),
    );
    _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
  }
  final WebSocketChannel _ws;
  late final StreamSubscription<dynamic> _sub;
  late final Timer _ping;
  final _out = StreamController<Json>.broadcast();
  Stream<Json> get events => _out.stream;

  void _send(Object m) {
    try {
      _ws.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  void subscribe({List<String> reports = const [], bool all = false}) => _send({'type': 'sub', 'reports': reports, 'all': all});

  Future<void> close() async {
    _ping.cancel();
    await _sub.cancel();
    await _ws.sink.close();
    await _out.close();
  }
}

// ---------------------------------------------------------------- định dạng (giống server blocks.ts)
String _nf(num v, int digits) {
  final neg = v < 0;
  var s = v.abs().toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final int0 = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${neg ? '-' : ''}$int0${parts.length > 1 ? ',${parts[1]}' : ''}';
}

/// Số kèm đơn vị: VND rút gọn tỷ / tr; % ; còn lại tách nghìn.
String fmtValue(num v, [String? unit]) {
  final u = (unit ?? '').trim();
  if (RegExp(r'^(vnd|đ|₫)$', caseSensitive: false).hasMatch(u)) {
    final a = v.abs();
    if (a >= 1e9) return '${_nf(v / 1e9, 2)} tỷ';
    if (a >= 1e6) return '${_nf(v / 1e6, a >= 1e8 ? 0 : 1)} tr';
    return '${_nf(v, 0)} ₫';
  }
  if (u == '%') return '${_nf(v, 1)}%';
  return u.isEmpty ? _nf(v, 2) : '${_nf(v, 2)} $u';
}

/// Giá trị rút gọn cho trục biểu đồ.
String fmtAxis(num v, [String? unit]) {
  final u = (unit ?? '').trim().toLowerCase();
  if (u == 'vnd' || u == 'đ' || u == '₫') return fmtValue(v, unit);
  final a = v.abs();
  if (a >= 1e9) return '${_nf(v / 1e9, 1)}B';
  if (a >= 1e6) return '${_nf(v / 1e6, 1)}M';
  if (a >= 1e4) return '${_nf(v / 1e3, 0)}k';
  return _nf(v, a < 10 ? 2 : 0);
}

String fmtPct(double p) => '${p >= 0 ? '+' : ''}${_nf(p * 100, p.abs() < 0.1 ? 1 : 0)}%';

/// Giờ ISO 8601 → "07:20 15/11".
String fmtAsOf(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final v = t.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(v.hour)}:${two(v.minute)} ${two(v.day)}/${two(v.month)}';
}

String fmtMs(int ms) => fmtAsOf(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String());
