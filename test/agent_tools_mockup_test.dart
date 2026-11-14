// Mockup (chỉ để duyệt thiết kế, chưa phải giao diện thật) cho Artifacts, Nghiên cứu sâu, Kiến thức dự án,
// Trò chuyện bằng giọng nói, MCP & Tiện ích. Chạy tay: MK_OUT=<thư mục> flutter test test/agent_tools_mockup_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/chat_themes.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f.startsWith('/') || f.startsWith('assets') ? f : '$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  await load('JetBrains Mono', ['assets/fonts/JetBrainsMono-Regular.ttf']);
}

const _orange = Color(0xFFD97757);

void main() {
  final out = Platform.environment['MK_OUT'];

  Future<void> shot(WidgetTester t, String name, Size size, Widget Function(BuildContext c, Pal pal) build, {bool dark = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    final theme = buildTheme(dark ? Brightness.dark : Brightness.light);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(builder: (c) {
        final pal = claudePal(Pal.of(c), dark);
        return Theme(
          data: theme.copyWith(extensions: [pal], scaffoldBackgroundColor: pal.bg),
          child: RepaintBoundary(key: key, child: Material(color: pal.bg, child: Builder(builder: (c) => build(c, pal)))),
        );
      }),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  }

  Widget card(Pal pal, Widget child, {EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Color.alphaBlend(pal.text.withValues(alpha: .035), pal.bg),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.text.withValues(alpha: .09)),
        ),
        child: child,
      );
  Widget chip(Pal pal, String t, {IconData? icon, Color? color}) => Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: (color ?? pal.text).withValues(alpha: .07), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color ?? pal.sub), const SizedBox(width: 4)],
          Text(t, style: TextStyle(fontSize: 12.5, color: color ?? pal.sub)),
        ]),
      );
  Widget btn(Pal pal, String t, IconData i, {bool primary = false}) => Container(
        margin: const EdgeInsets.only(right: 6, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: primary ? _orange.withValues(alpha: .14) : pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: primary ? _orange : pal.text),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary ? _orange : pal.text)),
        ]),
      );
  Widget userMsg(Pal pal, String t) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: pal.text.withValues(alpha: .07), borderRadius: BorderRadius.circular(18)),
          child: Text(t, style: TextStyle(fontSize: 15.5, color: pal.text)),
        ),
      );
  TextStyle body(Pal pal) => TextStyle(fontSize: 15.5, height: 1.55, color: pal.text);

  // ---- thẻ Nghiên cứu sâu
  Widget research(Pal pal) => card(
        pal,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.travel_explore_rounded, color: _orange, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Nghiên cứu sâu · xong', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text))),
            Text('31 lượt tìm · 23 nguồn · 6 phút', style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ]),
          const SizedBox(height: 10),
          Wrap(children: [
            for (final (d, n) in [('vneconomy.vn', 4), ('gso.gov.vn', 3), ('statista.com', 3), ('mitsubishielectric.com', 2), ('reuters.com', 2), ('+8 trang khác', 0)])
              chip(pal, n > 0 ? '$d · $n' : d, icon: n > 0 ? Icons.public : null),
          ]),
          const SizedBox(height: 4),
          Text('Kế hoạch: 1) quy mô thị trường 2023–2026 · 2) thị phần hãng · 3) nhu cầu theo phân khúc · 4) giá & bảo trì',
              style: TextStyle(fontSize: 12.5, color: pal.sub)),
          const SizedBox(height: 12),
          Text('Tóm tắt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(style: body(pal), children: [
              const TextSpan(text: 'Thị trường thang máy Việt Nam ước đạt khoảng 18.000 thang lắp mới năm 2025, tăng 6–8%/năm '),
              WidgetSpan(child: _cite(pal, 1)),
              const TextSpan(text: '. Phân khúc nhà ở cao tầng chiếm hơn một nửa nhu cầu '),
              WidgetSpan(child: _cite(pal, 2)),
              const TextSpan(text: ', còn thang gia đình tăng nhanh nhất ở các đô thị loại 1 '),
              WidgetSpan(child: _cite(pal, 3)),
              const TextSpan(text: '.'),
            ]),
          ),
          const SizedBox(height: 10),
          Text('NGUỒN', style: TextStyle(fontSize: 11.5, letterSpacing: .6, fontWeight: FontWeight.w700, color: pal.sub)),
          for (final (i, s) in [
            'Thị trường thang máy 2025 — vneconomy.vn',
            'Niên giám thống kê xây dựng — gso.gov.vn',
            'Elevator market Vietnam — statista.com',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                _cite(pal, i + 1),
                const SizedBox(width: 6),
                Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.accentText))),
              ]),
            ),
          Wrap(children: [
            btn(pal, 'Mở báo cáo đầy đủ', Icons.article_outlined, primary: true),
            btn(pal, 'Xuất PDF', Icons.picture_as_pdf_outlined),
            btn(pal, 'Sao chép', Icons.copy_rounded),
          ]),
        ]),
      );

  // ---- thẻ Artifact
  Widget artifact(Pal pal, {double height = 260}) => card(
        pal,
        padding: EdgeInsets.zero,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: _orange.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.insert_chart_outlined_rounded, size: 18, color: _orange),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Thị phần thang máy 2025', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text)),
                  Text('Artifact · HTML tương tác · phiên bản 2', style: TextStyle(fontSize: 12, color: pal.sub)),
                ]),
              ),
              chip(pal, 'v2', icon: Icons.history_rounded),
              Icon(Icons.open_in_full_rounded, size: 19, color: pal.sub),
              const SizedBox(width: 6),
            ]),
          ),
          Container(
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.text.withValues(alpha: .08))),
            child: CustomPaint(painter: _BarChart(), child: const SizedBox.expand()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
            child: Wrap(children: [
              btn(pal, 'Toàn màn hình', Icons.fullscreen_rounded, primary: true),
              btn(pal, 'Mở trong trình duyệt', Icons.open_in_browser_rounded),
              btn(pal, 'Sao chép HTML', Icons.code_rounded),
              btn(pal, 'Chia sẻ link', Icons.ios_share_rounded),
            ]),
          ),
        ]),
      );

  // ---- mục Kiến thức dự án (cột phải)
  Widget knowledge(Pal pal) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 4, 6),
          child: Row(children: [
            Icon(Icons.menu_book_outlined, size: 16, color: pal.sub),
            const SizedBox(width: 6),
            Expanded(child: Text('Kiến thức dự án', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.sub))),
            Text('4 tệp · 2,1 MB', style: TextStyle(fontSize: 12, color: pal.sub)),
          ]),
        ),
        card(
          pal,
          padding: const EdgeInsets.symmetric(vertical: 6),
          Column(children: [
            for (final (n, s, i) in [
              ('Quy trình bảo trì thang.pdf', '820 KB · mọi phiên dùng chung', Icons.picture_as_pdf_outlined),
              ('Bảng giá linh kiện 2026.xlsx', '310 KB', Icons.table_chart_outlined),
              ('Hướng dẫn xưng hô khách.md', '4 KB', Icons.description_outlined),
              ('Hợp đồng mẫu.docx', '1 MB', Icons.article_outlined),
            ])
              ListTile(
                dense: true,
                leading: Icon(i, color: _orange),
                title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: pal.text)),
                subtitle: Text(s, style: TextStyle(fontSize: 12, color: pal.sub)),
                trailing: Icon(Icons.more_horiz, color: pal.sub),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(children: [
                const Icon(Icons.upload_file_rounded, size: 18, color: _orange),
                const SizedBox(width: 8),
                Text('Tải tài liệu lên (kéo thả được)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _orange)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
          child: Text('Mọi phiên trong dự án tự đọc các tài liệu này khi cần. Sửa / xoá ở đây là cập nhật cho cả dự án.',
              style: TextStyle(fontSize: 12, height: 1.35, color: pal.sub)),
        ),
      ]);

  Widget panelHead(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 4, 6),
        child: Row(children: [
          Icon(Icons.tune_rounded, size: 16, color: pal.sub),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.sub)),
        ]),
      );

  testWidgets('mockup công cụ agent', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);

    // 1. Máy tính: chat với Nghiên cứu + Artifact, cột phải có Kiến thức dự án.
    await shot(t, 'tools-desktop', const Size(1280, 1240), (c, pal) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 20, 40, 20),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  userMsg(pal, 'Nghiên cứu thị trường thang máy Việt Nam 2026, vẽ biểu đồ thị phần các hãng'),
                  Row(children: [
                    chip(pal, 'Nghiên cứu sâu', icon: Icons.travel_explore_rounded, color: _orange),
                    chip(pal, 'Dùng kiến thức dự án', icon: Icons.menu_book_outlined),
                  ]),
                  const SizedBox(height: 6),
                  research(pal),
                  const SizedBox(height: 14),
                  Text('Em đã dựng biểu đồ thị phần, bấm vào cột để xem số liệu từng hãng:', style: body(pal)),
                  const SizedBox(height: 8),
                  artifact(pal),
                ]),
              ),
            ),
          ),
        ),
        Container(width: .5, height: 1240, color: pal.divider),
        SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Nghiên cứu thị trường', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: pal.text)),
              panelHead(pal, 'Thao tác'),
              card(pal, padding: const EdgeInsets.symmetric(vertical: 4), Column(children: [
                for (final (i, l) in [
                  (Icons.hub_outlined, 'Kết nối agent từ xa'),
                  (Icons.extension_outlined, 'MCP & tiện ích của agent'),
                  (Icons.call_split, 'Tách phiên (fork)'),
                  (Icons.edit_outlined, 'Đổi tên'),
                ])
                  ListTile(dense: true, leading: Icon(i, size: 20, color: pal.text.withValues(alpha: .75)), title: Text(l, style: TextStyle(fontSize: 14.5, color: pal.text))),
              ])),
              knowledge(pal),
              panelHead(pal, 'Artifacts của phiên'),
              card(pal, padding: const EdgeInsets.symmetric(vertical: 4), Column(children: [
                for (final (n, s) in [('Thị phần thang máy 2025', 'v2 · 15:42'), ('Báo cáo nghiên cứu (HTML)', 'v1 · 15:40')])
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.web_asset_rounded, color: _orange),
                    title: Text(n, style: TextStyle(fontSize: 14, color: pal.text)),
                    subtitle: Text(s, style: TextStyle(fontSize: 12, color: pal.sub)),
                  ),
              ])),
            ]),
          ),
        ),
      ]);
    });

    // 2. Điện thoại: menu + có mục mới; ô nhập có chip Nghiên cứu sâu.
    await shot(t, 'tools-phone-plus', const Size(390, 844), (c, pal) {
      return Column(children: [
        Expanded(
          child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              userMsg(pal, 'Làm cho anh trang tính giá bảo trì'),
              Text('Em làm xong rồi, Sếp thử luôn trong khung dưới:', style: body(pal)),
              const SizedBox(height: 8),
              artifact(pal, height: 128),
            ]),
          ))),
        ),
        Container(
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 16)],
          ),
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: pal.sub.withValues(alpha: .4), borderRadius: BorderRadius.circular(2))),
            for (final (i, l, s, isNew) in [
              (Icons.travel_explore_rounded, 'Nghiên cứu sâu', 'Tìm nhiều nguồn, báo cáo có trích dẫn', true),
              (Icons.graphic_eq_rounded, 'Trò chuyện bằng giọng nói', 'Nói với trợ lý, nghe trả lời', true),
              (Icons.menu_book_outlined, 'Kiến thức dự án', 'Tài liệu dùng chung cho mọi phiên', true),
              (Icons.attach_file_rounded, 'Ảnh / tệp', '', false),
              (Icons.alternate_email, 'Tag chat, luồng, agent', '', false),
            ])
              ListTile(
                leading: Icon(i, color: isNew ? _orange : pal.text),
                title: Row(children: [
                  Text(l, style: TextStyle(fontSize: 15.5, color: pal.text)),
                  if (isNew) ...[const SizedBox(width: 6), chip(pal, 'mới', color: _orange)],
                ]),
                subtitle: s.isEmpty ? null : Text(s, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ),
            Container(
              margin: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(border: Border.all(color: pal.text.withValues(alpha: .12)), borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                chip(pal, 'Nghiên cứu sâu', icon: Icons.travel_explore_rounded, color: _orange),
                Expanded(child: Text('Hỏi trợ lý…', style: TextStyle(color: pal.sub))),
                const Icon(Icons.graphic_eq_rounded, color: _orange),
              ]),
            ),
          ]),
        ),
      ]);
    });

    // 3. Điện thoại: chế độ giọng nói.
    await shot(t, 'tools-phone-voice', const Size(390, 844), dark: true, (c, pal) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        child: Column(children: [
          Row(children: [
            Icon(Icons.keyboard_arrow_down_rounded, color: pal.text),
            const Spacer(),
            Text('Trò chuyện bằng giọng nói', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)),
            const Spacer(),
            Icon(Icons.closed_caption_outlined, color: pal.text),
          ]),
          const Spacer(),
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [_orange, _orange.withValues(alpha: .35), Colors.transparent], stops: const [.45, .75, 1]),
            ),
          ),
          const SizedBox(height: 28),
          Text('Đang nghe…', style: TextStyle(fontSize: 18, color: pal.text, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text('“Kiểm tra giúp anh thang số 3 tòa B tuần này đã bảo trì chưa”', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: pal.sub)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final (i, l, bg) in [
              (Icons.mic_off_rounded, 'Tắt mic', pal.text.withValues(alpha: .12)),
              (Icons.volume_up_rounded, 'Đọc trả lời', _orange.withValues(alpha: .25)),
              (Icons.close_rounded, 'Kết thúc', const Color(0xFFD32F2F)),
            ])
              Column(children: [
                Container(width: 62, height: 62, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(i, color: Colors.white)),
                const SizedBox(height: 6),
                Text(l, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
          ]),
        ]),
      );
    });

    // 4. Trang chủ > Cá nhân > MCP & tiện ích (máy tính).
    Widget mcpItem(Pal pal, String name, String desc, IconData icon, bool on, List<String> agents) => card(
          pal,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: _orange.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                const SizedBox(height: 6),
                Wrap(children: [for (final a in agents) chip(pal, a, icon: Icons.smart_toy_outlined)]),
              ]),
            ),
            Switch(value: on, onChanged: (_) {}, activeTrackColor: _orange),
          ]),
        );
    Widget catalogItem(Pal pal, String name, String desc, IconData icon, {bool installed = false}) => card(
          pal,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: _orange),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text))),
            ]),
            const SizedBox(height: 4),
            Text(desc, maxLines: 2, style: TextStyle(fontSize: 12.5, height: 1.35, color: pal.sub)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: installed ? pal.text.withValues(alpha: .07) : _orange, borderRadius: BorderRadius.circular(20)),
              child: Text(installed ? 'Đã cài' : 'Cài 1 chạm',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: installed ? pal.sub : Colors.white)),
            ),
          ]),
        );
    final installed = [
      ('Google Drive', 'Đọc / tìm tài liệu trên Drive của bạn', Icons.add_to_drive_outlined, true, ['@my-claude', '@my-codex']),
      ('GitHub', 'Đọc repo, issue, PR', Icons.code_rounded, true, ['@my-claude']),
      ('Postgres (máy chủ kế toán)', 'Truy vấn chỉ đọc · cần mật khẩu', Icons.storage_rounded, false, ['@my-codex']),
    ];
    final catalog = [
      ('Gmail', 'Đọc và soạn thư nháp', Icons.mail_outline_rounded, false),
      ('Google Calendar', 'Xem lịch, tạo cuộc hẹn', Icons.event_outlined, false),
      ('Notion', 'Đọc / ghi trang Notion', Icons.notes_rounded, false),
      ('Figma', 'Đọc thiết kế, xuất ảnh', Icons.design_services_outlined, false),
      ('GitHub', 'Đọc repo, issue, PR', Icons.code_rounded, true),
      ('MCP tuỳ chỉnh', 'Dán URL máy chủ MCP hoặc lệnh npx', Icons.add_link_rounded, false),
    ];
    await shot(t, 'mcp-desktop', const Size(1180, 900), (c, pal) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.arrow_back, color: pal.text),
            const SizedBox(width: 12),
            Text('MCP & tiện ích', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
            const Spacer(),
            Text('Trang chủ › Cá nhân', style: TextStyle(fontSize: 13, color: pal.sub)),
          ]),
          const SizedBox(height: 6),
          Text('Công cụ cài ở đây dùng được cho các trợ lý của bạn. Khoá bí mật chỉ lưu trên máy chạy trợ lý, không lưu trên máy chủ chat.',
              style: TextStyle(fontSize: 13.5, color: pal.sub)),
          const SizedBox(height: 18),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ĐÃ CÀI (3)', style: TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: pal.sub)),
                  const SizedBox(height: 8),
                  for (final (n, d, i, on, a) in installed) Padding(padding: const EdgeInsets.only(bottom: 10), child: mcpItem(pal, n, d, i, on, a)),
                ]),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 6,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('THƯ VIỆN', style: TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: pal.sub)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final (n, d, i, inst) in catalog) SizedBox(width: 200, child: catalogItem(pal, n, d, i, installed: inst)),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      );
    });

    // 5. Điện thoại: Trang chủ > Cá nhân có ô MCP, và trang MCP.
    await shot(t, 'mcp-phone-home', const Size(390, 600), (c, pal) {
      final tiles = [
        (Icons.settings_outlined, 'Cài đặt', false),
        (Icons.devices_outlined, 'Thiết bị', false),
        (Icons.qr_code_scanner, 'Quét QR', false),
        (Icons.smart_toy_outlined, 'Trợ lý', false),
        (Icons.android_outlined, 'Bot', false),
        (Icons.extension_outlined, 'MCP & tiện ích', true),
        (Icons.translate, 'Ngôn ngữ', false),
        (Icons.lock_outline, 'Mật khẩu', false),
      ];
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cá nhân', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 14, children: [
            for (final (i, l, isNew) in tiles)
              SizedBox(
                width: 76,
                child: Column(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isNew ? _orange.withValues(alpha: .15) : pal.text.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(16),
                      border: isNew ? Border.all(color: _orange, width: 1.5) : null,
                    ),
                    child: Icon(i, color: isNew ? _orange : pal.text),
                  ),
                  const SizedBox(height: 6),
                  Text(l, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 12, color: pal.text)),
                ]),
              ),
          ]),
        ]),
      );
    });
    await shot(t, 'mcp-phone', const Size(390, 900), (c, pal) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.arrow_back, color: pal.text),
            const SizedBox(width: 10),
            Text('MCP & tiện ích', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            chip(pal, 'Đã cài · 3', color: _orange),
            chip(pal, 'Thư viện'),
          ]),
          const SizedBox(height: 6),
          for (final (n, d, i, on, a) in installed) Padding(padding: const EdgeInsets.only(bottom: 10), child: mcpItem(pal, n, d, i, on, a)),
          card(
            pal,
            Row(children: [
              const Icon(Icons.add_circle_outline, color: _orange),
              const SizedBox(width: 10),
              Text('Thêm từ thư viện hoặc dán URL MCP', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _orange)),
            ]),
          ),
        ]),
      );
    });
  });
}

