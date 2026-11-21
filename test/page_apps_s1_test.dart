// Đợt 1 của "mỗi trang là một app": Chào mừng, Chương trình (trang thường) và Chào mừng / Nội dung / Chờ lượt (trang hệ
// thống) trong vỏ app ở ba kiểu màn hình × tối / sáng, không tràn; thao tác gửi đúng hành động; dải thao tác nhanh dưới
// ô sân khấu. APP_OUT=<thư mục>: lưu ảnh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/pages_api.dart';
import 'package:flygo_chat/ui/pages/pages_sheet.dart';
import 'package:flygo_chat/ui/pages/sys_apps.dart';
import 'package:flygo_chat/ui/pages/types/welcome_agenda.dart';

import 'app_kit_helpers.dart';

final _now = DateTime.now().millisecondsSinceEpoch;
final _call = appTestState.calls;

/// Ngữ cảnh trang hệ thống như sysAppCtx, nhưng ghi lại hành động (không gọi máy chủ) và chọn vai trò.
PageCtx _sys(String id, {String role = 'viewer', bool presenting = false}) {
  final c = sysAppCtx(_call, id);
  return PageCtx(
    data: PageData(c.page, c.view, role, 0),
    api: PagesApi(_call),
    call: _call,
    presenting: presenting,
    onStage: false,
    act: (a, [b = const {}]) async => appActs.add((a, b)),
    reload: () async {},
  );
}

final _program = {
  'title': 'Nội dung giao ban', 'current': 1, 'auto': true,
  'fb': {'index': 1, 'more': ['x1', 'x2'], 'clear': ['x3']},
  'items': [
    {'title': 'Khai mạc', 'owner': 'u1', 'owner_name': 'Dương Văn Ba', 'minutes': 5},
    {'title': 'Tiến độ lắp đặt tòa B', 'owner': 'u2', 'owner_name': 'Nguyễn Văn Lợi', 'minutes': 10},
    {'title': 'Hợp đồng tháng 11', 'owner': 'u3', 'owner_name': 'Mai Kim', 'minutes': 8},
    {'title': 'An toàn lao động', 'owner': '', 'owner_name': '', 'minutes': 5},
  ],
};

Map<String, dynamic> _stage(Map<String, dynamic> extra) => {
      'page': '', 'theme_cfg': {'accent': '#3D7BFF', 'mode': 'dark'}, 'meeting_title': 'Giao ban tháng 12',
      'welcome_cfg': {'heading': 'Chào mừng mọi người đến buổi giao ban', 'subtitle': 'Tiến độ tòa B, hợp đồng tháng 11.', 'bg': 'brand:dark', 'countdown': true, 'countdown_to': _now + 292000, 'show_online': true},
      'program_cfg': _program,
      'handover_cfg': {'title': 'Mời {name} trình bày', 'auto_seconds': 10, 'show_avatar': true},
      'queue': [{'id': 'q1', 'name': 'Lê Minh'}, {'id': 'q2', 'name': 'Trần Quang'}],
      ...extra,
    };

