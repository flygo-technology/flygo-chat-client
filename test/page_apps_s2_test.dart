// Đợt 2 của "mỗi trang là một app": Tài liệu, Show, Video (trang thường), Chiếu màn hình, Video tự động / lưới (trang
// hệ thống) và Website của phòng trong vỏ app ở ba kiểu màn hình × tối / sáng, không tràn; thao tác gửi đúng hành động.
// APP_OUT=<thư mục>: lưu ảnh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/calls/call_service.dart';
import 'package:flygo_chat/calls/meet_room.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/meet/meet_present.dart' show PresentControl;
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/pages_api.dart';
import 'package:flygo_chat/ui/pages/sys_apps.dart';
import 'package:flygo_chat/ui/pages/sys_media_apps.dart';
import 'package:flygo_chat/ui/pages/types/media_apps.dart';
import 'package:provider/provider.dart';

import 'app_kit_helpers.dart';

final _call = appTestState.calls;
final _now = DateTime.now().millisecondsSinceEpoch;

Widget _withApp(Widget child) => ChangeNotifierProvider<AppState>.value(value: appTestState, child: child);

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

const _file = {'id': 'f1', 'url': '/meet/livekit/pagefile/hopdong.pdf', 'name': 'Hợp đồng tháng 11.pdf', 'pages': 12};

