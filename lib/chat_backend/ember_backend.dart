import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'chat_backend.dart';

/// Ember (fork flygo-technology/flygo-chat-ember, ghim v0.5.0-beta.10) qua API web của nó.
///
/// Khác Mattermost ở ba chỗ:
/// - Phiên là cookie `session_token` (`__Host-session_token` trên HTTPS), không có Bearer token. Đăng nhập Flygo ID
///   mở [ssoStartUrl] trong WebView rồi đọc cookie đó ([EmberBackend.withSession]).
/// - Mỗi phòng một WebSocket (`/api/rooms/:id/socket`); tải lịch sử, gửi tin, sửa, xoá đều là frame trên socket đó.
///   Socket chung `/api/socket` chỉ báo chưa đọc, phòng đổi, người dùng đổi.
/// - Máy chủ chặn yêu cầu "từ trang khác": mọi yêu cầu ghi và mọi socket phải mang `Origin` = địa chỉ máy chủ.
class EmberBackend implements ChatBackend {
  /// Phiên bản giao thức phòng mà adapter này nói (ROOM_PROTOCOL trong packages/protocol).
  static const roomProtocol = 4;

  final Uri base;
  String _session;
  final http.Client _http;
  final _events = StreamController<ChatEvent>.broadcast();
  final Map<String, _RoomSocket> _rooms = {};
  final Map<String, ChatUser> _users = {};
  WebSocket? _workspace;
  ChatUser? _me;
  bool _closed = false;

  EmberBackend._(this.base, this._session, this._http);

  /// Đã có cookie phiên (đọc từ WebView sau khi đăng nhập Flygo ID, hoặc lưu từ lần trước).
  factory EmberBackend.withSession(String baseUrl, String sessionToken, {http.Client? client}) =>
      EmberBackend._(Uri.parse(baseUrl), sessionToken, client ?? http.Client());

  /// Đăng nhập bằng email + mật khẩu (tài khoản tạo sẵn trên Ember, dùng cho test và bot).
  static Future<EmberBackend> signIn(String baseUrl, String email, String password, {http.Client? client}) async {
    final b = EmberBackend._(Uri.parse(baseUrl), '', client ?? http.Client());
    final res = await b._request('POST', '/api/session', {'emailAddress': email, 'password': password});
    final token = _sessionFromSetCookie(res.headers['set-cookie']);
    if (token == null) throw const ChatBackendException(500, 'máy chủ không trả cookie phiên');
    b._session = token;
    return b;
  }

  /// Trang bắt đầu đăng nhập Flygo ID (OIDC) của Ember: mở trong WebView, chờ về tới [base], rồi đọc cookie
  /// [sessionCookieName] của [base] làm phiên.
  Uri get ssoStartUrl => base.replace(path: '/auth/sso');
  String get sessionCookieName => base.scheme == 'https' ? '__Host-session_token' : 'session_token';
  String get sessionToken => _session;

  @override
  String get kind => 'ember';

  @override
  ChatUser get me => _me ?? (throw StateError('chưa connect()'));

  Map<String, String> get _headers => {
        'Cookie': '$sessionCookieName=$_session',
        'Origin': base.origin,
        // Trên HTTPS máy chủ coi yêu cầu không có Sec-Fetch-Site là từ trang khác.
        'Sec-Fetch-Site': 'same-origin',
        'Accept': 'application/json',
      };

