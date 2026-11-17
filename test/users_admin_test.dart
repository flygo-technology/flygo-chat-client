// Quản trị › Người dùng: kiểm tra mật khẩu (nút Đặt chỉ bật khi hợp lệ, lỗi máy chủ hiện trong hộp), quyền gộp theo
// app, và ảnh xem trước (chạy tay): USERS_OUT=<thư mục> flutter test test/users_admin_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/password_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/users_admin_page.dart';
import 'package:provider/provider.dart';

/// Flygo ID giả: trả dữ liệu mẫu theo đường dẫn, ghi lại các lời gọi ghi.
class _Id extends FlygoId {
  _Id({this.guard = true, this.passwordError}) : super(base: 'https://id.example.invalid', chatToken: 't');
  final bool guard;
  final String? passwordError;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> request(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    if (method == 'GET' && path.startsWith('/v1/admin/users?')) return {'users': _users, 'total': _users.length};
    if (method == 'GET' && path == '/v1/admin/login-guard') {
      if (!guard) throw FlygoIdException(404, 'không hỗ trợ');
      return _guard;
    }
    if (method == 'GET' && path.startsWith('/v1/admin/users/')) return _detail(path.split('/').last, guard: guard);
    if (path.endsWith('/password') && passwordError != null) throw FlygoIdException(400, passwordError!);
    return {'ok': true};
  }
}

final _now = DateTime.now().millisecondsSinceEpoch;
int _ago(Duration d) => _now - d.inMilliseconds;

final _users = <Map<String, dynamic>>[
  {
    'id': 'u1',
    'username': 'ba',
    'name': 'Nguyễn Văn Ba',
    'system_admin': true,
    'depts': [
      {'name': 'Ban giám đốc', 'head': true},
    ],
    'devices': 3,
  },
  {
    'id': 'u2',
    'username': 'hoa.nt',
    'name': 'Nguyễn Thị Hoa',
    'depts': [
      {'name': 'Kế toán'},
    ],
    'devices': 2,
    'login_allowed': true,
  },
  {
    'id': 'u3',
    'username': 'minh.tq',
    'name': 'Trần Quang Minh',
    'depts': [
      {'name': 'Kỹ thuật'},
    ],
    'devices': 1,
    'login_allowed': true,
  },
  {
    'id': 'u4',
    'username': 'lan.pt',
    'name': 'Phạm Thị Lan',
    'depts': [
      {'name': 'Kinh doanh'},
    ],
    'devices': 1,
    'login_allowed': false,
  },
  {
    'id': 'u5',
    'username': 'tuan.lv',
    'name': 'Lê Văn Tuấn',
    'depts': [
      {'name': 'Kho vận'},
    ],
    'login_allowed': false,
  },
  {
    'id': 'u6',
    'username': 'thao.vt',
    'name': 'Vũ Thu Thảo',
    'status': 'inactive',
    'depts': [
      {'name': 'Kinh doanh'},
    ],
  },
];

final _guard = <String, dynamic>{
  'enabled': true,
  'allowed_count': 18,
  'total': 46,
  'existing_sessions': 'keep',
  'allowed_depts': [
    {'id': 'kt', 'name': 'Kế toán'},
    {'id': 'ky', 'name': 'Kỹ thuật'},
  ],
  'depts': [
    {'id': 'bgd', 'name': 'Ban giám đốc', 'members': 3, 'allowed': false},
    {'id': 'kt', 'name': 'Kế toán', 'members': 6, 'allowed': true},
    {'id': 'ky', 'name': 'Kỹ thuật', 'members': 9, 'allowed': true},
    {'id': 'kd', 'name': 'Kinh doanh', 'members': 14, 'allowed': false},
    {'id': 'kv', 'name': 'Kho vận', 'members': 11, 'allowed': false},
  ],
};

