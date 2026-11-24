// Hẹn giờ gửi tin kèm ảnh: tệp được tải lên trước, rồi tạo tin hẹn giờ có file_ids (trước đây tin kèm ảnh bị gửi ngay, Sếp 25/11).
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';

class _FakeApi extends MmApi {
  _FakeApi() : super('t');
  final uploads = <String>[];
  final sent = <(String, Map)>[];
  @override
  Future<List<String>> uploadPath(String channelId, String name, String path, {int chunk = 20 << 20}) async {
    uploads.add('$channelId/$name');
    return ['f${uploads.length}'];
  }

  @override
  Future<dynamic> post(String p, Object? body) async {
    sent.add((p, (body as Map?) ?? const {}));
    return {};
  }

  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async => <dynamic>[];
}

void main() {
  test('scheduleMedia: tải tệp rồi hẹn giờ một tin có file_ids, không tạo tin gửi ngay', () async {
    final api = _FakeApi();
    final app = AppState('t', api: api)..me = MmUser({'id': 'me', 'username': 'ba'});
    app.aiConsent = true;
    final at = DateTime.now().add(const Duration(hours: 2));
    await app.scheduleMedia('c1', 'Ảnh báo cáo', at, [('/tmp/a.jpg', 'a.jpg'), ('/tmp/b.png', 'b.png')], rootId: 'r1');
    expect(api.uploads, ['c1/a.jpg', 'c1/b.png']);
    expect(api.sent.map((e) => e.$1), ['/posts/schedule']);
    final body = api.sent.single.$2;
    expect(body['file_ids'], ['f1', 'f2']);
    expect(body['message'], 'Ảnh báo cáo');
    expect(body['root_id'], 'r1');
    expect(body['scheduled_at'], at.millisecondsSinceEpoch);
  });
}
