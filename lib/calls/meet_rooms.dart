// Phòng họp có mã của app "Họp" (trạm push của máy chủ chat, /meet/rooms — relay/rooms.mjs): mỗi phòng là một kênh riêng
// `hop-<mã>` + thẻ cuộc họp trong đó. Mã kiểu abc-defg-hij; link mời <máy chủ chat>/__apps/hop/<mã>.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Mã phòng từ chữ người dùng nhập: mã trần, có / không gạch, hoặc link `…/hop/<mã>`. Null = không phải mã.
String? parseMeetCode(String input) {
  final s = input.trim().toLowerCase();
  final m = RegExp(r'(?:^|/hop/)([a-z]{3})-?([a-z]{4})-?([a-z]{3})(?:[/?#]|$)').firstMatch(s);
  return m == null ? null : '${m[1]}-${m[2]}-${m[3]}';
}

/// Link mời của một mã trên máy chủ hiện tại.
String meetLink(String code) => '$kServerUrl/__apps/hop/$code';

enum MeetRoomStatus { scheduled, open, live, ended, cancelled }

class MeetRoomInfo {
  final String code, url, channelId, title, creator, access;
  final DateTime? start, end;
  final bool allowEarly, ownChannel;
  final MeetRoomStatus status;
  final int participants;
  final bool? member;
  final List<String> invitees;
  /// App đã tạo phòng (vd Lịch: `calendar` / `vn.flygo.calendar`) và id sự kiện bên đó (có thể trống).
  final String sourceApp, sourceEventId;
  const MeetRoomInfo({
    required this.code,
    required this.url,
    required this.channelId,
    required this.title,
    required this.creator,
    required this.access,
    this.start,
    this.end,
    this.allowEarly = true,
    this.ownChannel = true,
    this.status = MeetRoomStatus.open,
    this.participants = 0,
    this.member,
    this.invitees = const [],
    this.sourceApp = '',
    this.sourceEventId = '',
  });

  factory MeetRoomInfo.fromJson(Map<String, dynamic> j) {
    DateTime? at(Object? v) => (v is num && v > 0) ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return MeetRoomInfo(
      code: '${j['code'] ?? ''}',
      url: '${j['url'] ?? ''}',
      channelId: '${j['channel_id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      creator: '${j['creator'] ?? ''}',
      access: '${j['access'] ?? 'company'}',
      start: at(j['start']),
      end: at(j['end']),
      allowEarly: j['allow_early'] != false,
      ownChannel: j['own_channel'] != false,
      status: MeetRoomStatus.values.asNameMap()['${j['status']}'] ?? MeetRoomStatus.open,
      participants: (j['participants'] as num?)?.toInt() ?? 0,
      member: j['member'] as bool?,
      invitees: [for (final x in (j['invitees'] as List? ?? const [])) '$x'],
      sourceApp: '${(j['source'] as Map?)?['app'] ?? ''}',
      sourceEventId: '${(j['source'] as Map?)?['event_id'] ?? ''}',
    );
  }

  bool get live => status == MeetRoomStatus.live;
  /// Cuộc họp gắn với một sự kiện trong Lịch: đổi giờ / huỷ đi qua Lịch để hai bên khớp nhau.
  bool get fromCalendar => sourceApp.contains('calendar');
  bool get finished => status == MeetRoomStatus.ended || status == MeetRoomStatus.cancelled;

  /// Chưa tới giờ và không cho vào sớm.
  bool get locked => status == MeetRoomStatus.scheduled;
}

/// Kết quả xin vào phòng.
enum MeetJoinResult { member, admitted, denied, timeout }

class MeetRoomsException implements Exception {
  final int status;
  final String message;
  const MeetRoomsException(this.status, this.message);

  /// Máy chủ chưa có app Họp (relay cũ).
  bool get unsupported => status == 404 && message == 'not found';
  @override
  String toString() => message;
}

