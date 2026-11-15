// Wiki: cây thư mục (Nhân viên, thư mục kín), xem trang, sửa (lưu kèm base + ghi chú, xung đột 409), phân quyền (kế thừa,
// thêm đối tượng), lịch sử (so sánh, khôi phục), tìm kiếm; bố cục máy tính và điện thoại, sáng / tối; với backend giả.
// Ảnh xem trước (chạy tay): WK_OUT=<thư mục> flutter test test/wiki_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/wiki/api.dart';
import 'package:flygo_chat/ui/wiki/model.dart';
import 'package:flygo_chat/ui/wiki/store.dart';
import 'package:flygo_chat/ui/wiki/wiki_page.dart';
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

final _now = DateTime.now().millisecondsSinceEpoch;
const _h = 3600000;

Map<String, dynamic> _f(String id, String? parent, String name, {String kind = 'normal', String? owner, bool closed = false, double sort = 0, String? role = 'manage', bool left = false}) =>
    {'id': id, 'parent': parent, 'name': name, 'kind': kind, 'owner': owner, 'inherit': !closed, 'closed': closed, 'sort': sort, 'left': left, 'role': role};

const _leave = '''Áp dụng cho toàn bộ nhân viên chính thức. Thử việc xem mục [Chế độ thử việc](wiki:p-thuviec).

## 1. Số ngày phép

- 12 ngày phép năm, cộng thêm 1 ngày cho mỗi 5 năm làm việc.
- Phép chưa dùng được chuyển sang **quý I** năm sau.

## 2. Cách xin nghỉ

1. Tạo đơn trong app [Quy trình → Đơn nghỉ phép](https://example.com/flows) trước ít nhất 2 ngày.
2. Trưởng phòng duyệt trong 24 giờ.
3. Hành chính cập nhật bảng công.

> Nghỉ đột xuất: nhắn trưởng phòng trước 8:00 và bổ sung đơn trong ngày.

### Tài liệu kèm theo

[Mau-don-nghi-phep.pdf](file:f-pdf)

| Loại nghỉ | Số ngày |
|---|---|
| Kết hôn | 3 |
| Tang | 3 |''';

class FakeBackend {
  FakeBackend({this.myRole = 'manage', this.admin = true});
  final String myRole;
  final bool admin;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool conflict = false;

  late final folders = <Map<String, dynamic>>[
    _f('f-gt', 'root', 'Giới thiệu công ty', role: 'view'),
    _f('f-qt', 'root', 'Quy trình & quy định', role: myRole),
    _f('f-kd', 'root', 'Kinh doanh', closed: true, role: myRole),
    _f('f-hd', 'f-kd', 'Hợp đồng mẫu', role: myRole),
    _f('f-kt', 'root', 'Kỹ thuật', role: 'view'),
    _f('f-ketoan', 'root', 'Kế toán', closed: true, role: null),
    _f('staff', 'root', 'Nhân viên', kind: 'staff_root', sort: 1e9, role: admin ? 'manage' : 'view'),
    _f('h_an', 'staff', 'Nguyễn Văn An', kind: 'staff_home', owner: 'an', role: 'manage'),
    _f('h_binh', 'staff', 'Trần Thị Bình', kind: 'staff_home', owner: 'binh', role: admin ? 'manage' : 'view'),
    _f('h_chau', 'staff', 'Lê Minh Châu', kind: 'staff_home', owner: 'chau', role: admin ? 'manage' : 'view'),
    _f('h_dung', 'staff', 'Phạm Quốc Dũng', kind: 'staff_home', owner: 'dung', role: admin ? 'manage' : 'view'),
    _f('h_ha', 'staff', 'Hoàng Thu Hà', kind: 'staff_home', owner: 'ha', role: admin ? 'manage' : 'view', left: true),
  ];
  late final pages = <String, Map<String, dynamic>>{
    'p-noiquy': _page('p-noiquy', 'f-qt', 'Nội quy làm việc', 'Giờ làm việc 8:00–17:30.', 3),
    'p-nghiphep': _page('p-nghiphep', 'f-qt', 'Quy trình nghỉ phép', _leave, 7),
    'p-ctp': _page('p-ctp', 'f-qt', 'Công tác phí', 'Mức **công tác phí** trong nước: 300.000đ/ngày.', 2),
    'p-thuviec': _page('p-thuviec', 'f-gt', 'Chế độ thử việc', 'Thử việc 2 tháng.', 1),
    'p-an': _page('p-an', 'h_an', 'Việc tuần này', '- [x] Gửi báo giá\n- [ ] Gọi khách Đà Nẵng', 4),
  };

