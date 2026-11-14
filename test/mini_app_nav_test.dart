import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/ui/mini_app_view.dart';
import 'package:flygo_chat/ui/theme.dart';

MiniApp _app([Map<String, dynamic> extra = const {}]) => MiniApp.fromJson({
      'id': 'vn.flygo.web.drive',
      'name': 'Drive',
      'origin': 'https://drive.example.com',
      'base_url': 'https://drive.example.com/drive',
      ...extra,
    });

void main() {
  group('manifest nav_bar', () {
    test('mặc định auto', () => expect(_app().navBar, MiniAppNavBar.auto));
    test('true / false', () {
      expect(_app({'nav_bar': true}).navBar, MiniAppNavBar.always);
      expect(_app({'nav_bar': false}).navBar, MiniAppNavBar.never);
      expect(_app({'nav_bar': 'auto'}).navBar, MiniAppNavBar.auto);
    });
    test('đọc cả features.nav_bar (registry chưa trả field nav_bar)', () {
      expect(_app({'features': {'nav_bar': false}}).navBar, MiniAppNavBar.never);
      expect(_app({'nav_bar': true, 'features': {'nav_bar': false}}).navBar, MiniAppNavBar.always);
    });
    test('toJson giữ nguyên khi đọc lại (bộ nhớ đệm danh sách app)', () {
      for (final v in [true, false, 'auto']) {
        expect(MiniApp.fromJson(_app({'nav_bar': v}).toJson()).navBar, _app({'nav_bar': v}).navBar);
      }
    });
  });

  group('underBase', () {
    final a = _app();
    test('trong base_url', () {
      expect(a.underBase(Uri.parse('https://drive.example.com/drive')), isTrue);
      expect(a.underBase(Uri.parse('https://drive.example.com/drive/f/1?x=1')), isTrue);
    });
    test('cùng origin nhưng ngoài đường dẫn base_url', () {
      expect(a.underBase(Uri.parse('https://drive.example.com/drivex')), isFalse);
      expect(a.underBase(Uri.parse('https://drive.example.com/apps/files')), isFalse);
    });
    test('origin khác', () => expect(a.underBase(Uri.parse('https://accounts.example.org/drive')), isFalse));
    test('base_url là gốc: mọi đường dẫn cùng origin', () {
      final r = MiniApp.fromJson({'id': 'x', 'origin': 'https://a.example.com', 'base_url': 'https://a.example.com/'});
      expect(r.underBase(Uri.parse('https://a.example.com/any/path')), isTrue);
    });
  });

  group('visible', () {
    final a = _app();
    final inside = Uri.parse('https://drive.example.com/drive/f/1');
    final outside = Uri.parse('https://docs.example.org/edit');
    test('auto: ẩn ở trang đầu, hiện khi lùi được hoặc ra ngoài base_url', () {
      expect(MiniAppNavBar.auto.visible(a, canGoBack: false, current: inside), isFalse);
      expect(MiniAppNavBar.auto.visible(a, canGoBack: true, current: inside), isTrue);
      expect(MiniAppNavBar.auto.visible(a, canGoBack: false, current: outside), isTrue);
      expect(MiniAppNavBar.auto.visible(a, canGoBack: false, current: Uri.parse('about:blank')), isFalse);
      expect(MiniAppNavBar.auto.visible(a, canGoBack: false), isFalse);
    });
    test('always / never', () {
      expect(MiniAppNavBar.always.visible(a, canGoBack: false, current: inside), isTrue);
      expect(MiniAppNavBar.never.visible(a, canGoBack: true, current: outside), isFalse);
    });
  });

  group('MiniAppNavStrip', () {
    Future<List<String>> pump(WidgetTester t, {Uri? url, bool back = false, bool fwd = false, bool outside = false}) async {
      final calls = <String>[];
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: MiniAppNavStrip(
            url: url,
            outside: outside,
            onBack: back ? () => calls.add('back') : null,
            onForward: fwd ? () => calls.add('forward') : null,
            onReload: () => calls.add('reload'),
            onCopy: url == null ? null : () => calls.add('copy'),
            onMenu: url == null ? null : (v) => calls.add('menu:$v'),
          ),
        ),
      ));
      return calls;
    }

    IconButton button(WidgetTester t, String key) => t.widget<IconButton>(find.byKey(ValueKey(key)));

    testWidgets('tên miền + khoá, nút lùi / tới mờ khi không đi được', (t) async {
      await pump(t, url: Uri.parse('https://drive.example.com/drive/f/1'));
      expect(find.text('drive.example.com'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(button(t, 'nav-back').onPressed, isNull);
      expect(button(t, 'nav-forward').onPressed, isNull);
      expect(button(t, 'nav-reload').onPressed, isNotNull);
    });

    testWidgets('http: khoá mở; cổng lạ hiện kèm tên miền', (t) async {
      await pump(t, url: Uri.parse('http://lan.example.com:8080/x'));
      expect(find.text('lan.example.com:8080'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    });

    testWidgets('bấm lùi, tới, tải lại, chạm tên miền để chép', (t) async {
      final calls = await pump(t, url: Uri.parse('https://drive.example.com/drive'), back: true, fwd: true);
      await t.tap(find.byKey(const ValueKey('nav-back')));
      await t.tap(find.byKey(const ValueKey('nav-forward')));
      await t.tap(find.byKey(const ValueKey('nav-reload')));
      await t.tap(find.byKey(const ValueKey('nav-domain')));
      expect(calls, ['back', 'forward', 'reload', 'copy']);
    });

    testWidgets('menu ⋯: mở trình duyệt, chép, chia sẻ liên kết', (t) async {
      final calls = await pump(t, url: Uri.parse('https://drive.example.com/drive'));
      for (final (i, v) in [(Icons.open_in_new_rounded, 'external'), (Icons.link_rounded, 'copy'), (Icons.ios_share_rounded, 'share')]) {
        await t.tap(find.byKey(const ValueKey('nav-menu')));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(i));
        await t.pumpAndSettle();
        expect(calls.last, 'menu:$v');
      }
    });

    testWidgets('chưa có trang: menu tắt, không lỗi', (t) async {
      await pump(t);
      expect(t.takeException(), isNull);
      expect(t.widget<PopupMenuButton<String>>(find.byKey(const ValueKey('nav-menu'))).enabled, isFalse);
    });
  });
}
