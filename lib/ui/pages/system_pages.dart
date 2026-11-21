import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_media.dart';
import 'page_types.dart';
import 'stage_frame.dart';
import 'pages_api.dart';
import 'types/builtin.dart' show pageField;

// Trang hệ thống của Họp (mới): không thuộc ai, người trình chiếu / chủ trì đưa lên sân khấu (metadata.stage.page = sys:…).
//   sys:grid      Video dạng lưới: mọi người bật camera, lưới đều.
//   sys:auto      Video tự động: người đang nói lên lớn (giữ một lúc để không nhảy liên tục).
//   sys:host      Chủ phòng (cũ, không còn trong danh sách): chủ trì lớn nhất, dải người bên dưới.
//   sys:screen    Chiếu màn hình: màn hình chia sẻ mới nhất kín khung; chưa ai chia sẻ thì nút "Chiếu màn hình của tôi".
//   sys:handover  Chờ lượt trình chiếu: "Mời {name} trình bày" tới khi người đó đưa trang đầu lên (cấu hình được).
// Ba trang video là bố cục của màn họp (call_screen.dart); màn hình chờ lượt vẽ ở đây (HandoverView), TV vẽ ở hop-web.

class SysPage {
  final String id;
  final String label, desc;
  final IconData icon;
  final Color color;
  const SysPage(this.id, this.label, this.desc, this.icon, this.color);
}

/// Trang hệ thống là một ô trên sân khấu (các trang khác là bố cục video của màn họp).
const sysStagePages = {'sys:handover', 'sys:welcome', 'sys:program'};

/// Chủ trì soạn trang hệ thống này (null = không có trình soạn).
Future<void> Function()? sysPageEditor(BuildContext context, CallService call, String id, {bool canCompany = false}) => switch (id) {
      'sys:handover' => () => showHandoverEditor(context, call, canCompany: canCompany),
      'sys:welcome' => () => showSysWelcomeEditor(context, call, canCompany: canCompany),
      'sys:program' => () => showProgramEditor(context, call, canCompany: canCompany),
      _ => null,
    };

List<SysPage> get sysPages => [
      SysPage('sys:welcome', tr('Chào mừng'), tr('Màn hình chờ của cuộc họp'), Icons.waving_hand_outlined, const Color(0xFF0E9F8E)),
      SysPage('sys:program', tr('Nội dung'), tr('Các phần của cuộc họp, ai phụ trách'), Icons.format_list_numbered_rounded, const Color(0xFF1A73E8)),
      SysPage('sys:auto', tr('Video tự động'), tr('Người đang nói lên lớn'), Icons.record_voice_over_outlined, const Color(0xFF2BB3A3)),
      SysPage('sys:grid', tr('Video dạng lưới'), tr('Mọi người bật camera, chia đều'), Icons.grid_view_rounded, const Color(0xFF4285F4)),
      // "Chủ phòng" bỏ khỏi danh sách (Sếp 2026-11-21); máy chủ / TV vẫn hiểu sys:host cho cuộc họp cũ.
      SysPage('sys:screen', tr('Chiếu màn hình'), tr('Màn hình đang được chia sẻ, bắt đầu / dừng ngay trên trang'), Icons.screen_share_outlined, const Color(0xFFF29900)),
      SysPage('sys:handover', tr('Chờ lượt trình chiếu'), tr('Mời người kế tiếp trình bày'), Icons.hourglass_top_rounded, const Color(0xFF9334E6)),
    ];

/// Nền của một trang từ cấu hình (ảnh > nền có sẵn của stage_frame.dart > mặc định).
BoxDecoration pageBackground(String bg, String image, [StageTheme t = const StageTheme()]) =>
    bg.isEmpty && image.isEmpty ? stageBackground('linear-gradient(135deg,#0E5C55,#173431)', '', t) : stageBackground(bg, image, t);


