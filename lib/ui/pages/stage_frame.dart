import 'package:flutter/material.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_media.dart';
import 'pages_api.dart' show pageAssetUrl;

// Khung sân khấu chung (Họp mới): mọi trang trên sân khấu / TV có cùng thanh đầu (loại trang, tên, người trình bày),
// vùng nội dung an toàn và thanh cuối (tiến độ, giờ, cách tham gia). Màu nhấn, tối / sáng, nền và logo theo "Giao diện
// sân khấu" của cuộc họp (chủ trì) hoặc mặc định của công ty (quản trị) — metadata stage.theme_cfg. TV (relay/hop-web)
// vẽ cùng khung, cùng bảng màu và cùng bộ nền có sẵn (giá trị nền là chuỗi CSS, `brand:*` tính từ màu nhấn).

/// Bảng màu của sân khấu.
class StageTheme {
  final bool light;
  final Color accent;
  const StageTheme({this.light = false, this.accent = const Color(0xFF3D7BFF)});

  factory StageTheme.of(Map? cfg) {
    final a = int.tryParse('${cfg?['accent'] ?? ''}'.replaceFirst('#', ''), radix: 16);
    return StageTheme(light: cfg?['mode'] == 'light', accent: a == null ? const Color(0xFF3D7BFF) : Color(0xFF000000 | a));
  }

  Color get bg => light ? const Color(0xFFF6F7F9) : const Color(0xFF0E1116);
  Color get surface => light ? Colors.white : const Color(0xFF171B22);
  Color get surface2 => light ? const Color(0xFFE9EDF2) : const Color(0xFF1F2530);
  Color get text => light ? const Color(0xFF141A23) : const Color(0xFFF3F5F8);
  Color get sub => light ? const Color(0xFF566070) : const Color(0xFFAEB8C6);
  Color get line => light ? const Color(0x14141A23) : const Color(0x14FFFFFF);
  Color get chip => light ? const Color(0xFFE4E8EE) : const Color(0x14FFFFFF);

  /// Màu nhấn dịu dùng làm nền chip / ô chọn.
  Color get accentSoft => accent.withValues(alpha: light ? .12 : .18);

  /// Dãy màu kết quả (bình chọn…): khác nhau cả về độ sáng, không chỉ khác sắc.
  List<Color> get series => [accent, const Color(0xFFF29A3D), const Color(0xFF22B8A6), const Color(0xFF9B6BFF), const Color(0xFFF5B544), const Color(0xFFE0609A)];
}

