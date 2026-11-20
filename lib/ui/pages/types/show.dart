import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../api/mini_apps.dart';
import '../../../api/show_api.dart';
import '../../../i18n/i18n.dart';
import '../../../state/app_state.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../page_types.dart';

// Trang "Show": chiếu một bộ trình chiếu của app Show trong cuộc họp. App Show vẫn là app riêng (soạn, AI, kiosk); trang chỉ
// giữ bộ nào (deck_id) và, khi lên sân khấu, buổi chiếu (pid) cùng link màn hình ghép sẵn (screen_invite). App và TV hiện link
// đó trong khung; Show tự lật slide theo người trình chiếu (realtime của Show). Người trình chiếu bấm ‹ › ở đây.

ShowClient? _client;

/// Phiên gọi app Show (mini app có màn hình native "show"); null = công ty chưa có Show.
Future<ShowClient?> _show(BuildContext context) async {
  if (_client != null) return _client;
  final app = context.read<AppState>();
  final apps = await MiniApps.list(app.token);
  final s = apps.where((a) => a.nativeScreen == 'show').firstOrNull;
  if (s == null) return null;
  return _client = ShowClient(s, app.token);
}

void registerShowPageType() {
  registerPageType(PageTypeSpec(
    type: 'show',
    label: tr('Show'),
    desc: tr('Bộ trình chiếu từ app Show'),
    icon: Icons.slideshow_outlined,
    color: const Color(0xFFE8710A),
    create: (context, call) async {
      final c = await _show(context);
      if (c == null) {
        if (context.mounted) meetToast(context, tr('Công ty chưa có app Show'));
        return null;
      }
      final r = await c.call('deck_list', {'limit': 200});
      final decks = [for (final d in (r['decks'] as List? ?? const [])) (d as Map).cast<String, dynamic>()];
      if (!context.mounted) return null;
      final d = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: const Color(0xFF23262C),
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 560),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Text(tr('Chọn bộ trình chiếu'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              if (decks.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(tr('Bạn chưa có bộ trình chiếu nào trong Show.'), style: const TextStyle(color: Colors.white70))),
              for (final x in decks)
                ListTile(
                  leading: const Icon(Icons.slideshow_outlined, color: Color(0xFFE8710A)),
                  title: Text('${x['title'] ?? x['id']}', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(tr('{0} slide', [x['slides'] ?? x['slide_count'] ?? '?']), style: const TextStyle(color: Colors.white54)),
                  onTap: () => Navigator.pop(ctx, x),
                ),
            ]),
          ),
        ),
      );
      if (d == null) return null;
      return PageDraft(title: '${d['title'] ?? tr('Show')}', content: {'deck_id': d['id'], 'deck_title': d['title'] ?? '', 'base': c.base});
    },
    view: (context, ctx) => _ShowView(ctx, key: ValueKey('show:${ctx.page.id}')),
    thumb: (context, call, page, data) => Container(
      color: const Color(0xFF2A1C10),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.slideshow_outlined, color: Color(0xFFE8710A), size: 26),
        Text('${page.content['deck_title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    ),
  ));
}

class _ShowView extends StatefulWidget {
  final PageCtx ctx;
  const _ShowView(this.ctx, {super.key});
  @override
  State<_ShowView> createState() => _ShowViewState();
}

class _ShowViewState extends State<_ShowView> {
  WebViewController? _web;
  String _loaded = '';
  bool _starting = false;

  Map<String, dynamic> get c => widget.ctx.page.content;
  static bool get _canWeb => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  @override
  void didUpdateWidget(_ShowView old) {
    super.didUpdateWidget(old);
    _ensure();
  }

  /// Người trình chiếu đưa trang lên sân khấu: mở buổi chiếu của Show (một lần) và link màn hình ghép sẵn.
  Future<void> _ensure() async {
    if (!mounted || _starting || !widget.ctx.onStage || !widget.ctx.control || '${c['pid'] ?? ''}'.isNotEmpty) return;
    if (widget.ctx.data.role != 'owner') return;
    _starting = true;
    try {
      final cl = await _show(context);
      if (cl == null) return;
      final st = await cl.call('show_start', {'deck_id': c['deck_id']});
      final pid = '${st['presentation_id'] ?? ''}';
      final inv = await cl.call('screen_invite', {'presentation_id': pid});
      // Màn hình không người bấm (TV, sân khấu): chọn sẵn tiếng Việt, không hỏi ngôn ngữ / toàn màn hình.
      final u = '${inv['url'] ?? ''}';
      final url = u.isEmpty ? '' : '$u${u.contains('?') ? '&' : '?'}lang=vi&embed=1';
      await widget.ctx.api.patch(widget.ctx.page.id, {'content': {...c, 'pid': pid, 'invite_url': url}});
      await widget.ctx.reload();
    } catch (e) {
      if (mounted) meetToast(context, tr('Không mở được Show: {0}', [e]));
    } finally {
      _starting = false;
    }
  }

  Future<void> _go(String tool) async {
    try {
      final cl = await _show(context);
      await cl?.call(tool, {'presentation_id': c['pid']});
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = '${c['invite_url'] ?? ''}';
    if (url.isNotEmpty && _canWeb && _loaded != url) {
      _loaded = url;
      final w = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
      // macOS (WKWebView qua AppKit) chưa hỗ trợ đặt màu nền: gọi là lỗi ngay và trang không tải (trắng).
      if (!Platform.isMacOS) {
        try {
          w.setBackgroundColor(Colors.black);
        } catch (_) {}
      }
      w.loadRequest(Uri.parse(url));
      _web = w;
    }
    final control = widget.ctx.control && '${c['pid'] ?? ''}'.isNotEmpty;
    return Stack(children: [
      Positioned.fill(
        child: url.isNotEmpty && _web != null
            ? WebViewWidget(controller: _web!)
            : Container(
                color: const Color(0xFF1B1410),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.slideshow_outlined, color: Color(0xFFE8710A), size: 48),
                  const SizedBox(height: 10),
                  Text('${c['deck_title'] ?? widget.ctx.page.title}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    url.isNotEmpty ? tr('Đang chiếu trên màn hình phòng họp') : (_starting ? tr('Đang mở buổi chiếu…') : tr('Lên sân khấu để bắt đầu chiếu')),
                    style: const TextStyle(color: Colors.white60),
                  ),
                ]),
              ),
      ),
      if (control && widget.ctx.onStage)
        Positioned(
          left: 12,
          bottom: 12,
          child: Row(children: [
            IconButton.filledTonal(tooltip: tr('Slide trước'), onPressed: () => _go('show_prev'), icon: const Icon(Icons.chevron_left_rounded)),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: tr('Slide sau'), onPressed: () => _go('show_next'), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
        ),
    ]);
  }
}
