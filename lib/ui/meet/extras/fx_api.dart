import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../calls/call_service.dart';
import '../../../config.dart';

// Gọi API tính năng thêm của Họp trên relay: /meet/extras/{rooms/<mã>|channel/<id kênh>}/<tính năng>[/...].

class FxError implements Exception {
  final int status;
  final String message;
  FxError(this.status, this.message);
  @override
  String toString() => message;
}

String fxRoomUrl(String code) => '$kPushUrl/meet/extras/rooms/$code';

String? _base(CallService call) {
  final code = call.meeting ? call.meetingInfo?.code : null;
  if (code != null && code.isNotEmpty) return '$kPushUrl/meet/extras/rooms/$code';
  final ch = call.channelId;
  return ch == null ? null : '$kPushUrl/meet/extras/channel/$ch';
}

Future<Map<String, dynamic>> fxRequest(CallService call, String method, String path, [Map<String, dynamic>? body]) async {
  final base = _base(call);
  if (base == null) throw FxError(400, 'Chưa ở trong cuộc họp');
  return fxSend(method, '$base$path', call.api.token, body);
}

/// Gọi thẳng một URL của API tính năng thêm (vd. trước khi vào cuộc họp, chưa có CallService).
Future<Map<String, dynamic>> fxSend(String method, String url, String token, [Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 10)]) async {
  final req = http.Request(method, Uri.parse(url))
    ..headers.addAll({
      'Authorization': 'Bearer $token',
      'X-MM-Server': kServerUrl,
      'Content-Type': 'application/json',
      'User-Agent': kUserAgent,
    });
  if (body != null) req.body = jsonEncode(body);
  final r = await http.Response.fromStream(await req.send().timeout(timeout));
  Map<String, dynamic> j;
  try {
    j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
  } catch (_) {
    j = const {};
  }
  if (r.statusCode != 200) throw FxError(r.statusCode, (j['error'] as String?) ?? 'Lỗi ${r.statusCode}');
  return j;
}
