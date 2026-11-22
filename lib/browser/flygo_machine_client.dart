// Flygo Chat bản máy tính đăng ký với Gateway bridge của mỗi máy chủ (<máy chủ>/__apps/gateway/ws) như một client kind
// "machine" ("Flygo Chat · <máy>") để nhận lệnh khởi động trình duyệt tích hợp từ xa (Sếp 2026-11-22: trình duyệt tích hợp luôn
// khởi động từ xa được). Tool khai báo: integrated_browser_start {tax?, profile?, url?, requester}. Máy của chính chủ: mở
// ngay ở nền; người khác yêu cầu: hỏi chủ máy mỗi lần (hook, mặc định hỏi).
// Giao thức như extension (xem flygo-browser-bridge README): hello {token, client, tools} → welcome; RPC tools/call; ping 20 s.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import '../config.dart';
import 'flygo_browser_host.dart';
import 'flygo_id.dart';
import 'my_browsers.dart';

class FlygoMachineClient {
  FlygoMachineClient._();
  static final instance = FlygoMachineClient._();

  /// Hỏi chủ máy khi người khác yêu cầu khởi động (giao diện đặt). null = từ chối.
  Future<bool> Function(String requester, String what)? askConsent;

  final _conns = <String, _Conn>{};
  final _secure = const FlutterSecureStorage();
  bool _started = false;

  static String get machine => Platform.localHostname.replaceAll(RegExp(r'\.(local|lan|home)$'), '');

  static const _tools = [
    {
      'name': 'integrated_browser_start',
      'description': 'Khởi động trình duyệt tích hợp (Ký số) trên máy này ở nền, đúng profile (tax = MST hoặc profile), url tuỳ chọn.',
      'inputSchema': {
        'type': 'object',
        'properties': {'tax': {'type': 'string'}, 'profile': {'type': 'string'}, 'url': {'type': 'string'}, 'requester': {'type': 'object'}},
      },
      'annotations': {'readOnlyHint': false},
    },
  ];

  /// Gọi khi đã đăng nhập (máy tính). Nối mọi máy chủ có Gateway bridge.
  Future<void> start(String chatToken) async {
    if (!FlygoBrowserHost.supported || _started) return;
    _started = true;
    for (final server in await FlygoBrowserHost.instance.bridgeServers()) {
      final c = _Conn(this, server, chatToken);
      _conns[server] = c;
      unawaited(c.run());
    }
  }

  void stop() {
    _started = false;
    for (final c in _conns.values) {
      c.close();
    }
    _conns.clear();
  }