/// Một nền có sẵn. [key] là giá trị lưu trong cấu hình (chuỗi CSS, hoặc `brand:*`).
class StagePreset {
  final String key, name;
  final List<Color> colors;
  final bool light;
  const StagePreset(this.key, this.name, this.colors, {this.light = false});
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Bộ nền có sẵn: 3 nền theo màu công ty + nền tối + nền sáng. Sáu khoá đầu của nhóm tối giữ nguyên chuỗi cũ (trang đã lưu).
List<StagePreset> stagePresets(Color accent) => [
      StagePreset('brand:dark', tr('Công ty · trầm'), [_mix(accent, Colors.black, .55), _mix(accent, Colors.black, .85)]),
      StagePreset('brand:vivid', tr('Công ty · tươi'), [accent, _mix(accent, Colors.black, .5)]),
      StagePreset('brand:light', tr('Công ty · sáng'), [Colors.white, _mix(accent, Colors.white, .82)], light: true),
      const StagePreset('linear-gradient(135deg,#1A3A6B,#101826)', 'Đêm xanh', [Color(0xFF1A3A6B), Color(0xFF101826)]),
      const StagePreset('linear-gradient(135deg,#0E5C55,#173431)', 'Ngọc', [Color(0xFF0E5C55), Color(0xFF173431)]),
      const StagePreset('linear-gradient(135deg,#5B2A86,#1C1230)', 'Tím', [Color(0xFF5B2A86), Color(0xFF1C1230)]),
      const StagePreset('linear-gradient(135deg,#8A3B12,#2A1408)', 'Hổ phách', [Color(0xFF8A3B12), Color(0xFF2A1408)]),
      const StagePreset('linear-gradient(135deg,#2B2E33,#121417)', 'Than chì', [Color(0xFF2B2E33), Color(0xFF121417)]),
      const StagePreset('linear-gradient(135deg,#0F2027,#2C5364)', 'Biển đêm', [Color(0xFF0F2027), Color(0xFF2C5364)]),
      const StagePreset('linear-gradient(135deg,#134E5E,#2F7D5B)', 'Rừng', [Color(0xFF134E5E), Color(0xFF2F7D5B)]),
      const StagePreset('linear-gradient(135deg,#3A1C71,#B4506A)', 'Hoàng hôn', [Color(0xFF3A1C71), Color(0xFFB4506A)]),
      const StagePreset('linear-gradient(135deg,#0B486B,#C4561C)', 'Bình minh', [Color(0xFF0B486B), Color(0xFFC4561C)]),
      const StagePreset('linear-gradient(135deg,#7F1D1D,#2A0C0C)', 'Đỏ trầm', [Color(0xFF7F1D1D), Color(0xFF2A0C0C)]),
      const StagePreset('linear-gradient(135deg,#141E30,#243B55)', 'Thép', [Color(0xFF141E30), Color(0xFF243B55)]),
      const StagePreset('linear-gradient(135deg,#FFFFFF,#E3EAF5)', 'Sáng xanh', [Color(0xFFFFFFFF), Color(0xFFE3EAF5)], light: true),
      const StagePreset('linear-gradient(135deg,#FFF9F0,#F8E1C6)', 'Sáng ấm', [Color(0xFFFFF9F0), Color(0xFFF8E1C6)], light: true),
      const StagePreset('#F7F8FA', 'Trắng', [Color(0xFFF7F8FA), Color(0xFFF7F8FA)], light: true),
    ];

/// Chuỗi CSS của một nền (TV dùng nguyên chuỗi; `brand:*` đổi theo màu nhấn).
String stageBgCss(String key, Color accent) {
  if (!key.startsWith('brand:')) return key;
  final p = stagePresets(accent).firstWhere((x) => x.key == key);
  return 'linear-gradient(135deg,${_hex(p.colors.first)},${_hex(p.colors.last)})';
}

/// Nền sáng (chữ tối) hay tối.
bool stageBgLight(String key, StageTheme t) {
  if (key.isEmpty) return t.light;
  for (final p in stagePresets(t.accent)) {
    if (p.key == key) return p.light;
  }
  return false;
}

/// Trang trí nền: ảnh > nền có sẵn > nền theo theme.
BoxDecoration stageBackground(String key, String image, StageTheme t) {
  if (image.startsWith('http') || image.startsWith('/')) {
    return BoxDecoration(color: Colors.black, image: DecorationImage(image: NetworkImage(pageAssetUrl(image)), fit: BoxFit.cover, opacity: .85));
  }
  for (final p in stagePresets(t.accent)) {
    if (p.key == key) return BoxDecoration(gradient: LinearGradient(colors: p.colors, begin: Alignment.topLeft, end: Alignment.bottomRight));
  }
  return BoxDecoration(color: t.bg);
}

/// Kích thước khung đang dựng (logic): ngang 1280 px, dọc (điện thoại) 600 px; trang con dùng để căn chỉnh.
class StageMetrics extends InheritedWidget {
  final StageTheme theme;
  final bool portrait;
  final Size size;
  const StageMetrics({super.key, required this.theme, required this.portrait, required this.size, required super.child});

  static StageMetrics? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StageMetrics>();

  /// Bảng màu của sân khấu (mặc định tối khi ngoài khung).
  static StageTheme themeOf(BuildContext context) => of(context)?.theme ?? const StageTheme();

  @override
  bool updateShouldNotify(StageMetrics old) => old.theme.light != theme.light || old.theme.accent != theme.accent || old.portrait != portrait || old.size != size;
}

/// Chip loại trang ở thanh đầu ("BÌNH CHỌN").
class StageTypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final StageTheme theme;
  const StageTypeChip({super.key, required this.icon, required this.label, required this.theme});
  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: theme.chip, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: theme.sub),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.text.withValues(alpha: .86), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
          ),
        ]),
      );
}

/// Viên thuốc ở thanh đầu / cuối (giờ, số người, cách tham gia).
class StagePill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final StageTheme theme;
  final bool accent;
  const StagePill(this.text, {super.key, this.icon, required this.theme, this.accent = false});
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: accent ? theme.accentSoft : theme.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: accent ? theme.accent : theme.text), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.text, fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ]),
      );
}

/// Chip người trình bày (ảnh chữ cái + tên).
class StagePresenterChip extends StatelessWidget {
  final String name, note;
  final StageTheme theme;
  const StagePresenterChip({super.key, required this.name, this.note = '', required this.theme});
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 4, right: 14),
        decoration: BoxDecoration(color: theme.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.accent,
            child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              note.isEmpty ? name : '$name · $note',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.text, fontSize: 14),
            ),
          ),
        ]),
      );
}