  Future<http.Response> _request(String method, String path, [Object? body]) async {
    final req = http.Request(method, base.replace(path: path))..headers.addAll(_headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    if (res.statusCode >= 400) {
      var msg = res.body;
      try {
        msg = (jsonDecode(res.body) as Map)['error'] as String? ?? msg;
      } catch (_) {}
      throw ChatBackendException(res.statusCode, msg);
    }
    return res;
  }

  Future<dynamic> _json(String method, String path, [Object? body]) async {
    final res = await _request(method, path, body);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  static String? _sessionFromSetCookie(String? header) =>
      header == null ? null : RegExp(r'(?:__Host-)?session_token=([\w-]{43})').firstMatch(header)?.group(1);

  @override
  Future<void> connect() async {
    final j = await _json('GET', '/api/me') as Map;
    _me = _user((j['user'] ?? j) as Map);
    await _connectWorkspace();
  }

  Future<void> _connectWorkspace() async {
    if (_closed) return;
    try {
      final ws = await _socket('/api/socket', {'visible': '1'});
      _workspace = ws;
      _events.add(const ConnectionChanged(true));
      ws.listen((data) => _onWorkspaceFrame(jsonDecode(data as String) as Map), onDone: _workspaceDown, onError: (_) => _workspaceDown());
    } catch (_) {
      _workspaceDown();
    }
  }

  void _workspaceDown() {
    _workspace = null;
    if (_closed) return;
    _events.add(const ConnectionChanged(false));
    Timer(Duration(seconds: 2 + Random().nextInt(5)), _connectWorkspace);
  }

  void _onWorkspaceFrame(Map f) {
    switch (f['type']) {
      case 'room.unread':
        _events.add(ChannelUnread(f['roomId'] as String, true, (f['count'] as num?)?.toInt()));
      case 'room.read':
        _events.add(ChannelUnread(f['roomId'] as String, false));
      case 'room.saved' || 'room.gone' || 'rooms.reordered':
        _events.add(const ChannelsChanged());
      case 'user.updated':
        final u = _user(f['user'] as Map);
        _users[u.id] = u;
    }
  }

  Future<WebSocket> _socket(String path, Map<String, String> query) => WebSocket.connect(
        base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: path, queryParameters: query).toString(),
        headers: {'Cookie': '$sessionCookieName=$_session', 'Origin': base.origin},
      ).timeout(const Duration(seconds: 20));

  @override
  Future<void> close() async {
    _closed = true;
    await _workspace?.close();
    for (final r in _rooms.values) {
      await r.close();
    }
    _rooms.clear();
    await _events.close();
  }

  @override
  Future<List<ChatChannel>> channels() async {
    final j = await _json('GET', '/api/sidebar') as Map;
    return [
      for (final r in (j['rooms'] as List).cast<Map>())
        ChatChannel(
          id: r['id'] as String,
          name: _roomName(r),
          kind: switch (r['kind']) {
            'open' => ChatChannelKind.open,
            'closed' => ChatChannelKind.private,
            _ => ((r['members'] as List?)?.length ?? 2) > 2 ? ChatChannelKind.group : ChatChannelKind.direct,
          },
          unread: r['unread'] == true,
          unreadCount: (r['unreadCount'] as num?)?.toInt() ?? 0,
          raw: r,
        ),
    ];
  }

  String _roomName(Map r) {
    if (r['name'] is String && (r['name'] as String).isNotEmpty) return r['name'] as String;
    final others = ((r['members'] as List?) ?? const []).cast<Map>().where((u) => u['id'] != _me?.id).map((u) => u['name']);
    return others.isEmpty ? (_me?.name ?? '') : others.join(', ');
  }

  ChatUser _user(Map u) => ChatUser(
        id: u['id'] as String,
        name: u['name'] as String? ?? '',
        email: u['emailAddress'] as String?,
        isBot: u['role'] == 'bot',
        raw: u,
      );

  ChatMessage _message(Map m) {
    final author = _user(m['creator'] as Map);
    _users.putIfAbsent(author.id, () => author);
    return ChatMessage(
      id: m['id'] as String,
      channelId: m['roomId'] as String,
      author: author,
      text: m['plainText'] as String? ?? '',
      rootId: m['parentId'] as String?,
      createdAt: DateTime.parse(m['createdAt'] as String),
      editedAt: m['editedAt'] == null ? null : DateTime.parse(m['editedAt'] as String),
      clientId: m['clientMessageId'] as String?,
      raw: m,
    );
  }

  Future<_RoomSocket> _room(String id) async {
    final cur = _rooms[id];
    if (cur != null && !cur.isClosed) return cur;
    final r = _RoomSocket(id, this);
    _rooms[id] = r;
    await r.open();
    return r;
  }

  @override
  Future<void> watch(String channelId) => _room(channelId);

  @override
  Future<void> unwatch(String channelId) async => _rooms.remove(channelId)?.close();

  @override
  Future<ChatPage> messages(String channelId, {String? before, int limit = 50}) async {
    final r = await _room(channelId);
    if (before == null) return r.welcomePage!;
    final f = await r.ask({'type': 'history.before', 'before': before, 'limit': limit}, (f) => f['type'] == 'history' && f['before'] == before);
    return ChatPage([for (final m in (f['messages'] as List).cast<Map>()) _message(m)], f['hasMore'] == true);
  }

  @override
  Future<ChatMessage> send(String channelId, String text, {String? rootId}) async {
    final r = await _room(channelId);
    final cid = _uuid();
    final f = await r.ask(
      {'type': 'message.create', 'clientMessageId': cid, 'body': _bodyOf(text), 'parentId': ?rootId},
      (f) => f['type'] == 'message.created' && (f['message'] as Map)['clientMessageId'] == cid,
      failsOn: (f) => f['type'] == 'error' && f['clientMessageId'] == cid,
    );
    return _message(f['message'] as Map);
  }

  /// Ember giữ tin dạng Action Text (HTML); app gửi chữ thuần nên bọc thành một đoạn, mỗi dòng một `<br>`.
  static String _bodyOf(String text) =>
      '<div>${const HtmlEscape(HtmlEscapeMode.element).convert(text).replaceAll('\n', '<br>')}</div>';

  @override
  Future<void> markRead(String channelId) async {
    // Phòng tính là đã đọc khi có socket đang hiện nó (visible=1); báo hiện lại để chắc chắn.
    final r = await _room(channelId);
    r.sendFrame({'type': 'presence.visible', 'visible': true});
  }

  @override
  Stream<ChatEvent> get events => _events.stream;

  static String _uuid() {
    final r = Random.secure(), b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Socket của một phòng: nhận welcome, chuyển sự kiện ra [EmberBackend.events], trả lời các yêu cầu [ask].
class _RoomSocket {
  final String id;
  final EmberBackend b;
  WebSocket? _ws;
  ChatPage? welcomePage;
  int _seq = 0;
  bool isClosed = false;
  Timer? _ping;
  final List<_Waiter> _waiters = [];

  _RoomSocket(this.id, this.b);

  Future<void> open() async {
    final welcomed = Completer<void>();
    final ws = await b._socket('/api/rooms/$id/socket', {
      'visible': '1',
      'protocol': '${EmberBackend.roomProtocol}',
      if (_seq > 0) 'since': '$_seq',
    });
    _ws = ws;
    _ping = Timer.periodic(const Duration(seconds: 30), (_) => sendFrame({'type': 'ping'}));
    ws.listen((data) {
      final f = (jsonDecode(data as String) as Map).cast<String, dynamic>();
      _onFrame(f);
      if ((f['type'] == 'welcome' || f['type'] == 'resumed') && !welcomed.isCompleted) welcomed.complete();
    }, onDone: () => _down(welcomed), onError: (_) => _down(welcomed));
    await welcomed.future.timeout(const Duration(seconds: 20));
  }

  void _down(Completer<void> welcomed) {
    _ping?.cancel();
    if (!welcomed.isCompleted) welcomed.completeError(ChatBackendException(_ws?.closeCode ?? 0, 'phòng $id đóng kết nối'));
    for (final w in _waiters) {
      w.done.completeError(const ChatBackendException(0, 'mất kết nối'));
    }
    _waiters.clear();
    if (isClosed || b._closed) return;
    // Kết nối lại với since = seq cuối để chỉ nhận phần đổi (frame resumed).
    Timer(Duration(seconds: 1 + Random().nextInt(4)), () => open().catchError((_) {}));
  }

  void _onFrame(Map<String, dynamic> f) {
    final seq = (f['seq'] as num?)?.toInt();
    if (seq != null && seq > _seq) _seq = seq;
    switch (f['type']) {
      case 'welcome' || 'history.around':
        welcomePage = ChatPage([for (final m in (f['messages'] as List).cast<Map>()) b._message(m)], f['hasMore'] == true);
      case 'resumed':
        for (final m in (f['messages'] as List).cast<Map>()) {
          b._events.add(MessageUpdated(b._message(m)));
        }
        for (final d in (f['deletedIds'] as List).cast<String>()) {
          b._events.add(MessageDeleted(id, d));
        }
      case 'message.created':
        b._events.add(MessageCreated(b._message(f['message'] as Map)));
      case 'message.updated':
        b._events.add(MessageUpdated(b._message(f['message'] as Map)));
      case 'message.deleted':
        b._events.add(MessageDeleted(id, f['messageId'] as String));
      case 'typing':
        b._events.add(Typing(id, (f['user'] as Map)['id'] as String, f['typing'] == true));
    }
    for (final w in List.of(_waiters)) {
      if (w.matches(f)) {
        _waiters.remove(w);
        w.done.complete(f);
      } else if (w.failsOn?.call(f) == true) {
        _waiters.remove(w);
        w.done.completeError(ChatBackendException(422, f['message'] as String? ?? 'lỗi'));
      }
    }
  }

  void sendFrame(Map<String, Object?> f) {
    try {
      _ws?.add(jsonEncode(f));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> ask(Map<String, Object?> frame, bool Function(Map<String, dynamic>) matches,
      {bool Function(Map<String, dynamic>)? failsOn}) {
    final w = _Waiter(matches, failsOn);
    _waiters.add(w);
    sendFrame(frame);
    return w.done.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _waiters.remove(w);
      throw const ChatBackendException(408, 'máy chủ không trả lời');
    });
  }

  Future<void> close() async {
    isClosed = true;
    _ping?.cancel();
    await _ws?.close();
  }
}

class _Waiter {
  final bool Function(Map<String, dynamic>) matches;
  final bool Function(Map<String, dynamic>)? failsOn;
  final done = Completer<Map<String, dynamic>>();
  _Waiter(this.matches, this.failsOn);
}
