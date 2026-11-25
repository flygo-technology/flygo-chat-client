// Bên yêu cầu xác thực từ xa (nút "Xác thực điện thoại" của hộp ký): POST /v1/verify, GET /v1/verify/{id}.
import 'dart:async';
import 'dart:convert';

import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('createVerify gửi tiêu đề, chi tiết, nhãn máy và ttl bằng phiên chat', () async {
    http.BaseRequest? sent;
    final id = FlygoId(
      base: 'https://id.test',
      chatToken: 'tok',
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'id': 'vr_abcdefghijkl', 'code': '47', 'expires_at': 1, 'devices': 2}), 200);
      }),
    );
    final r = await id.createVerify(title: 'Xác nhận ký số', details: {'Website': 'https://a.gov.vn'}, label: 'Trình duyệt Ký số · mac', ttl: 90);
    expect(sent!.method, 'POST');
    expect(sent!.url.toString(), 'https://id.test/v1/verify');
    expect(sent!.headers['Authorization'], 'Bearer tok');
    expect(sent!.headers['X-Flygo-Device'], isNotEmpty);
    expect(jsonDecode((sent! as http.Request).body), {
      'title': 'Xác nhận ký số',
      'details': {'Website': 'https://a.gov.vn'},
      'requester': {'label': 'Trình duyệt Ký số · mac'},
      'ttl': 90,
    });
    expect(r['code'], '47');
  });

  test('chưa có máy gắn khoá: lỗi mang thông điệp của Flygo ID', () async {
    final id = FlygoId(
      base: 'https://id.test',
      chatToken: 'tok',
      client: MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode({'error': 'chưa có máy nào gắn khoá', 'devices': 0})), 409,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    );
    await expectLater(
      id.createVerify(title: 't', details: const {}),
      throwsA(isA<FlygoIdException>().having((e) => '$e', 'message', contains('chưa có máy nào gắn khoá'))),
    );
  });

  test('verifyResult hỏi đúng yêu cầu', () async {
    http.BaseRequest? sent;
    final id = FlygoId(
      base: 'https://id.test',
      chatToken: 'tok',
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'id': 'vr_abcdefghijkl', 'status': 'approved', 'device': {'name': 'iPhone'}}), 200);
      }),
    );
    final r = await id.verifyResult('vr_abcdefghijkl');
    expect(sent!.method, 'GET');
    expect(sent!.url.path, '/v1/verify/vr_abcdefghijkl');
    expect(r['status'], 'approved');
  });

  test('máy tạo yêu cầu không tự mở màn Xác thực, kể cả khi sự kiện tới trước phản hồi', () async {
    final reply = Completer<http.Response>();
    final id = FlygoId(base: 'https://id.test', chatToken: 'tok', client: MockClient((_) => reply.future));
    final creating = id.createVerify(title: 't', details: const {});
    // Sự kiện verify_request tới lúc POST chưa trả lời.
    final own = FlygoId.isRequestedHere('vr_ownownownown');
    final other = FlygoId.isRequestedHere('vr_otherotherot');
    reply.complete(http.Response(jsonEncode({'id': 'vr_ownownownown', 'code': '12', 'expires_at': 1, 'devices': 1}), 200));
    await creating;
    expect(await own, isTrue);
    expect(await other, isFalse);
  });
}