/// Khung sân khấu: dựng ở kích thước logic (ngang 1280, dọc 600) rồi co cho vừa ô, nên chữ / khoảng cách giữ đúng tỉ lệ
/// từ điện thoại tới TV. [bleed]: trang tự vẽ nền kín khung (Chào mừng), thanh đầu / cuối nổi lên trên; ngược lại trang nằm
/// trong vùng an toàn trên nền theo theme.
class StageFrame extends StatelessWidget {
  final StageTheme theme;
  final Widget child;
  final bool bleed;
  final Decoration? background;
  final List<Widget> headerLeading, headerTrailing, footer;
  const StageFrame({
    super.key,
    required this.theme,
    required this.child,
    this.bleed = false,
    this.background,
    this.headerLeading = const [],
    this.headerTrailing = const [],
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (!box.maxWidth.isFinite || !box.maxHeight.isFinite || box.maxWidth <= 0 || box.maxHeight <= 0) return child;
        final portrait = box.maxWidth < box.maxHeight * 1.05;
        // Dọc (điện thoại): dựng hẹp hơn để chữ của trang không bị co quá nhỏ.
        final lw = portrait ? 440.0 : 1280.0;
        final lh = lw * box.maxHeight / box.maxWidth;
        final side = portrait ? 16.0 : 56.0;
        final top = portrait ? 14.0 : 28.0;
        final hasHead = headerLeading.isNotEmpty || headerTrailing.isNotEmpty;
        final headH = hasHead ? (portrait ? 36.0 : 48.0) : 0.0;
        final footH = footer.isNotEmpty ? 36.0 : 0.0;
        final bottom = portrait ? 12.0 : 24.0;
        final bodyTop = hasHead ? top + headH + (portrait ? 10 : 24) : top;
        final bodyBottom = footer.isNotEmpty ? bottom + footH + (portrait ? 10 : 16) : bottom;
        // Điện thoại: chỉ chip loại trang + nút điều khiển (tên trang, người trình bày ẩn bớt để không tràn).
        final lead = portrait ? headerLeading.take(1) : headerLeading;
        final trail = portrait ? headerTrailing.skip(headerTrailing.length > 1 ? 1 : 0) : headerTrailing;
        final head = Row(children: [
          Expanded(
            child: Row(children: [
              for (final (i, w) in lead.indexed) ...[if (i > 0) const SizedBox(width: 14), w is Flexible ? w : Flexible(child: w)],
            ]),
          ),
          for (final w in trail) ...[const SizedBox(width: 10), w],
        ]);
        // Thanh cuối: các mục trước Spacer nằm trái và co lại (chữ …) khi hẹp; các mục sau Spacer nằm phải, giữ kích thước.
        final gap = portrait ? 8.0 : 14.0;
        final split = footer.indexWhere((w) => w is Spacer);
        final left = split < 0 ? footer : footer.sublist(0, split);
        final right = split < 0 ? const <Widget>[] : footer.sublist(split + 1);
        final foot = Row(children: [
          Expanded(
            child: Row(children: [
              for (final (i, w) in left.indexed) ...[if (i > 0) SizedBox(width: gap), Flexible(child: w)],
            ]),
          ),
          for (final w in right) ...[SizedBox(width: gap), w],
        ]);
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: lw,
            height: lh,
            child: StageMetrics(
              theme: theme,
              portrait: portrait,
              size: Size(lw, lh),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: theme.text, fontFeatures: const [FontFeature.tabularFigures()]),
                child: DecoratedBox(
                  decoration: background ?? BoxDecoration(color: theme.bg),
                  child: Stack(children: [
                    if (bleed)
                      Positioned.fill(child: child)
                    else
                      Positioned(left: side, right: side, top: bodyTop, bottom: bodyBottom, child: child),
                    if (hasHead) Positioned(left: side, right: side, top: top, height: headH, child: head),
                    if (footer.isNotEmpty) Positioned(left: side, right: side, bottom: bottom, height: footH, child: foot),
                  ]),
                ),
              ),
            ),
          ),
        );
      });
}

/// Chọn nền: bộ nền có sẵn (theo màu công ty, tối, sáng) + ảnh từ máy / Drive. Dùng chung cho Chào mừng, Chờ lượt,
/// Nội dung và Giao diện sân khấu.
class StageBackgroundPicker extends StatelessWidget {
  final CallService call;
  final StageTheme theme;
  final String value, image;
  final ValueChanged<String> onBg;
  final ValueChanged<String> onImage;
  const StageBackgroundPicker({super.key, required this.call, required this.theme, required this.value, required this.image, required this.onBg, required this.onImage});