const _todoTools = [
  'list_notes',
  'get_note',
  'create_note',
  'update_note',
  'delete_note',
  'list_tasks',
  'create_task',
  'update_task',
  'complete_task',
  'search',
  'share_note',
  'list_labels',
];

List<Map<String, dynamic>> get _perms => [
  {'app': 'vn.flygo.todo', 'perm': 'use', 'via': 'everyone:*'},
  for (final t in _todoTools) {'app': 'vn.flygo.todo', 'perm': 'tool:$t', 'via': 'everyone:*'},
  {'app': 'vn.flygo.flows', 'perm': 'use', 'via': 'everyone:*'},
  {'app': 'vn.flygo.flows', 'perm': 'admin', 'via': 'user:u2'},
  for (final t in ['start_process', 'list_processes', 'my_tasks', 'complete_task', 'get_process'])
    {'app': 'vn.flygo.flows', 'perm': 'tool:$t', 'via': 'dept:kt'},
  {'app': 'vn.flygo.flows', 'perm': 'webhook:process.done', 'via': 'dept:kt'},
  {'app': 'vn.flygo.mail', 'perm': 'use', 'via': 'dept:kt'},
  {'app': 'vn.flygo.mail', 'perm': 'send', 'space': 'hoadon@flygo.vn', 'via': 'user:u2'},
  {'app': 'vn.flygo.ai', 'perm': 'use', 'via': 'everyone:*'},
  {'app': 'vn.flygo.kyso', 'perm': 'use', 'via': 'user:u2'},
  {'app': 'vn.flygo.kyso', 'perm': 'sign', 'space': 'flygo', 'via': 'user:u2'},
  {'app': 'vn.flygo.calendar', 'perm': 'use', 'via': 'everyone:*'},
  for (final t in ['list_events', 'create_event', 'update_event']) {'app': 'vn.flygo.calendar', 'perm': 'tool:$t', 'via': 'everyone:*'},
  {'app': 'vn.flygo.bangtin', 'perm': 'use', 'via': 'everyone:*'},
  {'app': 'vn.flygo.dich', 'perm': 'use', 'via': 'everyone:*'},
  {'app': 'vn.flygo.web.drive', 'perm': 'use', 'via': 'dept:kt'},
];

Map<String, dynamic> _detail(String id, {required bool guard}) {
  final u = _users.firstWhere((x) => x['id'] == id, orElse: () => _users[1]);
  final noPw = id == 'u4';
  return {
    'user': {
      ...u,
      'email': '${u['username']}@flygo.vn',
      'position': id == 'u2' ? 'Kế toán trưởng' : 'Nhân viên',
      'depts': [
        {'id': 'kt', 'name': '${(u['depts'] as List).first['name']}', 'primary': true, 'head': id == 'u2'},
        if (id == 'u2') {'id': 'bgd', 'name': 'Ban giám đốc'},
      ],
    },
    'password_login': {'google_linked': true, 'has_password': !noPw, 'allowed': false, 'enabled': false, 'google_enabled': false},
    if (guard) 'login': {'allowed': u['login_allowed'] == true, 'via': id == 'u2' ? 'user' : 'dept:kt', 'via_name': 'Kế toán', 'passkey_required': true},
    'perms': _perms,
    'devices': [
      {
        'device_id': 'd1',
        'name': 'iPhone 15 của Hoa',
        'platform': 'iOS 19.1',
        'app_version': '1.0.5+496',
        'last_seen': _ago(const Duration(minutes: 12)),
        if (guard) 'passkey': {'kind': 'Face ID', 'last_used': _ago(const Duration(minutes: 12))},
      },
      {
        'device_id': 'd2',
        'name': 'MacBook Air',
        'platform': 'macOS 16',
        'app_version': '1.0.5+494',
        'last_seen': _ago(const Duration(days: 2)),
        if (guard) 'passkey': {'kind': 'Touch ID', 'last_used': _ago(const Duration(days: 2))},
      },
      {'device_id': 'd3', 'name': 'Galaxy A55', 'platform': 'Android 16', 'app_version': '1.0.5+490', 'last_seen': _ago(const Duration(days: 9))},
    ],
    'audit': [
      {'action': 'user.password', 'at': _ago(const Duration(hours: 3)), 'actor': 'mm:ba'},
      {'action': 'grant.add', 'at': _ago(const Duration(days: 1)), 'actor': 'mm:ba'},
      {'action': 'user.depts', 'at': _ago(const Duration(days: 4)), 'actor': 'mm:ba'},
      {'action': 'user.create', 'at': _ago(const Duration(days: 30)), 'actor': 'mm:ba'},
    ],
  };
}

