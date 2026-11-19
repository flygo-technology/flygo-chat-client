// Mockup "Kiểm duyệt trao đổi giữa agent" (đề xuất ~/handoff/de-xuat-a2a-dlp.md), chỉ là ảnh, chưa nối dữ liệu thật.
// Chạy tay: AP_OUT=<thư mục> flutter test test/a2a_dlp_mockup_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
  for (final fam in ['Noto Sans', 'Flygo Inter']) {
    final l = FontLoader(fam);
    for (final f in ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }
  final mono = FontLoader('JetBrains Mono')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/JetBrainsMono-Regular.ttf').readAsBytesSync())));
  await mono.load();
}

// Màu theo mức hành động.
const _review = Color(0xFFE8A317), _block = Color(0xFFE5484D), _redact = Color(0xFF7C66DC), _log = Color(0xFF8E8E93), _ok = Color(0xFF30A46C);

Widget _sec(Pal pal, String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        Expanded(child: Text(t.toUpperCase(), style: TextStyle(fontSize: 13, color: pal.sub, letterSpacing: .3))),
        if (trailing != null) trailing,
      ]),
    );

Widget _card(Pal pal, List<Widget> rows) => Container(
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, r) in rows.indexed) ...[if (i > 0) Divider(height: 1, indent: 16, color: pal.divider), r],
      ]),
    );

Widget _pill(String t, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 3)],
        Text(t, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
      ]),
    );

Widget _action(String a) => switch (a) {
      'review' => _pill('Chờ duyệt', _review, icon: Icons.front_hand_outlined),
      'block' => _pill('Chặn luôn', _block, icon: Icons.block),
      'redact' => _pill('Tự ẩn', _redact, icon: Icons.visibility_off_outlined),
      'log' => _pill('Chỉ ghi nhật ký', _log, icon: Icons.notes),
      _ => _pill('Tắt', _log),
    };

/// Văn bản có đoạn khớp tô màu: [parts] xen kẽ (chữ thường, đoạn khớp, chữ thường, …).
Widget _marked(Pal pal, List<String> parts, {double size = 15, bool masked = false, Color mark = _review}) => Text.rich(
      TextSpan(style: TextStyle(fontSize: size, color: pal.text, height: 1.45), children: [
        for (final (i, p) in parts.indexed)
          i.isOdd
              ? TextSpan(
                  text: masked ? ' ${'•' * 8} ' : p,
                  style: TextStyle(backgroundColor: mark.withValues(alpha: .28), fontWeight: FontWeight.w600, fontFamily: masked ? null : 'JetBrains Mono', fontSize: size - 1))
              : TextSpan(text: p),
      ]),
    );

Widget _avatar(String t, Color c, {double r = 18}) => CircleAvatar(
    radius: r, backgroundColor: c.withValues(alpha: .18), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: r * .75)));

Widget _flow(Pal pal, String from, String to, String via) => Row(children: [
      _avatar(from[0].toUpperCase(), const Color(0xFFD97757), r: 13),
      const SizedBox(width: 6),
      Text('@$from', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text, fontSize: 14)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 16, color: pal.sub)),
      _avatar(to[0].toUpperCase(), const Color(0xFF10A37F), r: 13),
      const SizedBox(width: 6),
      Flexible(child: Text('@$to', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text, fontSize: 14))),
      if (via.isNotEmpty) const SizedBox(width: 8),
      if (via.isNotEmpty) Flexible(child: Text('· $via', overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.sub, fontSize: 13))),
    ]);

Widget _btn(String t, Color bg, Color fg, {IconData? icon, bool outline = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
          color: outline ? Colors.transparent : bg, borderRadius: BorderRadius.circular(12), border: outline ? Border.all(color: bg) : null),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 6)],
        Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14))),
      ]),
    );

AppBar _bar(Pal pal, String t, {List<Widget> actions = const []}) => AppBar(
      backgroundColor: pal.bg,
      surfaceTintColor: Colors.transparent,
      leading: Icon(Icons.arrow_back, color: pal.text),
      title: Text(t, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 18)),
      actions: actions,
    );

