// Ảnh trang "Chặn từ khoá nhạy cảm giữa agent" (chạy tay): AP_OUT=<thư mục> flutter test test/agent_dlp_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_dlp_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
  for (final fam in ['Noto Sans', 'Roboto']) {
    final l = FontLoader(fam);
    for (final f in ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }
  final mono = FontLoader('JetBrains Mono')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/JetBrainsMono-Regular.ttf').readAsBytesSync())));
  await mono.load();
}

void main() {
  final out = Platform.environment['AP_OUT'];
  final catalog = [
    {'id': 'secret', 'name': 'Khoá API / token', 'description': 'sk-…, sk-ant-…, fgk_…, fgb_…, ghp_…, glpat-…, xox…-, AIza…, khoá AWS, JWT, Bearer …'},
    {'id': 'private_key', 'name': 'Khoá riêng (private key)', 'description': '-----BEGIN … PRIVATE KEY-----, khoá SSH / PuTTY'},
    {'id': 'password', 'name': 'Mật khẩu', 'description': '"mật khẩu: …", "mk = …", "password: …", chuỗi kết nối user:pass@máy'},
    {'id': 'card', 'name': 'Số thẻ ngân hàng', 'description': '13–19 chữ số đúng thuật toán Luhn (Visa, Master, JCB, Amex, Napas 9704)'},
    {'id': 'bank_account', 'name': 'Số tài khoản ngân hàng', 'description': '8–19 chữ số đứng cạnh "STK", "số tài khoản", tên ngân hàng'},
    {'id': 'cccd', 'name': 'CCCD / CMND', 'description': '12 số (mã tỉnh hợp lệ) hoặc 9 số, đứng cạnh "CCCD", "CMND", "căn cước"'},
    {'id': 'otp', 'name': 'Mã OTP', 'description': '"OTP", "mã xác nhận", "mã xác thực", "verification code" + 4–8 chữ số'},
  ];
  final calls = <String>[];
  DlpApi.debugCall = (method, path, body) async {
    calls.add('$method $path');
    if (path == 'test') {
      return {
        'blocked': true,
        'hits': [
          {'rule': 'kw0', 'name': 'Từ khoá "dự án Kiara"', 'start': 9, 'end': 20},
          {'rule': 'password', 'name': 'Mật khẩu', 'start': 41, 'end': 60},
        ],
      };
    }
    return {
      'enabled': true,
      'notify': true,
      'builtins': {'secret': true, 'private_key': true, 'password': true, 'card': true, 'bank_account': true, 'cccd': true, 'otp': false},
      'keywords': [
        {'text': 'dự án Kiara', 'regex': false},
        {'text': 'giá vốn', 'regex': false},
        {'text': r'HD-\d{6}', 'regex': true},
      ],
      'catalog': catalog,
    };
  };

  Future<void> shot(WidgetTester t, String name, Size size, {bool dark = false, bool probe = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: AppState('t'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        home: RepaintBoundary(key: key, child: const AgentDlpPage()),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    if (probe) {
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField).last, 'Bảng giá dự án Kiara tháng 11, tài khoản admin, mật khẩu: Yla@2026!');
      await t.tap(find.text('Thử'));
      await t.pump(const Duration(milliseconds: 100));
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pump(const Duration(milliseconds: 300));
    }
    if (out != null) {
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('trang chặn từ khoá: tải cài đặt, bật / tắt lưu ngay, thử một câu', (t) async {
    await t.runAsync(_fonts);
    await shot(t, 'dlp-phone-light', const Size(400, 1250));
    expect(calls.first, 'GET settings');
    await shot(t, 'dlp-phone-dark-thu', const Size(400, 900), dark: true, probe: true);
    expect(calls, contains('POST test'));
  });
}
