import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/ui/home_page.dart' show kMainMiniApps;
import 'package:flygo_chat/ui/mini_app_view.dart';
import 'package:flygo_chat/ui/theme.dart';

MiniApp _dich(String icon) => MiniApp.fromJson({
      'id': 'vn.flygo.dich',
      'name': {'vi': 'Dịch thuật'},
      'icon': '🌐',
      'base_url': 'https://chat.example.com/__apps/dich',
      'tile': {'icon': icon, 'color': '#1A73E8'},
    });

Future<void> _pump(WidgetTester t, MiniApp a) =>
    t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Center(child: MiniAppIcon(a))));

void main() {
  test('Dịch thuật nằm ở mục Chính', () => expect(kMainMiniApps, contains('vn.flygo.dich')));

  testWidgets('tile.icon "translate": biểu tượng dịch', (t) async {
    await _pump(t, _dich('translate'));
    expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
  });

  testWidgets('tên biểu tượng lạ (như bản app cũ gặp "translate"): dùng emoji của app, không lỗi', (t) async {
    await _pump(t, _dich('khong-co'));
    expect(t.takeException(), isNull);
    expect(find.text('🌐'), findsOneWidget);
  });
}