const _policy = PasswordPolicy(minLength: 8);
Future<PasswordPolicy?> _loadPolicy() async => _policy;

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
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _app = AppState('t')..me = MmUser({'id': 'u1', 'username': 'ba', 'first_name': 'Ba'});
final _key = GlobalKey();

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pump(WidgetTester t, Widget home, {Size size = const Size(390, 844), Brightness b = Brightness.dark, double ratio = 1}) async {
  t.view.physicalSize = size * ratio;
  t.view.devicePixelRatio = ratio;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: _app,
      child: RepaintBoundary(
        key: _key,
        child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home),
      ),
    ),
  );
  await _settle(t);
}

void main() {
  group('PasswordCheck', () {
    const c = PasswordCheck(_policy);
    test('7 ký tự không hợp lệ', () {
      expect(c.valid('abc1234'), isFalse);
      expect(c.problems('abc1234').first, contains('8'));
    });
    test('đủ 8 ký tự, 2 loại', () => expect(c.valid('abcd1234'), isTrue));
    test('chỉ 1 loại ký tự là yếu', () => expect(c.valid('abcdefgh'), isFalse));
    test('máy chủ đặt 5 vẫn đòi ít nhất 8', () => expect(const PasswordCheck(PasswordPolicy(minLength: 5)).minLength, 8));
    test('máy chủ đặt 12 thì theo máy chủ', () => expect(const PasswordCheck(PasswordPolicy(minLength: 12)).valid('abcd1234'), isFalse));
    test('chính sách máy chủ: chữ hoa + ký tự đặc biệt', () {
      const s = PasswordCheck(PasswordPolicy(minLength: 8, upper: true, symbol: true));
      expect(s.valid('abcd1234'), isFalse);
      expect(s.valid('Abcd123!'), isTrue);
    });
    test('chữ có dấu bị chặn và có cảnh báo', () {
      expect(c.valid('mậtkhẩu123'), isFalse);
      expect(c.warnings('mậtkhẩu123'), isNotEmpty);
    });
    test('khoảng trắng đầu / cuối bị chặn, ở giữa chỉ cảnh báo', () {
      expect(c.valid(' abcd1234'), isFalse);
      expect(c.valid('abcd 1234'), isTrue);
      expect(c.warnings('abcd 1234'), isNotEmpty);
    });
    test('độ mạnh', () {
      expect(PasswordCheck.strength(''), 0);
      expect(PasswordCheck.strength('abc1234'), lessThanOrEqualTo(1));
      expect(PasswordCheck.strength('12345678'), lessThanOrEqualTo(1));
      expect(PasswordCheck.strength('Hoa@Flygo2026'), 4);
    });
  });

  group('AppGrants', () {
    test('gộp theo app, đếm quyền, nguồn', () {
      final g = AppGrants.group(_perms);
      expect(g.length, 9);
      final todo = g.firstWhere((x) => x.app == 'vn.flygo.todo');
      expect(todo.count, 13);
      expect(todo.tools.length, 12);
      expect(todo.kinds, {'everyone'});
      final flows = g.firstWhere((x) => x.app == 'vn.flygo.flows');
      expect(flows.kinds, {'everyone', 'user', 'dept'});
      expect(flows.events, ['process.done']);
      expect(flows.others.first, 'use');
    });
    test('trùng quyền từ nhiều nguồn tính 1', () {
      final g = AppGrants.group([
        {'app': 'a', 'perm': 'use', 'via': 'everyone:*'},
        {'app': 'a', 'perm': 'use', 'via': 'user:x'},
      ]);
      expect(g.single.count, 1);
      expect(g.single.perms['use'], {'everyone:*', 'user:x'});
    });
  });

  group('trang', () {
    testWidgets('quyền thu gọn theo app, mở ra mới thấy chi tiết', (t) async {
      await _pump(
        t,
        UserDetailPage(id: _Id(), userId: 'u2', policy: _loadPolicy),
        size: const Size(500, 2400),
      );
      expect(find.text('Ghi chú & Việc'), findsOneWidget);
      expect(find.text('13 quyền'), findsOneWidget);
      expect(find.text('Công cụ AI: 12'), findsNothing);
      expect(find.textContaining('tool:'), findsNothing);
      await t.tap(find.text('Ghi chú & Việc'));
      await _settle(t);
      expect(find.text('Công cụ AI: 12'), findsOneWidget);
    });

    testWidgets('tìm quyền lọc app', (t) async {
      await _pump(
        t,
        UserDetailPage(id: _Id(), userId: 'u2', policy: _loadPolicy),
        size: const Size(500, 2400),
      );
      await t.enterText(find.byKey(const ValueKey('grants-search')), 'ký số');
      await _settle(t);
      expect(find.text('Ghi chú & Việc'), findsNothing);
      expect(find.text('Ký số'), findsOneWidget);
    });

    testWidgets('Đăng nhập: 2 công tắc Google + mật khẩu, nhắc chưa có mật khẩu', (t) async {
      await _pump(
        t,
        UserDetailPage(id: _Id(guard: false), userId: 'u4', policy: _loadPolicy),
        size: const Size(500, 2400),
      );
      expect(find.byKey(const ValueKey('sw-google')), findsOneWidget);
      expect(find.byKey(const ValueKey('sw-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('no-password-hint')), findsOneWidget);
      // Máy chủ chưa có chặn đăng nhập / passkey: không hiện các công tắc đó.
      expect(find.byKey(const ValueKey('sw-allowed')), findsNothing);
      expect(find.byKey(const ValueKey('sw-passkey')), findsNothing);
    });

    Future<_Id> openDialog(WidgetTester t, {String? error}) async {
      final id = _Id(passwordError: error);
      await _pump(
        t,
        UserDetailPage(id: id, userId: 'u2', policy: _loadPolicy),
        size: const Size(500, 1400),
      );
      await t.tap(find.byKey(const ValueKey('btn-password')));
      await _settle(t);
      return id;
    }

    bool submitEnabled(WidgetTester t) => t.widget<FilledButton>(find.byKey(const ValueKey('pw-submit'))).onPressed != null;

    testWidgets('mật khẩu 7 ký tự: nút Đặt tắt', (t) async {
      await openDialog(t);
      expect(submitEnabled(t), isFalse);
      await t.enterText(find.byKey(const ValueKey('pw-new')), 'abc1234');
      await t.enterText(find.byKey(const ValueKey('pw-confirm')), 'abc1234');
      await _settle(t);
      expect(submitEnabled(t), isFalse);
    });

    testWidgets('hai ô không khớp: nút Đặt tắt; khớp: bật', (t) async {
      await openDialog(t);
      await t.enterText(find.byKey(const ValueKey('pw-new')), 'Hoa@Flygo2026');
      await t.enterText(find.byKey(const ValueKey('pw-confirm')), 'Hoa@Flygo202');
      await _settle(t);
      expect(submitEnabled(t), isFalse);
      expect(find.text('Hai mật khẩu chưa khớp'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('pw-confirm')), 'Hoa@Flygo2026');
      await _settle(t);
      expect(submitEnabled(t), isTrue);
    });

    testWidgets('chữ có dấu: nút Đặt tắt, có cảnh báo bộ gõ', (t) async {
      await openDialog(t);
      await t.enterText(find.byKey(const ValueKey('pw-new')), 'Đăng@2026x');
      await t.enterText(find.byKey(const ValueKey('pw-confirm')), 'Đăng@2026x');
      await _settle(t);
      expect(submitEnabled(t), isFalse);
      expect(find.textContaining('bộ gõ tiếng Việt'), findsOneWidget);
    });

    testWidgets('máy chủ từ chối: lỗi hiện ngay trong hộp, hộp không đóng', (t) async {
      final id = await openDialog(t, error: 'Mật khẩu phải có ít nhất 10 ký tự.');
      await t.enterText(find.byKey(const ValueKey('pw-new')), 'Hoa@Flygo2026');
      await t.enterText(find.byKey(const ValueKey('pw-confirm')), 'Hoa@Flygo2026');
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('pw-submit')));
      await _settle(t);
      expect(id.calls, contains('POST /v1/admin/users/u2/password'));
      expect(find.byKey(const ValueKey('pw-error')), findsOneWidget);
      expect(find.textContaining('ít nhất 10 ký tự'), findsOneWidget);
      expect(find.byKey(const ValueKey('pw-submit')), findsOneWidget);
    });

    testWidgets('công tắc tổng chỉ hiện khi máy chủ có', (t) async {
      await _pump(t, UsersAdminPage(id: _Id(guard: false), policy: _loadPolicy));
      expect(find.byKey(const ValueKey('guard-switch')), findsNothing);
      await _pump(t, UsersAdminPage(id: _Id(), policy: _loadPolicy));
      expect(find.byKey(const ValueKey('guard-switch')), findsOneWidget);
    });
  });

  _previews();
}

// ---------------------------------------------------------------- ảnh xem trước

void _previews() {
  final out = Platform.environment['USERS_OUT'];
  WidgetTester? t0;

  Future<void> save(WidgetTester t, String name) async {
    await _settle(t);
    await t.runAsync(() async {
      final img = await (_key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: t.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> top(String text, {bool last = false}) async {
    final f = find.text(text);
    await Scrollable.ensureVisible(t0!.element(last ? f.last : f.first), alignment: .02);
    await _settle(t0!);
  }

  Future<void> typePw(WidgetTester t, String a, String b) async {
    await t.enterText(find.byKey(const ValueKey('pw-new')), a);
    await t.enterText(find.byKey(const ValueKey('pw-confirm')), b);
    await _settle(t);
  }

  for (final b in [Brightness.dark, Brightness.light]) {
    final th = b == Brightness.light ? 'light' : 'dark';
    const phone = Size(390, 844);

    testWidgets('ảnh điện thoại $th', (t) async {
      if (out == null) return;
      t0 = t;
      await t.runAsync(_fonts);
      debugDisableShadows = false;
      await _pump(
        t,
        UsersAdminPage(id: _Id(), policy: _loadPolicy),
        b: b,
        ratio: 2,
      );
      await save(t, 'phone-$th-01-danh-sach-chan-dang-nhap');

      await t.tap(find.text('Cho phép theo phòng ban'));
      await save(t, 'phone-$th-02-cho-phep-theo-phong-ban');
      await t.tap(find.text('Huỷ'));
      await _settle(t);

      // Chi tiết: một ảnh dài cho cả trang.
      await _pump(
        t,
        UserDetailPage(id: _Id(), userId: 'u2', policy: _loadPolicy),
        size: const Size(390, 2050),
        b: b,
        ratio: 2,
      );
      await save(t, 'phone-$th-03-chi-tiet-toan-trang');
      await _pump(t, UserDetailPage(id: _Id(), userId: 'u2', policy: _loadPolicy), size: const Size(390, 1100), b: b, ratio: 2);
      await top('QUYỀN');
      await t.tap(find.text('Ghi chú & Việc'));
      await _settle(t);
      await t.tap(find.text('Công cụ AI: 12'));
      await _settle(t);
      await t.tap(find.text('Quy trình'));
      await _settle(t);
      await top('QUYỀN');
      await save(t, 'phone-$th-04-quyen-mo-rong');

      // Người chưa có mật khẩu, máy chủ hiện tại (chưa có chặn đăng nhập / passkey).
      await _pump(
        t,
        UserDetailPage(id: _Id(guard: false), userId: 'u4', policy: _loadPolicy),
        size: phone,
        b: b,
        ratio: 2,
      );
      await save(t, 'phone-$th-05-chua-co-mat-khau-may-chu-hien-tai');

      await _pump(
        t,
        UserDetailPage(id: _Id(), userId: 'u2', policy: _loadPolicy),
        size: phone,
        b: b,
        ratio: 2,
      );
      await t.tap(find.byKey(const ValueKey('btn-password')));
      await _settle(t);
      await typePw(t, 'abc1234', 'abc1234');
      await save(t, 'phone-$th-06-mat-khau-7-ky-tu-khoa-nut');
      await typePw(t, 'Hoà 2026', 'Hoà 2026');
      await save(t, 'phone-$th-07-mat-khau-co-dau-canh-bao');
      await typePw(t, 'Hoa@Flygo2026', 'Hoa@Flygo2026');
      await save(t, 'phone-$th-08-mat-khau-hop-le');

      await _pump(
        t,
        UserDetailPage(
          id: _Id(passwordError: 'Mật khẩu phải có ít nhất 10 ký tự.'),
          userId: 'u2',
          policy: _loadPolicy,
        ),
        size: phone,
        b: b,
        ratio: 2,
      );
      await t.tap(find.byKey(const ValueKey('btn-password')));
      await _settle(t);
      await typePw(t, 'Hoa@Flygo2026', 'Hoa@Flygo2026');
      await t.tap(find.byKey(const ValueKey('pw-submit')));
      await save(t, 'phone-$th-09-mat-khau-loi-may-chu');

      // Phía người dùng: passkey bắt buộc, bị chặn đăng nhập.
      for (final (i, (name, w)) in [
        ('dang-ky-passkey', const _PasskeyRegister()),
        ('xac-thuc-passkey', const _PasskeyVerify()),
        ('mat-may-khong-xac-thuc-duoc', const _PasskeyLost()),
        ('bi-chan-dang-nhap', const _LoginBlocked()),
      ].indexed) {
        await _pump(t, w, size: phone, b: b, ratio: 2);
        await save(t, 'phone-$th-${10 + i}-nguoi-dung-$name');
      }
      debugDisableShadows = true;
    });

    testWidgets('ảnh máy tính $th', (t) async {
      if (out == null) return;
      t0 = t;
      await t.runAsync(_fonts);
      debugDisableShadows = false;
      await _pump(
        t,
        UsersAdminPage(id: _Id(), policy: _loadPolicy),
        size: const Size(1440, 1000),
        b: b,
      );
      await t.tap(find.text('Nguyễn Thị Hoa'));
      await _settle(t);
      await save(t, 'desktop-$th-01-danh-sach-va-chi-tiet');
      await t.tap(find.byKey(const ValueKey('btn-password')));
      await _settle(t);
      await typePw(t, 'abc1234', 'abc123');
      await save(t, 'desktop-$th-03-dat-mat-khau');
      await t.tap(find.text('Huỷ'));
      await _settle(t);
      await t.tap(find.text('Quy trình'));
      await _settle(t);
      await top('QUYỀN');
      await save(t, 'desktop-$th-02-quyen-va-thiet-bi');
      await _pump(t, const _PasskeyVerify(), size: const Size(1440, 1000), b: b);
      await save(t, 'desktop-$th-04-nguoi-dung-xac-thuc-passkey');
      debugDisableShadows = true;
    });
  }
}

/// Khung chung của các màn người dùng (bản xem trước, chưa có trong app).
class _GateScreen extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, body;
  final List<Widget> actions;
  final Widget? extra;
  const _GateScreen({required this.icon, required this.color, required this.title, required this.body, required this.actions, this.extra});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .14)),
                      child: Icon(icon, size: 56, color: color),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: pal.sub),
                  ),
                  if (extra != null) ...[const SizedBox(height: 18), extra!],
                  const SizedBox(height: 28),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _account(Pal pal) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14)),
  child: Row(
    children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: pal.avatarBg,
        child: Icon(Icons.person, color: pal.avatarFg),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nguyễn Thị Hoa', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('hoa.nt@flygo.vn · iPhone 15', style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ],
        ),
      ),
    ],
  ),
);

