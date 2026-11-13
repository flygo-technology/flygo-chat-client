// Trang quản trị Ký số (web UI của máy chủ ký số) mở trong app bằng phiên quản trị đổi từ vé Flygo ID.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Đổi vé quản trị Flygo ID lấy phiên quản trị ở máy chủ ký số [origin] (POST /api/session/flygo).
Future<String> adminSession(String origin, String ticket) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(Uri.parse('$origin/api/session/flygo'));
    req.followRedirects = false;
    req.headers.set('authorization', 'Bearer $ticket');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'device_name': 'Flygo Chat (quản trị)'}));
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await res.transform(utf8.decoder).join();
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {}
    if (res.statusCode != 200 || j['access_token'] is! String) {
      throw '${j['error'] ?? 'máy chủ ký số trả lỗi ${res.statusCode}'}';
    }
    return j['access_token'] as String;
  } finally {
    client.close();
  }
}

/// Web quản trị của máy chủ ký số trong WebView của app (phiên trao qua `#token=`, web UI tự giữ theo tab).
class KysoAdminPage extends StatelessWidget {
  const KysoAdminPage({super.key, required this.url, required this.title});
  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final origin = Uri.parse(url).origin;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, isInspectable: true, incognito: true),
        // Chỉ trang của máy chủ ký số; link ra ngoài không mở trong cửa sổ quản trị.
        shouldOverrideUrlLoading: (_, action) async {
          final next = action.request.url;
          if (next == null || next.origin == origin || next.scheme == 'about') return NavigationActionPolicy.ALLOW;
          return NavigationActionPolicy.CANCEL;
        },
      ),
    );
  }
}
