import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/flygo_card.dart';

void main() {
  MmPost post(Object? card) => MmPost({'id': 'p', 'channel_id': 'c', 'user_id': 'u', 'create_at': 0, 'message': 'x', 'props': {'flygo_card': card}});

  test('nhận thẻ v1 có tiêu đề', () {
    expect(flygoCardOf(post({'v': 1, 'title': 'Hoá đơn'})), isNotNull);
  });

  test('bỏ qua thẻ sai phiên bản hoặc thiếu tiêu đề', () {
    expect(flygoCardOf(post({'v': 2, 'title': 'Hoá đơn'})), isNull);
    expect(flygoCardOf(post({'v': 1})), isNull);
    expect(flygoCardOf(post('chuỗi')), isNull);
    expect(flygoCardOf(post(null)), isNull);
  });
}