// ---------- 1. Trang Trợ lý: mục mới "Cài đặt trợ lý" ----------
Widget assistantsPage() => Builder(builder: (c) {
      final pal = Pal.of(c);
      Widget bot(String n, String eng, Color col, String st) => ListTile(
            leading: _avatar(n[0].toUpperCase(), col),
            title: Text(n, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
            subtitle: Text(eng, style: TextStyle(color: pal.sub, fontSize: 13)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: _ok, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(st, style: TextStyle(color: pal.sub, fontSize: 13)),
            ]),
          );
      Widget setting(IconData i, Color col, String t, String sub, {Widget? trail}) => ListTile(
            leading: Container(
                width: 36, height: 36, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(9)), child: Icon(i, color: Colors.white, size: 20)),
            title: Text(t, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
            subtitle: Text(sub, style: TextStyle(color: pal.sub, fontSize: 13)),
            trailing: trail ?? Icon(Icons.chevron_right, color: pal.sub),
          );
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: _bar(pal, 'Trợ lý', actions: [Icon(Icons.refresh, color: pal.text), const SizedBox(width: 12)]),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          _sec(pal, 'Trợ lý của tôi'),
          _card(pal, [
            bot('ba-claude', 'Claude · Mac mini', const Color(0xFFD97757), 'Đang chạy'),
            bot('ba-codex', 'Codex · Mac mini', const Color(0xFF10A37F), 'Đang chạy'),
            bot('ba-agy', 'Antigravity · Mac mini', const Color(0xFF4285F4), 'Đang chạy'),
          ]),
          _sec(pal, 'Cài đặt trợ lý'),
          _card(pal, [
            setting(Icons.shield_outlined, _review, 'Kiểm duyệt trao đổi giữa agent', 'Kiểm từ khoá cấm trước khi agent gửi cho nhau',
                trail: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: _block, borderRadius: BorderRadius.circular(10)),
                      child: const Text('2', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
                  Icon(Icons.chevron_right, color: pal.sub),
                ])),
            setting(Icons.hub_outlined, const Color(0xFF5E5CE6), 'MCP bên ngoài', '3 máy chủ MCP'),
            setting(Icons.data_usage_rounded, const Color(0xFF30A46C), 'Dung lượng & đồng ý gửi dữ liệu AI', 'Còn 62% tuần này'),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Áp cho mọi trợ lý của bạn. Tin có từ khoá cấm sẽ được giữ lại để bạn duyệt.', style: TextStyle(color: pal.sub, fontSize: 13)),
          ),
        ]),
      );
    });

// ---------- 2. Trang kiểm duyệt: tab Chờ duyệt ----------
Widget _tabs(Pal pal, int sel) => Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        for (final (i, t) in ['Chờ duyệt (2)', 'Quy tắc', 'Nhật ký'].indexed)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: i == sel ? pal.bg : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Text(t, style: TextStyle(color: i == sel ? pal.text : pal.sub, fontWeight: i == sel ? FontWeight.w600 : FontWeight.w500, fontSize: 14)),
            ),
          ),
      ]),
    );

Widget _ticket(Pal pal, {required String from, required String to, required String via, required String rule, required List<String> text, required String left, bool masked = false, String? note}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _review.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _flow(pal, from, to, ''),
        const SizedBox(height: 6),
        Row(children: [
          Text(via, style: TextStyle(color: pal.sub, fontSize: 13)),
          const Spacer(),
          Icon(Icons.timer_outlined, size: 15, color: _review),
          const SizedBox(width: 3),
          Text(left, style: const TextStyle(color: _review, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [_pill(rule, _review, icon: Icons.policy_outlined), if (note != null) _pill(note, pal.sub)]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(12)),
          child: _marked(pal, text, size: 14, masked: masked),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _btn(masked ? 'Nhận' : 'Cho gửi', _ok, Colors.white)),
          const SizedBox(width: 8),
          Expanded(child: _btn(masked ? 'Nhận bản ẩn' : 'Gửi bản ẩn', _redact, Colors.white)),
          const SizedBox(width: 8),
          Expanded(child: _btn(masked ? 'Từ chối' : 'Không gửi', _block, _block, outline: true)),
        ]),
      ]),
    );

