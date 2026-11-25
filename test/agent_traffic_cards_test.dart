// Thẻ gửi / nhận giữa các agent (biểu tượng, trạng thái, 3 dòng xem trước) và hộp xem đầy đủ khi bấm
// (điện thoại: trang trượt gần hết màn hình; máy tính: hộp giữa ~720 px). Thay cho thu gọn / mở rộng tại chỗ.
// Ảnh mockup (chạy tay): A2A_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/agent_traffic_cards_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_traffic.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f.startsWith('/') || f.startsWith('assets/') ? f : '$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  await load('Flygo Inter', [for (final f in ['Regular', 'Italic', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$f.ttf']);
  await load('JetBrains Mono', [for (final f in ['Regular', 'Medium', 'Bold']) 'assets/fonts/JetBrainsMono-$f.ttf']);
  final emoji = Platform.environment['EMOJI_FONT'];
  if (emoji != null) await load('Noto Color Emoji', [emoji]);
}

const _s3 = 's3aaaaaaaaaaaaaaaaaaaaaaaa';
const _hello = 'Chào đồng đội! Em là trợ lý của Sếp Ba. Nhờ anh kiểm tra giúp log build Windows mới nhất trên máy hn-kt-nam, '
    'báo lỗi đầu tiên và đề xuất cách sửa. Nếu cần quyền SSH thì báo lại em để em xin Sếp duyệt.';
const _long = '''Chạy lại toàn bộ test Flutter trên máy ảo **ct-a** (bản 531) và gửi lại:

1. Số test qua / lỗi
2. Tên các test lỗi, kèm 20 dòng log cuối của từng test
3. Thời gian chạy

Lưu ý:
- chạy `flutter test -j 2` (máy ảo yếu)
- nếu máy ảo không lên thì khởi động lại bằng `VBoxManage controlvm ct-a reset`
- xong thì báo em, em tổng hợp cho Sếp.''';

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.users['bot2'] = MmUser({'id': 'bot2', 'username': 'ba-claude', 'first_name': 'Ba Claude', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.channels[_s3] = MmChannel({'id': _s3, 'type': 'P', 'display_name': 'Build Windows'});
  app.online = true;
  final now = DateTime.now().millisecondsSinceEpoch;
  MmPost post(String id, String user, String msg, Map<String, dynamic> props, int ago) =>
      MmPost({'id': id, 'channel_id': 'dm', 'user_id': user, 'message': msg, 'create_at': now - ago * 60000, 'update_at': now, 'props': props});
  final posts = [
    post('u1', 'me', 'Nhờ @ba-claude xem log build Windows, và nhờ phiên Kiểm thử chạy lại test', {}, 30),
    post('r1', 'bot', _hello, {
      'flygo_silent': true,
      'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'out', 'from': {'session': 'dm', 'bot': 'jessica'}, 'to': {'bot': 'ba-claude'},
        'reply': {'state': 'failed', 'text': 'quá giờ, không có trả lời', 'at': now - 20 * 60000}},
    }, 29),
    post('r2', 'bot', _long, {
      'flygo_silent': true,
      'flygo_agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'out', 'from': {'session': 'dm', 'bot': 'jessica'}, 'to': {'session': _s3, 'name': 'Kiểm thử Android', 'bot': 'jessica'},
        'reply': {'state': 'completed', 'text': 'Đã chạy xong trên ct-a:\n- **1317** test qua\n- 1 bỏ qua\n- 0 lỗi\n\nThời gian: 3 phút 45 giây.', 'at': now - 12 * 60000}},
    }, 28),
    post('i1', 'bot', 'Kiểm tra giúp chứng thư số của công ty còn hạn tới khi nào, và gia hạn trước 30 ngày nếu sắp hết.', {
      'flygo_agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'in', 'from': {'session': _s3, 'name': 'Build Windows', 'bot': 'ba-claude'}, 'to': {'session': 'dm'}},
    }, 10),
    post('x1', 'me', 'Đã chạy test trên macbook: 42/42 qua, log ở ~/logs/test-531.txt', {
      'flygo_bridge': {'token_id': 't'},
      'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'in', 'from': {'agent': 'Claude Code · macbook'}},
    }, 6),
    post('a1', 'bot', 'Phiên **Kiểm thử Android** đã chạy lại: 1317 test qua, không lỗi ✅. @ba-claude chưa trả lời, em sẽ hỏi lại sau.', {
      'flygo_agent': {'status': 'done', 'engine': 'claude', 'texts': [''], 'steps': [
        {'id': 'a2a-1-x-q', 'seg': 0, 'kind': 'tool', 'status': 'done', 'title': 'Hỏi @ba-claude: $_hello', 'detail': _hello,
          'agent_link': {'v': 1, 'kind': 'message', 'dir': 'out', 'to': {'bot': 'ba-claude'}}},
        {'id': 'a2a-1-x-a', 'seg': 0, 'kind': 'message', 'status': 'done', 'title': '@ba-claude trả lời: Chào em, log có lỗi LNK1104…',
          'detail': 'Chào em, log có lỗi **LNK1104**: file `flygo_chat.exe` đang bị máy ảo cũ giữ. Khởi động lại máy ảo build là hết.',
          'agent_link': {'v': 1, 'kind': 'reply', 'dir': 'in', 'from': {'bot': 'ba-claude'}}},
      ]},
      'flygo_agent_message': {'streaming': false},
    }, 2),
  ];
  app.debugPutPosts('dm', posts.reversed.toList());
  app.hasMore['dm'] = false;
  return app;
}

