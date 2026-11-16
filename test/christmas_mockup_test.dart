// Ảnh mockup chủ đề Giáng sinh (chạy tay): XMAS_OUT=<thư mục> flutter test test/christmas_mockup_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/bubble_styles.dart';
import 'package:flygo_chat/ui/bubble_picker.dart';
import 'package:flygo_chat/ui/season/season.dart';
import 'package:flygo_chat/ui/season/season_art.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String path) => tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: tester.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    });

const _people = [('Lan Phạm', 0xFFE3A08A), ('Tuấn Vũ', 0xFF7FB7E6), ('Minh Anh', 0xFF9CCF8F), ('Hà My', 0xFFC7A6EE), ('Quang Huy', 0xFFF0C46A)];

Widget _avatar(String name, double size, {bool hat = true, int color = 0xFF7FB7E6}) {
  final initials = name.split(' ').map((w) => w[0]).take(2).join();
  return SantaHat(
    size: size,
    on: hat,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Color(color)),
      child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * .36)),
    ),
  );
}

BubbleStyle? _style(String id) => bubbleStyles.where((s) => s.id == id).firstOrNull;

/// Một tin: (người gửi hoặc null = mình, nội dung, kiểu bong bóng, giờ).
typedef _Msg = (int?, String, String?, String);

const _msgs = <_Msg>[
  (0, 'Chiều 24/12 liên hoan cuối năm ở sảnh tầng 3 nhé cả nhà', null, '09:12'),
  (1, 'Em mang loa với dây đèn ạ', 'caythong', '09:14'),
  (null, 'Ok, mình đặt bánh kem rồi', 'munoel', '09:15'),
  (null, 'Giáng sinh vui vẻ cả nhà!', 'munoel', '09:15'),
  (2, 'Merry Christmas!', 'chuong', '09:16'),
  (3, 'Ai làm ông già Noel phát quà vậy?', null, '09:18'),
];

class _ChatMock extends StatelessWidget {
  final Wallpaper? wallpaper;
  final bool lights, hats;
  final double t;
  final BurstKind? burst;
  final double burstP;
  final bool showHeader;
  const _ChatMock({this.wallpaper, this.lights = true, this.hats = true, this.t = 3.2, this.burst, this.burstP = .45, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final wp = wallpaper;
    final wpal = wp == null ? pal : wallpaperPal(wp);
    Widget bubble(_Msg m, bool first, bool last) {
      final mine = m.$1 == null;
      final st = m.$3 == null ? null : _style(m.$3!);
      final fill = mine ? (st?.color ?? pal.outBubble) : (st?.color ?? wpal.inBubble);
      final fg = st != null ? bubbleTextOn(fill) : (mine ? Colors.white : wpal.text);
      final body = StyledBubble(
        style: st,
        fill: fill,
        top: first,
        bottom: last,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: m.$2),
          TextSpan(text: '  ${m.$4}', style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: .7))),
        ]), style: TextStyle(fontSize: 15.5, color: fg, height: 1.3)),
      );
      if (mine) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(70, 2, 10, 2),
          child: Align(alignment: Alignment.centerRight, child: body),
        );
      }
      final p = _people[m.$1!];
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 60, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(width: 34, child: last ? _avatar(p.$1, 32, hat: hats, color: p.$2) : null),
          const SizedBox(width: 6),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (first)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 2, top: 14),
                  child: Text(p.$1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(p.$2))),
                ),
              body,
            ]),
          ),
        ]),
      );
    }

    final rows = <Widget>[
      Center(
        child: Container(
          margin: const EdgeInsets.only(top: 40, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: (wp?.dark ?? Theme.of(context).brightness == Brightness.dark) ? const Color(0x66000000) : const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(10)),
          child: Text('Hôm nay', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: wpal.text)),
        ),
      ),
      for (var i = 0; i < _msgs.length; i++)
        bubble(_msgs[i], i == 0 || _msgs[i - 1].$1 != _msgs[i].$1, i == _msgs.length - 1 || _msgs[i + 1].$1 != _msgs[i].$1),
      const SizedBox(height: 8),
    ];

    final chat = Stack(children: [
      Positioned.fill(child: wp == null ? Container(color: pal.chatBg) : WallpaperView(wallpaper: wp, frozenT: t)),
      Positioned.fill(child: ListView(reverse: false, padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), children: [
        const SizedBox(height: 0),
        ...rows,
      ])),
      if (lights) Positioned(left: 0, right: 0, top: 0, child: LightString(frozenT: t)),
      if (burst != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: BurstPainter(burstP, burst!)))),
    ]);

    return Column(children: [
      if (showHeader)
        Container(
          color: pal.surface,
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(children: [
            IconButton(onPressed: () {}, icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: pal.accent)),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2E7D32)),
              child: const Icon(Icons.groups_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Phòng Kinh doanh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
                Text('8 thành viên', style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
            ),
            Icon(Icons.call_outlined, color: pal.accent),
            const SizedBox(width: 14),
            Icon(Icons.more_vert_rounded, color: pal.accent),
          ]),
        ),
      Expanded(child: ClipRect(child: chat)),
      Container(
        color: pal.surface,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
        child: Row(children: [
          Icon(Icons.add_circle_outline_rounded, color: pal.sub),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(19)),
              child: Text('Nhắn tin', style: TextStyle(color: pal.sub, fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.mic_none_rounded, color: pal.sub),
        ]),
      ),
    ]);
  }
}

