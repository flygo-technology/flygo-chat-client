// Câu hỏi của trợ lý đã trả lời nằm đúng chỗ đã hỏi trong dòng thời gian (không ghim xuống cuối thẻ),
// giữ đủ các lựa chọn, lựa chọn của mình có ✓ và in đậm.
// Ảnh xem trước (chạy tay): ASK_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/ask_card_order_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_view.dart';
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

const _question = 'Modem TNH này do Sếp/công ty quản lý, và Sếp muốn em làm tới đâu với hướng dẫn agent vừa gửi?';
const _options = [
  {'label': 'Chỉ giải mã backup', 'description': 'Đọc cấu hình, không chạm modem'},
  {'label': 'Giải mã + truy cập admin modem', 'description': 'Cần SSH vào modem, xin duyệt từng bước'},
  {'label': 'Dừng lại', 'description': ''},
];

/// [legacy]: runner cũ (bước hỏi không có step.questions, chỉ tiêu đề + chi tiết). [pending]: chưa trả lời.
AppState _app({bool legacy = false, bool pending = false}) {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.online = true;
  final now = DateTime.now().millisecondsSinceEpoch;
  final q = {
    'id': 'q1', 'question': _question, 'header': '', 'options': _options, 'multi': false, 'allow_other': true,
    'status': pending ? 'pending' : 'answered',
    if (!pending) ...{'answer': 'Giải mã + truy cập admin modem', 'choices': ['Giải mã + truy cập admin modem']},
  };
  final askStep = legacy
      ? {'id': 'ask-1', 'seg': 1, 'kind': 'approval', 'status': pending ? 'waiting' : 'done', 'title': 'Chờ trả lời: ${_question.substring(0, 60)}…',
          if (!pending) 'detail': 'Đã trả lời: Giải mã + truy cập admin modem'}
      : {'id': 'ask-1', 'seg': 1, 'kind': 'approval', 'status': pending ? 'waiting' : 'done',
          'title': pending ? 'Chờ trả lời: ${_question.substring(0, 60)}' : 'Đã trả lời: Giải mã + truy cập admin modem',
          'questions': [{...q, 'post_id': 'qp'}]};
  final run = MmPost({
    'id': 'run', 'channel_id': 'dm', 'user_id': 'bot', 'create_at': now - 10 * 60000, 'update_at': now - 30000,
    'message': 'pycryptodome và openssl đều có. Em viết bộ giải mã lớp 1 (AES-256-CBC + gzip) và chạy trên bản sao tệp.',
    'props': {
      'flygo_agent': {
        'status': pending ? 'awaiting_approval' : 'done', 'engine': 'claude',
        'texts': [
          'Để em làm đúng ý, Sếp xác nhận giúp một câu:',
          if (!pending) 'Sếp đã duyệt: **giải mã backup + truy cập admin modem**. Em tự viết bộ giải mã bằng Python, chạy trên bản sao. Trước hết em kiểm tra thư viện sẵn có.',
          if (!pending) 'pycryptodome và openssl đều có. Em viết bộ giải mã lớp 1 (AES-256-CBC + gzip) và chạy trên bản sao tệp.',
        ],
        'steps': [
          askStep,
          if (!pending) {'id': 'c1', 'seg': 2, 'kind': 'command', 'status': 'done', 'title': r'$ python3 -c "import Crypto"', 'label': 'Check for AES crypto libraries'},
          if (!pending) {'id': 'c2', 'seg': 3, 'kind': 'command', 'status': 'done', 'title': r'$ python3 decrypt.py backup.bin', 'label': 'Run layer-1 decryption of the modem backup'},
        ],
      },
      'flygo_agent_message': {'streaming': false},
    },
  });
  // Tin câu hỏi tạo giữa lượt (sau tin của thẻ chạy): trước đây hiện ghim dưới mọi bước làm sau đó.
  final qp = MmPost({
    'id': 'qp', 'channel_id': 'dm', 'user_id': 'bot', 'create_at': now - 8 * 60000, 'update_at': now - 7 * 60000,
    'message': '❓ $_question', 'props': {'flygo_agent_question': q},
  });
  app.debugPutPosts('dm', [qp, run]);
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
  for (final legacy in [false, true]) {
    testWidgets('answered question sits at the ask step, above the work after it (${legacy ? 'old runner' : 'step.questions'})', (t) async {
      t.view.physicalSize = const Size(420, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(_app(legacy: legacy), Brightness.light));
      await t.pump(const Duration(milliseconds: 300));
      // Không còn thẻ câu hỏi ghim ở cuối; câu hỏi hiện trong dòng thời gian, đúng một lần.
      expect(find.byType(AgentQuestionCard), findsNothing);
      expect(find.byType(AgentAnsweredQuestion), findsOneWidget);
      expect(find.text(_question), findsOneWidget);
      // Đủ các lựa chọn; lựa chọn của Sếp in đậm, có ✓.
      for (final o in _options) {
        expect(find.text(o['label']!), findsOneWidget);
      }
      final chosen = t.widget<Text>(find.text('Giải mã + truy cập admin modem'));
      expect(chosen.style?.fontWeight, FontWeight.w700);
      expect(t.widget<Text>(find.text('Dừng lại')).style?.fontWeight, FontWeight.w400);
      // Thứ tự thời gian: câu hỏi ở trên, phần làm tiếp sau khi trả lời ở dưới.
      final qY = t.getTopLeft(find.byType(AgentAnsweredQuestion)).dy;
      expect(qY, lessThan(t.getTopLeft(find.textContaining('Sếp đã duyệt')).dy));
      expect(qY, lessThan(t.getTopLeft(find.textContaining('pycryptodome')).dy));
      expect(t.getTopLeft(find.textContaining('Để em làm đúng ý')).dy, lessThan(qY));
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('an unanswered question stays as the card at the bottom', (t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(pending: true), Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgentQuestionCard), findsOneWidget);
    expect(find.byType(AgentAnsweredQuestion), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('answered card (standalone, older run) lists every option with the choice and the free text', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: AgentAnswerOptions(q: {
          'options': [{'label': 'Phở'}, {'label': 'Bún'}, {'label': 'Cơm'}],
          'choices': ['Phở', 'Cơm'],
          'other': 'thêm trứng',
        }),
      ),
    ));
    expect(t.widget<Text>(find.text('Phở')).style?.fontWeight, FontWeight.w700);
    expect(t.widget<Text>(find.text('Bún')).style?.fontWeight, FontWeight.w400);
    expect(t.widget<Text>(find.text('Cơm')).style?.fontWeight, FontWeight.w700);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.textContaining('thêm trứng', findRichText: true), findsOneWidget);
  });

  final out = Platform.environment['ASK_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
      testWidgets('ảnh câu hỏi đúng chỗ $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        await _fonts();
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light, key));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
