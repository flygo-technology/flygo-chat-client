import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../api/mini_apps.dart';
import '../../../api/show_api.dart';
import '../../../i18n/i18n.dart';
import '../../../state/app_state.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
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
    // App (mockup bảng 07): người xem thả cảm xúc theo slide, xem lại tên các slide đã qua; người trình chiếu xem ghi chú
    // người nói + slide kế, lật slide, che màn đen.
    panel: (context, ctx) => ShowPanel(ctx),
    controls: (context, ctx) => ShowControls(ctx),
    stageThemed: true,
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
      if (control && widget.ctx.onStage && AppScope.maybeOf(context) == null)
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

// ------------------------------------------------------------------ App Show
// view (relay): slide, total, title, counts {hay, ro, chua}, mine, seen [{slide, title}].

const _kinds = [('hay', 'Hay'), ('ro', 'Rõ'), ('chua', 'Chưa hiểu')];

/// Người xem: slide đang chiếu, ba nút cảm xúc (bấm lại để bỏ), các slide đã qua (xem lại tên, không đổi của phòng).
class ShowPanel extends StatefulWidget {
  final PageCtx ctx;
  const ShowPanel(this.ctx, {super.key});
  @override
  State<ShowPanel> createState() => _ShowPanelState();
}

class _ShowPanelState extends State<ShowPanel> {
  int? _look; // slide đang xem lại (chỉ máy này)
  PageCtx get ctx => widget.ctx;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    final v = ctx.view;
    final slide = (v['slide'] as num?)?.toInt() ?? 0;
    final total = (v['total'] as num?)?.toInt() ?? 0;
    final counts = (v['counts'] as Map?) ?? const {};
    final mine = '${v['mine'] ?? ''}';
    final seen = [for (final x in (v['seen'] as List? ?? const [])) if (x is Map) x];
    if (slide == 0) {
      return AppCard(child: AppEmpty(icon: Icons.slideshow_outlined, title: tr('Chưa bắt đầu chiếu'), sub: tr('Khi người trình chiếu bắt đầu, bạn thả cảm xúc cho từng slide ở đây')));
    }
    final look = _look == null ? null : seen.where((x) => (x['slide'] as num?)?.toInt() == _look).firstOrNull;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(total > 0 ? tr('Slide {0} / {1}', [slide, total]) : tr('Slide {0}', [slide])),
        if ('${v['title'] ?? ''}'.isNotEmpty) Text('${v['title']}', style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(tr('Cảm xúc với slide này'), style: TextStyle(color: t.sub, fontSize: 12.5)),
        const SizedBox(height: 6),
        Row(children: [
          for (final (i, (k, label)) in _kinds.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                tr(label),
                key: ValueKey('show-react-$k'),
                kind: mine == k ? (k == 'chua' ? AppButtonKind.warn : AppButtonKind.primary) : AppButtonKind.tonal,
                onPressed: () => ctx.act('react', {'kind': mine == k ? '' : k}),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Text(tr('{0} hay · {1} rõ · {2} chưa hiểu', [counts['hay'] ?? 0, counts['ro'] ?? 0, counts['chua'] ?? 0]), key: const ValueKey('show-counts'), style: TextStyle(color: t.sub, fontSize: 12.5)),
        if (seen.length > 1) ...[
          const SizedBox(height: 12),
          Text(tr('Đã qua · bấm để xem lại'), style: TextStyle(color: t.sub, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in seen)
              AppChip(
                '${x['slide']}',
                key: ValueKey('show-seen-${x['slide']}'),
                selected: (x['slide'] as num?)?.toInt() == (_look ?? slide),
                onTap: () => setState(() => _look = (x['slide'] as num?)?.toInt() == _look ? null : (x['slide'] as num?)?.toInt()),
              ),
          ]),
          if (look != null) ...[
            const SizedBox(height: 8),
            Text(tr('Slide {0}: {1}', [look['slide'], '${look['title'] ?? ''}'.isEmpty ? tr('(không tên)') : look['title']]), style: TextStyle(color: t.text, fontSize: 14)),
          ],
        ],
      ]),
    );
  }
}

/// Người trình chiếu: ghi chú người nói và slide kế (chỉ mình thấy), lật slide, che màn đen, số cảm xúc ("Chưa hiểu" nổi bật).
/// Đọc trạng thái buổi chiếu từ app Show mỗi vài giây và báo slide đang chiếu cho trang (người xem thả cảm xúc theo slide).
class ShowControls extends StatefulWidget {
  final PageCtx ctx;
  const ShowControls(this.ctx, {super.key});
  @override
  State<ShowControls> createState() => _ShowControlsState();
}