/// Máy tính: cột danh sách chat bên trái + khung chat.
class _DesktopChat extends StatelessWidget {
  final Wallpaper? wallpaper;
  final BurstKind? burst;
  const _DesktopChat({this.wallpaper, this.burst});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget row(String name, String last, int color, {bool sel = false, bool group = false}) => Container(
          color: sel ? pal.chipSelBg : null,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            group
                ? Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2E7D32)),
                    child: const Icon(Icons.groups_rounded, color: Colors.white))
                : _avatar(name, 44, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: sel ? pal.chipSelFg : pal.text)),
                Text(last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: sel ? pal.chipSelFg.withValues(alpha: .8) : pal.sub)),
              ]),
            ),
          ]),
        );
    return Row(children: [
      Container(
        width: 320,
        color: pal.surface,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(children: [
              Text('Chat', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pal.text)),
              const Spacer(),
              Icon(Icons.edit_square, color: pal.accent),
            ]),
          ),
          row('Phòng Kinh doanh', 'Hà My: Ai làm ông già Noel phát quà vậy?', 0, sel: true, group: true),
          for (final p in _people) row(p.$1, 'Dạ vâng ạ', p.$2),
        ]),
      ),
      VerticalDivider(width: 1, color: pal.divider),
      Expanded(child: _ChatMock(wallpaper: wallpaper, burst: burst, burstP: .5)),
    ]);
  }
}

class _HomeMock extends StatelessWidget {
  final bool desktop;
  const _HomeMock({this.desktop = false});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget tile(IconData i, String label) => SizedBox(
          width: 94,
          child: Column(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: const Color(0xFF1E7BFF), borderRadius: BorderRadius.circular(16)),
              child: Icon(i, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 13, color: pal.text)),
          ]),
        );
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 50),
      Center(child: Text('Công ty Mẫu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text))),
      const SizedBox(height: 4),
      XmasBanner(now: DateTime(2026, 12, 10, 9), onClose: () {}),
      // Dải "Sắp diễn ra" sẵn có vẫn hiện ngay dưới.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(color: dark ? const Color(0xFF17305A) : const Color(0xFFE3EEFF), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.event_rounded, size: 22, color: dark ? const Color(0xFF4C97FF) : const Color(0xFF1E7BFF)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Họp tổng kết năm', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.text)),
                Text('Hôm nay 14:30–16:00', style: TextStyle(fontSize: 12, color: pal.sub)),
              ]),
            ),
            Text('còn 5 giờ 30 phút', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: dark ? const Color(0xFF4C97FF) : const Color(0xFF1E7BFF))),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(runSpacing: 18, children: [
          tile(Icons.chat_bubble_rounded, 'Chat'),
          tile(Icons.campaign_rounded, 'Bảng tin'),
          tile(Icons.event_rounded, 'Lịch'),
          tile(Icons.videocam_rounded, 'Họp'),
        ]),
      ),
    ]);
    return Container(
      color: pal.bg,
      child: desktop ? Center(child: SizedBox(width: 560, child: body)) : body,
    );
  }
}

