import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../meet/meet_home.dart' show meetToast;
import 'app_kit.dart';
import 'page_types.dart';
import 'pages_overview.dart' show LiveBadge;
import 'stage_frame.dart';

/// Vỏ của một trang-app trong bảng trang (điện thoại: bảng kéo lên; máy tính: cột phải của cuộc họp).
///
/// Bố cục theo mockup "mỗi trang là một app":
/// - hẹp / dọc: hình sân khấu 16:9 (có LIVE) trên, phần tương tác [PageTypeSpec.panel] giữa, điều khiển chủ trang
///   [PageTypeSpec.controls] trong thẻ dưới cùng;
/// - rộng & ngang (điện thoại ngang, máy tính bảng): hình sân khấu trái, cột phải tương tác + điều khiển;
/// - [stage] = false (máy tính khi trang đang LIVE: sân khấu đã hiện bên trái): chỉ tương tác + điều khiển.
/// Khi sửa tại chỗ ([editing]): hình sân khấu bấm được (ô sửa của app), thanh Huỷ / Xong ở cuối.
class PageAppShell extends StatefulWidget {
  final PageCtx ctx;
  final PageTypeSpec? spec;
  final bool stage;
  final bool editing;

  /// Thoát chế độ sửa (Huỷ, hoặc Xong đã lưu).
  final VoidCallback? onEditEnd;

  /// Menu của trang tại điểm nhấn giữ / chuột phải trên hình sân khấu.
  final void Function(Offset at)? onMenu;

  /// Bảng màu cố định (test / xem trước); null = theo Giao diện sân khấu của cuộc họp.
  final StageTheme? theme;
  const PageAppShell({super.key, required this.ctx, required this.spec, this.stage = true, this.editing = false, this.onEditEnd, this.onMenu, this.theme});
  @override
  State<PageAppShell> createState() => _PageAppShellState();
}

class _PageAppShellState extends State<PageAppShell> {
  final _hub = AppEditHub();

  PageCtx get ctx => widget.ctx;

  Future<void> _done() async {
    final f = _hub.onDone;
    try {
      if (f != null && !await f()) return;
      await ctx.reload();
      widget.onEditEnd?.call();
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ctx.call.roomStage ?? const {};
    final cfg = (st['theme_cfg'] as Map?) ?? const {};
    final t = widget.theme ?? StageTheme.of(cfg);
    return LayoutBuilder(builder: (context, box) {
      final screen = MediaQuery.sizeOf(context);
      final w = box.maxWidth;
      // Ngang đủ rộng để chia hai cột (điện thoại ngang, máy tính bảng ngang, bảng trang rộng).
      final split = widget.stage && w >= 600 && screen.width > screen.height;
      final form = split ? (screen.shortestSide < 520 ? AppForm.phoneLandscape : AppForm.wide) : (screen.width > screen.height ? AppForm.wide : AppForm.phonePortrait);
      return AppScope(
        form: form,
        theme: t,
        editing: widget.editing,
        hub: _hub,
        // Builder: phần của app (panel / controls / view) dựng dưới AppScope để đọc đúng kiểu màn hình và bảng màu.
        child: StageMetrics(
          theme: t,
          portrait: !split && form == AppForm.phonePortrait,
          size: Size(w, box.maxHeight.isFinite ? box.maxHeight : 600),
          child: Builder(builder: (context) => _layout(context, t, split, w)),
        ),
      );
    });
  }

  Widget _layout(BuildContext context, StageTheme t, bool split, double w) {
    final spec = widget.spec;
    final panel = spec?.panel?.call(context, ctx);
    final controls = ctx.control && spec?.controls != null ? spec!.controls!(context, ctx) : null;
    final side = <Widget>[
      ?panel,
      if (controls != null) AppCard(child: controls),
      if (widget.editing) _editBar(t),
    ];
    Widget gap(List<Widget> xs) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          for (final (i, x) in xs.indexed) ...[if (i > 0) const SizedBox(height: 12), x],
        ]);
    if (split) {
      final col = w >= 900 ? 380.0 : (w * .36).clamp(200.0, 340.0);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _stage(context, t)),
        const SizedBox(width: 12),
        SizedBox(width: col, child: gap(side)),
      ]);
    }
    return gap([if (widget.stage) _stage(context, t), ...side]);
  }

  /// Hình trang trên sân khấu trong khung chung, nhãn LIVE ở góc. Ngoài lúc sửa: chỉ xem (thao tác ở phần tương tác).
  Widget _stage(BuildContext context, StageTheme t) {
    final spec = widget.spec;
    final st = ctx.call.roomStage ?? const {};
    final cfg = widget.theme != null ? const {} : (st['theme_cfg'] as Map?) ?? const {};
    final sctx = PageCtx(data: ctx.data, api: ctx.api, call: ctx.call, presenting: ctx.presenting, onStage: true, act: ctx.act, reload: ctx.reload);
    final bg = '${cfg['bg'] ?? ''}', img = '${cfg['bg_image'] ?? ''}';
    final frame = StageFrame(
      theme: t,
      bleed: spec?.stageBleed ?? false,
      background: bg.isEmpty && img.isEmpty ? null : stageBackground(bg, img, t),
      headerLeading: [StageTypeChip(icon: spec?.icon ?? Icons.article_outlined, label: spec?.stageLabel?.call(sctx) ?? (spec?.label ?? tr('Trang')).split(RegExp(r' [/&] ')).first, theme: t)],
      headerTrailing: [if (ctx.live) const LiveBadge(size: 13)],
      child: spec == null ? unknownPageView(sctx) : spec.view(context, sctx),
    );
    return GestureDetector(
      onLongPressStart: widget.onMenu == null ? null : (d) => widget.onMenu!(d.globalPosition),
      onSecondaryTapDown: widget.onMenu == null ? null : (d) => widget.onMenu!(d.globalPosition),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: widget.editing ? frame : IgnorePointer(child: frame)),
      ),
    );
  }

  Widget _editBar(StageTheme t) => Row(children: [
        Expanded(child: AppButton(tr('Huỷ'), onPressed: () async => widget.onEditEnd?.call())),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: AppButton(tr('Xong'), kind: AppButtonKind.primary, onPressed: _done)),
      ]);
}
