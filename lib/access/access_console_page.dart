import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../i18n/i18n.dart';
import 'access_api.dart';

/// Một mục quản trị của Flygo Access console, nhúng bằng webview (Sếp, 2026-11-27: quản trị làm bằng web).
/// Hợp đồng nhúng: `console/?embed=1&theme=&org=#<mục>&token=<JWT 5 phút>`; trang đổi JWT lấy cookie rồi xoá khỏi
/// địa chỉ; báo về qua kênh `FlygoHost` (`page`, `session_expired`).
class AccessConsolePage extends StatefulWidget {
  const AccessConsolePage({super.key, required this.section, this.session});

  /// Mã mục ở trong app: apps, members, departments, grants, installed, market, billing, audit.
  final String section;
  final FlygoSession? session;

  /// Mã mục của console.
  static const sections = {
    'apps': 'apps',
    'members': 'members',
    'departments': 'depts',
    'grants': 'perms',
    'installed': 'installed',
    'market': 'store',
    'billing': 'cost',
    'audit': 'audit',
  };

  static String title(String section) => switch (section) {
    'apps' => tr('App của tôi'),
    'members' => tr('Người dùng'),
    'departments' => tr('Tổ chức'),
    'grants' => tr('Phân quyền'),
    'installed' => tr('App đã cài'),
    'market' => tr('Chợ app'),
    'billing' => tr('Thanh toán'),
    'audit' => tr('Nhật ký'),
    _ => tr('Quản trị'),
  };

  @override
  State<AccessConsolePage> createState() => _AccessConsolePageState();
}

class _AccessConsolePageState extends State<AccessConsolePage> {
  late final FlygoSession _s = widget.session ?? FlygoSession.instance;
  WebViewController? _web;
  String? _error;
  bool _loading = true;
  int _renews = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_web == null) _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (!await _s.restore()) throw AccessException(401, 'login_required');
      final jwt = await _s.token();
      if (!mounted) return;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final page = AccessConsolePage.sections[widget.section] ?? 'apps';
      final url = Uri.parse('$kAccessUrl/console/').replace(
        queryParameters: {'embed': '1', 'theme': dark ? 'dark' : 'light'},
        fragment: '$page&token=$jwt',
      );
      final web = _web ??= WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel('FlygoHost', onMessageReceived: (m) => _onHost(m.message))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            // Liên kết ra ngoài console và nút Mở app (/open/<tổ chức>/<app>): mở trình duyệt hệ thống.
            onNavigationRequest: (r) {
              final u = Uri.tryParse(r.url);
              if (u == null || u.scheme == 'about' || (u.origin == Uri.parse(kAccessUrl).origin && !u.path.startsWith('/open/'))) {
                return NavigationDecision.navigate;
              }
              launchUrl(u, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            },
          ),
        );
      await web.loadRequest(url);
      if (mounted) setState(() {});
    } on AccessException catch (e) {
      if (mounted) setState(() => _error = e.needLogin ? tr('Phiên Flygo ID đã hết. Đăng xuất rồi đăng nhập lại Flygo ID.') : (e.message ?? e.code));
    } catch (e) {
      if (mounted) setState(() => _error = tr('Không mở được trang quản trị. Kiểm tra mạng và thử lại.'));
    }
  }

  void _onHost(String raw) {
    Map m;
    try {
      m = jsonDecode(raw) as Map;
    } catch (_) {
      return;
    }
    if (m['source'] != 'flygo-access') return;
    switch (m['type']) {
      case 'page':
        _renews = 0;
        if (mounted) setState(() => _loading = false);
      case 'session_expired':
        // Lấy JWT mới, mở lại; không hỏi người dùng. Hỏng liên tục thì dừng để khỏi lặp.
        if (_renews++ < 2) _open();
        else if (mounted) setState(() => _error = tr('Không đăng nhập được trang quản trị.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AccessConsolePage.title(widget.section))),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () {
                      _renews = 0;
                      _open();
                    }, child: Text(tr('Thử lại'))),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                if (_web != null) WebViewWidget(controller: _web!),
                if (_loading) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
