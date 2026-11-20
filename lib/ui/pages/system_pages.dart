import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_media.dart';
import 'page_types.dart';
import 'pages_api.dart';
import 'types/builtin.dart' show pageField;

// Trang hệ thống của Họp (mới): không thuộc ai, người trình chiếu / chủ trì đưa lên sân khấu (metadata.stage.page = sys:…).
//   sys:grid      Video dạng lưới: mọi người bật camera, lưới đều.
//   sys:auto      Video tự động: người đang nói lên lớn (giữ một lúc để không nhảy liên tục).
//   sys:host      Chủ phòng: chủ trì lớn nhất, dải người bên dưới, ai mới bật camera đứng đầu.
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
      SysPage('sys:host', tr('Chủ phòng'), tr('Chủ trì lớn nhất, mọi người bên dưới'), Icons.person_pin_outlined, const Color(0xFFF29900)),
      SysPage('sys:handover', tr('Chờ lượt trình chiếu'), tr('Mời người kế tiếp trình bày'), Icons.hourglass_top_rounded, const Color(0xFF9334E6)),
    ];

/// Màu nền có sẵn cho trang Chào mừng / Chờ lượt (giá trị CSS: TV dùng nguyên chuỗi này).
const pageBackgrounds = <String, List<Color>>{
  'linear-gradient(135deg,#0E5C55,#173431)': [Color(0xFF0E5C55), Color(0xFF173431)],
  'linear-gradient(135deg,#1A3A6B,#101826)': [Color(0xFF1A3A6B), Color(0xFF101826)],
  'linear-gradient(135deg,#5B2A86,#1C1230)': [Color(0xFF5B2A86), Color(0xFF1C1230)],
  'linear-gradient(135deg,#8A3B12,#2A1408)': [Color(0xFF8A3B12), Color(0xFF2A1408)],
  'linear-gradient(135deg,#2B2E33,#121417)': [Color(0xFF2B2E33), Color(0xFF121417)],
  '#F7F8FA': [Color(0xFFF7F8FA), Color(0xFFF7F8FA)],
};

/// Nền của một trang từ cấu hình (ảnh > màu có sẵn > mặc định).
BoxDecoration pageBackground(String bg, String image) {
  if (image.startsWith('http') || image.startsWith('/')) {
    return BoxDecoration(color: Colors.black, image: DecorationImage(image: NetworkImage(pageAssetUrl(image)), fit: BoxFit.cover, opacity: .85));
  }
  final c = pageBackgrounds[bg] ?? pageBackgrounds.values.first;
  return BoxDecoration(gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight));
}

bool _light(String bg) => bg == '#F7F8FA';

/// Màn hình "Chờ lượt trình chiếu" (sân khấu, xem trước trong trình soạn).
class HandoverView extends StatelessWidget {
  /// metadata.stage: handover {name, uid, pages, seconds, next}, handover_cfg, ends_at.
  final Map stage;
  final Map? cfgOverride;
  const HandoverView({super.key, required this.stage, this.cfgOverride});

  @override
  Widget build(BuildContext context) {
    final h = (stage['handover'] as Map?) ?? const {};
    final c = cfgOverride ?? (stage['handover_cfg'] as Map?) ?? const {};
    final bg = '${c['bg'] ?? ''}';
    final fg = _light(bg) ? const Color(0xFF1B2430) : Colors.white;
    final sub = _light(bg) ? const Color(0xFF5C6670) : Colors.white70;
    final name = '${h['name'] ?? ''}';
    final title = '${c['title'] ?? ''}'.isEmpty ? tr('Mời {0} trình bày', [name]) : '${c['title']}'.replaceAll('{name}', name);
    final pages = (h['pages'] as num?)?.toInt() ?? 0;
    final mins = (((h['seconds'] as num?)?.toInt() ?? 0) / 60).round();
    final ends = (stage['ends_at'] as num?)?.toInt() ?? 0;
    final left = ends == 0 ? 0 : ((ends - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    return Container(
      decoration: pageBackground(bg, '${c['bg_image'] ?? ''}'),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if ('${c['icon'] ?? ''}'.isNotEmpty) Text('${c['icon']}', style: const TextStyle(fontSize: 56)),
            if (c['show_avatar'] != false) ...[
              const SizedBox(height: 10),
              CircleAvatar(
                radius: 52,
                backgroundColor: Colors.white24,
                child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(), style: TextStyle(color: fg, fontSize: 48, fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 38, fontWeight: FontWeight.w700)),
            if ('${c['desc'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${c['desc']}', textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 19)),
            ],
            if (c['show_pages'] != false && pages > 0) ...[
              const SizedBox(height: 14),
              Text(mins > 0 ? tr('{0} trang · {1} phút', [pages, mins]) : tr('{0} trang', [pages]), style: TextStyle(color: sub, fontSize: 18)),
            ],
            if (left > 0) ...[
              const SizedBox(height: 10),
              Text(tr('Bắt đầu sau {0} giây', [left]), style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w600)),
            ],
            if (c['show_next'] != false && '${h['next'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr('Tiếp theo: {0}', [h['next']]), style: TextStyle(color: sub, fontSize: 16)),
            ],
          ]),
        ),
      ),
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
  late final _image = TextEditingController(text: '${cfg['bg_image'] ?? ''}');
  bool _company = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _icon, _image]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _now => {...cfg, 'title': _title.text, 'desc': _desc.text, 'icon': _icon.text, 'bg_image': _image.text};

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
          SizedBox(width: 110, child: TextField(controller: _icon, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Biểu tượng')), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _image, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Ảnh nền (tuỳ chọn)')), onChanged: (_) => setState(() {}))),
          IconButton(
            tooltip: tr('Chọn ảnh nền'),
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
            onPressed: () async {
              final u = await pickPageMedia(context, widget.call, image: true);
              if (u != null && mounted) setState(() => _image.text = u);
            },
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in pageBackgrounds.entries)
            InkWell(
              onTap: () => setState(() => cfg['bg'] = e.key),
              child: Container(
                width: 44,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: e.value),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cfg['bg'] == e.key ? Colors.white : Colors.white24, width: cfg['bg'] == e.key ? 2 : 1),
                ),
              ),
            ),
        ]),
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
        'page': {'id': 'sys-welcome', 'type': 'welcome', 'title': tr('Chào mừng'), 'owner': '', 'visibility': 'meeting', 'content': cfg},
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

