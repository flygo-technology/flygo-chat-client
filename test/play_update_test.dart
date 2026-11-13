import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/update_banner.dart';
import 'package:flygo_chat/update/play_update.dart';
import 'package:flygo_chat/update/updater.dart';

/// Bản Google Play: hỏi Play có bản mới (In-App Updates), chọn cập nhật bắt buộc / linh hoạt, dải "Có bản mới".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('flygo/playupdate');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
    Updater.available.value = null;
    PlayUpdate.downloaded.value = false;
    PlayUpdate.progress.value = null;
  });

  test('ưu tiên >= 4 thì cập nhật bắt buộc, còn lại linh hoạt', () {
    PlayUpdateInfo i(int p, {bool imm = true, bool flex = true}) =>
        PlayUpdateInfo(available: true, priority: p, immediateAllowed: imm, flexibleAllowed: flex);
    expect(i(0).immediate, isFalse);
    expect(i(3).immediate, isFalse);
    expect(i(4).immediate, isTrue);
    expect(i(5, imm: false).immediate, isFalse, reason: 'Play không cho bắt buộc thì linh hoạt');
    expect(i(0, flex: false).immediate, isTrue, reason: 'Play chỉ cho bắt buộc');
  });

  test('hỏi Play: có bản mới thì Updater.available là bản Play; không có / lỗi thì null', () async {
    Object? reply = {'available': true, 'versionCode': 460, 'priority': 1, 'immediate': true, 'flexible': true, 'status': 0};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
      if (reply is PlatformException) throw reply;
      return reply;
    });
    final i = await Updater.checkPlay();
    expect(i!.versionCode, 460);
    expect(Updater.available.value!.play, isTrue);
    expect(Updater.available.value!.label, 'Google Play');

    reply = {'available': false, 'versionCode': 0, 'status': 0};
    await Updater.checkPlay();
    expect(Updater.available.value, isNull);

    reply = PlatformException(code: 'play', message: 'Install Error(-10): The app is not owned by any user on this device');
    expect(await Updater.checkPlay(), isNull);
    expect(PlayUpdate.lastError, contains('not owned'));
    expect(Updater.available.value, isNull);
  });

  testWidgets('dải cập nhật: bản Play hiện "Có bản mới trên Google Play"; tải xong thì "Khởi động lại để cập nhật"', (t) async {
    Updater.available.value = UpdateInfo.play(460);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: UpdateBanner())));
    expect(find.text('Có bản mới trên Google Play'), findsOneWidget);
    expect(find.text('Cập nhật'), findsOneWidget);
    PlayUpdate.progress.value = .4;
    await t.pump();
    expect(find.text('40%'), findsOneWidget);
    PlayUpdate.progress.value = null;
    PlayUpdate.downloaded.value = true;
    await t.pump();
    expect(find.text('Đã tải xong bản mới'), findsOneWidget);
    expect(find.text('Khởi động lại để cập nhật'), findsOneWidget);
  });
}