/// Màn hình "Chờ lượt trình chiếu" (sân khấu, xem trước trong trình soạn): người được mời (ảnh + vòng đếm ngược tự sang),
/// lời mời lớn, số trang / thời lượng, và hàng chờ bên phải.
class HandoverView extends StatelessWidget {
  /// metadata.stage: handover {name, uid, pages, seconds, next}, handover_cfg, queue, ends_at.
  final Map stage;
  final Map? cfgOverride;
  const HandoverView({super.key, required this.stage, this.cfgOverride});

  @override
  Widget build(BuildContext context) {
    final metrics = StageMetrics.of(context);
    final t = metrics?.theme ?? StageTheme.of(stage['theme_cfg'] as Map?);
    final h = (stage['handover'] as Map?) ?? const {};
    final c = cfgOverride ?? (stage['handover_cfg'] as Map?) ?? const {};
    final bg = '${c['bg'] ?? ''}', img = '${c['bg_image'] ?? ''}';
    // Không đặt nền riêng: theo bảng màu sân khấu (chế độ Sáng: chữ tối).
    final light = img.isEmpty && (bg.isEmpty ? t.light : stageBgLight(bg, t));
    final fg = light ? const Color(0xFF141A23) : Colors.white;
    final sub = light ? const Color(0xFF4A5565) : const Color(0xFFC9D2DE);
    final card = light ? Colors.white.withValues(alpha: .8) : Colors.white.withValues(alpha: .06);
    final name = '${h['name'] ?? ''}';
    final title = '${c['title'] ?? ''}'.isEmpty ? tr('Mời {0} trình bày', [name]) : '${c['title']}'.replaceAll('{name}', name);
    final pages = (h['pages'] as num?)?.toInt() ?? 0;
    final mins = (((h['seconds'] as num?)?.toInt() ?? 0) / 60).round();
    final ends = (stage['ends_at'] as num?)?.toInt() ?? 0;
    final left = ends == 0 ? 0 : ((ends - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(0, 9999);
    final auto = (c['auto_seconds'] as num?)?.toInt() ?? 0;
    final queue = [for (final q in (stage['queue'] as List? ?? const [])) (q as Map)];
    String initial(String n) => n.trim().isEmpty ? '?' : n.trim().characters.first.toUpperCase();

    Widget pill(String text, {bool accent = false}) => Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: accent ? t.accent.withValues(alpha: .2) : card, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w600))]),
        );

    Widget avatar(double size) => SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: auto > 0 && left > 0 ? 1 - left / auto : 1,
                strokeWidth: size * .045,
                backgroundColor: fg.withValues(alpha: .1),
                valueColor: AlwaysStoppedAnimation(t.accent),
              ),
            ),
            if (c['show_avatar'] != false)
              Container(
                width: size * .8,
                height: size * .8,
                decoration: const BoxDecoration(color: Color(0xFFE8710A), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(initial(name), style: TextStyle(color: Colors.white, fontSize: size * .34, fontWeight: FontWeight.w800)),
              )
            else if ('${c['icon'] ?? ''}'.isNotEmpty)
              Text('${c['icon']}', style: TextStyle(fontSize: size * .4)),
          ]),
        );

    Widget queueRow(String n, String note, String badge, {bool now = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14), border: now ? Border.all(color: t.accent, width: 1.5) : null),
          child: Row(children: [
            CircleAvatar(radius: 20, backgroundColor: now ? const Color(0xFFE8710A) : t.series[(n.hashCode % 5).abs() + 1], child: Text(initial(n), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w700)),
                if (note.isNotEmpty) Text(note, style: TextStyle(color: sub, fontSize: 14)),
              ]),
            ),
            Text(badge, style: TextStyle(color: now ? Color.lerp(t.accent, light ? Colors.black : Colors.white, .4) : sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .8)),
          ]),
        );

    Widget main(bool portrait) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            avatar(portrait ? 96 : 132),
            const SizedBox(width: 22),
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('TIẾP THEO'), style: TextStyle(color: Color.lerp(t.accent, light ? Colors.black : Colors.white, .35), fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2)),
                if (left > 0) Text(tr('Tự bắt đầu sau {0} giây', [left]), style: TextStyle(color: sub, fontSize: portrait ? 15 : 20)),
              ]),
            ),
          ]),
          SizedBox(height: portrait ? 18 : 26),
          Text(title, style: TextStyle(color: fg, fontSize: portrait ? 40 : 66, fontWeight: FontWeight.w800, height: 1.06, letterSpacing: -.5)),
          if ('${c['desc'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('${c['desc']}', style: TextStyle(color: sub, fontSize: portrait ? 16 : 22, height: 1.4)),
          ],
          const SizedBox(height: 22),
          Wrap(spacing: 12, runSpacing: 10, children: [
            if (c['show_pages'] != false && pages > 0) pill(tr('{0} trang chuẩn bị sẵn', [pages])),
            if (mins > 0) pill(tr('{0} phút', [mins])),
            if (c['show_next'] != false && '${h['next'] ?? ''}'.isNotEmpty) pill(tr('Sau đó: {0}', ['${h['next']}'])),
          ]),
        ]);

    Widget side() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('HÀNG CHỜ'), style: TextStyle(color: sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
          const SizedBox(height: 12),
          queueRow(name, mins > 0 ? tr('{0} phút', [mins]) : '', tr('BÂY GIỜ'), now: true),
          for (final (i, q) in queue.take(4).indexed) ...[const SizedBox(height: 10), queueRow('${q['name'] ?? ''}', '', '${i + 2}')],
        ]);

    Widget layout(bool portrait) => portrait
        ? Padding(padding: const EdgeInsets.fromLTRB(20, 70, 20, 70), child: Align(alignment: Alignment.centerLeft, child: main(true)))
        : Padding(
            padding: const EdgeInsets.fromLTRB(96, 110, 56, 92),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: main(false)),
              if (queue.isNotEmpty || name.isNotEmpty) ...[const SizedBox(width: 40), SizedBox(width: 360, child: side())],
            ]),
          );

    return Container(
      decoration: bg.isEmpty && img.isEmpty ? BoxDecoration(color: t.bg) : stageBackground(bg, img, t),
      child: metrics != null ? layout(metrics.portrait) : FittedBox(fit: BoxFit.cover, child: SizedBox(width: 1280, height: 720, child: layout(false))),
    );
  }
}