/// Trang "Nội dung" trên sân khấu: các phần, người phụ trách, phần đang diễn ra; chủ trì / người trình chiếu chuyển phần
/// và trao lượt cho người phụ trách.
class ProgramView extends StatelessWidget {
  final CallService call;
  final Map cfg;
  final bool controls;
  const ProgramView({super.key, required this.call, required this.cfg, this.controls = true});

  @override
  Widget build(BuildContext context) {
    final items = [for (final x in (cfg['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final cur = (cfg['current'] as num?)?.toInt() ?? 0;
    final can = controls && (call.canModerate || call.roomStage?['presenter'] == call.myId());
    Future<void> act(String a, [Map<String, dynamic> b = const {}]) async {
      final e = await call.stageAct(a, b);
      if (e != null && context.mounted) meetToast(context, e);
    }

    return Container(
      color: const Color(0xFF17191C),
      // Dưới cùng chừa chỗ cho nhãn sân khấu (góc trái dưới).
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 44),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${cfg['title'] ?? tr('Nội dung')}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (items.isEmpty) Text(tr('Chưa có nội dung. Chủ trì bấm ⚙ ở thẻ Nội dung để soạn.'), style: const TextStyle(color: Color(0xFF9AA0A6))),
        Expanded(
          child: ListView(children: [
            for (final (i, it) in items.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: i == cur ? const Color(0xFF173431) : const Color(0xFF26282C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: i == cur ? const Color(0xFF0E9F8E) : Colors.transparent),
                ),
                child: InkWell(
                  onTap: can ? () => act('program_goto', {'index': i}) : null,
                  child: Row(children: [
                    Icon(i < cur ? Icons.check_circle_rounded : (i == cur ? Icons.play_circle_fill_rounded : Icons.radio_button_unchecked_rounded),
                        size: 20, color: i < cur ? const Color(0xFF34A853) : (i == cur ? const Color(0xFF2BB3A3) : const Color(0xFF9AA0A6))),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${it['title']}', style: TextStyle(color: i < cur ? const Color(0xFF9AA0A6) : Colors.white, fontSize: 16))),
                    if ('${it['owner_name'] ?? ''}'.isNotEmpty) Text('${it['owner_name']}  ', style: const TextStyle(color: Color(0xFF9AA0A6))),
                    if ((it['minutes'] ?? 0) != 0) Text('${it['minutes']}′', style: const TextStyle(color: Color(0xFF9AA0A6))),
                  ]),
                ),
              ),
          ]),
        ),
        if (can && items.isNotEmpty)
          Row(children: [
            const Spacer(),
            if (call.canModerate && '${items[cur.clamp(0, items.length - 1)]['owner'] ?? ''}'.isNotEmpty)
              Flexible(
                flex: 4,
                child: FilledButton.tonalIcon(
                  onPressed: () => act('program_goto', {'index': cur, 'grant': true}),
                  icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                  label: Text(tr('Trao lượt cho {0}', [items[cur.clamp(0, items.length - 1)]['owner_name'] ?? '']), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: tr('Phần trước'), onPressed: cur > 0 ? () => act('program_goto', {'index': cur - 1}) : null, icon: const Icon(Icons.chevron_left_rounded)),
            const SizedBox(width: 4),
            IconButton.filledTonal(tooltip: tr('Phần sau'), onPressed: cur < items.length - 1 ? () => act('program_next') : null, icon: const Icon(Icons.chevron_right_rounded)),
          ]),
      ]),
    );
  }
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
          SizedBox(width: 110, child: TextField(controller: _icon, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Biểu tượng')), onChanged: (_) => setState(() {}))),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              final u = await pickPageMedia(context, widget.call, image: true);
              if (u != null && mounted) setState(() => cfg['bg_image'] = u);
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text('${cfg['bg_image'] ?? ''}'.isEmpty ? tr('Ảnh nền') : tr('Đổi ảnh nền')),
          ),
          if ('${cfg['bg_image'] ?? ''}'.isNotEmpty) IconButton(tooltip: tr('Bỏ ảnh nền'), onPressed: () => setState(() => cfg['bg_image'] = ''), icon: const Icon(Icons.close_rounded, color: Colors.white54)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in pageBackgrounds.entries)
            InkWell(
              onTap: () => setState(() => cfg['bg'] = e.key),
              child: Container(
                width: 44,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: e.value),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cfg['bg'] == e.key ? Colors.white : Colors.white24, width: cfg['bg'] == e.key ? 2 : 1),
                ),
              ),
            ),
        ]),
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