  @override
  Widget build(BuildContext context) {
    final presets = stagePresets(theme.accent);
    final hasImage = image.isNotEmpty;
    Widget swatch(StagePreset p) {
      final on = !hasImage && value == p.key;
      return Tooltip(
        message: p.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onBg(p.key),
          child: Container(
            width: 54,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: p.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? Colors.white : Colors.white24, width: on ? 2.5 : 1),
            ),
            child: on ? Icon(Icons.check_rounded, size: 18, color: p.light ? const Color(0xFF141A23) : Colors.white) : null,
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Nền'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in presets) swatch(p),
        Tooltip(
          message: tr('Ảnh từ máy hoặc Drive'),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final u = await pickPageMedia(context, call, image: true);
              if (u != null) onImage(u);
            },
            child: Container(
              width: 54,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: hasImage ? Colors.white : Colors.white24, width: hasImage ? 2.5 : 1),
                image: hasImage ? DecorationImage(image: NetworkImage(pageAssetUrl(image)), fit: BoxFit.cover) : null,
              ),
              child: hasImage ? null : const Icon(Icons.add_photo_alternate_outlined, size: 18, color: Colors.white70),
            ),
          ),
        ),
      ]),
      if (hasImage)
        TextButton.icon(
          onPressed: () => onImage(''),
          icon: const Icon(Icons.close_rounded, size: 16),
          label: Text(tr('Bỏ ảnh nền')),
        ),
    ]);
  }
}

/// Giao diện sân khấu của cuộc họp (chủ trì) hoặc mặc định của công ty (quản trị hệ thống).
Future<void> showStageThemeEditor(BuildContext context, CallService call, {bool canCompany = false}) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF23262C),
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => _ThemeEditor(call: call, canCompany: canCompany),
    );

const _accents = [Color(0xFF3D7BFF), Color(0xFF0E9F8E), Color(0xFFC8102E), Color(0xFFE8710A), Color(0xFF7C4DFF), Color(0xFF1B5E20), Color(0xFFD81B60), Color(0xFF37474F)];

class _ThemeEditor extends StatefulWidget {
  final CallService call;
  final bool canCompany;
  const _ThemeEditor({required this.call, required this.canCompany});
  @override
  State<_ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<_ThemeEditor> {
  late final Map<String, dynamic> cfg = {...((widget.call.roomStage?['theme_cfg'] as Map?) ?? const {})}.cast<String, dynamic>();
  bool _company = false, _busy = false;

  StageTheme get _t => StageTheme.of(cfg);

  Future<void> _save() async {
    setState(() => _busy = true);
    final e = await widget.call.stageAct('config', {'theme': cfg, 'scope': _company ? 'company' : 'meeting'});
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) return meetToast(context, e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final bg = '${cfg['bg'] ?? ''}';
    final img = '${cfg['bg_image'] ?? ''}';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Giao diện sân khấu'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(tr('Khung chung của mọi trang trên sân khấu và TV'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: StageFrame(
              theme: t,
              background: bg.isEmpty && img.isEmpty ? null : stageBackground(bg, img, t),
              headerLeading: [StageTypeChip(icon: Icons.bar_chart_rounded, label: tr('Bình chọn'), theme: t), Text(tr('Câu 1 / 3'), style: TextStyle(color: t.sub, fontSize: 15))],
              headerTrailing: [StagePresenterChip(name: tr('Người trình bày'), note: tr('đang trình bày'), theme: t)],
              footer: [StagePill(tr('18 / 22 đã trả lời'), theme: t), const Spacer(), StagePill(tr('Trả lời trên app Flygo'), theme: t, accent: true), StagePill('00:24', theme: t)],
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Ngày nào bàn giao cho chủ đầu tư?'), style: TextStyle(color: t.text, fontSize: 46, fontWeight: FontWeight.w800)),
                const SizedBox(height: 40),
                for (final (i, w) in [.61, .28, .11].indexed) ...[
                  Container(
                    height: 22,
                    decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: w,
                      child: Container(decoration: BoxDecoration(color: t.series[i], borderRadius: BorderRadius.circular(11))),
                    ),
                  ),
                  const SizedBox(height: 34),
                ],
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(tr('Màu nhấn'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in _accents)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => cfg['accent'] = _hex(c)),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: t.accent == c ? Colors.white : Colors.transparent, width: 2.5)),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined), label: Text(tr('Tối'))),
            ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined), label: Text(tr('Sáng'))),
          ],
          selected: {t.light ? 'light' : 'dark'},
          onSelectionChanged: (v) => setState(() => cfg['mode'] = v.first),
        ),
        const SizedBox(height: 14),
        StageBackgroundPicker(
          call: widget.call,
          theme: t,
          value: bg,
          image: img,
          onBg: (k) => setState(() {
            cfg['bg'] = cfg['bg'] == k ? '' : k;
            cfg['bg_image'] = '';
          }),
          onImage: (u) => setState(() => cfg['bg_image'] = u),
        ),
        const SizedBox(height: 6),
        Text(tr('Để trống nền: dùng màu nền theo chế độ Tối / Sáng.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