/// Trình soạn màn hình "Chờ lượt trình chiếu" (chủ trì: cuộc họp này; quản trị hệ thống: mặc định của công ty).
Future<void> showHandoverEditor(BuildContext context, CallService call, {bool canCompany = false}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23262C),
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => _HandoverEditor(call: call, canCompany: canCompany),
    );

class _HandoverEditor extends StatefulWidget {
  final CallService call;
  final bool canCompany;
  const _HandoverEditor({required this.call, required this.canCompany});
  @override
  State<_HandoverEditor> createState() => _HandoverEditorState();
}

class _HandoverEditorState extends State<_HandoverEditor> {
  late final Map<String, dynamic> cfg = {...((widget.call.roomStage?['handover_cfg'] as Map?) ?? const {})}.cast<String, dynamic>();
  late final _title = TextEditingController(text: '${cfg['title'] ?? tr('Mời {name} trình bày')}');
  late final _desc = TextEditingController(text: '${cfg['desc'] ?? ''}');
  late final _icon = TextEditingController(text: '${cfg['icon'] ?? ''}');
  bool _company = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _icon]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _now => {...cfg, 'title': _title.text, 'desc': _desc.text, 'icon': _icon.text};

  Future<void> _save() async {
    setState(() => _busy = true);
    final e = await widget.call.stageAct('config', {'handover': _now, 'scope': _company ? 'company' : 'meeting'});
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) return meetToast(context, e);
    Navigator.pop(context);
    meetToast(context, _company ? tr('Đã lưu mặc định cho mọi cuộc họp của công ty') : tr('Đã lưu cho cuộc họp này'));
  }

  Widget _switch(String k, String label) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: cfg[k] != false,
        title: Text(label, style: const TextStyle(color: Colors.white)),
        onChanged: (v) => setState(() => cfg[k] = v),
      );

  @override
  Widget build(BuildContext context) {
    final sample = {
      'handover': {'name': widget.call.roomStage?['presenter_name'] ?? tr('Nguyễn Văn A'), 'pages': 4, 'seconds': 900, 'next': tr('Người kế tiếp')},
      'ends_at': 0,
    };
    final auto = (cfg['auto_seconds'] as num?)?.toInt() ?? 0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Chờ lượt trình chiếu'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: HandoverView(stage: sample, cfgOverride: _now))),
        const SizedBox(height: 12),
        TextField(controller: _title, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Tiêu đề ({name} = tên người trình bày)')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        TextField(controller: _desc, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Mô tả')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 150, child: TextField(controller: _icon, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Biểu tượng')), onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 10),
        StageBackgroundPicker(
          call: widget.call,
          theme: StageTheme.of(widget.call.roomStage?['theme_cfg'] as Map?),
          value: '${cfg['bg'] ?? ''}',
          image: '${cfg['bg_image'] ?? ''}',
          onBg: (k) => setState(() {
            cfg['bg'] = k;
            cfg['bg_image'] = '';
          }),
          onImage: (u) => setState(() => cfg['bg_image'] = u),
        ),
        const SizedBox(height: 6),
        _switch('show_avatar', tr('Hiện ảnh đại diện')),
        _switch('show_pages', tr('Hiện số trang, thời lượng đã chuẩn bị')),
        _switch('show_next', tr('Hiện người kế tiếp')),
        Row(children: [
          Expanded(child: Text(tr('Tự sang trang đầu của người trình bày'), style: const TextStyle(color: Colors.white))),
          DropdownButton<int>(
            dropdownColor: const Color(0xFF2D3036),
            value: const [0, 5, 10, 15, 30, 60].contains(auto) ? auto : 0,
            items: [for (final s in const [0, 5, 10, 15, 30, 60]) DropdownMenuItem(value: s, child: Text(s == 0 ? tr('Không') : tr('sau {0} giây', [s]), style: const TextStyle(color: Colors.white)))],
            onChanged: (v) => setState(() => cfg['auto_seconds'] = v ?? 0),
          ),
        ]),
        if (widget.canCompany)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _company,
            title: Text(tr('Đặt làm mặc định cho mọi cuộc họp của công ty'), style: const TextStyle(color: Colors.white)),
            onChanged: (v) => setState(() => _company = v),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Lưu'))),
      ]),
    );
  }
}


