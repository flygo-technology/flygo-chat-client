// Ảnh xem trước cột phải chat trợ lý + thẻ bash (chạy tay): AP_OUT=<thư mục> flutter test test/agent_side_panel_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_side_panel.dart';
import 'package:flygo_chat/ui/agent_view.dart';
import 'package:flygo_chat/ui/chat_themes.dart';
import 'package:flygo_chat/ui/markdown_view.dart';
import 'package:flygo_chat/ui/shell_highlight.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']); // theme Linux dùng Noto Sans
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // Phông đóng gói của chat trợ lý (pubspec) — kiểm thử không tự nạp.
  Future<void> asset(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }

  await asset('Flygo Roboto', ['Roboto-Regular.ttf', 'Roboto-Italic.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await asset('JetBrains Mono', ['JetBrainsMono-Regular.ttf', 'JetBrainsMono-Medium.ttf', 'JetBrainsMono-Bold.ttf', 'JetBrainsMono-Italic.ttf']);
  // Chữ đơn cách cũ ('monospace': máy Linux lấy DejaVu) cho ảnh "trước".
  final mono = FontLoader('monospace');
  for (final f in ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf']) {
    if (File(f).existsSync()) mono.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await mono.load();
}

const _g = 'gggggggggggggggggggggggggg';
const _me = 'mmmmmmmmmmmmmmmmmmmmmmmmmm';

void main() {
  final out = Platform.environment['AP_OUT'];
  final app = AppState('t')..me = MmUser({'id': _me, 'username': 'owner', 'first_name': 'Owner'});
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'coder', 'first_name': 'Coder', 'is_bot': true});
  final now = DateTime(2026, 11, 14, 15, 30).millisecondsSinceEpoch;
  MmChannel session(String id, String title, int at, {String header = ''}) => MmChannel({
        'id': id,
        'name': 'a-$_g-$_me-${id.substring(0, 4)}',
        'display_name': 'AI · Dự án web · $title',
        'type': 'P',
        'header': header,
        'last_post_at': at,
        'create_at': at - 3600000,
      });
  app.channels[_g] = MmChannel({'id': _g, 'name': 'p-$_me-abcdefgh', 'display_name': 'Dự án web', 'type': 'P'});
  for (final c in [
    session('s1aaaaaaaaaaaaaaaaaaaaaaaa', 'Sửa lỗi build iOS', now),
    session('s2aaaaaaaaaaaaaaaaaaaaaaaa', 'Thêm trang báo cáo', now - 3 * 3600000),
    session('s3aaaaaaaaaaaaaaaaaaaaaaaa', 'Dọn ổ đĩa máy chủ', now - 26 * 3600000, header: '[flygo-ai-done]'),
    session('s4aaaaaaaaaaaaaaaaaaaaaaaa', 'Viết test API', now - 50 * 3600000),
  ]) {
    app.channels[c.id] = c;
  }
  const cur = 's1aaaaaaaaaaaaaaaaaaaaaaaa';
  MmPost post(String id, String by, String msg, int at, {Map<String, dynamic> props = const {}, List<Map<String, dynamic>> files = const []}) =>
      MmPost({'id': id, 'channel_id': cur, 'user_id': by, 'message': msg, 'create_at': at, 'update_at': at, 'props': props, 'metadata': {'files': files}});
  final posts = [
    post('p4', 'bot', 'Đã sửa xong, build chạy lại được.', now, props: {'flygo_bypass': true}),
    post('p3', _me, 'Xem log ở https://ci.example.com/builds/481 và tài liệu https://docs.flutter.dev/deployment/ios', now - 600000),
    post('p2', _me, 'Ảnh lỗi', now - 900000, files: [
      {'id': 'f1', 'name': 'loi-build.png', 'mime_type': 'image/png', 'size': 120000},
      {'id': 'f2', 'name': 'man-hinh.png', 'mime_type': 'image/png', 'size': 90000},
    ]),
    post('p1', _me, '', now - 1200000, files: [
      {'id': 'f3', 'name': 'build-log.txt', 'mime_type': 'text/plain', 'size': 48213},
      {'id': 'f4', 'name': 'Podfile.lock', 'mime_type': 'text/plain', 'size': 9120},
    ]),
  ];
  app.debugPutPosts(cur, posts);
  AgentSidePanel.debugScan = posts;
  AgentSidePanel.debugThumb = (f) => Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: f.id == 'f1' ? const [Color(0xFF5B8DEF), Color(0xFF9B6CF0)] : const [Color(0xFF3FB68B), Color(0xFFF2C14E)])),
        child: const Icon(Icons.image_outlined, color: Colors.white70),
      );
  BridgeApi.debugClient = MockClient((r) async {
    if (r.method == 'GET') {
      return http.Response(
          jsonEncode({
            'tokens': [
              {'token_id': 'tok1', 'created_at': now - 3600000, 'expires_at': now + 20 * 3600000, 'last_used_at': now - 120000, 'sends': 4, 'reads': 31},
            ]
          }),
          200);
    }
    return http.Response('{}', 200);
  });

  Future<void> shot(WidgetTester t, String name, Size size, Widget child, {bool dark = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    final theme = buildTheme(dark ? Brightness.dark : Brightness.light);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Builder(builder: (c) {
          final pal = claudePal(Pal.of(c), dark);
          return Theme(data: theme.copyWith(extensions: [pal], scaffoldBackgroundColor: pal.bg), child: RepaintBoundary(key: key, child: child));
        }),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  }

  final steps = <Map<String, dynamic>>[
    {
      'id': 'a',
      'kind': 'command',
      'title': r'$ cd ios && pod install --repo-update 2>&1 | tail -20',
      'label': 'Cài thư viện iOS',
      'status': 'done',
      'detail': 'Analyzing dependencies\nDownloading dependencies\nInstalling Firebase (11.4.0)\n[!] warning: deprecated option use_frameworks\nPod installation complete! There are 42 dependencies.'
    },
    {
      'id': 'b',
      'kind': 'command',
      'title': r'$ FLAVOR=prod flutter build ios --release --no-codesign && echo "ok: $?"',
      'label': 'Build iOS',
      'status': 'error',
      'detail': 'Running pod install...\nXcode build done.\nerror: Signing for "Runner" requires a development team.\nexit code 1'
    },
    {
      'id': 'c',
      'kind': 'command',
      'title': r'$ for f in lib/**/*.dart; do grep -n "TODO" "$f" || true; done # tìm việc còn sót',
      'label': 'Tìm TODO',
      'status': 'done',
      'detail': 'lib/main.dart:12: // TODO: bỏ cờ debug'
    },
  ];
  Widget stepList() => Builder(
        builder: (c) => Material(
          color: Pal.of(c).chatBg,
          child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, s) in steps.indexed) AgentStepRow(step: s, first: i == 0, last: i == steps.length - 1, open: true, onTap: () {}),
          ]),
        )),
      );
  Widget panel({bool page = false}) => AgentSidePanel(
        channelId: cur,
        asPage: page,
        onClose: page ? null : () {},
        onAction: (_) async {},
        actions: const [
          ('switch', Icons.view_list_outlined, 'Các phiên với trợ lý'),
          ('new', Icons.add_comment_outlined, 'Phiên mới'),
          ('window', Icons.open_in_new_rounded, 'Mở trong cửa sổ riêng'),
          ('fork', Icons.call_split, 'Tách phiên (fork)'),
          ('rename', Icons.edit_outlined, 'Đổi tên'),
          ('done', Icons.check_circle_outline_rounded, 'Đánh dấu xong'),
          ('fav', Icons.push_pin_outlined, 'Ghim'),
          ('search', Icons.search, 'Tìm trong đoạn chat'),
          ('archive', Icons.archive_outlined, 'Lưu trữ'),
          ('delete', Icons.delete_outline_rounded, 'Xoá phiên'),
        ],
      );

  const answer = '''## Nguyên nhân lỗi build iOS

Bản build thất bại vì **chưa chọn đội ký (development team)** cho target `Runner`. Xcode cần đội ký kể cả khi chỉ build thử trên máy.

Các bước sửa:

1. Mở `ios/Runner.xcworkspace` bằng Xcode.
2. Vào **Signing & Capabilities**, chọn đội *Flygo Technology*.
3. Chạy lại lệnh build:

```bash
flutter build ios --release
```

- Nếu vẫn lỗi, xoá thư mục `ios/Pods` rồi chạy `pod install`.
- Kiểm tra hồ sơ ký còn hạn: hồ sơ hết hạn sẽ báo lỗi tương tự.

> Ghi chú: lệnh ghi tệp vẫn chờ chủ phiên duyệt trước khi chạy.''';
  Widget answerView(TextStyle style) => Builder(
        builder: (c) => Material(
          color: Pal.of(c).chatBg,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), child: MarkdownView(text: answer, style: style)),
            ),
          ),
        ),
      );

  testWidgets('ảnh câu trả lời AI trước / sau', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    await shot(t, 'ai-answer-before', const Size(800, 760), Builder(builder: (c) => answerView(TextStyle(fontSize: 17, color: Pal.of(c).text, height: 1.3))));
    await shot(t, 'ai-answer-after', const Size(1000, 620), Builder(builder: (c) => answerView(aiAnswerStyle(Pal.of(c).text))));
    await shot(t, 'ai-answer-after-dark', const Size(1000, 620), Builder(builder: (c) => answerView(aiAnswerStyle(Pal.of(c).text))), dark: true);
  });

  testWidgets('ảnh xem trước cột phải + thẻ bash', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    await shot(t, 'bash-light', const Size(720, 560), stepList());
    await shot(t, 'bash-dark', const Size(720, 560), stepList(), dark: true);
    await shot(
        t,
        'desktop-panel',
        const Size(1280, 1500),
        Builder(
          builder: (c) => Scaffold(
            backgroundColor: Pal.of(c).bg,
            body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(child: stepList())),
              Container(width: .5, color: Pal.of(c).divider),
              SizedBox(width: 340, child: panel()),
            ]),
          ),
        ));
    await shot(t, 'desktop-panel-dark', const Size(340, 1500), panel(), dark: true);
    await shot(t, 'phone-panel', const Size(390, 1500), panel(page: true));
    await shot(
        t,
        'invite-dialog',
        const Size(520, 620),
        Builder(
          builder: (c) => Scaffold(
            body: BridgeInviteDialog(
              invite: BridgeInvite('tok2', 'https://chat.example.com/__apps/bridge/i/fgb_Q2xBa8Ws3mZt_7fKcX1d9vQyR2pLmN0aTsUeHgJbWo4i', '', '',
                  DateTime(2026, 11, 15, 15, 30)),
            ),
          ),
        ));
  });
}
