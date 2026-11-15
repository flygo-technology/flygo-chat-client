// Lịch: tạo phòng trên app Họp cho một sự kiện (chỉ khi máy chủ bật features.hop). App tự tạo phòng bằng token chat của
// người dùng (POST <push>/meet/rooms), rồi lưu {provider:"hop", code, url} vào sự kiện.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config.dart';
import 'model.dart';

Future<CConference> createHopRoom({
  required String mmToken,
  required String title,
  required int startMs,
  required int endMs,
  List<String> invitees = const [],
  String? eventId,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c
      .post(Uri.parse('$kPushUrl/meet/rooms'),
          headers: {'Authorization': 'Bearer $mmToken', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
          body: jsonEncode({
            'title': title,
            'start': startMs,
            'end': endMs,
            'invitees': invitees,
            'source': {'app': 'calendar', 'event_id': ?eventId},
          }))
      .timeout(const Duration(seconds: 20));
  Map j = const {};
  try {
    j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  } catch (_) {}
  if (res.statusCode >= 400 || j['code'] == null) throw StateError('${j['error'] ?? 'Không tạo được phòng họp (${res.statusCode})'}');
  return CConference(provider: 'hop', code: '${j['code']}', url: '${j['url'] ?? ''}');
}
