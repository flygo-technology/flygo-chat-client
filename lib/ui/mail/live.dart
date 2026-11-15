// Thư: kênh realtime `<base_url>/mail/api/live` (WebSocket, vé Flygo ID như các lệnh API khác).
// Máy chủ báo khi hộp thư có thư mới / thư đổi trạng thái (từ máy khác, từ thư đến) và khi danh sách hộp thư
// hay quyền thay đổi. Rớt thì nối lại (1 → 60 giây); trong lúc rớt màn hình tự tải lại định kỳ (dự phòng).
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

/// Một tin của kênh: `mail` (hộp [mailbox] đổi: [kinds] new/update/delete, [threads] các cuộc hội thoại),
/// `boxes` (danh sách hộp thư / quyền đổi), `resync` (vừa nối lại sau khi rớt, có thể đã lỡ tin),
/// `poll` (kênh đang rớt: tự tải lại).
class MailLiveEvent {
  const MailLiveEvent(this.type, {this.mailbox = '', this.kinds = const [], this.threads = const []});
  final String type, mailbox;
  final List<String> kinds, threads;

  bool get isNew => kinds.contains('new');

  static MailLiveEvent? parse(String s) {
    try {
      final j = jsonDecode(s);
      if (j is! Map) return null;
      final t = '${j['t'] ?? ''}';
      if (t == 'mail') {
        return MailLiveEvent('mail',
            mailbox: '${j['mailbox'] ?? ''}'.toLowerCase(),
            kinds: [for (final k in j['kinds'] as List? ?? const []) '$k'],
            threads: [for (final k in j['threads'] as List? ?? const []) '$k']);
      }
      if (t == 'boxes') return const MailLiveEvent('boxes');
    } catch (_) {}
    return null;
  }
}

/// Địa chỉ + header (vé) để nối kênh.
class MailLiveTarget {
  const MailLiveTarget(this.url, this.headers);
  final Uri url;
  final Map<String, String> headers;
}

/// Đường nối WebSocket tối giản (test thay bằng ống giả).
class MailLiveSocket {
  const MailLiveSocket(this.stream, this.send, this.close, this.closeCode);
  final Stream<dynamic> stream;
  final void Function(String) send;
  final void Function() close;
  final int? Function() closeCode;
}

typedef MailLiveConnector = Future<MailLiveSocket> Function(MailLiveTarget t);

Future<MailLiveSocket> _connectIo(MailLiveTarget t) async {
  final ch = IOWebSocketChannel.connect(t.url, headers: t.headers, connectTimeout: const Duration(seconds: 20));
  await ch.ready;
  return MailLiveSocket(ch.stream, ch.sink.add, () => ch.sink.close(), () => ch.closeCode);
}

class MailLive {
  MailLive({required this.target, required this.onEvent, MailLiveConnector? connector}) : _connector = connector ?? _connectIo;

  /// Xin địa chỉ + vé ([refresh] = vé mới, khi máy chủ vừa từ chối).
  final Future<MailLiveTarget?> Function({bool refresh}) target;
  final void Function(MailLiveEvent e) onEvent;
  final MailLiveConnector _connector;

  /// Đơn vị thời gian (test rút ngắn).
  static Duration unit = const Duration(seconds: 1);

  /// Máy chủ yêu cầu nối lại để nhận quyền mới (danh sách hộp thư vừa đổi).
  static const resyncCode = 4001;

  MailLiveSocket? _sock;
  StreamSubscription? _listen;
  Timer? _ping, _retry, _watchdog, _poll;
  bool _running = false, _connecting = false, _wasUp = false, _renew = false;
  int _backoff = 1;
  DateTime _lastRx = DateTime.now();

  /// Đang nối được (có tin "hello").
  bool up = false;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _poll?.cancel();
    _poll = null;
    _drop(retry: false);
  }

  /// App vừa mở lại / mạng vừa có lại: nối ngay thay vì chờ hết thời gian chờ.
  void kick() {
    if (!_running) return;
    if (_sock == null && !_connecting) {
      _retry?.cancel();
      _backoff = 1;
      _connect();
    } else if (_sock != null) {
      try {
        _sock!.send('ping');
      } catch (_) {}
    }
  }

  Future<void> _connect() async {
    if (!_running || _sock != null || _connecting) return;
    _connecting = true;
    try {
      final t = await target(refresh: _renew);
      _renew = false;
      if (t == null || !_running) return;
      final s = await _connector(t);
      if (!_running) {
        s.close();
        return;
      }
      _sock = s;
      _lastRx = DateTime.now();
      _listen = s.stream.listen(_onMessage, onDone: () => _drop(code: s.closeCode()), onError: (_) => _drop());
    } catch (e) {
      // Nối không được (mất mạng, vé hết hạn → lần sau xin vé mới).
      _renew = '$e'.contains('401');
      _drop();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(dynamic m) {
    _lastRx = DateTime.now();
    if (m is! String || m == 'pong') return;
    if (m.contains('"hello"')) {
      up = true;
      _backoff = 1;
      _poll?.cancel();
      _poll = null;
      _ping?.cancel();
      _ping = Timer.periodic(unit * 25, (_) {
        try {
          _sock?.send('ping');
        } catch (_) {}
      });
      _watchdog?.cancel();
      _watchdog = Timer.periodic(unit * 15, (_) {
        if (DateTime.now().difference(_lastRx) > unit * 70) _drop();
      });
      if (_wasUp) onEvent(const MailLiveEvent('resync'));
      _wasUp = true;
      return;
    }
    final e = MailLiveEvent.parse(m);
    if (e != null) onEvent(e);
  }

  void _drop({bool retry = true, int? code}) {
    up = false;
    _ping?.cancel();
    _watchdog?.cancel();
    _listen?.cancel();
    _listen = null;
    final s = _sock;
    _sock = null;
    try {
      s?.close();
    } catch (_) {}
    if (!retry || !_running) return;
    _retry?.cancel();
    if (code == resyncCode) {
      // Máy chủ chủ động đóng để nhận quyền mới: nối lại ngay (lệch ngẫu nhiên để không dồn cùng lúc).
      _retry = Timer(unit * (0.3 + DateTime.now().microsecond % 700 / 1000), _connect);
      return;
    }
    _retry = Timer(unit * _backoff, _connect);
    _backoff = (_backoff * 2).clamp(1, 60);
    // Kênh rớt: màn hình tự tải lại 45 giây một lần cho tới khi nối lại được.
    _poll ??= Timer.periodic(unit * 45, (_) {
      if (!up) onEvent(const MailLiveEvent('poll'));
    });
  }
}