  Map<String, dynamic> _page(String id, String folder, String title, String body, int v) => {
        'id': id, 'folder': folder, 'title': title, 'body': body, 'version': v, 'latest': v, 'note': '', 'created_by': 'chau', 'created_by_name': 'Lê Minh Châu',
        'created_at': _now - 400 * _h, 'updated_by': 'binh', 'updated_by_name': 'Trần Thị Bình', 'updated_at': _now - 2 * _h, 'updated_via': 'app',
      };

  String? roleOf(String folder) => folder == 'root' ? (admin ? 'manage' : 'view') : folders.firstWhere((f) => f['id'] == folder)['role'] as String?;
  List<Map<String, String>> pathOf(String folder) {
    final out = <Map<String, String>>[];
    String? p = folder;
    while (p != null && p != 'root') {
      final f = folders.firstWhere((x) => x['id'] == p);
      out.insert(0, {'id': '${f['id']}', 'name': '${f['name']}'});
      p = f['parent'] as String?;
    }
    return out;
  }

  Map<String, dynamic> pageJson(String id, {int? version}) {
    final p = Map<String, dynamic>.from(pages[id]!);
    if (version != null && version != p['version']) {
      p['version'] = version;
      p['body'] = (p['body'] as String).replaceFirst('12 ngày phép năm, cộng thêm 1 ngày cho mỗi 5 năm làm việc.', '12 ngày phép năm.').replaceFirst('ít nhất 2 ngày', 'ít nhất 3 ngày');
    }
    return {
      ...p,
      'role': roleOf('${p['folder']}'),
      'path': pathOf('${p['folder']}'),
      'files': [if ((p['body'] as String).contains('file:f-pdf')) {'id': 'f-pdf', 'name': 'Mau-don-nghi-phep.pdf', 'mime': 'application/pdf', 'size': 186368}],
      'access': [
        {'stype': 'everyone', 'sid': '*', 'role': 'view', 'name': 'Mọi người'},
        {'stype': 'dept', 'sid': 'hc', 'role': 'edit', 'name': 'Hành chính'},
      ],
    };
  }

