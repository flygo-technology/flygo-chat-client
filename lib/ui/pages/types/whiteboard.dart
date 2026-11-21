import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config.dart';
import '../../../i18n/i18n.dart';
import '../../meet/extras/board.dart' show configureBoardWeb;
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';

// Loại trang "Bảng trắng" (máy chủ: relay/meet-pt-whiteboard.mjs + meet-fx-board.mjs; mockup "mỗi trang là một app" 21/11/2026).
// Mỗi trang một bảng Excalidraw riêng chạy trong WebView (trang bảng của relay). Sân khấu: bảng chỉ xem, đi theo người trình bày.
// Phần người xem: bảng vẽ được (theo chế độ của chủ trang). Chủ trang: ai được vẽ, đi theo người trình bày, lưu ảnh, xoá bảng.

const _color = Color(0xFF0B8043);

/// WebView của bảng đang mở ở phần người xem, theo id trang (nút "Lưu ảnh" của chủ trang gọi vào).
final _boards = <String, WebViewController>{};

bool get _inAppWeb => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) && WebViewPlatform.instance != null;

void registerWhiteboardPageType() {
  registerPageType(PageTypeSpec(
    type: 'whiteboard',
    label: tr('Bảng trắng'),
    desc: tr('Vẽ cùng nhau, đi theo người trình bày'),
    icon: Icons.draw_outlined,
    color: _color,
    create: (context, call) async => PageDraft(title: tr('Bảng trắng'), init: const {'mode': 'all', 'follow': true}),
    view: (context, ctx) => WhiteboardView(ctx, interactive: false),
    stageThemed: true,
    stageBleed: false,
    panel: (context, ctx) => WhiteboardPanel(ctx),
    controls: (context, ctx) => WhiteboardControls(ctx),
  ));
}

Uri _url(Map<String, dynamic> v, {required bool viewOnly}) =>
    Uri.parse('$kPushUrl${v['path']}${viewOnly ? '&view=1' : ''}&t=${Uri.encodeQueryComponent('${v['token'] ?? ''}')}');

/// Bảng trong WebView. [interactive] = false: chỉ xem (sân khấu). Tải lại khi được vẽ trở lại (vé mới) hoặc đổi bảng.
class WhiteboardView extends StatefulWidget {
  final PageCtx ctx;
  final bool interactive;
  const WhiteboardView(this.ctx, {super.key, required this.interactive});
  @override
  State<WhiteboardView> createState() => _WhiteboardViewState();
}

class _WhiteboardViewState extends State<WhiteboardView> {
  WebViewController? _web;
  String _loaded = '';

  Map<String, dynamic> get v => widget.ctx.view;

  /// Khoá tải: bảng + được vẽ hay không (vé chỉ đổi khi quyền vẽ đổi, tránh tải lại mỗi lần trang đổi).
  String get _key => '${v['board']}|${widget.interactive && v['can_draw'] == true}';

  void _ensure() {
    if (!_inAppWeb || v['token'] == null || v['path'] == null) return;
    if (_key == _loaded && _web != null) return;
    _loaded = _key;
    _web = configureBoardWeb(WebViewController(), _url(v, viewOnly: !widget.interactive), isMacOS: !kIsWeb && Platform.isMacOS);
    if (widget.interactive) _boards[widget.ctx.page.id] = _web!;
  }

  @override
  void dispose() {
    if (_boards[widget.ctx.page.id] == _web) _boards.remove(widget.ctx.page.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    _ensure();
    if (_web == null) {
      // Windows / Linux / kiểm thử: không có WebView trong app.
      return Container(
        decoration: BoxDecoration(color: t.light ? Colors.white : const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.draw_outlined, size: 40, color: _color),
          const SizedBox(height: 8),
          Text(tr('Bảng trắng · {0} nét vẽ', [v['count'] ?? 0]), style: const TextStyle(color: Color(0xFF151A22), fontWeight: FontWeight.w700)),
          if (widget.interactive && v['token'] != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => launchUrl(_url(v, viewOnly: false), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(tr('Mở bảng trong trình duyệt')),
            ),
          ],
        ]),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: WebViewWidget(controller: _web!));
  }
}

class WhiteboardPanel extends StatelessWidget {
  final PageCtx ctx;
  const WhiteboardPanel(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    final v = ctx.view;
    final mode = '${v['mode'] ?? 'all'}';
    final h = switch (s.form) { AppForm.phoneLandscape => 300.0, AppForm.wide => 460.0, _ => 440.0 };
    final note = v['can_draw'] == true
        ? (v['follow'] == true ? tr('Vẽ bằng thanh công cụ; 2 ngón để kéo / phóng. Bấm "Đi theo" trên bảng để thoát / bật lại.') : tr('Vẽ bằng thanh công cụ; 2 ngón để kéo / phóng.'))
        : mode == 'locked'
            ? tr('Bảng đang khoá: chỉ xem.')
            : tr('Chỉ chủ trang được vẽ: bạn xem và đi theo.');
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: h, child: WhiteboardView(ctx, interactive: true)),
        const SizedBox(height: 8),
        Text(note, style: TextStyle(color: t.sub, fontSize: 12.5)),
      ]),
    );
  }
}

class WhiteboardControls extends StatelessWidget {
  final PageCtx ctx;
  const WhiteboardControls(this.ctx, {super.key});

  Future<void> _act(BuildContext context, String a, [Map<String, dynamic> b = const {}]) async {
    try {
      await ctx.act(a, b);
    } catch (e) {
      if (context.mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ctx.view;
    final web = _boards[ctx.page.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(ctx.live ? tr('Đang chiếu · {0} nét vẽ', [v['count'] ?? 0]) : tr('Ai được vẽ')),
      AppSegmented<String>(
        items: [('all', tr('Mọi người')), ('owner', tr('Chỉ mình tôi')), ('locked', tr('Khoá'))],
        value: '${v['mode'] ?? 'all'}',
        onChanged: (x) => _act(context, 'mode', {'mode': x}),
      ),
      const SizedBox(height: 6),
      AppToggleRow(tr('Mọi người đi theo người trình bày'), sub: tr('Bảng của mọi người (và TV) xem đúng vùng bạn đang xem'), value: v['follow'] == true, onChanged: (x) => _act(context, 'follow', {'on': x})),
      const SizedBox(height: 8),
      if (ctx.page.meeting != null)
        AppButton(
          tr('Lưu ảnh vào Biên bản'),
          icon: Icons.image_outlined,
          onPressed: web == null
              ? null
              : () async {
                  try {
                    await web.runJavaScript('window.fxExport && window.fxExport()');
                    if (context.mounted) meetToast(context, tr('Đang lưu ảnh bảng vào chat và Biên bản'));
                  } catch (e) {
                    if (context.mounted) meetToast(context, '$e');
                  }
                },
        ),
      const SizedBox(height: 8),
      AppButton(tr('Xoá bảng'), kind: AppButtonKind.danger, confirm: true, confirmLabel: tr('Bấm lần nữa để xoá hết'), onPressed: () => _act(context, 'clear')),
    ]);
  }
}
