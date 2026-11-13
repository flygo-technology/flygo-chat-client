// Chỉnh sửa hồ sơ (Sếp, 2026-11-13): mở từ nút "Chỉnh sửa hồ sơ" của thẻ người dùng trang Mở ứng dụng. Điện thoại:
// trang riêng; máy tính: hộp thoại rộng 520. Sửa ảnh đại diện (đổi / xoá), tên hiển thị, biệt danh, @tên người dùng,
// chức danh, số điện thoại (props.phone), giới thiệu ngắn (props.bio); email chỉ xem. Lưu: PATCH /users/me chỉ các trường
// đã đổi; lỗi của máy chủ (trùng tên người dùng, trường do đăng nhập Google quản lý...) hiện ngay dưới ô.
// Ảnh bìa: chưa làm (vẫn là dải màu chuyển của app).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/mm_api.dart';
import '../config.dart' show isDesktop;
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'app_route.dart';
import 'common.dart';
import 'theme.dart';

final usernamePattern = RegExp(r'^[a-z][a-z0-9._-]{2,21}$');
const kBioMax = 160;

/// Bản vá hồ sơ: chỉ các trường đã đổi (rỗng nếu không đổi gì). Tên hiển thị như app đang tính (họ + tên, không có thì
/// biệt danh): đổi tên thì ghi cả vào first_name, bỏ last_name. Máy chủ thay cả props khi patch nên gửi kèm props khác.
Map<String, dynamic> profilePatch(MmUser me,
    {required String name, required String nickname, required String username, required String position, required String phone, required String bio}) {
  final patch = <String, dynamic>{};
  final n = name.trim();
  if (n.isNotEmpty && n != me.displayName) patch.addAll({'first_name': n.length > 64 ? n.substring(0, 64) : n, 'last_name': ''});
  if (nickname.trim() != me.nickname) patch['nickname'] = nickname.trim();
  final un = username.trim().toLowerCase();
  if (un.isNotEmpty && un != me.username) patch['username'] = un;
  if (position.trim() != '${me.raw['position'] ?? ''}') patch['position'] = position.trim();
  final props = ((me.raw['props'] as Map?) ?? const {}).cast<String, dynamic>();
  final b = bio.trim();
  final p = phone.trim();
  if (p != '${props['phone'] ?? ''}' || b != '${props['bio'] ?? ''}') {
    patch['props'] = {...props, 'phone': p, 'bio': b.length > kBioMax ? b.substring(0, kBioMax) : b}
      ..removeWhere((k, v) => (k == 'phone' || k == 'bio') && v == '');
  }
  return patch;
}

/// Lỗi lưu hồ sơ của máy chủ: (ô bị lỗi hoặc null, lời báo).
(String?, String) profileError(Object e) {
  final id = e is ApiException ? '${e.id} ${e.message}' : '$e';
  if (id.contains('username_exists') || id.contains('username') && id.contains('exists')) return ('username', tr('Tên người dùng này đã có người dùng.'));
  if (id.contains('username') && (id.contains('restricted') || id.contains('invalid'))) return ('username', tr('Tên người dùng không hợp lệ.'));
  if (id.contains('login_provider_attribute') || id.contains('sso')) {
    return (null, tr('Một số thông tin do đăng nhập Google / Flygo ID quản lý nên không đổi được ở đây.'));
  }
  return (null, tr('Không lưu được hồ sơ. Kiểm tra kết nối mạng rồi thử lại.'));
}

/// Mở màn chỉnh sửa hồ sơ (máy tính: hộp thoại; điện thoại: trang).
Future<void> showEditProfile(BuildContext context) {
  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const SizedBox(width: 520, height: 680, child: EditProfilePage(dialog: true)),
      ),
    );
  }
  return Navigator.of(context).push(AppPageRoute(builder: (_) => const EditProfilePage()));
}

class EditProfilePage extends StatefulWidget {
  final bool dialog;
  const EditProfilePage({super.key, this.dialog = false});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final MmUser _me = context.read<AppState>().me!;
  late final _name = TextEditingController(text: _me.displayName);
  late final _nick = TextEditingController(text: _me.nickname);
  late final _user = TextEditingController(text: _me.username);
  late final _position = TextEditingController(text: '${_me.raw['position'] ?? ''}');
  late final _phone = TextEditingController(text: '${(_me.raw['props'] as Map?)?['phone'] ?? ''}');
  late final _bio = TextEditingController(text: '${(_me.raw['props'] as Map?)?['bio'] ?? ''}');
  late final _email = TextEditingController(text: _me.email);
  bool _saving = false;
  String? _userError, _error;