Widget _wrap(AppState app, Brightness b, [Key? key]) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ChatPage(channelId: 'dm'),
        ),
      ),
    );

void main() {
  testWidgets('sent / received records are cards; tapping opens the full view (sheet on phone) with the reply', (t) async {
    t.view.physicalSize = const Size(420, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgentTrafficCard), findsNWidgets(4));
    expect(find.text('Gửi tới @ba-claude'), findsOneWidget);
    expect(find.text('không có trả lời'), findsOneWidget);
    expect(find.text('Gửi tới phiên Kiểm thử Android · @jessica'), findsOneWidget);
    expect(find.text('đã trả lời'), findsOneWidget);
    expect(find.text('Nhận từ phiên Build Windows · @ba-claude'), findsOneWidget);
    expect(find.text('Nhận từ agent ngoài Claude Code · macbook'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('agent-traffic-r2')));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-traffic-reply')), findsOneWidget);
    expect(find.descendant(of: find.byType(AgentTrafficView), matching: find.textContaining('VBoxManage', findRichText: true)), findsOneWidget);
    expect(find.text('Mở phiên'), findsOneWidget);
    expect(find.text('Sao chép'), findsOneWidget);
    await t.tap(find.byTooltip('Đóng'));
    await t.pumpAndSettle();

    // Bước "Hỏi @ba-claude" trong thẻ chạy: mở cùng hộp xem, kèm câu trả lời của bước đi kèm.
    await t.tap(find.text('Đã gửi tới @ba-claude, nhận 1 câu trả lời'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Hỏi @ba-claude').first);
    await t.pumpAndSettle();
    expect(find.byType(AgentTrafficView), findsOneWidget);
    expect(find.descendant(of: find.byType(AgentTrafficView), matching: find.textContaining('LNK1104', findRichText: true)), findsOneWidget);
    expect(find.text('Mở cuộc chat với @ba-claude'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop: a centred dialog ~720 px wide, at most 85% of the height', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('agent-traffic-r2')));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    final r = t.getRect(find.byType(AgentTrafficView));
    expect(r.width, lessThanOrEqualTo(720));
    expect(r.height, lessThanOrEqualTo(900 * .85 + .5));
    await t.pumpWidget(const SizedBox.shrink());
  });

  final out = Platform.environment['A2A_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
      for (final dialog in [false, true]) {
        testWidgets('mockup ${dialog ? 'hộp xem' : 'thẻ'} $name ${dark ? 'dark' : 'light'}', (t) async {
          if (out == null) return;
          await _fonts();
          t.view.physicalSize = size * 2;
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light, key));
          await t.pump(const Duration(milliseconds: 400));
          if (dialog) {
            await t.tap(find.byKey(const ValueKey('agent-traffic-r2')));
            await t.pump(const Duration(milliseconds: 600));
            await t.pump(const Duration(milliseconds: 600));
          }
          await t.runAsync(() async {
            // Hộp xem nằm ở lớp trên cùng: chụp cả màn hình.
            final ro = t.binding.renderViews.first.child!;
            final layer = ro.debugLayer! as OffsetLayer;
            final img = await layer.toImage(Offset.zero & size, pixelRatio: 2);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File('$out/${dialog ? 'dialog' : 'cards'}-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
          });
          key.toString();
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
