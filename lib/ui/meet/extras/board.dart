import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../calls/call_service.dart';
import '../../../config.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// Bảng trắng dùng chung (Excalidraw) của cuộc họp: relay cấp vé vẽ, trang bảng chạy trong WebView (Android / iOS / macOS),
// Windows / Linux mở bằng trình duyệt. TV tự hiện bảng ở chế độ chỉ xem khi bảng đang mở.

bool boardOpen(CallService call) => (call.roomExtras['board'] as Map?)?['on'] == true;

Future<void> openBoard(BuildContext context, CallService call) async {
  final Map<String, dynamic> j;
  try {
    j = await fxRequest(call, 'POST', '/board/open');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    return;
  }
  final url = Uri.parse('$kPushUrl${j['path']}&t=${Uri.encodeQueryComponent('${j['token']}')}');
  final inApp = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
  if (!inApp) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _BoardPage(url: url, call: call)));
}

/// Chủ trì / phó phòng đóng bảng cho mọi người.
Future<void> closeBoard(BuildContext context, CallService call) async {
  try {
    await fxRequest(call, 'POST', '/board/close');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
  }
}

class _BoardPage extends StatefulWidget {
  final Uri url;
  final CallService call;
  const _BoardPage({required this.url, required this.call});
  @override
  State<_BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<_BoardPage> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white)
    ..loadRequest(widget.url);

  @override
  void initState() {
    super.initState();
    widget.call.addListener(_changed);
  }

  @override
  void dispose() {
    widget.call.removeListener(_changed);
    super.dispose();
  }

  // Chủ trì đóng bảng / cuộc họp kết thúc: tự quay lại màn hình họp.
  void _changed() {
    if (mounted && (!boardOpen(widget.call) || widget.call.phase == CallPhase.ended || widget.call.phase == CallPhase.idle)) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(tr('Bảng trắng')),
          actions: [
            if (widget.call.canModerate)
              TextButton(
                onPressed: () async {
                  await closeBoard(context, widget.call);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
                child: Text(tr('Đóng bảng cho mọi người')),
              ),
          ],
        ),
        body: SafeArea(child: WebViewWidget(controller: _web)),
      );
}
