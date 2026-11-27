// Ảnh xem trước màn quản trị Flygo Access (chạy tay): ACCESS_OUT=<thư mục> flutter test test/access_admin_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/access/access_admin_page.dart';
import 'package:flygo_chat/access/access_api.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _dir = {
  'members': [
    {'sub': 'u1', 'display': 'Dương Văn Ba', 'email': 'ba@example.vn', 'status': 'active'},
    {'sub': 'u2', 'display': 'Nguyễn Thị Uyên', 'email': 'uyen@example.vn', 'status': 'active'},
    {'sub': 'u3', 'display': 'Trần Văn Duy', 'email': 'duy@example.vn', 'status': 'active'},
    {'sub': 'u4', 'display': 'Lê Thu Thảo', 'email': 'thao@example.vn', 'status': 'suspended'},
  ],
  'departments': [
    {'id': 'kd', 'name': 'Kinh doanh', 'parent_id': null},
    {'id': 'kd-hn', 'name': 'Kinh doanh Hà Nội', 'parent_id': 'kd'},
    {'id': 'kt', 'name': 'Kế toán', 'parent_id': null},
  ],
  'dept_members': [
    {'dept_id': 'kd', 'sub': 'u2', 'role': 'lead'},
    {'dept_id': 'kd-hn', 'sub': 'u4', 'role': 'member'},
    {'dept_id': 'kt', 'sub': 'u3', 'role': 'deputy'},
  ],
};

Object? _route(http.Request r) {
  final p = r.url.path;
  if (p.endsWith('/api/auth/token')) return {'token': 'jwt'};
  if (p == '/v1/my-orgs')
    return {
      'sub': 'u1',
      'orgs': [
        {'org': 'flygo', 'admin': true, 'member': true},
      ],
    };
  if (p.endsWith('/my-apps')) {
    return {
      'apps': [
        for (final n in ['Ký số', 'Hợp đồng', 'Thư', 'Lịch', 'Drive', 'Báo cáo']) {'app': n, 'name': n, 'web_url': 'https://x'},
      ],
    };
  }
  if (p.endsWith('/directory')) return _dir;
  if (p.endsWith('/grants')) {
    return {
      'grants': [
        {
          'app': 'kyso',
          'app_name': 'Ký số',
          'kind': 'admin',
          'signed_by': 'Qm3xK2',
          'perm': 'sign',
          'perm_label': 'Ký văn bản',
          'sensitive': true,
          'via': 'group',
          'group': 'kt',
          'group_size': 3,
          'params': {'max_amount': '500.000.000'},
        },
        {
          'app': 'mail',
          'app_name': 'Thư',
          'kind': 'base',
          'perm': 'read',
          'perm_label': 'Đọc hộp thư chung',
          'sensitive': false,
          'via': 'everyone',
          'params': null,
        },
        {
          'app': 'hd',
          'app_name': 'Hợp đồng',
          'kind': 'admin',
          'signed_by': 'Qm3xK2',
          'perm': 'approve',
          'perm_label': 'Duyệt hợp đồng',
          'sensitive': true,
          'via': 'direct',
          'sub': 'u2',
          'params': {'loai': 'mua bán'},
        },
      ],
    };
  }
  if (p == '/v1/apps') {
    return {
      'apps': [
        {
          'id': 'kyso',
          'name': 'Ký số',
          'publisher': 'Flygo',
          'rating': {'count': 12, 'stars': 4.8},
        },
        {
          'id': 'hd',
          'name': 'Hợp đồng',
          'publisher': 'Flygo',
          'rating': {'count': 3, 'stars': 4.3},
        },
        {
          'id': 'crm',
          'name': 'CRM bán hàng',
          'publisher': 'Đối tác',
          'rating': {'count': 0, 'stars': null},
        },
      ],
    };
  }
  if (p.endsWith('/apps')) {
    return {
      'apps': [
        {'app': 'kyso', 'name': 'Ký số', 'mode': 'signed', 'in_sync': true},
        {'app': 'hd', 'name': 'Hợp đồng', 'mode': 'token', 'in_sync': true},
      ],
    };
  }
  if (p.endsWith('/audit')) {
    return {
      'items': [
        {
          'id': 2,
          'at': '2026-11-27T09:12:00Z',
          'action': 'policy.put',
          'detail': {'app': 'kyso', 'ver': 4},
        },
        {
          'id': 1,
          'at': '2026-11-26T03:40:00Z',
          'action': 'member.put',
          'detail': {'sub': 'u4', 'status': 'suspended'},
        },
      ],
    };
  }
  if (p.endsWith('/billing')) {
    return {
      'currency': 'VND',
      'month': '2026-11',
      'current': {
        'month': '2026-11',
        'total': 1500000,
        'calls': 320,
        'lines': [
          {'app': 'kyso', 'name': 'Ký số', 'model': 'monthly', 'total': 1000000, 'calls': 0},
          {'app': 'hd', 'name': 'Hợp đồng', 'model': 'usage', 'total': 500000, 'calls': 320},
        ],
      },
      'history': [
        {'month': '2026-10', 'total': 1200000, 'calls': 210},
      ],
    };
  }
  return {};
}

void main() {
  final out = Platform.environment['ACCESS_OUT'];
  final key = GlobalKey();

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> shot(WidgetTester t, String name, Size size, Brightness b, int tab) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final s = FlygoSession(
      client: MockClient((r) async => http.Response(jsonEncode(_route(r)), 200, headers: {'content-type': 'application/json; charset=utf-8'})),
      preset: 'x',
    );
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: AccessAdminPage(session: s, initialTab: tab),
        ),
      ),
    );
    await settle(t);
    expect(find.byType(AccessAdminPage), findsOneWidget);
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  setUpAll(_fonts);
  const phone = Size(390, 844), desk = Size(1280, 800);
  const tabs = ['app', 'thanh-vien', 'quyen', 'cho-app', 'phong-ban', 'da-cai', 'khoa', 'nhat-ky', 'thanh-toan'];
  for (var i = 0; i < tabs.length; i++) {
    testWidgets('điện thoại sáng ${tabs[i]}', (t) => shot(t, 'dt-sang-${i + 1}-${tabs[i]}', phone, Brightness.light, i));
    testWidgets('máy tính tối ${tabs[i]}', (t) => shot(t, 'mt-toi-${i + 1}-${tabs[i]}', desk, Brightness.dark, i));
  }
  testWidgets('điện thoại tối quyền', (t) => shot(t, 'dt-toi-3-quyen', phone, Brightness.dark, 2));
  testWidgets('máy tính sáng thành viên', (t) => shot(t, 'mt-sang-2-thanh-vien', desk, Brightness.light, 1));
}