/// Sheet "Giao diện chat": 3 tab, đang ở tab Hình nền.
class _AppearanceSheet extends StatelessWidget {
  final bool desktop;
  const _AppearanceSheet({this.desktop = false});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sel = dark ? 'demnoel' : 'tuyettrang';
    Widget tile(Widget art, String name, {bool on = false, bool soon = false}) => SizedBox(
          width: 88,
          child: Column(children: [
            Container(
              width: 80,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? pal.accent : pal.divider, width: on ? 3 : 1),
              ),
              padding: EdgeInsets.all(on ? 3 : 1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  art,
                  if (soon)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: .5),
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        child: const Text('Sắp có', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ),
                  if (on) const Positioned(right: 6, bottom: 6, child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 22)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: pal.text)),
          ]),
        );
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: pal.text)),
        );
    Widget sw(String title, String sub, bool v) => SwitchListTile(
          value: v,
          onChanged: (_) {},
          title: Text(title, style: TextStyle(fontSize: 15, color: pal.text)),
          subtitle: Text(sub, style: TextStyle(fontSize: 12.5, color: pal.sub)),
        );
    final tabs = Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        for (final (i, t) in ['Màu chat', 'Bong bóng', 'Hình nền'].indexed)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: i == 2 ? BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)]) : null,
              child: Text(t, style: TextStyle(fontSize: 14, fontWeight: i == 2 ? FontWeight.w700 : FontWeight.w500, color: i == 2 ? pal.text : pal.sub)),
            ),
          ),
      ]),
    );
    final picker = ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text('Chỉ mình thấy, riêng chat này. Màu bong bóng và chữ giữ nguyên.', style: TextStyle(fontSize: 13, color: pal.sub)),
      ),
      section('Giáng sinh'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Wrap(spacing: 4, runSpacing: 12, children: [
          for (final w in wallpapers) tile(WallpaperView(wallpaper: w, frozenT: 2.4), w.name, on: w.id == sel),
          tile(Container(color: const Color(0xFFB71C1C), child: const Center(child: Icon(Icons.local_florist_rounded, color: Color(0xFFFFD54F), size: 34))), 'Tết', soon: true),
          tile(Container(color: const Color(0xFF283593), child: const Center(child: Icon(Icons.nightlight_round, color: Color(0xFFFFE082), size: 34))), 'Trung thu', soon: true),
        ]),
      ),
      section('Cơ bản'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Wrap(spacing: 4, runSpacing: 12, children: [
          tile(Container(color: pal.chatBg, child: Center(child: Icon(Icons.chat_bubble_outline_rounded, color: pal.sub))), 'Mặc định'),
          tile(Container(color: dark ? const Color(0xFF1F2933) : const Color(0xFFE8EEF4)), 'Màu trơn'),
          tile(Container(color: pal.surface2, child: Center(child: Icon(Icons.add_photo_alternate_outlined, color: pal.sub, size: 30))), 'Ảnh của mình'),
        ]),
      ),
      const SizedBox(height: 8),
      Divider(color: pal.divider, height: 24),
      sw('Hiệu ứng động', 'Tuyết rơi, đèn nhấp nháy. Tự tắt khi bật giảm chuyển động / tiết kiệm pin.', true),
      sw('Dây đèn trên khung chat', 'Mọi chat, trong mùa Giáng sinh', true),
      const SizedBox(height: 24),
    ]);
    final sheet = Material(
      color: pal.surface,
      borderRadius: BorderRadius.vertical(top: const Radius.circular(20), bottom: Radius.circular(desktop ? 20 : 0)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        if (!desktop) Container(margin: const EdgeInsets.only(top: 8), width: 38, height: 4, decoration: BoxDecoration(color: pal.divider, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Row(children: [
            Expanded(child: Text('Giao diện chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: pal.text))),
            TextButton(onPressed: () {}, child: const Text('Xong', style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
        tabs,
        Expanded(child: picker),
      ]),
    );
    if (desktop) {
      return Stack(children: [
        const Positioned.fill(child: _DesktopChat()),
        Positioned.fill(child: Container(color: Colors.black45)),
        Center(child: SizedBox(width: 520, height: 680, child: sheet)),
      ]);
    }
    return Stack(children: [
      Positioned.fill(child: _ChatMock(wallpaper: wallpaperById(sel), lights: true)),
      Positioned.fill(child: Container(color: Colors.black38)),
      Positioned(left: 0, right: 0, bottom: 0, height: 700, child: sheet),
    ]);
  }
}

/// Cài đặt cá nhân > Mùa lễ hội: tắt từng phần, hoặc tắt hẳn.
class _SeasonSettings extends StatelessWidget {
  const _SeasonSettings();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget sw(IconData i, String title, String? sub, bool v, {bool enabled = true}) => SwitchListTile(
          value: v,
          onChanged: enabled ? (_) {} : null,
          secondary: Icon(i, color: pal.accent),
          title: Text(title, style: TextStyle(fontSize: 15, color: pal.text)),
          subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12.5, color: pal.sub)),
        );
    Widget card(List<Widget> c) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Material(color: pal.surface, borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias, child: Column(children: c)),
        );
    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 44, 16, 8),
          child: Row(children: [
            IconButton(onPressed: () {}, icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: pal.accent)),
            Text('Mùa lễ hội', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: pal.text)),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [Color(0xFFB3202A), Color(0xFF0F4D2E)]),
          ),
          child: Row(children: [
            CustomPaint(size: const Size(34, 40), painter: MiniTreePainter(1)),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Giáng sinh đang bật', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 2),
                Text('Công ty bật từ 01/12 đến 26/12, sau đó tự tắt.', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
        card([sw(Icons.celebration_outlined, 'Dùng giao diện mùa lễ', 'Tắt mục này là tắt hết bên dưới, chỉ trên máy của mình', true)]),
        card([
          sw(Icons.wallpaper_rounded, 'Hình nền mặc định', 'Đêm Noel (tối) · Tuyết trắng (sáng). Chat đã tự chọn hình nền thì giữ nguyên', true),
          Divider(height: 1, color: pal.divider, indent: 56),
          sw(Icons.light_rounded, 'Dây đèn trên khung chat', null, true),
          Divider(height: 1, color: pal.divider, indent: 56),
          sw(Icons.face_retouching_natural_rounded, 'Hiện mũ Noel trên ảnh đại diện', 'Chỉ tháng 12, trên máy của mình', true),
          Divider(height: 1, color: pal.divider, indent: 56),
          sw(Icons.person_outline_rounded, 'Đội mũ cho ảnh của mình', 'Tắt thì mọi người thấy ảnh mình không có mũ', true),
          Divider(height: 1, color: pal.divider, indent: 56),
          sw(Icons.auto_awesome_rounded, 'Hiệu ứng khi có lời chúc', '"Giáng sinh vui vẻ", "Merry Christmas", "Noel"', true),
          Divider(height: 1, color: pal.divider, indent: 56),
          sw(Icons.home_outlined, 'Banner ở Trang chủ', 'Đếm ngược đến 24/12', true),
        ]),
        card([sw(Icons.animation_rounded, 'Hiệu ứng động', 'Tự tắt khi máy bật giảm chuyển động hoặc tiết kiệm pin', true)]),
      ]),
    );
  }
}