Widget _cite(Pal pal, int n) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: _orange.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
      child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _orange)),
    );

class _BarChart extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const data = [('Mitsubishi', .27), ('Otis', .19), ('Schindler', .14), ('Kone', .12), ('Fuji', .10), ('Khác', .18)];
    const colors = [Color(0xFFD97757), Color(0xFF5B8DEF), Color(0xFF3FB68B), Color(0xFFF2C14E), Color(0xFF9B6CF0), Color(0xFF9AA0A6)];
    final title = TextPainter(
        text: const TextSpan(text: 'Thị phần lắp mới 2025 (%)', style: TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2328))),
        textDirection: TextDirection.ltr)
      ..layout();
    title.paint(canvas, const Offset(16, 12));
    final left = 16.0, bottom = size.height - 30, top = 44.0;
    final bw = (size.width - 32) / data.length;
    for (var i = 0; i < data.length; i++) {
      final h = (bottom - top) * data[i].$2 / .3;
      final r = RRect.fromRectAndCorners(Rect.fromLTWH(left + i * bw + bw * .2, bottom - h, bw * .6, h), topLeft: const Radius.circular(6), topRight: const Radius.circular(6));
      canvas.drawRRect(r, Paint()..color = colors[i]);
      final v = TextPainter(text: TextSpan(text: '${(data[i].$2 * 100).round()}', style: const TextStyle(fontFamily: 'Roboto', fontSize: 11.5, color: Color(0xFF59636E))), textDirection: TextDirection.ltr)..layout();
      v.paint(canvas, Offset(left + i * bw + bw / 2 - v.width / 2, bottom - h - 16));
      final l = TextPainter(text: TextSpan(text: data[i].$1, style: const TextStyle(fontFamily: 'Roboto', fontSize: 11.5, color: Color(0xFF1F2328))), textDirection: TextDirection.ltr)..layout(maxWidth: bw);
      l.paint(canvas, Offset(left + i * bw + bw / 2 - l.width / 2, bottom + 8));
    }
    canvas.drawLine(Offset(left, bottom), Offset(size.width - 16, bottom), Paint()..color = const Color(0xFFD8DEE4));
    // con trỏ chuột đang chỉ vào cột Otis
    final tip = RRect.fromRectAndRadius(Rect.fromLTWH(left + bw * 1.55, top + 6, 118, 40), const Radius.circular(8));
    canvas.drawRRect(tip, Paint()..color = const Color(0xFF1F2328));
    final tt = TextPainter(text: const TextSpan(text: 'Otis: 3.420 thang\n+9% so với 2024', style: TextStyle(fontFamily: 'Roboto', fontSize: 11, color: Colors.white, height: 1.3)), textDirection: TextDirection.ltr)
      ..layout();
    tt.paint(canvas, Offset(left + bw * 1.55 + 8, top + 12));
    canvas.drawCircle(Offset(left + bw * 1.5, top + 60 + max(0, 0)), 0, Paint());
  }

  @override
  bool shouldRepaint(_BarChart oldDelegate) => false;
}
