import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'flows_api.dart';

/// Một tin đẩy của kênh realtime Flows: dòng luồng (`instance`) / tiến trình (`process`) vừa đổi, giống dòng danh sách
/// REST; `resync`: có thể đã lỡ tin (kênh vừa nối lại / máy chủ bỏ tin vì app đọc chậm) → tải lại bằng REST.
class FlowsLiveEvent {
  final String type;
  final String id;
  final String flowId;
  final Map<String, dynamic> row;
  final bool done;
  const FlowsLiveEvent(this.type, {this.id = '', this.flowId = '', this.row = const {}, this.done = false});

  bool get resync => type == 'resync';
}

/// Đường nối WebSocket tối giản (để test thay bằng ống giả).
class FlowsLiveSocket {
  final Stream<dynamic> stream;
  final void Function(String) send;
  final void Function() close;
  const FlowsLiveSocket(this.stream, this.send, this.close);
}

typedef FlowsLiveConnector = Future<FlowsLiveSocket> Function(Uri url);

Future<FlowsLiveSocket> _wsConnect(Uri url) async {
  final ws = WebSocketChannel.connect(url);
  await ws.ready;
  return FlowsLiveSocket(ws.stream, ws.sink.add, () => ws.sink.close());
}

/// Đăng ký một chủ đề; [cancel] khi đóng màn hình (hoặc tiến trình xong).
class FlowsLiveSub {
  final FlowsLive _live;
  final String topic;
  final void Function(FlowsLiveEvent) _on;
  bool _cancelled = false;
  FlowsLiveSub._(this._live, this.topic, this._on);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _live._remove(this);
  }
}

/// Kênh realtime `<máy chủ>/__apps/flows/ws`, một kết nối cho mỗi máy chủ + phiên đăng nhập, dùng chung cho mọi màn hình.
/// Nối khi có màn hình đăng ký chủ đề đầu tiên, đóng khi hết đăng ký (sau 30 giây, đỡ nối lại khi chuyển màn hình);
/// rớt thì nối lại (2 → 60 giây). [up]: đang nối được: màn hình tắt tự tải lại 5 giây một lần, chỉ dùng khi kênh rớt.
///
/// Chủ đề: `instance:<mã luồng>`, `process:<mã tiến trình>`, `flow:<mã quy trình>`, `processes` (mọi tiến trình).
class FlowsLive {
  static final _all = <String, FlowsLive>{};

  /// Thay đường nối WebSocket (test).
  static FlowsLiveConnector connector = _wsConnect;

  /// Đơn vị thời gian chờ nối lại / đóng khi hết đăng ký (test rút ngắn).
  static Duration unit = const Duration(seconds: 1);

  /// Test dùng client HTTP giả mà chưa thay đường nối: không nối WebSocket thật (màn hình tự tải lại như cũ).
  static bool get _offline => FlowsApi.usesTestClient && identical(connector, _wsConnect);

  /// Kênh dùng chung của [api] (máy chủ + phiên đăng nhập).
  static FlowsLive of(FlowsApi api) => _all.putIfAbsent('${api.server}|${api.token}', () => FlowsLive._(api));

  /// Chỉ cho test: bỏ mọi kênh.
  static void resetForTest() {
    for (final l in _all.values) {
      l._shutdown();
    }
    _all.clear();
    connector = _wsConnect;
    unit = const Duration(seconds: 1);
  }

  final FlowsApi _api;
  FlowsLive._(this._api);

  final _subs = <String, List<FlowsLiveSub>>{};
  FlowsLiveSocket? _sock;
  StreamSubscription? _listen;
  Timer? _ping, _retry, _watchdog, _idle;
  bool _connecting = false, _ready = false, _renew = false, _wasUp = false;
  int _backoff = 2;
  DateTime _lastRx = DateTime.now();

  bool get up => _ready;

  /// Đăng ký [topic]; tin của chủ đề gọi [onEvent] (kể cả `resync`).
  FlowsLiveSub subscribe(String topic, void Function(FlowsLiveEvent) onEvent) {
    final s = FlowsLiveSub._(this, topic, onEvent);
    final list = _subs.putIfAbsent(topic, () => []);
    list.add(s);
    _idle?.cancel();
    if (list.length == 1 && _ready) _send({'op': 'sub', 'topics': [topic]});
    _connect();
    return s;
  }