/// Trang Chào mừng của hệ thống: dùng lại phần hiện của loại trang Chào mừng với cấu hình của cuộc họp (stage.welcome_cfg).
PageCtx sysWelcomeCtx(CallService call, Map cfg, {bool onStage = true}) => PageCtx(
      data: PageData.from({
        'page': {'id': 'sys:welcome', 'type': 'welcome', 'title': tr('Chào mừng'), 'owner': '', 'visibility': 'meeting', 'content': cfg},
        'view': const {},
        'role': 'viewer',
        'rev': 0,
      }),
      api: PagesApi(call),
      call: call,
      presenting: false,
      onStage: onStage,
      act: (a, [b = const {}]) async {},
      reload: () async {},
    );

/// Trang "Nội dung" trên sân khấu: các phần, người phụ trách, phần đang diễn ra (lớn, nổi bật), phần đã xong gạch đi.
/// Nút chuyển phần / trao lượt nằm ở thanh cuối của khung ([programFooter]); ngoài khung thì nằm dưới danh sách.
class ProgramView extends StatelessWidget {
  final CallService call;
  final Map cfg;
  final bool controls;
  const ProgramView({super.key, required this.call, required this.cfg, this.controls = true});

  @override
  Widget build(BuildContext context) {
    final metrics = StageMetrics.of(context);
    final t = metrics?.theme ?? StageTheme.of(call.roomStage?['theme_cfg'] as Map?);
    final portrait = metrics?.portrait ?? false;
    final items = [for (final x in (cfg['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final cur = ((cfg['current'] as num?)?.toInt() ?? 0).clamp(0, items.isEmpty ? 0 : items.length - 1);
    final rest = items.skip(cur).fold<int>(0, (a, x) => a + ((x['minutes'] as num?)?.toInt() ?? 0));
    final can = controls && metrics == null && (call.canModerate || call.roomStage?['presenter'] == call.myId());
    final fb = (cfg['fb'] as Map?) ?? const {};
    final fbNow = (fb['index'] as num?)?.toInt() == cur;
    final fbMore = fbNow ? (fb['more'] as List? ?? const []).length : 0, fbClear = fbNow ? (fb['clear'] as List? ?? const []).length : 0;

    Widget who(Map it, {bool big = false}) {
      final n = '${it['owner_name'] ?? ''}';
      if (n.isEmpty) return const SizedBox.shrink();
      return Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: big ? 16 : 14,
          backgroundColor: t.series[(n.hashCode % 5).abs() + 1],
          child: Text(n.trim().characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: big ? t.text : t.sub, fontSize: big ? 18 : 16))),
      ]);
    }

    Widget row(int i, Map<String, dynamic> it) {
      final done = i < cur, now = i == cur;
      final mins = (it['minutes'] as num?)?.toInt() ?? 0;
      return Container(
        height: now ? (portrait ? 84 : 92) : (portrait ? 54 : 62),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: now ? t.accent.withValues(alpha: .16) : (done ? t.surface.withValues(alpha: .6) : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
          border: now ? Border.all(color: t.accent, width: 1.5) : null,
        ),
        child: Row(children: [
          SizedBox(
            width: 44,
            child: done
                ? const Icon(Icons.check_rounded, color: Color(0xFF38C793), size: 26)
                : Text('${i + 1}', style: TextStyle(color: now ? t.text : t.sub, fontSize: now ? 26 : 20, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (now)
                Text(
                  // Phản hồi của người xem cho phần này (app: "Cần thêm thời gian" / "Đã rõ").
                  fbMore + fbClear > 0 ? '${tr('ĐANG DIỄN RA')} · ${tr('{0} CẦN THÊM THỜI GIAN · {1} ĐÃ RÕ', [fbMore, fbClear])}' : tr('ĐANG DIỄN RA'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color.lerp(t.accent, t.light ? Colors.black : Colors.white, .35), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.6),
                ),
              Text(
                '${it['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: done ? t.sub : t.text,
                  fontSize: now ? (portrait ? 24 : 30) : (portrait ? 18 : 22),
                  fontWeight: now ? FontWeight.w700 : FontWeight.w500,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: t.sub,
                ),
              ),
            ]),
          ),
          if (!portrait) SizedBox(width: 240, child: who(it, big: now)),
          SizedBox(width: 64, child: Text(mins > 0 ? '$mins′' : '', textAlign: TextAlign.right, style: TextStyle(color: now ? t.text : t.sub, fontSize: now ? 22 : 18, fontWeight: now ? FontWeight.w700 : FontWeight.w400))),
        ]),
      );
    }

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flex(
        direction: portrait ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: portrait ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          if (portrait)
            Text('${cfg['title'] ?? tr('Nội dung')}', style: TextStyle(color: t.text, fontSize: 28, fontWeight: FontWeight.w800))
          else
            Expanded(child: Text('${cfg['title'] ?? tr('Nội dung')}', style: TextStyle(color: t.text, fontSize: 44, fontWeight: FontWeight.w800))),
          if (items.isNotEmpty) Text(tr('Phần {0} / {1}', [cur + 1, items.length]) + (rest > 0 ? tr(' · còn {0} phút', [rest]) : ''), style: TextStyle(color: t.sub, fontSize: portrait ? 14 : 18)),
        ],
      ),
      SizedBox(height: portrait ? 14 : 22),
      if (items.isEmpty)
        Text(tr('Chưa có nội dung. Chủ trì bấm ⚙ ở thẻ Nội dung để soạn.'), style: TextStyle(color: t.sub, fontSize: 18))
      else
        Expanded(child: ListView(padding: EdgeInsets.zero, children: [for (final (i, it) in items.indexed) row(i, it)])),
      if (can && items.isNotEmpty) Row(children: programFooter(context, call, cfg, t)),
    ]);
    if (metrics != null) return content;
    return Container(color: t.bg, padding: const EdgeInsets.fromLTRB(20, 52, 20, 16), child: content);
  }
}

