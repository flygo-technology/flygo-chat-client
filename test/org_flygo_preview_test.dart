// Ảnh xem trước trang Tổ chức (Flygo ID): ORG_OUT=<thư mục> flutter test test/org_flygo_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/org_flygo.dart';
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

  // Theme trên Linux dùng 'Noto Sans': nạp Roboto dưới cả hai tên (Roboto có đủ dấu tiếng Việt).
  for (final f in ['Roboto', 'Noto Sans']) {
    await load(f, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

http.Response _json(Object o, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), status, headers: {'content-type': 'application/json'});

void main() {
  final out = Platform.environment['ORG_OUT'];
  kServerUrl = 'https://chat.example.com';
  final app = AppState('test')..me = MmUser({'id': 'ba', 'username': 'ba', 'first_name': 'Ba'});
  for (final (id, n) in [('ba', 'Trần Văn Bình'), ('lan', 'Lan Kế toán'), ('tuan', 'Tuấn Kinh doanh'), ('hoa', 'Hoa Kế toán trưởng'), ('minh', 'Minh Kỹ thuật')]) {
    app.users[id] = MmUser({'id': id, 'username': id, 'first_name': n});
  }
  final org = {
    'version': 7,
    'can_edit': true,
    'departments': {
      'cty': {'id': 'cty', 'name': 'Công ty Ví Dụ', 'parent': null, 'manager': 'ba', 'members': [{'user': 'ba', 'primary': true, 'deputy': false}]},
      'kt': {'id': 'kt', 'name': 'Kế toán', 'parent': 'cty', 'manager': 'hoa', 'members': [{'user': 'hoa', 'primary': true, 'deputy': false}, {'user': 'lan', 'primary': true, 'deputy': true}]},
      'kd': {'id': 'kd', 'name': 'Kinh doanh', 'parent': 'cty', 'manager': null, 'members': [{'user': 'tuan', 'primary': true, 'deputy': false}]},
      'kt_thue': {'id': 'kt_thue', 'name': 'Tổ thuế', 'parent': 'kt', 'manager': null, 'members': []},
    },
    'roles': {'ke_toan_truong': {'name': 'Kế toán trưởng', 'members': ['hoa']}},
    'delegations': {},
  };
  final catalog = {
    'apps': [
      {'id': 'vn.example.bank', 'name': 'Ngân hàng', 'perms': {
        'use': {'name': 'Dùng app', 'level': 'normal', 'per_space': false},
        'tool:read_balance': {'name': 'Xem số dư', 'level': 'normal', 'per_space': true},
        'tool:read_statement': {'name': 'Xem sao kê', 'level': 'normal', 'per_space': true},
        'tool:transfer': {'name': 'Chuyển khoản', 'level': 'sensitive', 'per_space': true},
        'webhook:payment.received': {'name': 'Tiền về tài khoản', 'level': 'normal', 'per_space': true},
      }, 'tools': {'read_balance': {'kind': 'read'}, 'read_statement': {'kind': 'read'}, 'transfer': {'kind': 'write'}}},
      {'id': 'vn.flygo.minvoice', 'name': 'Hoá đơn điện tử', 'perms': {
        'use': {'name': 'Dùng app', 'level': 'normal', 'per_space': false},
        'tool:list_invoices': {'name': 'Danh sách hoá đơn', 'level': 'normal', 'per_space': false},
      }, 'tools': {'list_invoices': {'kind': 'read'}}},
      {'id': 'vn.flygo.kyso', 'name': 'Ký số', 'hidden': true, 'perms': {
        'admin': {'name': 'Quản trị', 'level': 'sensitive', 'per_space': true},
        'use': {'name': 'Dùng app', 'level': 'normal', 'per_space': false},
        'sign': {'name': 'Ký số', 'level': 'sensitive', 'per_space': true},
      }, 'tools': {}},
      {'id': 'vn.flygo.flows', 'name': 'Quy trình', 'hidden': true, 'perms': {
        'use': {'name': 'Dùng app', 'level': 'normal', 'per_space': false},
        'admin': {'name': 'Quản trị quy trình', 'level': 'sensitive', 'per_space': false},
      }, 'tools': {}},
    ],
    'spaces': {
      'vn.flygo.kyso/fpt-40d4': {'name': 'Ký số CÔNG TY TNHH ABC VINA', 'provider': 'vn.flygo.kyso'},
      'vn.flygo.kyso/fpt-7e3f': {'name': 'Ký số CÔNG TY TNHH ABC CAPITAL', 'provider': 'vn.flygo.kyso'},
    },
  };
  final posted = <Map>[];
  FlygoOrgView.debugClient = MockClient((r) async {
    final p = r.url.path;
    if (p == '/v1/admin/grants' && r.method == 'POST') {
      final b = jsonDecode(r.body) as Map;
      posted.add(b);
      return _json({'grant': {'id': 'n${posted.length}', ...b}});
    }
    if (p == '/v1/org') return _json(org);
    if (p == '/v1/admin/catalog') return _json(catalog);
    if (p == '/v1/admin/grants') {
      final sid = r.url.queryParameters['subject_id'];
      if (sid == 'kt') return _json({'grants': [{'id': 'g2', 'app': 'vn.example.bank', 'perm': 'tool:read_statement', 'space': null}, {'id': 'g3', 'app': 'vn.flygo.kyso', 'perm': 'sign', 'space': 'vn.flygo.kyso/fpt-7e3f'}]});
      return _json({'grants': sid == 'kt_thue' ? [{'id': 'g1', 'app': 'vn.flygo.minvoice', 'perm': 'tool:list_invoices', 'space': null}] : sid == 'kt' ? [{'id': 'g2', 'app': 'vn.example.bank', 'perm': 'tool:read_statement', 'space': null}] : []});
    }
    if (p.startsWith('/v1/admin/subjects/')) {
      return _json({'perms': p.contains('/kt_thue/')
          ? [
              {'app': 'vn.flygo.minvoice', 'perm': 'tool:list_invoices', 'space': null, 'via': 'dept:kt_thue'},
              {'app': 'vn.example.bank', 'perm': 'tool:read_statement', 'space': null, 'via': 'dept:kt'},
              {'app': 'vn.flygo.flows', 'perm': 'use', 'space': null, 'via': 'dept:cty'},
            ]
          : []});
    }
    return _json({'ok': true});
  });

  testWidgets('trang Tổ chức (Flygo ID)', (tester) async {
    await tester.runAsync(_fonts);
    Future<void> shot(String name, Size size, Brightness b, {Future<void> Function()? before}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(b),
            home: Scaffold(appBar: AppBar(title: const Text('Tổ chức')), body: FlygoOrgView(app: app, fid: FlygoId(base: 'https://apps.test', chatToken: 't'))),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (before != null) await before();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (out == null) return;
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }

    Future<void> openThue() async {
      final row = find.ancestor(of: find.text('Kế toán'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.keyboard_arrow_right_rounded)));
      await tester.pump();
      await tester.tap(find.text('Tổ thuế'));
      await tester.pump();
    }

    await shot('org-pc', const Size(1280, 800), Brightness.light, before: openThue);
    await shot('org-pc-toi', const Size(1280, 800), Brightness.dark, before: openThue);
    await shot('org-mobile', const Size(420, 820), Brightness.light);
    await shot('org-kyso', const Size(1280, 1400), Brightness.light, before: () async {
      await tester.tap(find.text('Kế toán'));
      await tester.pump();
    });
    await shot('org-menu', const Size(1280, 800), Brightness.light, before: () async {
      await tester.tapAt(tester.getCenter(find.text('Kế toán')), buttons: kSecondaryButton);
      await tester.pump();
    });
  });

  testWidgets('quyền theo app: nhóm thu gọn, đếm n/N, chọn cả nhóm, Chọn tất cả (hỏi lại khi > 10)', (tester) async {
    posted.clear();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: FlygoOrgView(app: app, fid: FlygoId(base: 'https://apps.test', chatToken: 't')))),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    await tester.tap(find.text('Kinh doanh'));
    await settle();
    // Chưa có quyền nào: nhóm thu gọn, đếm 0/N.
    expect(find.byKey(const ValueKey('perm-count-vn.example.bank')), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
    expect(find.text('Xem số dư'), findsNothing, reason: 'thu gọn: không hiện từng quyền');
    await tester.tap(find.byKey(const ValueKey('perm-group-vn.example.bank')));
    await settle();
    expect(find.text('Xem số dư'), findsOneWidget, reason: 'bấm đầu nhóm thì mở ra');
    // Ô chọn cả nhóm (2 quyền: không hỏi lại).
    await tester.tap(find.byKey(const ValueKey('perm-group-check-vn.flygo.minvoice')));
    await settle();
    expect(posted.length, 2);
    expect(find.text('2/2'), findsOneWidget);
    // Chọn tất cả: còn 10 quyền -> không hỏi; bỏ tất cả 12 -> hỏi lại.
    await tester.tap(find.byKey(const ValueKey('perm-all-on')));
    await settle();
    expect(posted.length, 12);
    expect(find.text('5/5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('perm-all-off')));
    await settle();
    expect(find.textContaining('Bỏ 12 quyền của'), findsOneWidget);
    await tester.tap(find.text('Bỏ quyền'));
    await settle();
    expect(find.text('0/5'), findsOneWidget);
  });
}