Widget reviewList() => Builder(builder: (c) {
      final pal = Pal.of(c);
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: _bar(pal, 'Kiểm duyệt trao đổi giữa agent'),
        body: Column(children: [
          _tabs(pal, 0),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
              _ticket(pal,
                  from: 'ba-claude',
                  to: 'dang-codex',
                  via: 'team_ask',
                  rule: 'Số tài khoản',
                  left: 'còn 27 phút',
                  text: ['Anh kiểm giúp em giao dịch hoàn tiền cho khách: chuyển vào STK ', '19036218453016', ' Techcombank, số tiền 2.450.000đ, nội dung "HOAN DON 8812".']),
              _ticket(pal,
                  from: 'ba-codex',
                  to: 'agent ngoài (Cursor)',
                  via: 'cầu nối MCP',
                  rule: 'Khoá API',
                  left: 'còn 12 phút',
                  note: 'chiều ra',
                  text: ['Đã cấu hình xong. Biến môi trường dùng: OPENAI_API_KEY=', 'sk-proj-Hq3…', ', còn webhook để ở ', '192.168.2.4:8066', '.']),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text('Hết giờ mà chưa duyệt thì tin không được gửi. Bot gửi vẫn chờ trong lúc này.', style: TextStyle(color: pal.sub, fontSize: 13)),
              ),
            ]),
          ),
        ]),
      );
    });

// ---------- 3. Tờ duyệt mở từ thông báo / DM (bên nhận chỉ thấy bản che) ----------
Widget reviewSheet({bool receiver = false}) => Builder(builder: (c) {
      final pal = Pal.of(c);
      return Scaffold(
        backgroundColor: Colors.black.withValues(alpha: .55),
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            decoration: BoxDecoration(color: pal.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: pal.divider, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.shield_outlined, color: _review),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(receiver ? 'Tin gửi tới trợ lý của bạn cần duyệt' : 'Tin trợ lý của bạn sắp gửi cần duyệt',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text))),
              ]),
              const SizedBox(height: 12),
              receiver ? _flow(pal, 'ba-claude', 'dang-codex', 'ask_agent') : _flow(pal, 'ba-claude', 'dang-codex', 'ask_agent'),
              const SizedBox(height: 4),
              Text(receiver ? 'Khớp quy tắc nhận vào của bạn · 14:05' : 'Phiên "Hoàn tiền đơn 8812" · 14:05', style: TextStyle(color: pal.sub, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _pill('Mật khẩu', _review, icon: Icons.policy_outlined),
                _pill('IP nội bộ', _log, icon: Icons.notes),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14)),
                child: _marked(pal, [
                  'Anh đăng nhập máy chấm công giúp em để xuất bảng tháng 11: địa chỉ ',
                  '192.168.4.250',
                  ', tài khoản admin, ',
                  'mật khẩu: Yla@2026!',
                  '. Xuất xong gửi file CSV vào phiên này nhé.'
                ], masked: receiver),
              ),
              if (receiver)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.lock_outline, size: 14, color: pal.sub),
                    const SizedBox(width: 4),
                    Expanded(child: Text('Đoạn khớp được che: bạn không xem được dữ liệu của người gửi.', style: TextStyle(color: pal.sub, fontSize: 12.5))),
                  ]),
                ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: _btn(receiver ? 'Nhận' : 'Cho gửi', _ok, Colors.white, icon: Icons.check)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: _btn(receiver ? 'Nhận bản đã ẩn' : 'Gửi bản đã ẩn đoạn khớp', _redact, Colors.white, icon: Icons.visibility_off_outlined)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: _btn(receiver ? 'Từ chối' : 'Không gửi', _block, _block, icon: Icons.close, outline: true)),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(width: 22, height: 22, child: Checkbox(value: false, onChanged: (_) {})),
                const SizedBox(width: 8),
                Expanded(child: Text('Luôn cho phép đoạn này với @dang-codex', style: TextStyle(color: pal.text, fontSize: 14))),
                Text('còn 27:41', style: TextStyle(color: _review, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ]),
          ),
        ),
      );
    });