void main() {
  setUpAll(loadAppTestFonts);
  setUp(() {
    appActs.clear();
    sysVideoMine.value = '';
    webFollow.value = true;
    webSync.value = true;
  });
  tearDown(() {
    _call.roomStage = null;
    _call.roomPresent = null;
  });

  testWidgets('Tài liệu: chưa chiếu, người xem theo / tự lật, chủ trang lật cho cả phòng + bút vẽ', (t) async {
    final spec = pageTypeOf('doc')!;
    // Chưa trình chiếu: tên tệp, số trang; chủ trang có "Trình chiếu".
    await pumpAppForms(t, 'tai-lieu-chua-chieu', spec, appCtx('doc', const {}, content: {'file': _file}), wrap: _withApp, check: (t, _, _) async {
      expect(find.text('12 trang · chưa trình chiếu'), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-show')), findsOneWidget);
    });
    // Đang chiếu, người xem: theo người trình bày, bấm "Tự lật" rồi "Về trang đang trình bày".
    _call.roomPresent = {'id': 'f1', 'page_id': 'p1', 'by': 'loi', 'by_name': 'Nguyễn Văn Lợi', 'page': 4, 'pages': 12, 'name': _file['name'], 'url': _file['url']};
    final pc = PresentControl.of(_call);
    pc.free = false;
    await pumpAppForms(t, 'tai-lieu-nguoi-xem', spec, appCtx('doc', const {}, role: 'member', content: {'file': _file, 'allow_download': true}), wrap: _withApp, check: (t, form, light) async {
      expect(find.text('Đang theo Nguyễn Văn Lợi · trang 4 / 12'), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-download')), findsOneWidget);
      expect(find.text('ĐIỀU KHIỂN · CẢ PHÒNG THEO'), findsNothing);
    });
    await pumpAppForms(t, 'tai-lieu-tu-lat', spec, appCtx('doc', const {}, role: 'member', content: {'file': _file}), wrap: _withApp, forms: ['dien-thoai-doc'], check: (t, _, light) async {
      if (light) return;
      await t.ensureVisible(find.byKey(const ValueKey('doc-next')));
      await t.tap(find.byKey(const ValueKey('doc-next')));
      await t.pump();
      expect(find.text('Bạn đang tự xem trang 5 / 12'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('doc-follow')));
      await t.pump();
      expect(pc.free, isFalse);
    });
    // Chủ trang tắt tự lật: người xem không có dải trang, nút lật tắt.
    await pumpAppForms(t, 'tai-lieu-khoa-lat', spec, appCtx('doc', const {}, role: 'member', content: {'file': _file, 'viewer_flip': false}), wrap: _withApp, forms: ['dien-thoai-doc'], check: (t, _, _) async {
      expect(find.text('Chủ trang đang để mọi người theo người trình bày'), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-thumb-1')), findsNothing);
    });
    // Chủ trang đang trình bày: lật cả phòng, bút vẽ, laser.
    _call.roomPresent = {..._call.roomPresent!, 'by': ''};
    await pumpAppForms(t, 'tai-lieu-chu-trang', spec, appCtx('doc', const {}, content: {'file': _file}), wrap: _withApp, check: (t, form, light) async {
      expect(find.text('ĐIỀU KHIỂN · CẢ PHÒNG THEO'), findsOneWidget);
      expect(find.text('Trang 4 / 12'), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-tool-pen')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-stop')), findsOneWidget);
    });
    await pumpAppForms(t, 'tai-lieu-but', spec, appCtx('doc', const {}, content: {'file': _file}), wrap: _withApp, forms: ['dien-thoai-doc'], check: (t, _, light) async {
      if (light) return;
      await t.ensureVisible(find.byKey(const ValueKey('doc-tool-pen')));
      await t.tap(find.byKey(const ValueKey('doc-tool-pen')));
      await t.pump();
      expect(pc.ink, isTrue);
      expect(docStageInput(appCtx('doc', const {}, content: {'file': _file})), isTrue);
      expect(find.byKey(ValueKey('doc-color-${'#FFCC00'}')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('doc-tool-laser')));
      await t.pump();
      expect(pc.ink, isFalse);
      expect(pc.laser, isTrue);
      pc.laser = false;
    });
  });

  testWidgets('Video: người xem mốc chương / xem riêng / hỏi tại mốc, chủ trang phát cho cả phòng, sửa mốc', (t) async {
    final spec = pageTypeOf('video')!;
    final content = {
      'url': '', 'subtitles': '/x.vtt', 'allow_seek': true, 'auto_next': true,
      'chapters': [{'t': 0, 'title': 'Mở đầu'}, {'t': 115, 'title': 'Kiểm tra trước khi lên nóc cabin'}, {'t': 350, 'title': 'Cứu hộ khi kẹt thang'}],
    };
    final view = {'playing': false, 'pos': 252.0, 'at': _now, 'asks': [{'id': 'a1', 't': 270, 'text': 'Dây an toàn loại nào?', 'name': 'Mai Kim', 'mine': true}]};
    // Không có url: trống, chủ trang được nhắc thêm.
    await pumpAppForms(t, 'video-trong', spec, appCtx('video', view, role: 'member', content: content), forms: ['dien-thoai-doc'], check: (t, _, _) async {
      expect(find.text('Chưa có video'), findsOneWidget);
    });
    final c2 = {...content, 'url': 'https://example.invalid/an-toan.mp4'};
    await pumpAppForms(t, 'video-nguoi-xem', spec, appCtx('video', view, role: 'member', content: c2), check: (t, _, light) async {
      expect(find.text('Đang xem cùng phòng · 04:12'), findsOneWidget);
      expect(find.text('Kiểm tra trước khi lên nóc cabin'), findsOneWidget);
      expect(find.text('Hỏi ở 04:12'), findsOneWidget);
      expect(find.text('Bạn đã hỏi 1 lần'), findsOneWidget);
    });
    await pumpAppForms(t, 'video-hoi', spec, appCtx('video', view, role: 'member', content: c2), forms: ['dien-thoai-doc'], check: (t, _, light) async {
      if (light) return;
      await t.tap(find.byKey(const ValueKey('video-chapter-2')));
      await t.pump();
      expect(find.text('Bạn đang xem riêng'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('video-follow')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('video-ask')));
      await t.tap(find.byKey(const ValueKey('video-ask')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('video-ask-text')), 'Khoá cửa tầng thế nào?');
      await t.ensureVisible(find.byKey(const ValueKey('video-ask-send')));
      await t.tap(find.byKey(const ValueKey('video-ask-send')));
      await t.pump();
      expect(appActs.last.$1, 'ask');
      expect(appActs.last.$2['text'], 'Khoá cửa tầng thế nào?');
      expect((appActs.last.$2['t'] as num).round(), 252);
    });
    await pumpAppForms(t, 'video-chu-trang', spec, appCtx('video', view, content: c2), check: (t, _, light) async {
      expect(find.byKey(const ValueKey('video-play')), findsOneWidget);
      expect(find.text('CÂU HỎI THEO MỐC'), findsOneWidget);
      if (light) return;
      await t.ensureVisible(find.byKey(const ValueKey('video-play')));
      await t.tap(find.byKey(const ValueKey('video-play')));
      await t.pump();
      expect(appActs.last.$1, 'play');
    });
    await pumpAppForms(t, 'video-sua', spec, appCtx('video', view, content: c2), editing: true, forms: ['dien-thoai-doc', 'may-tinh'], check: (t, _, _) async {
      expect(find.text('SỬA VIDEO'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-ch-1')), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);
    });
  });

  test('phụ đề WebVTT', () {
    final cues = parseVtt('WEBVTT\n\n00:01.000 --> 00:04.000\nLuôn đeo dây an toàn\n\n1\n00:00:05.500 --> 00:00:07.000 align:center\n<b>Kiểm tra</b> cáp tải\n');
    expect(cues.length, 2);
    expect(cues[0].$3, 'Luôn đeo dây an toàn');
    expect(cues[1].$1, 5.5);
    expect(cues[1].$3, 'Kiểm tra cáp tải');
    expect(fmtClock(3725), '1:02:05');
  });

  testWidgets('Show: người xem thả cảm xúc theo slide / xem lại slide đã qua, chủ trang điều khiển', (t) async {
    final spec = pageTypeOf('show')!;
    final view = {'slide': 6, 'total': 18, 'title': 'Mục tiêu tăng 18%', 'counts': {'hay': 12, 'ro': 7, 'chua': 2}, 'mine': 'hay',
      'seen': [for (var i = 1; i <= 6; i++) {'slide': i, 'title': i == 6 ? 'Mục tiêu tăng 18%' : 'Slide $i'}]};
    await pumpAppForms(t, 'show-nguoi-xem', spec, appCtx('show', view, role: 'member', content: {'deck_title': 'Kế hoạch quý 1', 'pid': 'p9'}), wrap: _withApp, check: (t, form, light) async {
      expect(find.text('SLIDE 6 / 18'), findsOneWidget);
      expect(find.text('12 hay · 7 rõ · 2 chưa hiểu'), findsOneWidget);
      if (light || form != 'dien-thoai-doc') return;
      await t.ensureVisible(find.byKey(const ValueKey('show-react-chua')));
      await t.tap(find.byKey(const ValueKey('show-react-chua')));
      await t.pump();
      expect(appActs.last.$1, 'react');
      expect(appActs.last.$2, {'kind': 'chua'});
      await t.tap(find.byKey(const ValueKey('show-react-hay')));
      await t.pump();
      expect(appActs.last.$1, 'react');
      expect(appActs.last.$2, {'kind': ''});
      await t.ensureVisible(find.byKey(const ValueKey('show-seen-3')));
      await t.tap(find.byKey(const ValueKey('show-seen-3')));
      await t.pump();
      expect(find.text('Slide 3: Slide 3'), findsOneWidget);
    });
    await pumpAppForms(t, 'show-chua-chieu', spec, appCtx('show', {'slide': 0}, role: 'member', content: {'deck_title': 'Kế hoạch quý 1'}), wrap: _withApp, forms: ['dien-thoai-doc'], check: (t, _, _) async {
      expect(find.text('Chưa bắt đầu chiếu'), findsOneWidget);
      expect(find.text('ĐIỀU KHIỂN'), findsNothing);
    });
    await pumpAppForms(t, 'show-chu-trang', spec, appCtx('show', view, content: {'deck_title': 'Kế hoạch quý 1', 'pid': 'p9'}), wrap: _withApp, check: (t, _, _) async {
      expect(find.text('GHI CHÚ NGƯỜI NÓI'), findsOneWidget);
      expect(find.byKey(const ValueKey('show-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('show-blank')), findsOneWidget);
    });
  });

  testWidgets('Chiếu màn hình (hệ thống): người xem vừa khung / chỉ laser, chủ trì che màn hình, cho chỉ laser', (t) async {
    _call.debugMeeting('ch-media', [CallParticipant('s1', 'u1')..screen = true..screenAt = _now]);
    _call.roomStage = {'page': 'sys:screen', 'presenter': '', 'theme_cfg': {'mode': 'dark'}, 'screen_cfg': {'cover': false, 'laser': true}};
    final spec = sysAppSpec('sys:screen')!;
    await pumpAppForms(t, 'chieu-man-hinh-nguoi-xem', spec, _sys('sys:screen'), wrap: _withApp, check: (t, _, light) async {
      expect(find.byKey(const ValueKey('screen-fit')), findsOneWidget);
      expect(find.byKey(const ValueKey('screen-laser')), findsOneWidget);
      expect(find.text('ĐIỀU KHIỂN'), findsNothing);
      if (light) return;
      final z = screenZoomReset.value;
      await t.tap(find.byKey(const ValueKey('screen-fit')));
      await t.pump();
      expect(screenZoomReset.value, z + 1);
      await t.tap(find.byKey(const ValueKey('screen-laser')));
      await t.pump();
      expect(screenLaserOn.value, isTrue);
      screenLaserOn.value = false;
    });
    await pumpAppForms(t, 'chieu-man-hinh-chu-tri', spec, _sys('sys:screen', role: 'manager'), wrap: _withApp, check: (t, _, light) async {
      expect(find.text('ĐIỀU KHIỂN'), findsOneWidget);
      if (light) return;
      await t.ensureVisible(find.byKey(const ValueKey('screen-cover')));
      await t.tap(find.byKey(const ValueKey('screen-cover')));
      await t.pump();
      expect(appActs.last.$1, 'screen_cfg');
      expect(appActs.last.$2, {'cover': true});
    });
  });

  testWidgets('Video tự động / lưới (hệ thống): người xem xem riêng / giơ tay, chủ trì bố cục cả phòng', (t) async {
    _call.debugMeeting('ch-media', [CallParticipant('s1', 'u1')..speaking = true, CallParticipant('s2', 'u2')..raisedHand = true, CallParticipant('s3', 'u3')]);
    _call.roomStage = {'page': 'sys:auto', 'theme_cfg': {'mode': 'dark'}, 'video_cfg': {'spot': '', 'hide_off': false, 'lock': false}};
    final spec = sysAppSpec('sys:auto')!;
    await pumpAppForms(t, 'video-tu-dong-nguoi-xem', spec, _sys('sys:auto'), wrap: _withApp, check: (t, _, light) async {
      expect(find.text('Theo phòng'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-hand')), findsOneWidget);
      if (light) return;
      await t.tap(find.text('Lưới'));
      await t.pump();
      expect(sysVideoMine.value, 'grid');
      sysVideoMine.value = '';
    });
    await pumpAppForms(t, 'video-tu-dong-chu-tri', spec, _sys('sys:auto', role: 'manager'), wrap: _withApp, check: (t, _, light) async {
      expect(find.text('CẢ PHÒNG XEM'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-spot-u2')), findsOneWidget);
      if (light) return;
      await t.ensureVisible(find.byKey(const ValueKey('video-spot-u2')));
      await t.tap(find.byKey(const ValueKey('video-spot-u2')));
      await t.pump();
      expect([for (final a in appActs.sublist(appActs.length - 2)) a.$1], ['show', 'video_cfg']);
      expect(appActs.last.$2, {'spot': 'u2'});
      await t.ensureVisible(find.byKey(const ValueKey('video-lock')));
      await t.tap(find.byKey(const ValueKey('video-lock')));
      await t.pump();
      expect(appActs.last.$1, 'video_cfg');
      expect(appActs.last.$2, {'lock': true});
    });
    // Chủ trì khoá bố cục: người xem không đổi được cách xem riêng.
    _call.roomStage = {'page': 'sys:grid', 'theme_cfg': {'mode': 'dark'}, 'video_cfg': {'spot': '', 'lock': true}};
    await pumpAppForms(t, 'video-luoi-khoa', sysAppSpec('sys:grid')!, _sys('sys:grid'), wrap: _withApp, forms: ['dien-thoai-doc'], check: (t, _, _) async {
      expect(find.text('Chủ trì đang khoá bố cục'), findsOneWidget);
    });
  });

  testWidgets('Website của phòng: người xem tự cuộn / chép link, người điều khiển gõ địa chỉ, đồng bộ cuộn, dừng', (t) async {
    final room = MeetRoom(channelId: 'ch-web', token: 't', server: '', myId: 'me', onMuteMe: () {}, connect: false);
    room.debugApply({'type': 'web_open', 'url': 'https://flygo.vn/du-an/toa-b', 'from': {'user_id': 'loi'}});
    await pumpAppForms(t, 'website-nguoi-xem', webAppSpec(room), webAppCtx(_call, room), wrap: _withApp, check: (t, form, light) async {
      expect(find.byKey(const ValueKey('web-url')), findsOneWidget);
      expect(find.text('Đang theo cuộn của người điều khiển'), findsOneWidget);
      expect(find.text('ĐIỀU KHIỂN'), findsNothing);
      if (light || form != 'dien-thoai-doc') return;
      await t.tap(find.byKey(const ValueKey('web-follow')));
      await t.pump();
      expect(webFollow.value, isFalse);
      expect(find.text('Bạn đang tự cuộn'), findsOneWidget);
      webFollow.value = true;
      await t.pump();
    });
    room.debugApply({'type': 'web_open', 'url': 'https://flygo.vn/du-an/toa-b', 'from': {'user_id': 'me'}});
    await pumpAppForms(t, 'website-dieu-khien', webAppSpec(room), webAppCtx(_call, room), wrap: _withApp, check: (t, form, light) async {
      expect(find.text('ĐIỀU KHIỂN'), findsOneWidget);
      expect(find.byKey(const ValueKey('web-close')), findsOneWidget);
      if (light || form != 'dien-thoai-doc') return;
      await t.ensureVisible(find.byKey(const ValueKey('web-sync')));
      await t.tap(find.byKey(const ValueKey('web-sync')));
      await t.pump();
      expect(webSync.value, isFalse);
      webSync.value = true;
      await t.pump();
    });
    room.dispose();
  });
}