/// Quản trị > Giao diện mùa lễ (quản trị viên Flygo ID của công ty).
class _AdminSeason extends StatelessWidget {
  const _AdminSeason();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget season(String name, String range, String status, bool on, Color c, IconData i, {bool soon = false}) => Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? c.withValues(alpha: .6) : pal.divider)),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)), child: Icon(i, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: pal.text)),
                Text(range, style: TextStyle(fontSize: 13, color: pal.sub)),
                const SizedBox(height: 3),
                Text(status, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? const Color(0xFF2E9D57) : pal.sub)),
              ]),
            ),
            Switch(value: on, onChanged: soon ? null : (_) {}),
          ]),
        );
    Widget check(String t, bool v) => CheckboxListTile(
          dense: true,
          value: v,
          onChanged: (_) {},
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(t, style: TextStyle(fontSize: 14.5, color: pal.text)),
        );
    return Container(
      color: pal.bg,
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 44, 16, 4),
          child: Row(children: [
            IconButton(onPressed: () {}, icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: pal.accent)),
            Expanded(child: Text('Giao diện mùa lễ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: pal.text))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Text('Bật một lần, áp dụng cho cả công ty. Đến ngày tự bật, hết ngày tự tắt, năm sau lặp lại. Mỗi người vẫn tự tắt được trong Cài đặt.',
              style: TextStyle(fontSize: 13, color: pal.sub, height: 1.35)),
        ),
        season('Giáng sinh', '01/12 – 26/12 hằng năm', 'Đã bật · tự bật lúc 00:00 01/12', true, const Color(0xFFC62828), Icons.park_rounded),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(color: pal.surface, borderRadius: BorderRadius.circular(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text('Mặc định cho mọi người', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: pal.sub)),
            ),
            check('Hình nền Đêm Noel / Tuyết trắng', true),
            check('Dây đèn trên khung chat', true),
            check('Mũ Noel trên ảnh đại diện (chỉ tháng 12)', true),
            check('Hiệu ứng khi có lời chúc', true),
            check('Banner + đếm ngược ở Trang chủ', true),
            const SizedBox(height: 6),
          ])),
        ),
        season('Tết Nguyên đán', 'Theo âm lịch (2027: 26/01 – 14/02)', 'Sắp có', false, const Color(0xFFD84315), Icons.local_florist_rounded, soon: true),
        season('Trung thu', 'Theo âm lịch', 'Sắp có', false, const Color(0xFF3949AB), Icons.nightlight_round, soon: true),
      ]),
    );
  }
}