  @override
  void dispose() {
    for (final c in [_name, _nick, _user, _position, _phone, _bio, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _patch => profilePatch(context.read<AppState>().me ?? _me,
      name: _name.text, nickname: _nick.text, username: _user.text, position: _position.text, phone: _phone.text, bio: _bio.text);

  String? get _userFormatError {
    final un = _user.text.trim().toLowerCase();
    return un.isEmpty || usernamePattern.hasMatch(un) ? null : tr('3–22 ký tự, bắt đầu bằng chữ, chỉ gồm a-z, 0-9, dấu . - _');
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final patch = _patch;
    if (patch.isEmpty) return nav.pop();
    setState(() {
      _saving = true;
      _userError = null;
      _error = null;
    });
    try {
      await app.updateMyProfile(patch);
      messenger.showSnackBar(toast(Text(tr('Đã lưu hồ sơ'))));
      nav.pop();
    } catch (e) {
      final (field, msg) = profileError(e);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (field == 'username') {
          _userError = msg;
        } else {
          _error = msg;
        }
      });
    }
  }

  Future<void> _removeAvatar() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.removeMyImage();
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Không xoá được ảnh đại diện.'))));
    }
  }

  Widget _field(Pal pal, String key, TextEditingController c, String label,
      {String? hint, String? prefix, String? error, int maxLines = 1, int? maxLength, TextInputType? type, bool enabled = true, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        key: ValueKey('edit-$key'),
        controller: c,
        enabled: enabled && !_saving,
        maxLines: maxLines,
        minLines: 1,
        maxLength: maxLength,
        keyboardType: type,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: enabled ? pal.text : pal.sub, fontSize: 15.5),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          errorText: error,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final me = app.me ?? _me;
    final changed = _patch.isNotEmpty;
    final canSave = changed && !_saving && _userFormatError == null;
    final body = ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      Center(
        child: EditableAvatar(
          size: 112,
          avatar: Avatar(userId: me.id, name: me.displayName, size: 112, status: false),
          onPicked: (n, b) => app.setUserImage(me.id, n, b),
        ),
      ),
      Center(
        child: TextButton(
          key: const ValueKey('edit-remove-avatar'),
          onPressed: _saving ? null : _removeAvatar,
          style: TextButton.styleFrom(foregroundColor: pal.sub),
          child: Text(tr('Xoá ảnh đại diện')),
        ),
      ),
      const SizedBox(height: 8),
      _field(pal, 'name', _name, tr('Tên hiển thị'), maxLength: 64, icon: Icons.badge_outlined),
      _field(pal, 'nickname', _nick, tr('Biệt danh'), maxLength: 64, icon: Icons.tag_faces_outlined),
      _field(pal, 'username', _user, tr('Tên người dùng'), prefix: '@', maxLength: 22, error: _userError ?? _userFormatError, icon: Icons.alternate_email_rounded),
      _field(pal, 'position', _position, tr('Chức danh'), hint: tr('VD: Trưởng phòng Kinh doanh'), maxLength: 128, icon: Icons.work_outline_rounded),
      _field(pal, 'phone', _phone, tr('Số điện thoại'), type: TextInputType.phone, maxLength: 20, icon: Icons.phone_outlined),
      _field(pal, 'bio', _bio, tr('Giới thiệu ngắn'), maxLines: 3, maxLength: kBioMax, icon: Icons.notes_rounded),
      _field(pal, 'email', _email, tr('Email'), enabled: false, icon: Icons.mail_outline_rounded),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_error!, key: const ValueKey('edit-error'), style: const TextStyle(color: Color(0xFFE53935), fontSize: 13.5)),
        ),
    ]);
    final save = FilledButton(
      key: const ValueKey('edit-save'),
      onPressed: canSave ? _save : null,
      child: _saving
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(tr('Lưu')),
    );
    final title = Text(tr('Chỉnh sửa hồ sơ'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text));
    if (widget.dialog) {
      return Material(
        color: pal.bg,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(children: [
              Expanded(child: title),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
              const SizedBox(width: 6),
              save,
            ]),
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        foregroundColor: pal.text,
        elevation: 0,
        title: title,
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: save)],
      ),
      body: body,
    );
  }
}
