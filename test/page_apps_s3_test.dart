// Đợt 3 của "mỗi trang là một app": Biên bản trong vỏ app ở ba kiểu màn hình × tối / sáng, không tràn; người xem nhận việc,
// đổi hạn, đề xuất sửa một dòng; người ghi gắn nhãn, duyệt đề xuất, chốt. APP_OUT=<thư mục>: lưu ảnh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/pages/app_shell.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/stage_frame.dart';
import 'package:flygo_chat/ui/pages/types/minutes_app.dart';

import 'app_kit_helpers.dart';

final _now = DateTime.now().millisecondsSinceEpoch;
const _text = '## 2 · Tiến độ lắp đặt tòa B\n'
    '09:14 · Lợi báo đã lắp xong ray tầng 1–10, còn 2 tầng.\n'
    '09:18 · QUYẾT ĐỊNH: Bàn giao tòa B Thứ Sáu 28/11 (bình chọn 54%).\n'
    '\n## 3 · Hợp đồng tháng 11\n'
    '09:32 · Kim trình bày 3 hợp đồng mới.\n'
    '09:40 · Thảo luận chọn nhà thầu phụ: 13 đồng ý A, 7 phản đối.\n'
    '09:41 · QUYẾT ĐỊNH: Chọn đơn vị A cho gói ray, B làm thử cửa tầng';

Map<String, dynamic> _view({bool writer = false, bool closed = false}) => {
      'text': _text, 'edited_by': 'Hoàng Lan', 'edited_at': _now - 5000, 'closed': closed, 'writer': writer,
      'tasks': [
        {'id': 't1', 'text': 'Lịch trực ca tối tòa B', 'who': '@ba', 'due': '26/11', 'done': false},
        {'id': 't2', 'text': 'Đặt vật tư cửa tầng', 'who': 'Mai Kim', 'due': '01/12', 'done': false, 'claimed': true},
      ],
      'suggestions': [
        if (writer) {'id': 's1', 'by': 'Lê Minh', 'by_id': 'm', 'orig': '09:14 · Lợi báo đã lắp xong ray tầng 1–10, còn 2 tầng.', 'text': '09:14 · … còn 2 tầng + phòng máy.'},
      ],
    };

void main() {
  setUpAll(loadAppTestFonts);
  setUp(() {
    appActs.clear();
    appTestState.me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Dương Văn', 'last_name': 'Ba'});
  });
  tearDown(() => appTestState.me = null);
  PageTypeSpec spec() => pageTypeOf('minutes')!;

  test('đọc biên bản: đề mục, giờ, quyết định', () {
    final s = parseMinutes(_text);
    expect(s.map((x) => x.title), ['2 · Tiến độ lắp đặt tòa B', '3 · Hợp đồng tháng 11']);
    expect(s[0].lines[1].decision, isTrue);
    expect(s[0].lines[1].time, '09:18');
    expect(s[0].lines[1].text, startsWith('Bàn giao tòa B'));
    expect(s[1].lines.length, 3);
  });

  testWidgets('người xem: ba kiểu màn hình × tối / sáng; việc của tôi nổi bật', (t) async {
    await pumpAppForms(t, 'bien-ban-nguoi-xem', spec(), appCtx('minutes', _view(), role: 'member', title: 'Biên bản giao ban T12'), check: (t, form, light) async {
      expect(find.text('Nhận việc'), findsOneWidget);
      expect(find.textContaining('Việc của tôi · 1'), findsOneWidget);
      expect(find.text('Gõ thẳng vào biên bản…'), findsNothing);
    });
  });

  testWidgets('người ghi: ba kiểu màn hình × tối / sáng; hộp đề xuất, nút gắn nhãn, chốt', (t) async {
    await pumpAppForms(t, 'bien-ban-nguoi-ghi', spec(), appCtx('minutes', _view(writer: true), title: 'Biên bản giao ban T12'), check: (t, form, light) async {
      expect(find.text('Quyết định'), findsOneWidget);
      expect(find.text('ĐỀ XUẤT SỬA · 1'), findsOneWidget);
      expect(find.text('Chốt và gửi mọi người'), findsOneWidget);
    });
  });

  Future<void> pump(WidgetTester t, PageCtx ctx) async {
    t.view.physicalSize = const Size(430, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PageAppShell(ctx: ctx, spec: spec(), theme: const StageTheme())))));
    await t.pump();
  }

  testWidgets('người xem: nhận việc, đổi hạn, đề xuất sửa một dòng', (t) async {
    await pump(t, appCtx('minutes', _view(), role: 'member'));
    await t.tap(find.text('Nhận việc'));
    await t.pump();
    expect(appActs.last.$1, 'claim');
    expect(appActs.last.$2, {'id': 't1'});
    await t.tap(find.text('Đổi hạn'));
    await t.pump();
    await t.tap(find.text('Ngày mai'));
    await t.pump();
    expect(appActs.last.$1, 'task');
    expect(appActs.last.$2['id'], 't1');
    expect(appActs.last.$2['due'], matches(RegExp(r'^\d{2}/\d{2}$')));
    await t.tap(find.textContaining('Kim trình bày 3 hợp đồng mới').last);
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('min-suggest-text')), '09:32 · Kim trình bày 3 hợp đồng mới, tổng 4 tỷ.');
    await t.tap(find.text('Gửi đề xuất'));
    await t.pump();
    expect(appActs.last.$1, 'suggest');
    expect(appActs.last.$2, {'orig': '09:32 · Kim trình bày 3 hợp đồng mới.', 'text': '09:32 · Kim trình bày 3 hợp đồng mới, tổng 4 tỷ.'});
  });

  testWidgets('người ghi: gắn nhãn Quyết định vào biên bản, nhận đề xuất, thêm việc, chốt hai lần bấm', (t) async {
    await pump(t, appCtx('minutes', _view(writer: true)));
    await t.tap(find.text('Quyết định'));
    await t.pump(const Duration(seconds: 1));
    expect(appActs.last.$1, 'text');
    expect('${appActs.last.$2['text']}', matches(RegExp(r'\n\d{2}:\d{2} · QUYẾT ĐỊNH: $')));
    await t.tap(find.text('Nhận'));
    await t.pump();
    expect(appActs.last.$1, 'suggest_accept');
    expect(appActs.last.$2, {'id': 's1'});
    await t.tap(find.text('Việc + người'));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('min-task-text')), 'Gửi báo giá');
    await t.tap(find.text('Thêm việc'));
    await t.pump();
    expect(appActs.last.$1, 'add_task');
    expect(appActs.last.$2['text'], 'Gửi báo giá');
    appActs.clear();
    await t.ensureVisible(find.byKey(const ValueKey('min-close')));
    await t.tap(find.byKey(const ValueKey('min-close')));
    await t.pump();
    expect(appActs, isEmpty);
    await t.tap(find.byKey(const ValueKey('min-close')));
    await t.pump();
    expect(appActs.first.$1, 'close');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('sân khấu: mục đang ghi, đã chốt hôm nay', (t) async {
    for (final light in [false, true]) {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(MaterialApp(
        home: Material(
          color: StageTheme(light: light).bg,
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: StageMetrics(theme: StageTheme(light: light), portrait: false, size: const Size(1200, 640), child: MinutesAppStage(appCtx('minutes', _view()))),
          ),
        ),
      ));
      expect(find.text('3 · HỢP ĐỒNG THÁNG 11'), findsOneWidget);
      expect(find.text('ĐÃ CHỐT HÔM NAY'), findsOneWidget);
      expect(find.textContaining('Chọn đơn vị A'), findsWidgets);
    }
    t.view.resetPhysicalSize();
  });
}
