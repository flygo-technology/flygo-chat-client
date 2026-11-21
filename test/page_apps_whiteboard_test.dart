// Bảng trắng theo mockup "mỗi trang là một app" (21/11): phần người xem (bảng; kiểm thử không có WebView nên hiện ô thay thế),
// chủ trang (ai được vẽ, đi theo, xoá bảng bấm hai lần). Ảnh: APP_OUT=<thư mục> flutter test test/page_apps_whiteboard_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';

import 'app_kit_helpers.dart';

Map<String, dynamic> _wb({String mode = 'all', bool draw = true}) => {
      'board': 'pg-abcdefghijkl', 'mode': mode, 'follow': true, 'can_manage': false, 'can_draw': draw,
      'path': '/meet/extras/board-web/index.html?b=pg-abcdefghijkl', 'token': 'x.y', 'count': 12,
    };

void main() {
  setUpAll(loadAppTestFonts);
  setUp(appActs.clear);
  final wb = pageTypeOf('whiteboard')!;

  testWidgets('bảng trắng: người xem, chủ trang (ai được vẽ, đi theo, xoá bảng hai lần)', (t) async {
    await pumpAppForms(t, 'bang-trang-nguoi-xem', wb, appCtx('whiteboard', _wb(mode: 'owner', draw: false), role: 'member'), check: (t, f, l) async {
      expect(find.text('Chỉ chủ trang được vẽ: bạn xem và đi theo.'), findsOneWidget);
    });
    await pumpAppForms(t, 'bang-trang-chu-trang', wb, appCtx('whiteboard', _wb()), check: (t, f, l) async {
      expect(find.text('Mọi người đi theo người trình bày'), findsOneWidget);
    });
    appActs.clear();
    t.view.physicalSize = const Size(1280, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pump();
    await t.ensureVisible(find.text('Khoá').first);
    await t.pump();
    await t.tap(find.text('Khoá').first);
    await t.pump(const Duration(milliseconds: 100));
    await t.ensureVisible(find.text('Xoá bảng'));
    await t.pump();
    await t.tap(find.text('Xoá bảng'));
    await t.pump(const Duration(milliseconds: 100));
    expect(appActs.map((e) => e.$1), ['mode']); // lần bấm đầu chỉ hỏi lại
    await t.tap(find.text('Bấm lần nữa để xoá hết'));
    await t.pump(const Duration(milliseconds: 100));
    expect(appActs.map((e) => e.$1), ['mode', 'clear']);
    expect(appActs.first.$2, {'mode': 'locked'});
    await t.pump(const Duration(seconds: 5)); // hết giờ "bấm lần nữa" của nút xoá
  });
}