/// Thanh cuối của trang Nội dung: trao lượt cho người phụ trách phần hiện tại, phần trước / sau.
List<Widget> programFooter(BuildContext context, CallService call, Map cfg, StageTheme t) {
  final items = [for (final x in (cfg['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  if (items.isEmpty) return const [];
  final cur = ((cfg['current'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1);
  final can = call.canModerate || call.roomStage?['presenter'] == call.myId();
  final next = cur + 1 < items.length ? items[cur + 1] : null;
  Future<void> act(String a, [Map<String, dynamic> b = const {}]) async {
    final e = await call.stageAct(a, b);
    if (e != null && context.mounted) meetToast(context, e);
  }

  // Màn hẹp (điện thoại): bỏ dòng "Tiếp: …" để đủ chỗ cho nút.
  final narrow = MediaQuery.sizeOf(context).width < 600;
  return [
    if (!narrow) StagePill(next == null ? tr('Phần cuối') : tr('Tiếp: {0}', ['${next['title']}${'${next['owner_name'] ?? ''}'.isEmpty ? '' : ' · ${next['owner_name']}'}']), theme: t),
    const Spacer(),
    if (can && call.canModerate && '${items[cur]['owner'] ?? ''}'.isNotEmpty)
      FilledButton.tonalIcon(
        onPressed: () => act('program_goto', {'index': cur, 'grant': true}),
        icon: const Icon(Icons.record_voice_over_outlined, size: 18),
        label: Text(tr('Trao lượt cho {0}', ['${items[cur]['owner_name'] ?? ''}'])),
      ),
    if (can) ...[
      IconButton.filledTonal(tooltip: tr('Phần trước'), onPressed: cur > 0 ? () => act('program_goto', {'index': cur - 1}) : null, icon: const Icon(Icons.chevron_left_rounded)),
      IconButton.filledTonal(tooltip: tr('Phần sau'), onPressed: cur < items.length - 1 ? () => act('program_next') : null, icon: const Icon(Icons.chevron_right_rounded)),
    ],
  ];
}

/// Soạn trang Chào mừng của hệ thống (chủ trì: cuộc họp này; quản trị hệ thống: mặc định của công ty).
Future<void> showSysWelcomeEditor(BuildContext context, CallService call, {bool canCompany = false}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23262C),
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => _SysWelcomeEditor(call: call, canCompany: canCompany),
    );

class _SysWelcomeEditor extends StatefulWidget {
  final CallService call;
  final bool canCompany;
  const _SysWelcomeEditor({required this.call, required this.canCompany});
  @override
  State<_SysWelcomeEditor> createState() => _SysWelcomeEditorState();
}

class _SysWelcomeEditorState extends State<_SysWelcomeEditor> {
  late final Map<String, dynamic> cfg = {...((widget.call.roomStage?['welcome_cfg'] as Map?) ?? const {})}.cast<String, dynamic>();
  late final _heading = TextEditingController(text: '${cfg['heading'] ?? ''}');
  late final _sub = TextEditingController(text: '${cfg['subtitle'] ?? ''}');
  late final _icon = TextEditingController(text: '${cfg['icon'] ?? ''}');
  bool _company = false, _busy = false;

  @override
  void dispose() {
    for (final c in [_heading, _sub, _icon]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _now => {...cfg, 'heading': _heading.text, 'subtitle': _sub.text, 'icon': _icon.text};

  Future<void> _save() async {
    setState(() => _busy = true);
    final e = await widget.call.stageAct('config', {'welcome': _now, 'scope': _company ? 'company' : 'meeting'});
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) return meetToast(context, e);
    Navigator.pop(context);
  }

  Widget _sw(String k, String label, {String? sub}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: cfg[k] == true,
        title: Text(label, style: const TextStyle(color: Colors.white)),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        onChanged: (v) => setState(() => cfg[k] = v),
      );

  @override
  Widget build(BuildContext context) {
    final spec = pageTypeOf('welcome');
    final vol = ((cfg['music_volume'] as num?)?.toDouble() ?? 40).clamp(0.0, 100.0);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Chào mừng (trang hệ thống)'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (spec != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: IgnorePointer(child: spec.view(context, sysWelcomeCtx(widget.call, _now, onStage: false)))),
          ),
        const SizedBox(height: 12),
        TextField(controller: _heading, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Dòng chữ lớn')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        TextField(controller: _sub, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Mô tả')), maxLines: 2, onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 150, child: TextField(controller: _icon, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Biểu tượng')), onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 8),
        StageBackgroundPicker(
          call: widget.call,
          theme: StageTheme.of(widget.call.roomStage?['theme_cfg'] as Map?),
          value: '${cfg['bg'] ?? ''}',
          image: '${cfg['bg_image'] ?? ''}',
          onBg: (k) => setState(() {
            cfg['bg'] = k;
            cfg['bg_image'] = '';
          }),
          onImage: (u) => setState(() => cfg['bg_image'] = u),
        ),
        const SizedBox(height: 6),
        _sw('show_online', tr('Hiện danh sách người đã vào')),
        _sw('countdown', tr('Đếm ngược'), sub: tr('Tới giờ bắt đầu cuộc họp')),
        const Divider(color: Colors.white12),
        Row(children: [
          Expanded(child: Text('${cfg['music'] ?? ''}'.isEmpty ? tr('Chưa có nhạc nền') : tr('Có nhạc nền'), style: const TextStyle(color: Colors.white))),
          TextButton.icon(
            onPressed: () async {
              final u = await pickPageMedia(context, widget.call, image: false);
              if (u != null && mounted) setState(() => cfg['music'] = u);
            },
            icon: const Icon(Icons.library_music_outlined),
            label: Text(tr('Chọn nhạc')),
          ),
          if ('${cfg['music'] ?? ''}'.isNotEmpty) IconButton(tooltip: tr('Bỏ nhạc'), onPressed: () => setState(() => cfg['music'] = ''), icon: const Icon(Icons.close_rounded, color: Colors.white54)),
        ]),
        Slider(value: vol, max: 100, divisions: 20, label: '${vol.round()}%', onChanged: (v) => setState(() => cfg['music_volume'] = v.round())),
        _sw('music_devices', tr('Phát nhạc cả trên máy của mọi người'), sub: tr('Mặc định chỉ phát trên TV / màn hình phòng')),
        if (widget.canCompany)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _company,
            title: Text(tr('Đặt làm mặc định cho mọi cuộc họp của công ty'), style: const TextStyle(color: Colors.white)),
            onChanged: (v) => setState(() => _company = v),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Lưu'))),
      ]),
    );
  }
}

/// Soạn trang "Nội dung" (các phần của cuộc họp, người phụ trách, thời lượng).
Future<void> showProgramEditor(BuildContext context, CallService call, {bool canCompany = false}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23262C),
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => _ProgramEditor(call: call, canCompany: canCompany),
    );

class _ProgramEditor extends StatefulWidget {
  final CallService call;
  final bool canCompany;
  const _ProgramEditor({required this.call, required this.canCompany});
  @override
  State<_ProgramEditor> createState() => _ProgramEditorState();
}

class _ProgramEditorState extends State<_ProgramEditor> {
  late final Map cfg0 = (widget.call.roomStage?['program_cfg'] as Map?) ?? const {};
  late final _title = TextEditingController(text: '${cfg0['title'] ?? tr('Nội dung')}');
  late final List<Map<String, dynamic>> items = [for (final x in (cfg0['items'] as List? ?? const [])) {...(x as Map).cast<String, dynamic>()}];
  bool _company = false, _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final e = await widget.call.stageAct('config', {'program': {'title': _title.text, 'items': items}, 'scope': _company ? 'company' : 'meeting'});
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) return meetToast(context, e);
    Navigator.pop(context);
  }

  /// Một phần: máy rộng một hàng (phần | phụ trách | phút | xoá); điện thoại hai hàng (phần trên, phụ trách + phút dưới).
  Widget _row(int i, Map<String, dynamic> it, Map<String, String> people, bool narrow) {
    final title = TextFormField(
      key: ValueKey('t$i${items.length}'),
      initialValue: '${it['title'] ?? ''}',
      style: const TextStyle(color: Colors.white),
      decoration: pageField(tr('Phần {0}', [i + 1])),
      onChanged: (v) => it['title'] = v,
    );
    final owner = DropdownButtonFormField<String>(
      key: ValueKey('o$i${items.length}'),
      initialValue: people.containsKey(it['owner']) ? '${it['owner']}' : null,
      dropdownColor: const Color(0xFF2D3036),
      isExpanded: true,
      decoration: pageField(tr('Phụ trách')),
      items: [for (final e in people.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)))],
      onChanged: (v) => setState(() {
        it['owner'] = v ?? '';
        it['owner_name'] = people[v] ?? '';
      }),
    );
    final mins = SizedBox(
      width: 70,
      child: TextFormField(
        key: ValueKey('m$i${items.length}'),
        initialValue: (it['minutes'] ?? 0) == 0 ? '' : '${it['minutes']}',
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: pageField(tr('Phút')),
        onChanged: (v) => it['minutes'] = int.tryParse(v) ?? 0,
      ),
    );
    final del = IconButton(tooltip: tr('Xoá phần này'), icon: const Icon(Icons.close_rounded, color: Colors.white54), onPressed: () => setState(() => items.removeAt(i)));
    if (!narrow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Expanded(flex: 5, child: title), const SizedBox(width: 6), Expanded(flex: 4, child: owner), const SizedBox(width: 6), mins, del]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [Expanded(child: title), del]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: owner), const SizedBox(width: 8), mins, const SizedBox(width: 44)]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final narrow = MediaQuery.sizeOf(context).width < 520;
    // Người phụ trách: những người đang trong cuộc họp (và chính mình).
    final people = <String, String>{
      if (app.me != null) app.me!.id: app.me!.displayName,
      for (final p in widget.call.participants)
        if (!p.userId.contains(':') && p.userId.isNotEmpty) p.userId: app.users[p.userId]?.displayName ?? p.userId,
    };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Nội dung cuộc họp'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(controller: _title, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Tiêu đề'))),
        const SizedBox(height: 10),
        for (final (i, it) in items.indexed) _row(i, it, people, narrow),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => setState(() => items.add({'title': '', 'owner': '', 'owner_name': '', 'minutes': 0})), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm phần'))),
        ),
        if (widget.canCompany)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _company,
            title: Text(tr('Đặt làm mẫu mặc định cho công ty'), style: const TextStyle(color: Colors.white)),
            onChanged: (v) => setState(() => _company = v),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Lưu'))),
      ]),
    );
  }
}
