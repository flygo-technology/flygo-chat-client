import 'package:flutter/material.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_media.dart';
import 'pages_api.dart' show pageAssetUrl;
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

List<SysPage> get sysPages => [
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