class MeetRoomsApi {
  final String token;
  final http.Client? client;
  MeetRoomsApi(this.token, {this.client});

  Map<String, String> get _h => {
    'Authorization': 'Bearer $token',
    'X-MM-Server': kServerUrl,
    'Content-Type': 'application/json',
    'User-Agent': kUserAgent,
  };

  Future<Map<String, dynamic>> _call(String method, String path, [Map<String, dynamic>? body, Duration? timeout]) async {
    final req = http.Request(method, Uri.parse('$kPushUrl$path'))..headers.addAll(_h);
    if (body != null) req.body = jsonEncode(body);
    final c = client ?? http.Client();
    try {
      final r = await http.Response.fromStream(await c.send(req).timeout(timeout ?? const Duration(seconds: 20)));
      Object? j;
      try {
        j = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      if (r.statusCode != 200) {
        throw MeetRoomsException(r.statusCode, j is Map ? '${j['error'] ?? 'HTTP ${r.statusCode}'}' : 'HTTP ${r.statusCode}');
      }
      return (j as Map).cast<String, dynamic>();
    } finally {
      if (client == null) c.close();
    }
  }

  /// Tạo phòng. [channelId]: họp trong một nhóm chat có sẵn (không tạo kênh riêng).
  Future<MeetRoomInfo> create({
    required String title,
    DateTime? start,
    DateTime? end,
    List<String> invitees = const [],
    String? access,
    bool allowEarly = true,
    String? channelId,
    String? teamId,
  }) async => MeetRoomInfo.fromJson(
    await _call('POST', '/meet/rooms', {
      'title': title,
      if (start != null) 'start': start.millisecondsSinceEpoch,
      if (end != null) 'end': end.millisecondsSinceEpoch,
      if (invitees.isNotEmpty) 'invitees': invitees,
      'access': ?access,
      'allow_early': allowEarly,
      'channel_id': ?channelId,
      'team_id': ?teamId,
    }),
  );

  Future<List<MeetRoomInfo>> mine() async {
    final j = await _call('GET', '/meet/rooms/mine');
    return [for (final r in (j['rooms'] as List? ?? const [])) MeetRoomInfo.fromJson((r as Map).cast())];
  }

  Future<MeetRoomInfo> get(String code) async => MeetRoomInfo.fromJson(await _call('GET', '/meet/rooms/$code'));

  /// Vào phòng (chưa ở kênh thì máy chủ thêm vào, phòng chỉ dành cho người được mời thì chờ chủ phòng cho vào).
  Future<(MeetJoinResult, String?)> join(String code) async {
    final j = await _call('POST', '/meet/rooms/$code/join', null, const Duration(seconds: 100));
    final st = MeetJoinResult.values.asNameMap()['${j['status']}'] ?? MeetJoinResult.denied;
    return (st, j['channel_id'] as String?);
  }

  Future<void> admit(String code, String req, bool allow) => _call('POST', '/meet/rooms/$code/admit', {'req': req, 'allow': allow});

  /// Huỷ cuộc họp: máy chủ báo trong nhóm của cuộc họp và ngắt người đang họp.
  Future<void> cancel(String code) => _call('DELETE', '/meet/rooms/$code');

  /// Sửa cuộc họp (người tạo / quản trị). Đổi giờ thì máy chủ báo trong nhóm của cuộc họp.
  Future<MeetRoomInfo> update(String code, {String? title, DateTime? start, DateTime? end, List<String>? invitees, String? access}) async =>
      MeetRoomInfo.fromJson(await _call('PATCH', '/meet/rooms/$code', {
        'title': ?title,
        if (start != null) 'start': start.millisecondsSinceEpoch,
        if (end != null) 'end': end.millisecondsSinceEpoch,
        'invitees': ?invitees,
        'access': ?access,
      }));

  /// Xoá khỏi danh sách của mình (lịch sử).
  Future<void> hide(String code) => _call('POST', '/meet/rooms/$code/hide');
}