// ---------- 4. Tab Quy tắc + thử một câu (máy tính) ----------
Widget rulesDesktop() => Builder(builder: (c) {
      final pal = Pal.of(c);
      Widget rule(String name, String desc, String act, {bool locked = false, bool on = true, String? src}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(name, style: TextStyle(color: on ? pal.text : pal.sub, fontWeight: FontWeight.w600, fontSize: 14.5))),
                    if (locked) ...[const SizedBox(width: 6), Icon(Icons.lock_outline, size: 14, color: pal.sub)],
                    if (src != null) ...[const SizedBox(width: 6), _pill(src, pal.sub)],
                  ]),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(color: pal.sub, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 10),
              on ? _action(act) : _action('off'),
              const SizedBox(width: 6),
              Icon(Icons.expand_more, size: 18, color: pal.sub),
            ]),
          );
      final left = ListView(padding: const EdgeInsets.fromLTRB(20, 0, 12, 20), children: [
        _sec(pal, 'Mặc định công ty', trailing: Text('do quản trị đặt', style: TextStyle(color: pal.sub, fontSize: 12.5))),
        _card(pal, [
          rule('Khoá riêng (private key)', '-----BEGIN … PRIVATE KEY-----, khoá SSH / Nebula', 'block', locked: true),
          rule('Khoá API / token', 'sk-…, sk-ant-…, fgk_…, fgb_…, ghp_…, JWT, Bearer …', 'review', locked: true),
          rule('Khoá AWS', 'AKIA… / ASIA… + secret', 'review', locked: true),
          rule('Số thẻ ngân hàng', '13–19 số, đúng Luhn', 'review'),
          rule('IP / tên máy nội bộ', '10.x, 192.168.x, 10.88.x, *.lan, hn-maychu, flygo-03…', 'log'),
        ]),
        _sec(pal, 'Phát hiện có sẵn'),
        _card(pal, [
          rule('Mật khẩu viết ra', '"mật khẩu:", "mk=", "password:" + chuỗi', 'review'),
          rule('Số tài khoản', '8–19 số cạnh "STK", "tài khoản", tên ngân hàng', 'review'),
          rule('CCCD / CMND', '12 số, mã tỉnh hợp lệ, cạnh "CCCD"', 'review'),
          rule('Mã OTP', '"OTP", "mã xác nhận" + 4–8 số', 'review'),
          rule('Chuỗi base64 / hex dài', '≥ 200 ký tự base64, ≥ 128 hex · giải mã rồi kiểm lại', 'review'),
          rule('Email', 'tắt mặc định', 'log', on: false),
          rule('Số điện thoại', 'tắt mặc định', 'log', on: false),
        ]),
        _sec(pal, 'Từ khoá của tôi',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 18, color: pal.accentText),
              Text('Thêm', style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w600)),
            ])),
        _card(pal, [
          rule('dự án Kiara', 'Từ khoá · cả hai chiều · mọi kênh', 'review'),
          rule('giá vốn', 'Từ khoá · gửi đi · khác chủ', 'redact'),
          rule(r'HD-\d{6}', 'Biểu thức · gửi đi · cầu nối MCP', 'review'),
          rule('lương', 'Từ khoá · cả hai chiều', 'block'),
        ]),
      ]);
      final right = ListView(padding: const EdgeInsets.fromLTRB(12, 0, 20, 20), children: [
        _sec(pal, 'Thử một câu'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
              child: _marked(pal, [
                'Bảng ',
                'giá vốn',
                ' tháng 11 của ',
                'dự án Kiara',
                ' em để trên ',
                'hn-maychu',
                ', đơn ',
                'HD-260117',
                ' đã thanh toán 1.250.000đ ngày 18/11.'
              ], size: 14),
            ),
            const SizedBox(height: 12),
            Text('4 đoạn khớp · nếu agent gửi câu này:', style: TextStyle(color: pal.sub, fontSize: 13)),
            const SizedBox(height: 8),
            for (final (t, r, a) in [
              ('giá vốn', 'Từ khoá của tôi', 'redact'),
              ('dự án Kiara', 'Từ khoá của tôi', 'review'),
              ('hn-maychu', 'IP / tên máy nội bộ', 'log'),
              ('HD-260117', r'HD-\d{6}', 'review'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(t, style: TextStyle(color: pal.text, fontFamily: 'JetBrains Mono', fontSize: 13))),
                  Expanded(child: Text(r, style: TextStyle(color: pal.sub, fontSize: 13))),
                  _action(a),
                ]),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _review.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.front_hand_outlined, size: 18, color: _review),
                const SizedBox(width: 8),
                Expanded(child: Text('Kết quả: giữ lại chờ bạn duyệt (mức nặng nhất).', style: TextStyle(color: pal.text, fontSize: 13.5))),
              ]),
            ),
            const SizedBox(height: 8),
            Text('"1.250.000đ" và "18/11" không bị coi là số tài khoản. Câu thử không được lưu.', style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ]),
        ),
        _sec(pal, '7 ngày qua'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final (n, l, col) in [('412', 'tin đã kiểm', pal.text), ('9', 'đã duyệt', _ok), ('3', 'không gửi', _block), ('5', 'tự ẩn', _redact)])
              Column(children: [
                Text(n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: col)),
                Text(l, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
          ]),
        ),
      ]);
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: _bar(pal, 'Kiểm duyệt trao đổi giữa agent'),
        body: Column(children: [
          SizedBox(width: 520, child: _tabs(pal, 1)),
          Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: left), Expanded(flex: 5, child: right)])),
        ]),
      );
    });

