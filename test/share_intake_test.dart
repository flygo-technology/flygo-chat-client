import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/forward_page.dart';
import 'package:flygo_chat/ui/share_intake.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Nhận chia sẻ từ app khác: đổi dữ liệu hệ điều hành thành tệp + chữ; màn "Gửi tới…" có ô chú thích.
void main() {
  bool exists(String p) => !p.contains('mat');

  test('tệp: bỏ tệp không còn trên máy; chữ / chú thích giữ nguyên', () {
    final p = parseShared({
      'files': ['/cache/a.jpg', '/cache/b.mp4', '/cache/da-mat.png', 3, ''],
      'text': '  Gửi anh báo giá  ',
    }, exists: exists)!;
    expect(p.paths, ['/cache/a.jpg', '/cache/b.mp4']);
    expect(p.text, 'Gửi anh báo giá');
  });

  test('chỉ chữ / link', () {
    final p = parseShared({'files': const [], 'text': 'Xem https://flygo.vn nhé'}, exists: exists)!;
    expect(p.paths, isEmpty);
    expect(p.text, 'Xem https://flygo.vn nhé');
  });

  test('không có gì dùng được → null', () {
    expect(parseShared(null, exists: exists), isNull);
    expect(parseShared({'files': ['/cache/da-mat.png'], 'text': ' '}, exists: exists), isNull);
    expect(parseShared('rác', exists: exists), isNull);
  });

  testWidgets('màn "Gửi tới…": tiêu đề, số tệp, ô chú thích điền sẵn chữ được chia sẻ', (t) async {
    final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const ForwardPage.share(localPaths: ['/cache/a.jpg', '/cache/b.pdf'], sharedText: 'https://flygo.vn'),
      ),
    ));
    await t.pump();
    expect(find.text('Gửi tới…'), findsOneWidget);
    expect(find.text('2 tệp'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('share-caption'))).controller!.text, 'https://flygo.vn');
  });
}
