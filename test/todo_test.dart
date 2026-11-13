// Todo: trang chủ kiểu Keep (lưới, ghim, nhãn, nhắc, chia sẻ, hình nền), trang sửa (rich text, ô tick, Enter tách dòng,
// xoá đầu dòng gộp dòng), kho offline (mất mạng thì giữ lệnh, có mạng thì gửi) với backend giả.
// Ảnh xem trước (chạy tay): TD_OUT=<thư mục> flutter test test/todo_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/todo/api.dart';
import 'package:flygo_chat/ui/todo/block_editor.dart';
import 'package:flygo_chat/ui/todo/look.dart';
import 'package:flygo_chat/ui/todo/model.dart';
import 'package:flygo_chat/ui/todo/note_page.dart';
import 'package:flygo_chat/ui/todo/rich.dart';
import 'package:flygo_chat/ui/todo/store.dart';
import 'package:flygo_chat/ui/todo/todo_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _fonts() async {
  Future<void> load(String family, List<File> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (f.existsSync()) l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', [File('$dir/MaterialIcons-Regular.otf')]);
  await load('Noto Sans', [
    for (final f in ['noto/NotoSans-Regular.ttf', 'noto/NotoSans-Bold.ttf', 'dejavu/DejaVuSans.ttf', 'dejavu/DejaVuSans-Bold.ttf']) File('/usr/share/fonts/truetype/$f'),
  ]);
  await load('monospace', [File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')]);
}

Future<Uint8List> _png(Color a, Color b) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const r = Rect.fromLTWH(0, 0, 600, 400);
  c.drawRect(r, Paint()..shader = LinearGradient(colors: [a, b]).createShader(r));
  c.drawCircle(const Offset(430, 130), 80, Paint()..color = Colors.white.withValues(alpha: .55));
  c.drawPath(Path()..moveTo(0, 400)..lineTo(200, 230)..lineTo(380, 400)..close(), Paint()..color = Colors.black.withValues(alpha: .18));
  final img = await rec.endRecording().toImage(600, 400);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

final _now = DateTime.now().millisecondsSinceEpoch;
Map<String, dynamic> _run(String x, [Map<String, dynamic> f = const {}]) => {'x': x, ...f};
Map<String, dynamic> _b(String t, List<Map<String, dynamic>> r, {bool done = false, int ind = 0, String? id}) =>
    {'id': id ?? todoId(8), 't': t, 'r': r, if (done) 'done': true, if (ind > 0) 'ind': ind};
Map<String, dynamic> _p(String s) => _b('p', [_run(s)]);
Map<String, dynamic> _c(String s, [bool done = false]) => _b('check', [_run(s)], done: done);

const _me = {'id': 'me', 'name': 'Ba', 'role': 'owner'};
Map<String, dynamic> _note(String id, {String title = '', String kind = 'note', List<Map<String, dynamic>> blocks = const [], String color = 'default', String? bg,
        bool pinned = false, bool archived = false, double sort = 0, List<String> labels = const [], Map<String, dynamic>? reminder, List<Map<String, dynamic>> members = const [_me],
        String role = 'owner', List<Map<String, dynamic>> files = const [], int version = 1}) =>
    {
      'id': id, 'kind': kind, 'title': title, 'blocks': blocks, 'color': color, 'bg': bg, 'files': files, 'version': version, 'created_at': _now - 86400000,
      'updated_at': _now - 3600000, 'edited_by': 'me', 'role': role, 'pinned': pinned, 'archived': archived, 'trashed_at': null, 'sort': sort, 'labels': labels,
      'reminder': reminder, 'members': members,
    };

final _seed = <Map<String, dynamic>>[
  _note('n-plan', title: 'Kế hoạch tuần 46', pinned: true, sort: 100, color: 'sand', labels: ['l-work'], reminder: {'at': _now + 3 * 3600000, 'repeat': 'weekly'}, blocks: [
    _b('h2', [_run('Ưu tiên')]),
    _c('Chốt báo giá cho khách Hà Nội', true),
    _c('Gửi hợp đồng bản ký số'),
    _b('check', [_run('Họp '), _run('Kinh doanh', {'b': true}), _run(' lúc 14:00')]),
    _b('p', [_run('Ghi chú: '), _run('nhớ mang laptop', {'hl': 'yellow'})]),
  ]),
  _note('n-wifi', title: 'Wifi văn phòng', pinned: true, sort: 90, bg: 'g-ocean', blocks: [_b('p', [_run('Mạng: '), _run('Flygo-Office', {'c': true})]), _p('Khách dùng mạng Guest.')]),
  _note('n-shop', title: 'Đi chợ', kind: 'list', sort: 80, color: 'mint', bg: 'leaves', members: [_me, {'id': 'u2', 'name': 'Lan', 'role': 'editor'}], blocks: [
    _c('Sữa tươi'), _c('Bánh mì'), _c('Trứng gà', true), _c('Rau cải'),
  ]),
  _note('n-trip', title: 'Đà Lạt cuối tháng', sort: 70, files: [{'id': 'img1', 'name': 'da-lat.png', 'mime': 'image/png', 'size': 20480}], blocks: [_p('Đặt homestay gần hồ Xuân Hương, thuê xe máy 2 ngày.')]),
  _note('n-idea', title: '', sort: 60, color: 'dusk', bg: 'stars', blocks: [_b('p', [_run('Ý tưởng: '), _run('app Todo có MCP cho agent', {'i': true})])]),
  _note('n-meet', title: 'Biên bản họp', sort: 50, color: 'fog', labels: ['l-work'], files: [{'id': 'f-pdf', 'name': 'bien-ban-hop.pdf', 'mime': 'application/pdf', 'size': 182000}], blocks: [
    _b('ol', [_run('Doanh số tháng 11 tăng 18%')]), _b('ol', [_run('Tuyển thêm 2 kỹ thuật')]), _b('ul', [_run('Phụ trách: '), _run('Nam', {'fg': 'blue'})], ind: 1),
  ]),
  _note('n-quote', title: 'Câu hay', sort: 40, bg: 'g-sunset', blocks: [_b('quote', [_run('Làm ít nhưng làm cho tới.')])]),
  _note('n-shared', title: 'Lịch trực Tết', sort: 30, role: 'viewer', color: 'coral', members: [{'id': 'u3', 'name': 'Hoa', 'role': 'owner'}, {'id': 'me', 'name': 'Ba', 'role': 'viewer'}],
      blocks: [_p('29 Tết: Nam, Tuấn'), _p('Mùng 4: Lan, Mỹ')]),
  _note('n-old', title: 'Hoá đơn tháng 10', archived: true, sort: 20, blocks: [_p('Đã gửi kế toán')]),
];

class FakeBackend {
  final notes = <String, Map<String, dynamic>>{};
  final labels = [
    {'id': 'l-work', 'name': 'Công việc'},
    {'id': 'l-home', 'name': 'Nhà'},
  ];
  final files = <String, Uint8List>{};
  final calls = <String>[];
  bool down = false;
  int seq = 10;

  FakeBackend() {
    for (final n in _seed) {
      notes[n['id'] as String] = jsonDecode(jsonEncode(n)) as Map<String, dynamic>;
    }
  }

  http.Client client() => MockClient((req) async {
        final p = req.url.path;
        if (p == '/v1/token') return http.Response(jsonEncode({'token': 'tk', 'expires_in': 600, 'scope': ['use']}), 200, headers: {'content-type': 'application/json'});
        if (down) throw const SocketException('mất mạng');
        calls.add('${req.method} $p');
        Object? body;
        if (p == '/td/api/me') body = {'user': {'id': 'me', 'name': 'Ba', 'username': 'ba'}};
        if (p == '/td/api/sync') body = {'seq': seq, 'full': req.url.queryParameters['since'] == '0', 'notes': notes.values.toList(), 'gone': [], 'labels': labels};
        final m = RegExp(r'^/td/api/notes/([\w-]+)$').firstMatch(p);
        if (m != null && req.method == 'PUT') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final n = notes[m[1]!] ??= _note(m[1]!, version: 0);
          for (final k in ['kind', 'title', 'blocks', 'color', 'bg', 'pinned', 'archived', 'sort', 'labels', 'reminder']) {
            if (b.containsKey(k)) n[k] = b[k];
          }
          if (b.containsKey('trashed')) n['trashed_at'] = b['trashed'] == true ? _now : null;
          if (b.keys.any((k) => const {'kind', 'title', 'blocks', 'color', 'bg', 'files'}.contains(k))) n['version'] = (n['version'] as int) + 1;
          seq++;
          body = {'note': n, 'seq': seq};
        }
        final f = RegExp(r'^/td/api/files/(\w+)$').firstMatch(p);
        if (f != null && files[f[1]!] != null) return http.Response.bytes(files[f[1]!]!, 200, headers: {'content-type': 'image/png'});
        if (p == '/td/api/people') body = {'people': [{'id': 'u2', 'name': 'Lan', 'username': 'lan'}, {'id': 'u4', 'name': 'Nam', 'username': 'nam'}]};
        return body == null ? http.Response('{"error":"không có"}', 404) : http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });
}

void main() {
  final out = Platform.environment['TD_OUT'];

  late FakeBackend be;
  TodoStore newStore() {
    final c = be.client();
    return TodoStore(TodoApi(base: 'https://chat.test/td', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c), pollEvery: const Duration(hours: 1));
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, Widget child, {Size size = const Size(420, 900), Brightness theme = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      if (out != null) await _fonts();
      be.files['img1'] ??= await _png(const Color(0xFF7FB3D5), const Color(0xFF2E86C1));
    });
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)));
    await settle(t);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(t, 3);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  setUp(() => be = FakeBackend());

  testWidgets('trang chủ điện thoại: ghi chú nhanh, đã ghim / khác, nhãn, nhắc, chia sẻ, chỉ xem; lưu trữ không hiện', (t) async {
    final s = newStore();
    await pump(t, TodoHome(store: s, ownsStore: false), size: const Size(420, 1500));
    expect(find.text('Ghi chú nhanh…'), findsOneWidget);
    expect(find.text('ĐÃ GHIM'), findsOneWidget);
    expect(find.text('KHÁC'), findsOneWidget);
    expect(find.text('Kế hoạch tuần 46'), findsOneWidget);
    expect(find.text('Hoá đơn tháng 10'), findsNothing);
    expect(find.text('Chỉ xem'), findsOneWidget);
    expect(find.text('Công việc'), findsNWidgets(2));
    expect(t.getTopLeft(find.text('Kế hoạch tuần 46')).dy, lessThan(t.getTopLeft(find.text('Đi chợ')).dy));
    await shot(t, 'todo-1-dien-thoai-sang');
    // Tick ngay trên thẻ: gửi PUT.
    await t.tap(find.byType(Checkbox).at(2));
    await settle(t);
    expect(be.calls.where((c) => c.startsWith('PUT /td/api/notes/n-plan')), isNotEmpty);
    // Tìm kiếm.
    await t.tap(find.byTooltip('Tìm kiếm'));
    await t.pump();
    await t.enterText(find.byType(TextField), 'homestay');
    await settle(t, 2);
    expect(find.text('Đà Lạt cuối tháng'), findsOneWidget);
    expect(find.text('Đi chợ'), findsNothing);
    s.dispose();
  });

  testWidgets('điện thoại: bấm giữ thẻ rồi thả tay mở menu Ghim / Lưu trữ / Xoá; có nút đóng góc trên bên phải', (t) async {
    final s = newStore();
    await pump(t, Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => TodoHome(store: s, ownsStore: false))), child: const Text('mở'))))),
        size: const Size(420, 1500));
    await t.tap(find.text('mở'));
    await settle(t);
    expect(find.byTooltip('Đóng'), findsOneWidget);
    await t.longPress(find.text('Đi chợ'));
    await settle(t, 3);
    expect(find.text('Ghim'), findsOneWidget);
    expect(find.text('Lưu trữ'), findsOneWidget);
    expect(find.text('Xoá'), findsOneWidget);
    await shot(t, 'todo-7-bam-giu');
    await t.tap(find.text('Lưu trữ'));
    await settle(t, 3);
    expect(be.notes['n-shop']!['archived'], isTrue);
    expect(find.text('Đi chợ'), findsNothing);
    expect(find.text('Hoàn tác'), findsOneWidget);
    // Thẻ đã ghim: menu có "Bỏ ghim".
    await t.longPress(find.text('Wifi văn phòng'));
    await settle(t, 3);
    expect(find.text('Bỏ ghim'), findsOneWidget);
    await t.tap(find.text('Bỏ ghim'));
    await settle(t, 3);
    expect(be.notes['n-wifi']!['pinned'], isFalse);
    // Xoá: vào thùng rác.
    await t.longPress(find.text('Câu hay'));
    await settle(t, 3);
    await t.tap(find.text('Xoá'));
    await settle(t, 3);
    expect(be.notes['n-quote']!['trashed_at'], isNotNull);
    await t.tap(find.byTooltip('Đóng'));
    await settle(t, 2);
    expect(find.text('mở'), findsOneWidget);
    // Menu: "Quay về app Flygo Chat" đóng Todo.
    await t.tap(find.text('mở'));
    await settle(t);
    await t.tap(find.byTooltip('Menu'));
    await settle(t, 3);
    expect(find.text('Quay về app Flygo Chat'), findsOneWidget);
    await shot(t, 'todo-8-menu-quay-ve');
    await t.tap(find.text('Quay về app Flygo Chat'));
    await settle(t, 8);
    expect(find.text('mở'), findsOneWidget);
    expect(find.text('Ghi chú nhanh…'), findsNothing);
    await t.pump(const Duration(seconds: 5)); // thông báo "Hoàn tác" hết giờ
    s.dispose();
  });

  testWidgets('trang chủ máy tính: menu bên trái, lưới masonry nhiều cột, nền tối', (t) async {
    final s = newStore();
    await pump(t, TodoHome(store: s, ownsStore: false), size: const Size(1440, 900), theme: Brightness.dark);
    expect(find.text('Lời nhắc'), findsOneWidget);
    expect(find.text('Thùng rác'), findsOneWidget);
    await shot(t, 'todo-2-may-tinh-toi');
    s.dispose();
  });

  testWidgets('trang chủ máy tính nền sáng + mục Lưu trữ', (t) async {
    final s = newStore();
    await pump(t, TodoHome(store: s, ownsStore: false), size: const Size(1440, 900));
    await shot(t, 'todo-3-may-tinh-sang');
    await t.tap(find.text('Lưu trữ'));
    await settle(t, 2);
    expect(find.text('Hoá đơn tháng 10'), findsOneWidget);
    expect(find.text('Kế hoạch tuần 46'), findsNothing);
    s.dispose();
  });

  testWidgets('trang sửa: rich text, ô tick, Enter tách dòng, xoá đầu dòng gộp dòng, đậm', (t) async {
    final s = newStore();
    await t.runAsync(s.sync);
    final n = s.notes['n-plan']!;
    await pump(t, NotePage(store: s, note: n), size: const Size(420, 900));
    expect(find.text('Kế hoạch tuần 46'), findsOneWidget);
    await t.tap(find.byTooltip('Định dạng'));
    await settle(t, 2);
    expect(find.byTooltip('Đậm'), findsOneWidget);
    await shot(t, 'todo-4-sua-dien-thoai');
    s.dispose();
  });

  testWidgets('trang sửa danh sách việc, nền hình lá, màu và hình nền', (t) async {
    final s = newStore();
    await t.runAsync(s.sync);
    await pump(t, NotePage(store: s, note: s.notes['n-shop']!), size: const Size(420, 900), theme: Brightness.dark);
    expect(find.text('1 mục đã hoàn thành'), findsOneWidget);
    expect(find.text('Mục danh sách'), findsOneWidget);
    await shot(t, 'todo-5-danh-sach-toi');
    await t.tap(find.byTooltip('Màu và hình nền'));
    await settle(t, 3);
    expect(find.text('Màu chuyển'), findsOneWidget);
    await shot(t, 'todo-6-chon-nen');
    s.dispose();
  });

  testWidgets('soạn: Enter tách khối, xoá ở đầu dòng gộp lại, Ctrl+B đậm phần chọn', (t) async {
    var blocks = <TBlock>[TBlock.text('Xin chào bạn')];
    final ctl = BlockEditorController();
    await pump(t, Scaffold(body: BlockEditor(blocks: blocks, controller: ctl, onChanged: (b) => blocks = b)));
    final field = find.byType(TextField).first;
    await t.tap(field);
    await t.pump();
    final rc = (t.widget<TextField>(field).controller as RichController);
    // Đặt con trỏ sau "Xin chào" rồi Enter.
    rc.selection = const TextSelection.collapsed(offset: 1 + 8);
    rc.value = rc.value.copyWith(text: rc.text.replaceRange(9, 9, '\n'), selection: const TextSelection.collapsed(offset: 10));
    await settle(t, 2);
    expect(blocks.map((b) => b.text), ['Xin chào', ' bạn']);
    // Xoá ký tự rỗng đầu dòng thứ hai: gộp lại.
    final rc2 = t.widget<TextField>(find.byType(TextField).at(1)).controller as RichController;
    rc2.value = TextEditingValue(text: rc2.text.substring(1), selection: const TextSelection.collapsed(offset: 0));
    await settle(t, 2);
    expect(blocks.map((b) => b.text), ['Xin chào bạn']);
    // Chọn "chào" rồi đậm.
    final rc3 = t.widget<TextField>(find.byType(TextField).first).controller as RichController;
    rc3.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
    rc3.toggle('b');
    await settle(t, 1);
    expect(blocks.single.toJson()['r'], [
      {'x': 'Xin '},
      {'x': 'chào', 'b': true},
      {'x': ' bạn'},
    ]);
    // Gõ tiếp sau chữ đậm: chữ mới cũng đậm.
    rc3.value = TextEditingValue(text: rc3.text.replaceRange(9, 9, '!'), selection: const TextSelection.collapsed(offset: 10));
    await settle(t, 1);
    expect(blocks.single.r[1].x, 'chào!');
  });

  test('kho offline: mất mạng thì giữ lệnh, gộp nhiều lần sửa, có mạng thì gửi', () async {
    be = FakeBackend();
    final s = newStore();
    await s.sync();
    expect(s.notes.length, _seed.length);
    be.down = true;
    final n = s.draft();
    n.title = 'Viết lúc mất mạng';
    s.put(n, {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Lệnh trước đã gửi hỏng (mất mạng): lần sửa sau gộp vào lệnh đó.
    s.put(s.notes[n.id]!, {'title': 'Viết lúc mất mạng (sửa)'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.offline, isTrue);
    expect(s.pending, 1);
    expect(s.view('notes').first.title, 'Viết lúc mất mạng (sửa)');
    be.down = false;
    await s.sync();
    expect(s.pending, 0);
    expect(be.notes[n.id]!['title'], 'Viết lúc mất mạng (sửa)');
    expect(s.notes[n.id]!.version, 1);
    s.dispose();
  });

  test('hình nền: id duy nhất, có đủ ba nhóm', () {
    expect(kBackgrounds.map((b) => b.id).toSet().length, kBackgrounds.length);
    expect(kBackgrounds.map((b) => b.group).toSet(), {'Hoạ tiết', 'Minh hoạ', 'Màu chuyển'});
    expect(kBackgrounds.length, greaterThanOrEqualTo(25));
  });
}