// ---------- 5. Thêm quy tắc ----------
Widget addRule() => Builder(builder: (c) {
      final pal = Pal.of(c);
      Widget seg(List<String> items, int sel, {List<Color>? colors}) => Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              for (final (i, t) in items.indexed)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: i == sel ? (colors?[i] ?? pal.bg) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                    child: Text(t,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: i == sel ? (colors != null ? Colors.white : pal.text) : pal.sub)),
                  ),
                ),
            ]),
          );
      Widget label(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(t, style: TextStyle(color: pal.sub, fontSize: 13)));
      Widget field(String v, {String? hint, bool mono = false}) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
            child: Text(v.isEmpty ? hint! : v,
                style: TextStyle(color: v.isEmpty ? pal.sub : pal.text, fontSize: 15, fontFamily: mono ? 'JetBrains Mono' : null)),
          );
      Widget chip(String t, bool on) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: on ? pal.chipSelBg : pal.surface, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (on) ...[Icon(Icons.check, size: 15, color: pal.chipSelFg), const SizedBox(width: 4)],
              Text(t, style: TextStyle(color: on ? pal.chipSelFg : pal.sub, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ]),
          );
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          leading: Icon(Icons.close, color: pal.text),
          title: Text('Thêm từ khoá cấm', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 18)),
          actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Text('Lưu', style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w700, fontSize: 16)))],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          label('Loại'),
          seg(['Từ khoá', 'Biểu thức', 'Danh sách'], 0),
          label('Từ khoá'),
          field('dự án Kiara'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Không phân biệt hoa thường và dấu: khớp cả "DU AN KIARA". Khớp nguyên từ.', style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ),
          label('Khi phát hiện'),
          seg(['Chờ duyệt', 'Chặn luôn', 'Tự ẩn', 'Ghi nhật ký'], 0, colors: [_review, _block, _redact, _log]),
          label('Chiều'),
          seg(['Gửi đi', 'Nhận vào', 'Cả hai'], 2),
          label('Kênh'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            chip('Nhờ agent (A2A)', true),
            chip('Đồng đội dự án', true),
            chip('Hỏi phiên khác', true),
            chip('Cầu nối MCP', true),
            chip('Tệp', true),
          ]),
          label('Ngoại lệ (không tính là khớp)'),
          field('', hint: 'vd. dự án Kiara công khai'),
          label('Chỉ áp khi gửi cho'),
          seg(['Mọi agent', 'Agent của người khác'], 1),
        ]),
      );
    });