void main() {
  final out = Platform.environment['XMAS_OUT'];
  final xmasNow = Wallpaper('x', '', '', dark: true, painter: NoelNightPainter.new); // giữ import season_art khi lọc
  assert(xmasNow.dark);

  Future<void> render(WidgetTester tester, String name, Size size, bool dark, Widget child) async {
    await _fonts();
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        home: Scaffold(body: child),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await _shot(tester, key, '$out/$name-${dark ? 'dark' : 'light'}.png');
  }

  const phone = Size(390, 844), desktop = Size(1280, 800);
  for (final dark in [false, true]) {
    final wp = wallpaperById(dark ? 'demnoel' : 'tuyettrang');
    final mode = dark ? 'dark' : 'light';
    testWidgets('chat phone $mode', (t) async {
      if (out != null) await render(t, '01-chat-phone', phone, dark, _ChatMock(wallpaper: wp));
    });
    testWidgets('chat phone other wallpaper $mode', (t) async {
      // Hình nền ngược chế độ máy: Tuyết trắng khi máy tối / Đêm Noel khi máy sáng.
      if (out != null) await render(t, '02-chat-phone-alt', phone, dark, _ChatMock(wallpaper: wallpaperById(dark ? 'tuyettrang' : 'demnoel')));
    });
    testWidgets('chat desktop $mode', (t) async {
      if (out != null) await render(t, '03-chat-desktop', desktop, dark, _DesktopChat(wallpaper: wp));
    });
    testWidgets('effect phone $mode', (t) async {
      if (out != null) await render(t, '04-effect-phone', phone, dark, _ChatMock(wallpaper: wp, burst: dark ? BurstKind.snow : BurstKind.gifts));
    });
    testWidgets('effect desktop $mode', (t) async {
      if (out != null) await render(t, '05-effect-desktop', desktop, dark, _DesktopChat(wallpaper: wp, burst: dark ? BurstKind.gifts : BurstKind.snow));
    });
    testWidgets('home phone $mode', (t) async {
      if (out != null) await render(t, '06-home-phone', phone, dark, const _HomeMock());
    });
    testWidgets('home desktop $mode', (t) async {
      if (out != null) await render(t, '07-home-desktop', desktop, dark, const _HomeMock(desktop: true));
    });
    testWidgets('appearance sheet phone $mode', (t) async {
      if (out != null) await render(t, '08-sheet-phone', phone, dark, const _AppearanceSheet());
    });
    testWidgets('appearance sheet desktop $mode', (t) async {
      if (out != null) await render(t, '09-sheet-desktop', desktop, dark, const _AppearanceSheet(desktop: true));
    });
    testWidgets('season settings $mode', (t) async {
      if (out != null) await render(t, '10-season-settings-phone', phone, dark, const _SeasonSettings());
    });
    testWidgets('appearance sheet tall $mode', (t) async {
      if (out != null) await render(t, '08b-sheet-phone-full', const Size(390, 1100), dark, const _AppearanceSheet());
    });
    testWidgets('hats close-up $mode', (t) async {
      if (out == null) return;
      final pal = dark ? Pal.dark : Pal.light;
      await render(t, '12-hats', const Size(420, 200), dark, Container(
        color: pal.bg,
        alignment: Alignment.center,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, sz) in [24.0, 32.0, 44.0, 64.0, 96.0].indexed) _avatar(_people[i].$1, sz, color: _people[i].$2),
        ]),
      ));
    });
    testWidgets('admin $mode', (t) async {
      if (out != null) await render(t, '11-admin-phone', phone, dark, const _AdminSeason());
    });
  }

  test('lời chúc Giáng sinh', () {
    for (final s in ['Giáng sinh vui vẻ cả nhà!', 'giang sinh vui ve', 'MERRY CHRISTMAS', 'Merry Xmas', 'Chúc mừng Noel']) {
      expect(isXmasGreeting(s), isTrue, reason: s);
    }
    for (final s in ['Noelia gửi file', 'Giáng sinh năm nay nghỉ mấy ngày?', 'merry go round']) {
      expect(isXmasGreeting(s), isFalse, reason: s);
    }
  });

  test('khung ngày mùa lễ', () {
    final x = seasons.first;
    expect(x.activeOn(DateTime(2026, 11, 30)), isFalse);
    expect(x.activeOn(DateTime(2026, 12, 1)), isTrue);
    expect(x.activeOn(DateTime(2026, 12, 26)), isTrue);
    expect(x.activeOn(DateTime(2026, 12, 27)), isFalse);
  });
}
