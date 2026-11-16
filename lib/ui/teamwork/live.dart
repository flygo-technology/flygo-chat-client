// TeamWork: kết nối WebSocket nhận sự kiện realtime ({t:'ev', type, project_id, task_id…}). Tự nối lại khi rớt mạng
// (chờ tăng dần tới 30 giây), đăng ký lại các dự án đang mở sau mỗi lần nối.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';

class TwLive {
  TwLive(this.api, {required this.onEvent, this.onState});
  final TwApi api;
  final void Function(Map ev) onEvent;
  /// true khi vừa nối được, false khi rớt.
  final void Function(bool up)? onState;

  WebSocket? _ws;
  Timer? _retry, _ping;
  int _backoff = 1;
  bool _closed = false;
  List<String> _subs = [];

  void connect() async {
    if (_closed) return;
    try {
      final ws = await WebSocket.connect('${await api.wsUri()}').timeout(const Duration(seconds: 20));
      if (_closed) {
        await ws.close();
        return;
      }
      _ws = ws;
      _backoff = 1;
      onState?.call(true);
      _send({'t': 'sub', 'projects': _subs});
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'t': 'ping'}));
      ws.listen((data) {
        try {
          final m = jsonDecode('$data');
          if (m is Map && m['t'] == 'ev') onEvent(m);
        } catch (_) {}
      }, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
    } catch (e) {
      debugPrint('[teamwork] WebSocket chưa nối được: $e');
      _lost();
    }
  }

  void _lost() {
    _ping?.cancel();
    _ws = null;
    if (_closed) return;
    onState?.call(false);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), connect);
    _backoff = (_backoff * 2).clamp(1, 30);
  }

  void _send(Map m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  /// Đăng ký nhận sự kiện của các dự án [ids] (thay danh sách cũ).
  void subscribe(List<String> ids) {
    _subs = ids;
    _send({'t': 'sub', 'projects': ids});
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    _ws?.close();
  }
}