// ---------- 6. Nhật ký ----------
Widget auditLog() => Builder(builder: (c) {
      final pal = Pal.of(c);
      Widget row(String time, String rule, String from, String to, String via, String result, Color col, String h) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(time, style: TextStyle(color: pal.sub, fontSize: 12.5)),
                const SizedBox(width: 8),
                Expanded(child: Text(rule, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 14))),
                _pill(result, col),
              ]),
              const SizedBox(height: 5),
              Text('@$from → @$to · $via', style: TextStyle(color: pal.sub, fontSize: 13)),
              const SizedBox(height: 2),
              Text('dấu vết $h', style: TextStyle(color: pal.sub, fontSize: 11.5, fontFamily: 'JetBrains Mono')),
            ]),
          );
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: _bar(pal, 'Kiểm duyệt trao đổi giữa agent'),
        body: Column(children: [
          _tabs(pal, 2),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final (t, on) in [('Tất cả', true), ('Không gửi', false), ('Đã duyệt', false), ('Tự ẩn', false), ('ba-claude', false)])
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: on ? pal.chipSelBg : pal.surface, borderRadius: BorderRadius.circular(20)),
                    child: Text(t, style: TextStyle(color: on ? pal.chipSelFg : pal.sub, fontSize: 13.5)),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
              _sec(pal, 'Hôm nay'),
              _card(pal, [
                row('14:05', 'Mật khẩu viết ra', 'ba-claude', 'dang-codex', 'ask_agent', 'Không gửi · Sếp', _block, 'a91f…0c2e · 18 ký tự'),
                row('11:42', 'Số tài khoản', 'ba-claude', 'dang-codex', 'team_ask', 'Đã duyệt · Sếp · 3 phút', _ok, '5d02…e771 · 14 ký tự'),
                row('10:18', 'giá vốn', 'ba-codex', 'Agent ngoài', 'cầu nối MCP', 'Tự ẩn', _redact, '0b6c…91aa · 7 ký tự'),
                row('09:00', 'Khoá API / token', 'ba-agy', 'ba-codex', 'tệp env.txt', 'Hết giờ · không gửi', _block, 'f3e8…22d1 · 51 ký tự'),
              ]),
              _sec(pal, 'Hôm qua'),
              _card(pal, [
                row('22:31', 'IP / tên máy nội bộ', 'ba-codex', 'ba-claude', 'team_post', 'Ghi nhật ký', _log, '77ad…3b10 · 11 ký tự'),
                row('16:07', 'Chuỗi base64 dài', 'ba-claude', 'dang-claude', 'ask_agent', 'Không gửi · Sếp', _block, 'c4d1…9e0f · 2.304 ký tự'),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Text('Nhật ký không lưu nội dung tin hay đoạn khớp, chỉ lưu dấu vết (mã băm) để nhận ra cùng một dữ liệu gửi lặp lại. Giữ 90 ngày.',
                    style: TextStyle(color: pal.sub, fontSize: 12.5)),
              ),
            ]),
          ),
        ]),
      );
    });