  http.Response _json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  http.Client client() => MockClient((req) async {
        final p = req.url.path.replaceFirst('/wk', '');
        calls.add('${req.method} $p');
        if (req.body.isNotEmpty) bodies['${req.method} $p'] = jsonDecode(req.body) as Map<String, dynamic>;
        if (p == '/api/tree') {
          return _json({
            'folders': folders,
            'pages': [for (final x in pages.values) {'id': x['id'], 'folder': x['folder'], 'title': x['title'], 'sort': 0, 'version': x['version'], 'updated_at': x['updated_at'], 'updated_by_name': x['updated_by_name']}],
            'root': {'id': 'root', 'name': 'Công ty', 'role': admin ? 'manage' : 'view'},
            'home': 'h_an', 'admin': admin, 'staff_count': 23,
          });
        }
        var m = RegExp(r'^/api/pages/([\w-]+)$').firstMatch(p);
        if (m != null && req.method == 'GET') {
          final v = int.tryParse(req.url.queryParameters['version'] ?? '');
          return _json({'page': pageJson(m[1]!, version: v)});
        }
        if (m != null && req.method == 'PUT') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final id = m[1]!;
          if (conflict && b['force'] != true) {
            return _json({'error': 'có người vừa lưu bản 8 của trang này', 'current': {...pageJson(id), 'version': 8, 'updated_by_name': 'Lê Minh Châu'}}, 409);
          }
          final cur = pages[id] ?? _page(id, '${b['folder']}', '${b['title']}', '', 0);
          pages[id] = {...cur, if (b['title'] != null) 'title': b['title'], if (b['body'] != null) 'body': b['body'], 'version': (cur['version'] as int) + 1, 'updated_by_name': 'Nguyễn Văn An', 'updated_at': _now};
          return _json({'page': pageJson(id), 'changed': true});
        }
        m = RegExp(r'^/api/pages/([\w-]+)/history$').firstMatch(p);
        if (m != null) {
          return _json({
            'versions': [
              {'version': 7, 'title': 'Quy trình nghỉ phép', 'author': 'binh', 'author_name': 'Trần Thị Bình', 'via': 'app', 'note': 'Cộng ngày phép theo thâm niên', 'at': _now - 2 * _h},
              {'version': 6, 'title': 'Quy trình nghỉ phép', 'author': 'binh', 'author_name': 'Trần Thị Bình', 'via': 'app', 'note': 'Báo trước 2 ngày thay vì 3', 'at': _now - 60 * _h},
              {'version': 5, 'title': 'Quy trình nghỉ phép', 'author': 'an', 'author_name': 'Nguyễn Văn An', 'via': 'mcp', 'note': 'Sửa chính tả', 'at': _now - 110 * _h},
              {'version': 4, 'title': 'Quy trình nghỉ phép', 'author': 'chau', 'author_name': 'Lê Minh Châu', 'via': 'app', 'note': 'Thêm mẫu đơn PDF', 'at': _now - 300 * _h},
              {'version': 1, 'title': 'Quy trình nghỉ phép', 'author': 'chau', 'author_name': 'Lê Minh Châu', 'via': 'app', 'note': '', 'at': _now - 400 * _h},
            ],
          });
        }
        m = RegExp(r'^/api/pages/([\w-]+)/restore$').firstMatch(p);
        if (m != null) return _json({'page': pageJson(m[1]!), 'changed': true});
        m = RegExp(r'^/api/folders/([\w-]+)/acl$').firstMatch(p);
        if (m != null) {
          return _json({
            'folder': m[1], 'name': folders.firstWhere((f) => f['id'] == m![1])['name'], 'kind': 'normal', 'inherit': false, 'parent_name': 'Công ty',
            'entries': [
              {'stype': 'user', 'sid': 'dung', 'role': 'manage', 'name': 'Phạm Quốc Dũng', 'detail': '@dung'},
              {'stype': 'dept', 'sid': 'kd', 'role': 'edit', 'name': 'Phòng Kinh doanh', 'members': 9},
              {'stype': 'role', 'sid': 'bgd', 'role': 'view', 'name': 'Ban giám đốc', 'members': 3},
            ],
            'inherited': [
              {'stype': 'everyone', 'sid': '*', 'role': 'view', 'name': 'Mọi người', 'from': 'root', 'from_name': 'Công ty'},
            ],
            'my_role': myRole, 'can_manage': myRole == 'manage',
          });
        }
        if (p == '/api/subjects') {
          return _json({'subjects': [
            {'stype': 'dept', 'sid': 'hc', 'name': 'Hành chính', 'detail': 'Phòng ban · 4 người', 'members': 4},
            {'stype': 'user', 'sid': 'ha', 'name': 'Hoàng Thu Hà', 'detail': '@ha'},
          ]});
        }
        if (p == '/api/search') {
          return _json({'results': [
            {'id': 'p-ctp', 'title': 'Công tác phí', 'folder': 'f-qt', 'path': ['Quy trình & quy định'], 'updated_at': _now, 'snippet': {'text': 'Mức công tác phí trong nước: 300.000đ/ngày.', 'hl': [[4, 12]]}},
            {'id': 'p-an', 'title': 'Ghi chú chuyến Đà Nẵng', 'folder': 'h_an', 'path': ['Nhân viên', 'Nguyễn Văn An'], 'updated_at': _now, 'snippet': {'text': '…tạm ứng công tác phí 2 ngày, khách sạn gần văn phòng đối tác…', 'hl': [[9, 12]]}},
          ]});
        }
        if (p == '/api/trash') return _json({'items': [], 'days': 30});
        return _json({'error': 'không có'}, 404);
      });
}

