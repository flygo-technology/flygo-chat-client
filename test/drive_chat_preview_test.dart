import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/drive/session.dart';
import 'package:flygo_chat/ui/file_card.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  final drive = MiniApp.fromJson({'id': 'vn.flygo.web.drive', 'name': 'Drive', 'base_url': 'https://drive.example.com'});

  test('driveShareToken: link chia sẻ của máy Drive đang dùng, cả /index.php và /download', () {
    MiniApps.debugSetCached([drive]);
    expect(driveShareToken(Uri.parse('https://drive.example.com/s/9EPPbraywXFfRb3')), '9EPPbraywXFfRb3');
    expect(driveShareToken(Uri.parse('https://drive.example.com/index.php/s/AbC123/download')), 'AbC123');
    expect(driveShareToken(Uri.parse('https://other.example.com/s/9EPPbraywXFfRb3')), isNull);
    expect(driveShareToken(Uri.parse('https://drive.example.com/s/ab')), isNull);
    expect(driveShareToken(Uri.parse('https://drive.example.com/drive/')), isNull);
    MiniApps.debugSetCached([]);
    expect(driveShareToken(Uri.parse('https://drive.example.com/s/9EPPbraywXFfRb3')), isNull);
  });

  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: AppState('test'),
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child)),
      );

  testWidgets('Thẻ tệp trong chat: nút Xem cho PDF / ảnh; Word / Excel khi máy chủ có Drive; không có cho tệp khác', (t) async {
    MiniApps.debugSetCached([]);
    MmFile f(String name, String mime) => MmFile({'id': name, 'name': name, 'size': 1000, 'mime_type': mime});
    await t.pumpWidget(wrap(FileCard(file: f('hop-dong.pdf', 'application/pdf'), desktop: true)));
    expect(find.text('Xem'), findsOneWidget);
    await t.pumpWidget(wrap(FileCard(file: f('Okie.xlsx', ''), desktop: true)));
    expect(find.text('Xem'), findsNothing); // chưa có Drive để chuyển sang PDF
    MiniApps.debugSetCached([drive]);
    await t.pumpWidget(wrap(FileCard(key: const ValueKey(2), file: f('Okie.xlsx', ''), desktop: false)));
    expect(find.text('Xem'), findsOneWidget);
    await t.pumpWidget(wrap(FileCard(key: const ValueKey(3), file: f('a.zip', ''), desktop: false)));
    expect(find.text('Xem'), findsNothing);
  });
}