  Future<Map<String, dynamic>> _pair(String server, String chatToken, {bool fresh = false}) async {
    final key = 'flygo-machine:$server';
    if (!fresh) {
      try {
        final raw = await _secure.read(key: key);
        if (raw != null) return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    String? old;
    try {
      old = (jsonDecode(await _secure.read(key: key) ?? '{}') as Map)['client_id'] as String?;
    } catch (_) {}
    final current = server == kServerUrl.replaceAll(RegExp(r'/+$'), '');
    final tok = current ? chatToken : await TokenStore.readFor(server);
    if (tok == null) throw StateError('chưa đăng nhập $server');
    final ticket = current ? await (await FlygoId.current(tok))!.ticket(kBrowserApp) : await _ticketOn(server, tok);
    final r = await http.post(Uri.parse('$server/__apps/gateway/api/pair'),
        headers: {'Authorization': 'Bearer $ticket', 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
        body: jsonEncode({
          'client': {'type': 'app', 'kind': 'machine', 'name': 'Flygo Chat · $machine', 'engine': 'Flygo Chat', 'os': Platform.isMacOS ? 'macOS' : 'Windows'},
          'replace': ?old,
          'machine_name': machine,
        })).timeout(const Duration(seconds: 15));
    final j = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    if (r.statusCode != 200 || j['token'] == null) throw HttpException('${j['error'] ?? r.statusCode}');
    final saved = {'client_id': (j['client'] as Map?)?['id'], 'token': j['token'], 'ws_url': j['ws_url']};
    await _secure.write(key: key, value: jsonEncode(saved));
    return saved;
  }

  static Future<String> _ticketOn(String root, String chatToken) async {
    final t = await http.post(Uri.parse('$root/flygo-id/v1/token'),
        headers: {'Authorization': 'Bearer $chatToken', 'X-MM-Server': root, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
        body: jsonEncode({'audience': kBrowserApp})).timeout(const Duration(seconds: 15));
    final j = jsonDecode(t.body) as Map;
    if (t.statusCode != 200 || j['token'] == null) throw HttpException('${j['error'] ?? t.statusCode}');
    return '${j['token']}';
  }

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> a) async {
    if (name != 'integrated_browser_start') return _text('Không có tool $name', error: true);
    final req = (a['requester'] as Map?) ?? const {};
    final tax = a['tax'] as String?, profile = a['profile'] as String?, url = a['url'] as String?;
    if (url != null && !RegExp(r'^https?://').hasMatch(url)) return _text('url phải là http(s)', error: true);
    if (req['own'] != true) {
      // Người khác yêu cầu mở trình duyệt trên máy này: hỏi chủ máy mỗi lần (mặc định).
      final ok = await (askConsent?.call('${req['name'] ?? 'Agent'}', 'Ký số ${tax ?? profile ?? ''}') ?? Future.value(false));
      if (!ok) return _text('Chủ máy từ chối khởi động trình duyệt.', error: true);
    }
    final ok = await FlygoBrowserHost.instance.openBackground(tax: tax, profile: profile, url: url);
    return ok ? _text('Đã khởi động trình duyệt tích hợp trên $machine.') : _text('Không khởi động được trình duyệt tích hợp trên $machine.', error: true);
  }

  static Map<String, dynamic> _text(String s, {bool error = false}) => {
        if (error) 'isError': true,
        'content': [
          {'type': 'text', 'text': s},
        ],
      };
}

class _Conn {
  _Conn(this.owner, this.server, this.chatToken);
  final FlygoMachineClient owner;
  final String server;
  final String chatToken;
  WebSocket? _ws;
  Timer? _ping;
  bool _closed = false;
  int _retry = 0;

  void close() {
    _closed = true;
    _ping?.cancel();
    _ws?.close();
  }

  Future<void> run() async {
    while (!_closed) {
      try {
        var creds = await owner._pair(server, chatToken);
        final ws = await WebSocket.connect('${creds['ws_url']}').timeout(const Duration(seconds: 15));
        _ws = ws;
        ws.add(jsonEncode({
          't': 'hello',
          'token': creds['token'],
          'client': {'type': 'app', 'kind': 'machine', 'name': 'Flygo Chat · ${FlygoMachineClient.machine}', 'version': '1.0'},
          'tools': FlygoMachineClient._tools,
          'capabilities': <String>[],
        }));
        _ping = Timer.periodic(const Duration(seconds: 20), (_) => ws.add(jsonEncode({'t': 'ping'})));
        _retry = 0;
        await for (final data in ws) {
          final m = jsonDecode(data as String) as Map;
          if (m['id'] != null && m['method'] == 'tools/call') {
            final p = (m['params'] as Map?) ?? const {};
            final r = await owner._call('${p['name']}', Map<String, dynamic>.from((p['arguments'] as Map?) ?? const {})).catchError((Object e) => FlygoMachineClient._text('$e', error: true));
            ws.add(jsonEncode({'id': m['id'], 'result': r}));
          } else if (m['id'] != null && m['method'] != null) {
            ws.add(jsonEncode({'id': m['id'], 'error': {'message': 'không hỗ trợ ${m['method']}'}}));
          }
        }
        _ping?.cancel();
        // Gateway đóng 4401 / 4403: token hỏng / bị gỡ → ghép lại lần sau.
        if (ws.closeCode == 4401 || ws.closeCode == 4403) creds = await owner._pair(server, chatToken, fresh: true);
      } catch (e) {
        debugPrint('[flygo-machine] $server: $e');
      }
      if (_closed) break;
      await Future<void>.delayed(Duration(seconds: [3, 6, 15, 30, 60][_retry.clamp(0, 4)]));
      _retry++;
    }
  }
}