// ---------- 7. Thẻ trợ lý trong chat AI khi tin bị giữ + DM báo ----------
Widget chatCard() => Builder(builder: (c) {
      final pal = Pal.of(c);
      Widget step(IconData i, Color col, String t, {String? sub}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 17, color: col),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: TextStyle(color: pal.text, fontSize: 14)),
                  if (sub != null) Text(sub, style: TextStyle(color: pal.sub, fontSize: 12.5)),
                ]),
              ),
            ]),
          );
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          leading: Icon(Icons.arrow_back, color: pal.text),
          titleSpacing: 0,
          title: Row(children: [
            _avatar('B', const Color(0xFFD97757), r: 16),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hoàn tiền đơn 8812', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 16)),
              Text('@ba-claude · chờ Sếp duyệt', style: TextStyle(color: _review, fontSize: 12.5)),
            ]),
          ]),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: pal.outBubble, borderRadius: BorderRadius.circular(16)),
              child: const Text('Nhờ @dang-codex kiểm và làm lệnh hoàn tiền đơn 8812 cho khách nhé', style: TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              step(Icons.check_circle_outline, _ok, 'Đọc đơn 8812 trong Teable'),
              step(Icons.check_circle_outline, _ok, 'Tìm giao dịch Techcombank'),
              step(Icons.shield_outlined, _review, 'Nhờ @dang-codex: đang chờ Sếp duyệt', sub: 'Khớp quy tắc "Số tài khoản" · còn 27 phút'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _review.withValues(alpha: .5))),
                child: _marked(pal, ['…chuyển vào STK ', '19036218453016', ' Techcombank, số tiền 2.450.000đ, nội dung "HOAN DON 8812".'], size: 14),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _btn('Cho gửi', _ok, Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: _btn('Gửi bản ẩn', _redact, Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: _btn('Không gửi', _block, _block, outline: true)),
              ]),
            ]),
          ),
          const SizedBox(height: 22),
          Center(child: Text('Tin báo trong DM với bot (khi Sếp không mở phiên này)', style: TextStyle(color: pal.sub, fontSize: 12.5))),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar('B', const Color(0xFFD97757), r: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.shield_outlined, size: 17, color: _review),
                    const SizedBox(width: 6),
                    Text('Cần Sếp duyệt 1 tin', style: TextStyle(color: pal.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ]),
                  const SizedBox(height: 6),
                  Text('@ba-claude → @dang-codex · team_ask · quy tắc "Số tài khoản" · 14:05', style: TextStyle(color: pal.sub, fontSize: 13)),
                  const SizedBox(height: 10),
                  _btn('Xem & duyệt', pal.accent, Colors.white, icon: Icons.open_in_new),
                ]),
              ),
            ),
          ]),
        ]),
      );
    });