class _ShowControlsState extends State<ShowControls> {
  Timer? _poll;
  Map<String, dynamic> _st = const {};
  bool _blank = false;
  PageCtx get ctx => widget.ctx;
  String get _pid => '${ctx.page.content['pid'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _status());
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _status() async {
    if (!mounted || _pid.isEmpty) return;
    try {
      final cl = await _show(context);
      if (cl == null) return;
      final st = await cl.call('show_status', {'presentation_id': _pid});
      if (!mounted) return;
      final old = (ctx.view['slide'] as num?)?.toInt() ?? 0;
      final slide = (st['slide'] as num?)?.toInt() ?? 0;
      setState(() => _st = st);
      if (slide != old && slide > 0) {
        await ctx.act('sync', {'slide': slide, 'total': (st['total'] as num?)?.toInt() ?? _pages(st).length, 'title': _titleOf(st, slide)});
      }
    } catch (_) {}
  }

  List<Map> _pages(Map st) => [for (final p in (st['pages'] as List? ?? const [])) if (p is Map && '${p['scene'] ?? 'slide'}' == 'slide') p];
  String _titleOf(Map st, int n) => '${_pages(st).where((p) => (p['slide'] as num?)?.toInt() == n).firstOrNull?['title'] ?? (n == ((st['slide'] as num?)?.toInt() ?? 0) ? st['slide_title'] ?? '' : '')}';

  Future<void> _go(String tool) async {
    try {
      final cl = await _show(context);
      await cl?.call(tool, {'presentation_id': _pid});
      await _status();
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  /// Tắt hình mọi màn hình đã ghép của buổi chiếu (màn đen), bấm lại để hiện.
  Future<void> _blankAll() async {
    try {
      final cl = await _show(context);
      if (cl == null) return;
      final r = await cl.call('screen_list', {'presentation_id': _pid});
      final screens = [for (final x in (r['screens'] as List? ?? const [])) if (x is Map) x];
      final blank = !_blank;
      for (final x in screens) {
        await cl.call('screen_set', {'presentation_id': _pid, 'screen_id': x['screen_id'], 'blanked': blank});
      }
      if (mounted) setState(() => _blank = blank);
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final v = ctx.view;
    final counts = (v['counts'] as Map?) ?? const {};
    if (_pid.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Điều khiển')),
        Text(tr('Lên sân khấu để mở buổi chiếu của "{0}"', ['${ctx.page.content['deck_title'] ?? ctx.page.title}']), style: TextStyle(color: t.sub, fontSize: 13.5)),
        const SizedBox(height: 10),
        AppButton(tr('Trình chiếu'), key: const ValueKey('show-stage'), kind: AppButtonKind.primary, icon: Icons.play_arrow_rounded, onPressed: () async {
          final e = await ctx.call.stageAct('show', {'page': ctx.page.id});
          if (e != null && context.mounted) meetToast(context, e);
        }),
      ]);
    }
    final slide = (_st['slide'] as num?)?.toInt() ?? (v['slide'] as num?)?.toInt() ?? 0;
    final next = _titleOf(_st, slide + 1);
    final notes = '${_st['notes'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Ghi chú người nói')),
      Text(notes.isEmpty ? tr('Slide này không có ghi chú') : notes, key: const ValueKey('show-notes'), style: TextStyle(color: notes.isEmpty ? t.sub : t.text, fontSize: 14.5, height: 1.45)),
      if (next.isNotEmpty) ...[
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.all(10),
          color: t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1F232B),
          child: Row(children: [
            Icon(Icons.skip_next_rounded, color: t.sub),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('Slide kế: {0}', [next]), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 13.5))),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, label) in _kinds) AppChip('${tr(label)} ${counts[k] ?? 0}', color: k == 'chua' ? const Color(0xFFF5B544) : null),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(width: 70, child: AppButton('‹', key: const ValueKey('show-prev'), onPressed: () => _go('show_prev'))),
        const SizedBox(width: 8),
        Expanded(child: AppButton(tr('Slide kế ›'), key: const ValueKey('show-next'), kind: AppButtonKind.primary, onPressed: () => _go('show_next'))),
      ]),
      const SizedBox(height: 8),
      AppButton(_blank ? tr('Hiện lại màn hình') : tr('Che màn đen'), key: const ValueKey('show-blank'), icon: _blank ? Icons.visibility_outlined : Icons.visibility_off_outlined, onPressed: _blankAll),
    ]);
  }
}