class _PasskeyRegister extends StatelessWidget {
  const _PasskeyRegister();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return _GateScreen(
      icon: Icons.fingerprint_rounded,
      color: const Color(0xFF14B8A6),
      title: 'Đăng ký passkey cho máy này',
      body:
          'Công ty yêu cầu mỗi thiết bị có passkey. Bạn chỉ cần xác nhận bằng Face ID, vân tay hoặc mã mở máy. '
          'Không có passkey thì chưa dùng được app trên máy này.',
      extra: _account(pal),
      actions: [
        FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.fingerprint_rounded), label: const Text('Tạo passkey bằng Face ID')),
        const SizedBox(height: 8),
        TextButton(onPressed: () {}, child: const Text('Đăng xuất')),
      ],
    );
  }
}

class _PasskeyVerify extends StatelessWidget {
  const _PasskeyVerify();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return _GateScreen(
      icon: Icons.lock_person_rounded,
      color: pal.accent,
      title: 'Xác thực để mở Flygo Chat',
      body: 'Dùng passkey của máy này (Face ID / vân tay / mã mở máy) để tiếp tục.',
      extra: _account(pal),
      actions: [
        FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.face_rounded), label: const Text('Xác thực bằng Face ID')),
        const SizedBox(height: 8),
        TextButton(onPressed: () {}, child: const Text('Không xác thực được?')),
      ],
    );
  }
}

