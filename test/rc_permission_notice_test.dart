// Điều khiển máy tính (Sếp không điều khiển được MacBook / Mac mini của mình từ iPhone): máy bị điều khiển thiếu quyền
// macOS thì báo rõ quyền nào, trên cả hai máy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/remote/rc_native.dart';
import 'package:flygo_chat/remote/rc_service.dart';
import 'package:flygo_chat/remote/rc_ui.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  test('quyền còn thiếu gửi cho máy điều khiển', () {
    expect(rcMissingOf(const RcPermissions(accessibility: true, screen: true)), isNull);
    expect(rcMissingOf(const RcPermissions(accessibility: true, screen: false)), 'screen');
    expect(rcMissingOf(const RcPermissions(accessibility: false, screen: true)), 'accessibility');
    expect(rcMissingOf(const RcPermissions(accessibility: false, screen: false)), 'both');
  });

  test('câu báo trên máy điều khiển: nói rõ quyền nào, các bước, cần mở lại app khi thiếu Ghi màn hình', () {
    final s = rcPermissionText('MacBook của Ba', 'screen');
    expect(s, startsWith('Máy MacBook của Ba chưa bật quyền Ghi màn hình cho Flygo Chat.'));
    expect(s, contains('Quyền riêng tư & Bảo mật › Ghi màn hình'));
    expect(s, contains('mở lại Flygo Chat'));
    final a = rcPermissionText('Mac mini', 'accessibility');
    expect(a, contains('Trợ năng'));
    expect(a, isNot(contains('mở lại')));
    expect(rcPermissionText('Mac mini', 'both'), contains('Ghi màn hình và Trợ năng'));
    // Máy kia bản cũ (không gửi quyền nào): câu cũ.
    expect(rcPermissionText('Lan', null), 'Máy của Lan chưa cấp quyền điều khiển. Thử lại sau khi họ cấp quyền.');
  });

  testWidgets('máy bị điều khiển: hộp báo thiếu quyền có nút mở Cài đặt cho quyền thiếu và Mở lại Flygo Chat', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: RcPermissionNotice(fromName: 'iPhone của Ba', debugPermissions: RcPermissions(accessibility: true, screen: false)),
      ),
    ));
    expect(find.text('Flygo Chat chưa có quyền điều khiển máy này'), findsOneWidget);
    expect(find.textContaining('iPhone của Ba vừa yêu cầu'), findsOneWidget);
    expect(find.byKey(const ValueKey('rc-perm-open-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('rc-perm-open-accessibility')), findsNothing);
    expect(find.byKey(const ValueKey('rc-perm-relaunch')), findsOneWidget);
  });

  testWidgets('chỉ thiếu Trợ năng: không cần mở lại app', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
        body: RcPermissionNotice(fromName: 'Ba', debugPermissions: RcPermissions(accessibility: false, screen: true)),
      ),
    ));
    expect(find.byKey(const ValueKey('rc-perm-open-accessibility')), findsOneWidget);
    expect(find.byKey(const ValueKey('rc-perm-relaunch')), findsNothing);
  });
}