// ---------- 8. Quản trị: mặc định công ty ----------
Widget adminDefaults() => Builder(builder: (c) {
      final pal = Pal.of(c);
      Widget row(String n, String d, String act, bool lock) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 14.5)),
                  Text(d, style: TextStyle(color: pal.sub, fontSize: 12.5)),
                ]),
              ),
              SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: _action(act))),
              SizedBox(
                width: 150,
                child: Row(children: [
                  Switch(value: lock, onChanged: (_) {}),
                  const SizedBox(width: 4),
                  Text(lock ? 'Khoá' : 'Cho đổi', style: TextStyle(color: pal.sub, fontSize: 13)),
                ]),
              ),
            ]),
          );
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: _bar(pal, 'Quản trị · Mặc định kiểm duyệt agent'),
        body: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Áp cho mọi trợ lý trên chat.flygo.vn. "Khoá" = người dùng không tắt hoặc hạ mức được, chỉ nâng lên.', style: TextStyle(color: pal.sub, fontSize: 13.5)),
          ),
          _sec(pal, 'Quy tắc công ty',
              trailing: Row(children: [
                const SizedBox(width: 20),
                SizedBox(width: 140, child: Text('KHI PHÁT HIỆN', style: TextStyle(color: pal.sub, fontSize: 12))),
                SizedBox(width: 150, child: Text('NGƯỜI DÙNG', style: TextStyle(color: pal.sub, fontSize: 12))),
              ])),
          _card(pal, [
            row('Khoá riêng (private key)', 'RSA / EC / OpenSSH / Nebula', 'block', true),
            row('Khoá API / token', 'sk-, sk-ant-, fgk_, fgb_, ghp_, glpat-, xox, AIza, JWT', 'review', true),
            row('Khoá AWS', 'AKIA / ASIA + secret', 'review', true),
            row('Số thẻ ngân hàng', 'Luhn', 'review', false),
            row('Mật khẩu viết ra', 'mật khẩu: / mk= / password:', 'review', false),
            row('Chuỗi base64 / hex dài', 'ngưỡng 200 / 128 ký tự', 'review', false),
            row('IP / tên máy nội bộ', 'dải riêng + danh sách bên dưới', 'log', false),
          ]),
          _sec(pal, 'Tên máy / miền nội bộ'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in ['hn-maychu', 'flygo-01', 'flygo-02', 'flygo-03', 'larkpanel-main', '*.flygo.lan', 'tnh.lan', '10.88.0.0/16', '10.90.0.0/16'])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(8)),
                  child: Text(t, style: TextStyle(color: pal.text, fontFamily: 'JetBrains Mono', fontSize: 13)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(8)),
                child: Text('+ thêm', style: TextStyle(color: pal.accentText, fontSize: 13)),
              ),
            ]),
          ),
          _sec(pal, 'Duyệt'),
          _card(pal, [
            ListTile(
              title: Text('Thời gian chờ duyệt', style: TextStyle(color: pal.text)),
              subtitle: Text('Quá hạn thì không gửi', style: TextStyle(color: pal.sub, fontSize: 13)),
              trailing: Text('30 phút', style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              title: Text('Người duyệt thay khi chủ vắng', style: TextStyle(color: pal.text)),
              subtitle: Text('Tắt', style: TextStyle(color: pal.sub, fontSize: 13)),
              trailing: Icon(Icons.chevron_right, color: pal.sub),
            ),
            ListTile(
              title: Text('Tối đa tin chờ duyệt mỗi phiên', style: TextStyle(color: pal.text)),
              subtitle: Text('Quá thì tin sau bị chặn luôn', style: TextStyle(color: pal.sub, fontSize: 13)),
              trailing: Text('3', style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w600)),
            ),
          ]),
        ]),
      );
    });

void main() {
  final out = Platform.environment['AP_OUT'];

  Future<void> shot(WidgetTester t, String name, Size size, Widget child, {bool dark = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    final base = buildTheme(dark ? Brightness.dark : Brightness.light);
    final theme = base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Flygo Inter'));
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: DefaultTextStyle.merge(style: const TextStyle(fontFamily: 'Flygo Inter'), child: RepaintBoundary(key: key, child: child)),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('mockup kiểm duyệt trao đổi giữa agent', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    const phone = Size(400, 860);
    await shot(t, '01-tro-ly-cai-dat', phone, assistantsPage());
    await shot(t, '02-cho-duyet', phone, reviewList());
    await shot(t, '02-cho-duyet-dark', phone, reviewList(), dark: true);
    await shot(t, '03-to-duyet-ben-gui', phone, reviewSheet());
    await shot(t, '03b-to-duyet-ben-nhan-dark', phone, reviewSheet(receiver: true), dark: true);
    await shot(t, '04-quy-tac-thu-cau-desktop', const Size(1280, 900), rulesDesktop());
    await shot(t, '05-them-quy-tac', phone, addRule());
    await shot(t, '06-nhat-ky-dark', phone, auditLog(), dark: true);
    await shot(t, '07-the-chat-cho-duyet', phone, chatCard());
    await shot(t, '08-quan-tri-mac-dinh-dark', const Size(1100, 980), adminDefaults(), dark: true);
  });
}
