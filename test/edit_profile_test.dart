import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/edit_profile_page.dart';

/// Chỉnh sửa hồ sơ: chỉ gửi trường đã đổi; giữ props khác; lỗi máy chủ hiện đúng chỗ.
void main() {
  final me = MmUser({
    'id': 'me', 'username': 'nguyenvana', 'first_name': 'Nguyễn Văn', 'last_name': 'An', 'nickname': '', 'position': 'Kế toán',
    'props': {'customStatus': '{"text":"x"}', 'phone': '0900'},
  });
  Map<String, dynamic> patch({String? name, String? nick, String? user, String? pos, String? phone, String? bio}) => profilePatch(me,
      name: name ?? 'Nguyễn Văn An', nickname: nick ?? '', username: user ?? 'nguyenvana', position: pos ?? 'Kế toán', phone: phone ?? '0900', bio: bio ?? '');

  test('không đổi gì: bản vá rỗng', () => expect(patch(), isEmpty));

  test('đổi tên: ghi vào first_name, bỏ last_name; tên người dùng viết thường', () {
    expect(patch(name: 'An Nguyễn'), {'first_name': 'An Nguyễn', 'last_name': ''});
    expect(patch(user: 'An.Nguyen'), {'username': 'an.nguyen'});
    expect(patch(pos: 'Trưởng phòng'), {'position': 'Trưởng phòng'});
    expect(patch(nick: 'An'), {'nickname': 'An'});
  });

  test('số điện thoại / giới thiệu: gửi kèm props khác, bỏ trường rỗng, cắt giới thiệu quá dài', () {
    final p = patch(bio: 'x' * 200)['props'] as Map;
    expect(p['customStatus'], '{"text":"x"}');
    expect(p['phone'], '0900');
    expect((p['bio'] as String).length, kBioMax);
    final cleared = patch(phone: '')['props'] as Map;
    expect(cleared.containsKey('phone'), isFalse);
  });

  test('lỗi máy chủ: trùng tên người dùng vào ô tên người dùng; trường do SSO quản lý báo chung', () {
    expect(profileError(ApiException(400, 'An account with that username already exists.', 'app.user.save.username_exists.app_error')).$1, 'username');
    final sso = profileError(ApiException(400, 'x', 'api.user.update_user.login_provider_attribute_set.app_error'));
    expect(sso.$1, isNull);
    expect(sso.$2, contains('Google'));
    expect(profileError(Exception('mạng')).$1, isNull);
  });
}
