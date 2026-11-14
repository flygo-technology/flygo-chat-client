// Kênh realtime Flows (FlowsLive): đăng nhập bằng tin đầu, đăng ký / huỷ chủ đề, chia tin theo chủ đề, nối lại khi
// rớt (kèm resync), đóng khi hết đăng ký.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/api/flows_live.dart';
import 'package:flygo_chat/config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Fake {
  final urls = <Uri>[];
  final sent = <Map<String, dynamic>>[];
  StreamController<dynamic>? srv;
  int closed = 0;

  Future<FlowsLiveSocket> connect(Uri u) async {
    urls.add(u);
    final c = StreamController<dynamic>();
    srv = c;
    return FlowsLiveSocket(c.stream, (m) => sent.add((jsonDecode(m) as Map).cast<String, dynamic>()), () {
      closed++;
      c.close();
    });
  }

  void push(Map<String, dynamic> m) => srv!.add(jsonEncode(m));
  List<String> ops() => [for (final m in sent) '${m['op']}${m['topics'] == null ? '' : ' ${(m['topics'] as List).join(',')}'}'];
}

Future<void> _tick([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  kServerUrl = 'https://chat.test';
  late _Fake fake;
  late FlowsApi api;

  setUp(() {
    FlowsApi.debugClient = MockClient((_) async => http.Response('{}', 200));
    fake = _Fake();
    FlowsLive.connector = fake.connect;
    FlowsLive.unit = const Duration(milliseconds: 10);
    api = FlowsApi('tok-me');
  });

  tearDown(() {
    FlowsLive.resetForTest();
    FlowsApi.debugClient = null;
  });

  test('đăng nhập bằng tin đầu, đăng ký chủ đề, chia tin theo chủ đề', () async {
    final live = FlowsLive.of(api);
    expect(identical(live, FlowsLive.of(FlowsApi('tok-me'))), isTrue, reason: 'một kênh cho mỗi máy chủ + phiên');
    final flowEvents = <FlowsLiveEvent>[], procEvents = <FlowsLiveEvent>[];
    final a = live.subscribe('flow:f1', flowEvents.add);
    live.subscribe('process:p1', procEvents.add);
    await _tick();
    expect(fake.urls.single.toString(), 'wss://chat.test/__apps/flows/ws');
    expect(fake.sent.first, {'op': 'auth', 'token': 'tok-me', 'server': 'https://chat.test'});
    expect(live.up, isFalse);
    fake.push({'type': 'ready'});
    await _tick();
    expect(live.up, isTrue);
    expect(fake.ops().last, 'sub flow:f1,process:p1');

    fake.push({'type': 'instance', 'id': 'i1', 'flow_id': 'f1', 'row': {'id': 'i1', 'status': 'running'}, 'done': false});
    fake.push({'type': 'process', 'id': 'p1', 'flow_id': 'f1', 'row': {'id': 'p1', 'state': 'done'}, 'done': true});
    fake.push({'type': 'instance', 'id': 'i9', 'flow_id': 'khac', 'row': {'id': 'i9'}});
    await _tick();
    expect([for (final e in flowEvents) '${e.type}:${e.id}'], ['instance:i1', 'process:p1']);
    expect(procEvents.single.done, isTrue);
    expect(procEvents.single.row['state'], 'done');

    // Huỷ chủ đề cuối của một chủ đề: gửi unsub; chủ đề mới khi đang nối: gửi sub ngay.
    a.cancel();
    live.subscribe('instance:i2', (_) {});
    await _tick();
    expect(fake.ops().sublist(fake.ops().length - 2), ['unsub flow:f1', 'sub instance:i2']);
  });

  test('rớt thì nối lại và báo resync; vé bị từ chối thì xin vé mới', () async {
    final live = FlowsLive.of(api);
    final got = <String>[];
    live.subscribe('flow:f1', (e) => got.add(e.type));
    await _tick();
    fake.push({'type': 'ready'});
    await _tick();
    fake.srv!.close();
    await _tick(5);
    expect(live.up, isFalse);
    await _tick(60);
    expect(fake.urls.length, 2);
    fake.push({'type': 'ready'});
    await _tick();
    expect(live.up, isTrue);
    expect(got, ['resync'], reason: 'nối lại: có thể đã lỡ tin trong lúc rớt');
    expect(fake.ops().last, 'sub flow:f1');
    // Máy chủ bỏ tin (app đọc chậm).
    fake.push({'type': 'resync'});
    await _tick();
    expect(got, ['resync', 'resync']);
    // Lỗi đăng nhập: đóng, nối lại sau.
    fake.push({'type': 'error', 'status': 401, 'message': 'hết hạn'});
    await _tick();
    expect(live.up, isFalse);
    await _tick(80);
    expect(fake.urls.length, 3);
  });

  test('hết đăng ký thì đóng kết nối, không nối lại', () async {
    final live = FlowsLive.of(api);
    final s = live.subscribe('process:p1', (_) {});
    await _tick();
    fake.push({'type': 'ready'});
    await _tick();
    s.cancel();
    expect(fake.closed, 0, reason: 'chờ một lúc rồi mới đóng (chuyển màn hình không nối lại)');
    await _tick(400);
    expect(fake.closed, 1);
    expect(live.up, isFalse);
    await _tick(100);
    expect(fake.urls.length, 1);
  });

  test('test dùng HTTP giả mà không thay đường nối: không nối WebSocket', () async {
    FlowsLive.resetForTest();
    final live = FlowsLive.of(api);
    final s = live.subscribe('flow:f1', (_) {});
    await _tick();
    expect(live.up, isFalse);
    s.cancel();
  });
}