void main() {
  final out = Platform.environment['WK_OUT'];
  late FakeBackend be;
  WikiStore newStore() => WikiStore(WikiApi(base: 'https://chat.test/wk', client: be.client(), ticket: () async => 'tk'));

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, Widget child, {Size size = const Size(1440, 900), Brightness theme = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    if (out != null) await t.runAsync(_fonts);
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)));
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await settle(t, 2);
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> open(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey(key)));
    await settle(t);
  }

  setUp(() => be = FakeBackend());

  test('so sánh dòng và thời gian tương đối', () {
    expect(lineDiff('a\nb\nc', 'a\nB\nc\nd'), [(' ', 'a'), ('-', 'b'), ('+', 'B'), (' ', 'c'), ('+', 'd')]);
    expect(lineDiff('x', 'x'), [(' ', 'x')]);
    final now = DateTime(2026, 11, 15, 12);
    expect(agoLabel(now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch, now: now), '5 phút trước');
    expect(agoLabel(DateTime(2026, 11, 2, 9).millisecondsSinceEpoch, now: now), '02/11');
    expect(roleRank('manage') > roleRank('edit') && roleRank('edit') > roleRank('view') && roleRank(null) == 0, isTrue);
  });

  testWidgets('máy tính: cây thư mục, Nhân viên, thư mục kín, xem trang, sửa và lưu kèm base + ghi chú', (t) async {
    final s = newStore();
    await pump(t, WikiHome(store: s, ownsStore: false, forceWide: true));
    // Cây: thư mục cấp đầu, Nhân viên mở sẵn với thư mục của mình đứng đầu ("Của tôi"), thư mục kín có khoá, người đã nghỉ.
    expect(find.text('CÔNG TY'), findsOneWidget);
    expect(find.text('Nhân viên'), findsWidgets);
    expect(find.text('Của tôi'), findsOneWidget);
    expect(find.text('Đã nghỉ'), findsOneWidget);
    for (final k in ['wiki-folder-f-kd', 'wiki-folder-f-ketoan']) {
      expect(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byIcon(Icons.lock_outline_rounded)), findsOneWidget);
    }
    expect(t.getTopLeft(find.text('Nguyễn Văn An')).dy, lessThan(t.getTopLeft(find.text('Trần Thị Bình')).dy));
    // Mở thư mục rồi mở trang.
    await open(t, 'wiki-folder-f-qt');
    expect(find.byKey(const ValueKey('wiki-page-p-nghiphep')), findsOneWidget);
    await open(t, 'wiki-page-p-nghiphep');
    expect(find.text('1. Số ngày phép'), findsOneWidget);
    expect(find.text('Mau-don-nghi-phep.pdf'), findsOneWidget);
    expect(find.textContaining('Trần Thị Bình sửa'), findsOneWidget);
    expect(find.textContaining('Hành chính sửa · Mọi người xem'), findsOneWidget);
    await shot(t, 'wiki-1-may-tinh-trang');
    // Sửa: chia đôi, thêm dòng, ghi chú phiên bản, lưu.
    await open(t, 'wiki-edit');
    expect(find.text('Chia đôi'), findsOneWidget);
    final body = find.byKey(const ValueKey('wiki-editor-body'));
    await t.enterText(body, '${_leave.split('## 2.').first.trimRight()}\n- Nghỉ cưới: 3 ngày, nghỉ tang: 3 ngày.\n\n## 2.${_leave.split('## 2.').last}');
    await t.enterText(find.byKey(const ValueKey('wiki-editor-note')), 'Thêm nghỉ cưới, nghỉ tang');
    await settle(t, 2);
    await shot(t, 'wiki-2-may-tinh-sua');
    await open(t, 'wiki-editor-save');
    final put = be.bodies['PUT /api/pages/p-nghiphep']!;
    expect(put['base'], 7);
    expect(put['note'], 'Thêm nghỉ cưới, nghỉ tang');
    expect(put['body'], contains('Nghỉ cưới: 3 ngày'));
    expect(find.text('Chia đôi'), findsNothing);
    expect(find.textContaining('bản 8'), findsOneWidget);
    s.dispose();
  });

  testWidgets('máy tính: lưu khi có người vừa lưu trước thì hỏi (xem chỗ khác, ghi đè)', (t) async {
    be.conflict = true;
    final s = newStore();
    await pump(t, WikiHome(store: s, ownsStore: false, forceWide: true, openPageId: 'p-ctp'));
    await open(t, 'wiki-edit');
    await t.enterText(find.byKey(const ValueKey('wiki-editor-body')), 'Mức công tác phí trong nước: 350.000đ/ngày.');
    await settle(t, 2);
    await open(t, 'wiki-editor-save');
    expect(find.text('Có người vừa lưu bản 8'), findsOneWidget);
    expect(find.textContaining('350.000đ'), findsWidgets);
    await shot(t, 'wiki-7-xung-dot');
    await t.tap(find.text('Ghi đè bằng bản của tôi'));
    await settle(t);
    expect(be.bodies['PUT /api/pages/p-ctp']!['force'], true);
    s.dispose();
  });

  testWidgets('máy tính: phân quyền thư mục (kế thừa, quyền riêng, thêm phòng ban), lịch sử, tìm kiếm, giao diện tối', (t) async {
    final s = newStore();
    await pump(t, WikiHome(store: s, ownsStore: false, forceWide: true));
    await open(t, 'wiki-folder-f-kd');
    await t.tap(find.text('Phân quyền'));
    await settle(t);
    expect(find.text('Quyền của thư mục “Kinh doanh”'), findsOneWidget);
    expect(find.text('Phòng Kinh doanh'), findsOneWidget);
    expect(find.text('Quản trị wiki'), findsOneWidget);
    await shot(t, 'wiki-3-may-tinh-phan-quyen');
    // Thêm Hành chính (Xem) rồi bật kế thừa, lưu.
    await t.enterText(find.byKey(const ValueKey('wiki-acl-add')), 'hành');
    await settle(t, 4);
    await t.tap(find.text('Hành chính'));
    await settle(t, 2);
    await t.tap(find.byKey(const ValueKey('wiki-acl-inherit')));
    await settle(t, 2);
    expect(find.text('Kế thừa từ “Công ty”'), findsWidgets);
    await open(t, 'wiki-acl-save');
    final acl = be.bodies['PUT /api/folders/f-kd/acl']!;
    expect(acl['inherit'], true);
    expect((acl['entries'] as List).map((e) => '${e['stype']}:${e['sid']}:${e['role']}'), ['user:dung:manage', 'dept:kd:edit', 'role:bgd:view', 'dept:hc:view']);
    // Lịch sử: chọn sẵn bản 6, so với hiện tại, khôi phục.
    await open(t, 'wiki-folder-f-qt');
    await open(t, 'wiki-page-p-nghiphep');
    await t.tap(find.text('Lịch sử'));
    await settle(t);
    expect(find.text('Bản 7 · hiện tại'), findsOneWidget);
    expect(find.text('Bản 6 so với bản hiện tại (7)'), findsOneWidget);
    expect(find.textContaining('Agent của Nguyễn Văn An'), findsOneWidget);
    expect(find.textContaining('− 1. Tạo đơn'), findsOneWidget);
    await shot(t, 'wiki-4-may-tinh-lich-su');
    await open(t, 'wiki-restore');
    expect(be.bodies['POST /api/pages/p-nghiphep/restore']!['version'], 6);
    await t.pump(const Duration(seconds: 5)); // chờ thông báo tắt
    await settle(t, 2);
    // Tìm kiếm: đoạn trích có tô chữ khớp.
    await t.enterText(find.byKey(const ValueKey('wiki-search')), 'cong tac phi');
    await settle(t, 6);
    expect(find.text('2 kết quả (chỉ hiện trang bạn được xem)'), findsOneWidget);
    expect(find.text('Ghi chú chuyến Đà Nẵng'), findsOneWidget);
    await shot(t, 'wiki-5-may-tinh-tim-kiem');
    s.dispose();
  });

  testWidgets('máy tính tối: xem trang', (t) async {
    final s = newStore();
    await pump(t, WikiHome(store: s, ownsStore: false, forceWide: true, openPageId: 'p-nghiphep'), theme: Brightness.dark);
    expect(find.text('Quy trình nghỉ phép'), findsWidgets);
    await shot(t, 'wiki-6-may-tinh-toi');
    s.dispose();
  });

  testWidgets('người chỉ được xem: không có nút sửa, không tạo thư mục cấp đầu', (t) async {
    be = FakeBackend(myRole: 'view', admin: false);
    final s = newStore();
    await pump(t, WikiHome(store: s, ownsStore: false, forceWide: true, openPageId: 'p-nghiphep'));
    expect(find.text('1. Số ngày phép'), findsOneWidget);
    expect(find.byKey(const ValueKey('wiki-edit')), findsNothing);
    expect(find.byTooltip('Thư mục mới'), findsNothing);
    expect(find.text('Đồng bộ nhân viên'), findsNothing);
    // Thư mục của mình vẫn sửa được.
    await open(t, 'wiki-folder-h_an');
    await open(t, 'wiki-page-p-an');
    expect(find.byKey(const ValueKey('wiki-edit')), findsOneWidget);
    s.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('điện thoại${dark ? ' tối' : ''}: cây, mở trang, sửa, phân quyền', (t) async {
      final s = newStore();
      final theme = dark ? Brightness.dark : Brightness.light;
      final tag = dark ? 'toi' : 'sang';
      await pump(t, WikiHome(store: s, ownsStore: false, forceWide: false), size: const Size(390, 844), theme: theme);
      expect(find.text('Wiki của tôi'), findsOneWidget);
      expect(find.text('Mới sửa gần đây'), findsOneWidget);
      await open(t, 'wiki-folder-f-qt');
      expect(find.byKey(const ValueKey('wiki-page-p-nghiphep')), findsOneWidget);
      await shot(t, 'wiki-p1-dien-thoai-cay-$tag');
      await open(t, 'wiki-page-p-nghiphep');
      expect(find.text('1. Số ngày phép'), findsOneWidget);
      await shot(t, 'wiki-p2-dien-thoai-trang-$tag');
      if (dark) {
        s.dispose();
        return;
      }
      await open(t, 'wiki-edit');
      expect(find.text('Viết'), findsOneWidget);
      expect(find.text('Chia đôi'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('wiki-editor-note')), 'Thêm nghỉ cưới');
      await settle(t, 2);
      await shot(t, 'wiki-p3-dien-thoai-sua');
      await open(t, 'wiki-editor-save');
      expect(be.bodies['PUT /api/pages/p-nghiphep']!['note'], 'Thêm nghỉ cưới');
      await t.pageBack();
      await settle(t);
      // Nhấn giữ thư mục: menu, chọn Phân quyền.
      await t.longPress(find.byKey(const ValueKey('wiki-folder-f-kd')));
      await settle(t);
      await t.tap(find.text('Phân quyền…'));
      await settle(t);
      expect(find.text('Quyền của thư mục “Kinh doanh”'), findsOneWidget);
      expect(find.text('Lưu quyền'), findsOneWidget);
      await shot(t, 'wiki-p4-dien-thoai-phan-quyen');
      s.dispose();
    });
  }
}
