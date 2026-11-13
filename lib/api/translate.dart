import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

String get _home => Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

/// Runner trợ lý AI đang chạy trên máy này, của [myId], cùng máy chủ: tệp `~/.config/flygo-agent/local-<bot>.json`
/// ({port, key, server, owners, engine}) do runner ghi lúc chạy. Claude trước (nhanh hơn Codex).
List<Map<String, dynamic>> _localRunners(String myId) {
  final sep = Platform.pathSeparator;
  final dir = Directory('$_home$sep.config${sep}flygo-agent');
  if (!isDesktop || !dir.existsSync()) return const [];
  final out = <Map<String, dynamic>>[];
  for (final f in dir.listSync().whereType<File>().where((f) => RegExp(r'local-[^/\\]+\.json$').hasMatch(f.path))) {
    try {
      final j = (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
      if (j['server'] == kServerUrl && (j['owners'] as List? ?? const []).contains(myId)) out.add(j);
    } catch (_) {}
  }
  out.sort((a, b) => (a['engine'] == 'claude' ? 0 : 1) - (b['engine'] == 'claude' ? 0 : 1));
  return out;
}

/// Máy chủ chat có dịch vụ dịch không (`GET <trạm>/translate/info`): có thì mọi người thấy nút "Dịch AI".
Future<bool> translateInfo() async {
  try {
    final r = await http
        .get(Uri.parse('${pushUrlFor(kServerUrl)}/translate/info'), headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 10));
    return r.statusCode == 200 && (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['ok'] == true;
  } catch (_) {
    return false;
  }
}

/// Dịch [text] sang ngôn ngữ [to] (vi, en, ko, ja, th, zh…) bằng bot dịch dùng chung của máy chủ chat: trạm đẩy
/// (`POST /translate`, xác thực bằng phiên máy chủ chat; chỉ dùng trạm của chính máy chủ đang chat) chuyển cho dịch vụ dịch
/// chạy cách ly. Trạm lỗi / không gọi được thì máy tính thử runner trợ lý AI của mình trên máy này (nếu có).
/// Trả về bản dịch và mã ngôn ngữ gốc đoán được.
Future<({String text, String from})> translateText(String token, String text, String to, {String myId = ''}) async {
  Object error;
  var status = 0;
  try {
    final r = await http
        .post(Uri.parse('${pushUrlFor(kServerUrl)}/translate'),
            headers: {
              'Authorization': 'Bearer $token',
              'X-MM-Server': kServerUrl,
              'Content-Type': 'application/json',
              'User-Agent': kUserAgent,
            },
            body: jsonEncode({'text': text, 'to': to}))
        .timeout(const Duration(seconds: 75));
    status = r.statusCode;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    if (status == 200 && '${j['text'] ?? ''}'.trim().isNotEmpty) return (text: '${j['text']}', from: '${j['from'] ?? ''}');
    error = HttpException('${j['error'] ?? 'translate $status'}');
  } catch (e) {
    error = e;
  }
  // Hết lượt / tin quá dài / sai yêu cầu: báo luôn, không chuyển sang runner.
  if (status == 429 || status == 413 || status == 400) throw error;
  for (final r in myId.isEmpty ? const <Map<String, dynamic>>[] : _localRunners(myId)) {
    try {
      final res = await http
          .post(Uri.parse('http://127.0.0.1:${r['port']}/translate'),
              headers: {'x-flygo-key': '${r['key']}', 'Content-Type': 'application/json'},
              body: jsonEncode({'text': text, 'to': to, 'user': myId}))
          .timeout(Duration(seconds: r['engine'] == 'claude' ? 35 : 70));
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      if (j['ok'] == true && '${j['text']}'.trim().isNotEmpty) return (text: '${j['text']}', from: '${j['from'] ?? ''}');
    } catch (_) {}
  }
  throw error;
}

/// Tin song ngữ (nút "Dịch AI"): props.flygo_bilingual = {v:1, langs:[gốc, dịch], texts:[bản gốc, bản dịch]}.
/// Nội dung tin (message) là bản gốc + dòng kẻ + bản dịch, để app khác vẫn đọc được cả hai.
const kBilingualRule = '───';

({List<String> langs, List<String> texts})? bilingualOf(Map<String, dynamic> props) {
  final b = props['flygo_bilingual'];
  if (b is! Map) return null;
  final langs = [for (final x in (b['langs'] as List? ?? const [])) '$x'];
  final texts = [for (final x in (b['texts'] as List? ?? const [])) '$x'];
  if (langs.length != 2 || texts.length != 2) return null;
  return (langs: langs, texts: texts);
}