  void _remove(FlowsLiveSub s) {
    final list = _subs[s.topic];
    if (list == null) return;
    list.remove(s);
    if (list.isNotEmpty) return;
    _subs.remove(s.topic);
    if (_ready) _send({'op': 'unsub', 'topics': [s.topic]});
    if (_subs.isEmpty) {
      _idle?.cancel();
      if (_sock == null) return _drop(retry: false);
      _idle = Timer(unit * 30, () {
        if (_subs.isEmpty) _drop(retry: false);
      });
    }
  }

  void _send(Map<String, dynamic> m) {
    try {
      _sock?.send(jsonEncode(m));
    } catch (_) {}
  }

  Uri get _url {
    final u = Uri.parse('${_api.base}/flows/ws');
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws');
  }

  Future<void> _connect() async {
    if (_sock != null || _connecting || _subs.isEmpty || _offline) return;
    _connecting = true;
    _retry?.cancel();
    try {
      final token = await _api.liveTicket(refresh: _renew);
      _renew = false;
      final sock = await connector(_url);
      if (_subs.isEmpty) {
        sock.close();
        return;
      }
      _sock = sock;
      _lastRx = DateTime.now();
      _listen = sock.stream.listen(_onMessage, onDone: () => _drop(), onError: (_) => _drop());
      sock.send(jsonEncode({'op': 'auth', 'token': token, 'server': _api.server}));
    } catch (_) {
      _drop();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic m) {
    _lastRx = DateTime.now();
    if (m is! String) return;
    Map j;
    try {
      final d = jsonDecode(m);
      if (d is! Map) return;
      j = d;
    } catch (_) {
      return;
    }
    switch ('${j['type'] ?? ''}') {
      case 'ready':
        _ready = true;
        _backoff = 2;
        _ping?.cancel();
        _ping = Timer.periodic(unit * 25, (_) => _send({'op': 'ping'}));
        _watchdog?.cancel();
        _watchdog = Timer.periodic(unit * 15, (_) {
          if (DateTime.now().difference(_lastRx) > unit * 60) _drop();
        });
        if (_subs.isNotEmpty) _send({'op': 'sub', 'topics': _subs.keys.toList()});
        // Nối lại sau khi rớt: có thể đã lỡ tin trong lúc rớt.
        if (_wasUp) _emitAll(const FlowsLiveEvent('resync'));
        _wasUp = true;
      case 'error' when j['topic'] == null:
        // Không đăng nhập được (vé hết hạn): lần sau xin vé mới.
        _renew = j['status'] == 401;
        _drop();
      case 'resync':
        _emitAll(const FlowsLiveEvent('resync'));
      case 'instance' || 'process':
        final type = '${j['type']}';
        final e = FlowsLiveEvent(type,
            id: '${j['id'] ?? ''}',
            flowId: '${j['flow_id'] ?? ''}',
            row: j['row'] is Map ? (j['row'] as Map).cast<String, dynamic>() : const {},
            done: j['done'] == true);
        final seen = <FlowsLiveSub>{};
        for (final t in ['$type:${e.id}', 'flow:${e.flowId}', if (type == 'process') 'processes']) {
          for (final s in [...?_subs[t]]) {
            if (seen.add(s) && !s._cancelled) s._on(e);
          }
        }
    }
  }

  void _emitAll(FlowsLiveEvent e) {
    for (final s in [for (final l in _subs.values) ...l]) {
      if (!s._cancelled) s._on(e);
    }
  }

  void _drop({bool retry = true}) {
    _ready = false;
    _ping?.cancel();
    _watchdog?.cancel();
    _listen?.cancel();
    _listen = null;
    final s = _sock;
    _sock = null;
    try {
      s?.close();
    } catch (_) {}
    if (!retry || _subs.isEmpty) {
      _retry?.cancel();
      _wasUp = false;
      return;
    }
    _retry?.cancel();
    _retry = Timer(unit * _backoff, _connect);
    _backoff = (_backoff * 2).clamp(2, 60);
  }

  void _shutdown() {
    _subs.clear();
    _idle?.cancel();
    _retry?.cancel();
    _drop(retry: false);
  }
}