void main() {
  setUpAll(loadAppTestFonts);
  setUp(() {
    appActs.clear();
    AgendaReminders.debugReset();
    sysAppEditing.value = null;
  });
  tearDown(() => _call.roomStage = null);

  testWidgets('Chào mừng: người xem vẫy chào, chủ trang chỉnh nền / sửa chữ tại chỗ', (t) async {
    final spec = pageTypeOf('welcome')!;
    final content = {'heading': 'Chào mừng mọi người đến buổi giao ban', 'subtitle': 'Tiến độ tòa B, hợp đồng tháng 11.', 'bg': 'brand:dark', 'countdown': true, 'countdown_to': _now + 292000};
    await pumpAppForms(t, 'chao-mung-nguoi-xem', spec, appCtx('welcome', const {}, role: 'member', content: content), check: (t, form, _) async {
      expect(find.byKey(const ValueKey('welcome-wave')), findsOneWidget);
      expect(find.text('ĐIỀU KHIỂN'), findsNothing);
    });
    await pumpAppForms(t, 'chao-mung-chu-trang', spec, appCtx('welcome', const {}, content: content), check: (t, form, _) async {
      expect(find.text('ĐIỀU KHIỂN'), findsOneWidget);
      expect(find.text('Đếm ngược tới giờ họp'), findsOneWidget);
    });
    await pumpAppForms(t, 'chao-mung-sua', spec, appCtx('welcome', const {}, content: content), editing: true, forms: ['dien-thoai-doc', 'may-tinh'], check: (t, form, _) async {
      expect(find.byKey(const ValueKey('welcome-heading')), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);
    });
    // Bấm vẫy chào: tên hiện trên khung sân khấu.
    await pumpAppForms(t, 'chao-mung-vay', spec, appCtx('welcome', const {}, role: 'member', content: content), forms: ['dien-thoai-doc'], check: (t, _, _) async {
      await t.tap(find.byKey(const ValueKey('welcome-wave')));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Bạn vẫy chào'), findsWidgets);
    });
  });

  testWidgets('Chương trình: dòng thời gian, nhắc tôi, chủ trang chuyển phiên / dời lịch / sửa', (t) async {
    final spec = pageTypeOf('agenda')!;
    final content = {
      'items': [
        {'text': 'Khai mạc', 'who': 'Dương Văn Ba', 'time': '08:30', 'minutes': 30, 'room': 'Hội trường A'},
        {'text': 'Thang máy không phòng máy thế hệ mới', 'who': 'Nguyễn Văn Lợi', 'minutes': 45, 'room': 'Hội trường A'},
        {'text': 'Nghỉ giải lao', 'minutes': 15},
        {'text': 'Bảo trì dự đoán bằng cảm biến', 'who': 'Mai Kim', 'minutes': 45, 'room': 'Phòng B2'},
        {'text': 'Tọa đàm: an toàn khu chung cư', 'minutes': 60},
      ],
    };
    final view = {'current': 1, 'started_at': _now - 27 * 60000};
    await pumpAppForms(t, 'chuong-trinh-nguoi-xem', spec, appCtx('agenda', view, role: 'member', content: content), check: (t, form, _) async {
      expect(find.text('ĐANG DIỄN RA'), findsOneWidget);
      expect(find.text('09:00'), findsWidgets);
      expect(find.text('ĐIỀU KHIỂN'), findsNothing);
    });
    await pumpAppForms(t, 'chuong-trinh-nhac', spec, appCtx('agenda', view, role: 'member', content: content), forms: ['dien-thoai-doc'], check: (t, _, light) async {
      // Trạng thái (nhắc, tab) giữ qua lần dựng sáng: chỉ thao tác ở lần tối.
      if (light) return;
      await t.ensureVisible(find.byKey(const ValueKey('agenda-remind-3')));
      await t.tap(find.byKey(const ValueKey('agenda-remind-3')));
      await t.pump();
      expect(find.text('Của tôi · 1'), findsOneWidget);
      await t.tap(find.text('Của tôi · 1'));
      await t.pump();
      expect(find.text('Bảo trì dự đoán bằng cảm biến'), findsWidgets);
      expect(find.byKey(const ValueKey('agenda-remind-2')), findsNothing);
      expect(find.byKey(const ValueKey('agenda-remind-3')), findsOneWidget);
    });
    await pumpAppForms(t, 'chuong-trinh-chu-trang', spec, appCtx('agenda', view, content: content), check: (t, form, _) async {
      expect(find.byKey(const ValueKey('agenda-shift-10')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('agenda-next')));
      await t.tap(find.byKey(const ValueKey('agenda-next')));
      await t.pump();
      expect(appActs.last.$1, 'next');
    });
    await pumpAppForms(t, 'chuong-trinh-sua', spec, appCtx('agenda', view, content: content), editing: true, forms: ['dien-thoai-doc', 'may-tinh'], check: (t, _, _) async {
      expect(find.byKey(const ValueKey('agenda-add')), findsOneWidget);
      expect(find.text('SỬA CHƯƠNG TRÌNH'), findsOneWidget);
    });
  });

  testWidgets('Nội dung (hệ thống): người xem "Cần thêm thời gian / Đã rõ", chủ trì trao lượt, tự chạy, sửa', (t) async {
    _call.roomStage = _stage({'page': 'sys:program', 'presenter': 'u1', 'presenter_name': 'Dương Văn Ba'});
    final spec = sysAppSpec('sys:program')!;
    await pumpAppForms(t, 'noi-dung-nguoi-xem', spec, _sys('sys:program'), check: (t, form, _) async {
      expect(find.text('2 người cần thêm thời gian · 1 người đã rõ'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('program-more')));
      await t.tap(find.byKey(const ValueKey('program-more')));
      await t.pump();
      expect((appActs.last.$1, appActs.last.$2['fb']), ('program_fb', 'more'));
    });
    await pumpAppForms(t, 'noi-dung-chu-tri', spec, _sys('sys:program', role: 'manager'), check: (t, form, _) async {
      expect(find.text('Trao lượt cho Nguyễn Văn Lợi'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('program-next')));
      await t.tap(find.byKey(const ValueKey('program-next')));
      await t.pump();
      expect(appActs.last.$1, 'program_next');
    });
    await pumpAppForms(t, 'noi-dung-sua', spec, _sys('sys:program', role: 'manager'), editing: true, forms: ['dien-thoai-doc', 'may-tinh'], check: (t, _, _) async {
      expect(find.byKey(const ValueKey('program-add')), findsOneWidget);
      expect(find.text('Phụ trách'), findsNWidgets(4));
    });
  });

  testWidgets('Chờ lượt (hệ thống): hàng chờ + xin lượt, người được mời bắt đầu / lùi, chủ trì sắp xếp', (t) async {
    final spec = sysAppSpec('sys:handover')!;
    _call.roomStage = _stage({
      'page': 'sys:handover', 'presenter': 'kim', 'presenter_name': 'Mai Kim', 'ends_at': _now + 6000,
      'handover': {'name': 'Mai Kim', 'uid': 'kim', 'pages': 2, 'seconds': 480, 'next': 'Lê Minh'},
    });
    await pumpAppForms(t, 'cho-luot-nguoi-xem', spec, _sys('sys:handover'), check: (t, form, _) async {
      expect(find.text('BÂY GIỜ'), findsWidgets);
      await t.ensureVisible(find.byKey(const ValueKey('handover-request')));
      await t.tap(find.byKey(const ValueKey('handover-request')));
      await t.pump();
      expect(appActs.last.$1, 'request');
    });
    await pumpAppForms(t, 'cho-luot-chu-tri', spec, _sys('sys:handover', role: 'manager'), forms: ['dien-thoai-doc', 'may-tinh'], check: (t, form, _) async {
      await t.ensureVisible(find.byKey(const ValueKey('handover-up-1')));
      await t.tap(find.byKey(const ValueKey('handover-up-1')));
      await t.pump();
      expect((appActs.last.$1, appActs.last.$2['user'], appActs.last.$2['to']), ('queue_move', 'q2', 0));
    });
    appTestState.me = MmUser({'id': 'me1', 'username': 'ba', 'first_name': 'Ba'});
    addTearDown(() => appTestState.me = null);
    _call.roomStage = {..._call.roomStage!, 'presenter': 'me1', 'presenter_name': 'Dương Văn Ba'};
    await pumpAppForms(t, 'cho-luot-den-luot', spec, _sys('sys:handover'), forms: ['dien-thoai-doc', 'dien-thoai-ngang'], check: (t, form, _) async {
      expect(find.text('ĐẾN LƯỢT BẠN TRÌNH BÀY'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('handover-defer')));
      await t.tap(find.byKey(const ValueKey('handover-defer')));
      await t.pump();
      expect(appActs.last.$1, 'defer');
    });
  });

  testWidgets('Chào mừng (hệ thống): chủ trì có nút sửa chữ tại chỗ', (t) async {
    _call.roomStage = _stage({'page': 'sys:welcome'});
    await pumpAppForms(t, 'chao-mung-he-thong', sysAppSpec('sys:welcome')!, _sys('sys:welcome', role: 'manager'), forms: ['dien-thoai-doc'], check: (t, _, _) async {
      expect(find.byKey(const ValueKey('welcome-edit')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('welcome-edit')));
      await t.tap(find.byKey(const ValueKey('welcome-edit')));
      await t.pump();
      expect(sysAppEditing.value, 'sys:welcome');
    });
  });

  testWidgets('ô sân khấu: dải thao tác nhanh dưới trang hệ thống, ô thu nhỏ thì không', (t) async {
    t.view.physicalSize = const Size(800, 560);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final (id, key) in [('sys:program', 'strip-more'), ('sys:welcome', 'strip-wave'), ('sys:handover', 'strip-request')]) {
      _call.roomStage = _stage({'page': id, 'presenter': 'kim', 'presenter_name': 'Mai Kim', 'handover': {'name': 'Mai Kim', 'uid': 'kim'}});
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 800, height: 520, child: StagePageView(call: _call)))));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: id);
      expect(find.byKey(ValueKey('strip-open-$id')), findsOneWidget);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 800, height: 520, child: StagePageView(call: _call, compact: true)))));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