class _PasskeyLost extends StatelessWidget {
  const _PasskeyLost();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget step(String n, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: pal.accent.withValues(alpha: .15),
            child: Text(n, style: TextStyle(fontSize: 12, color: pal.accent)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
    return _GateScreen(
      icon: Icons.phonelink_erase_rounded,
      color: const Color(0xFFF5B544),
      title: 'Không xác thực được passkey',
      body: 'Đổi máy, cài lại app hoặc mất passkey? Vì an toàn, chỉ quản trị viên mới đặt lại được.',
      extra: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            step('1', 'Báo quản trị viên (Quản trị › Người dùng › Thiết bị & passkey).'),
            step('2', 'Quản trị viên thu hồi máy cũ; máy này bị đăng xuất.'),
            step('3', 'Đăng nhập lại và đăng ký passkey mới.'),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.support_agent_rounded), label: const Text('Nhắn quản trị viên')),
        const SizedBox(height: 8),
        TextButton(onPressed: () {}, child: const Text('Thử lại')),
      ],
    );
  }
}

class _LoginBlocked extends StatelessWidget {
  const _LoginBlocked();
  @override
  Widget build(BuildContext context) => const _GateScreen(
    icon: Icons.shield_rounded,
    color: Color(0xFFFF6B6B),
    title: 'Tài khoản chưa được phép đăng nhập',
    body:
        'Công ty đang chặn đăng nhập để bảo vệ tài khoản. Nhờ quản trị viên bật "Được phép đăng nhập" cho bạn '
        'hoặc cho phòng ban của bạn, rồi đăng nhập lại.',
    actions: [],
  );
}
