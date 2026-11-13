import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/servers.dart';

/// Danh sách máy chủ không được mất khi tệp ghi dở / hỏng (app bị tắt giữa lúc ghi, ghi chồng nhau).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  const ch = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('servers_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (_) async => tmp.path);
    ServerList.items = [];
    ServerList.current = '';
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
    tmp.deleteSync(recursive: true);
  });
  File file() => File('${tmp.path}/servers.json');

  test('tệp chính hỏng: đọc bản dự phòng, không thành danh sách rỗng', () async {
    await ServerList.add('https://chat.a.test', 'A');
    await ServerList.add('https://chat.b.test', 'B');
    file().writeAsStringSync('{"current": "https://chat.b.te');
    ServerList.items = [];
    await ServerList.load();
    expect(ServerList.items.map((e) => e.url), ['https://chat.a.test']);
    expect(ServerList.current, 'https://chat.a.test');
  });

  test('ghi nhiều lần cùng lúc: tệp vẫn đúng và đủ', () async {
    ServerList.items = [ServerEntry('https://chat.a.test', 'A')];
    ServerList.current = 'https://chat.a.test';
    await Future.wait([for (var i = 0; i < 10; i++) ServerList.setServerId('https://chat.a.test', 'id$i')]);
    ServerList.items = [];
    await ServerList.load();
    expect(ServerList.items.single.url, 'https://chat.a.test');
    expect(ServerList.items.single.serverId, 'id9');
    expect(File('${file().path}.tmp').existsSync(), isFalse);
  });

  test('chưa có tệp: danh sách rỗng (lần đầu cài app)', () async {
    await ServerList.load();
    expect(ServerList.items, isEmpty);
    expect(ServerList.current, '');
  });
}
