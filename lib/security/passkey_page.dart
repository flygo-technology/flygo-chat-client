// Cá nhân › Passkey (Sếp, 498): trạng thái passkey của máy này, đăng ký / xác thực lại, các máy của mình (passkey đã
// duyệt chưa, thu hồi máy) và duyệt điện thoại mới đang xin dùng tài khoản (bấm đúng số + vân tay, verify_page.dart).
// Dữ liệu: GET /v1/me/passkey (devices, to_approve) của Flygo ID (flygo-id/id/src/passkey.ts).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../browser/flygo_id.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import '../ui/app_route.dart';
import '../ui/devices_page.dart' show confirmCountdown;
import '../ui/theme.dart';
import 'device_key.dart';
import 'passkey_gate.dart';
import 'verify_page.dart';

class PasskeyPage extends StatefulWidget {
  /// Thử nghiệm: thay Flygo ID.
  final PasskeyApi? api;
  /// Thử nghiệm: máy có khoá thiết bị không (mặc định: điện thoại iOS / Android).
  final bool? keySupported;
  const PasskeyPage({super.key, this.api, this.keySupported});
  @override
  State<PasskeyPage> createState() => _PasskeyPageState();
}

class _PasskeyPageState extends State<PasskeyPage> {
  PasskeyApi? _api;
  PasskeyStatus? _st;
  String? _error;
  /// Máy này tạo được khoá thiết bị (điện thoại; Mac có Secure Enclave). null = chưa biết.
  bool? _localOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_api == null) {
        final token = context.read<AppState>().token;
        final id = widget.api?.id ?? await FlygoId.current(token);
        if (id == null) throw tr('Máy chủ này chưa có Flygo ID.');
        _api = widget.api ?? PasskeyApi(id, token);
      }
      final st = await _api!.status();
      if (widget.keySupported == null && _localOk == null) {
        _localOk = DeviceKey.platformSupported ? await DeviceKey.status().then((s) => s.supported, onError: (_) => false) : false;
      }
      if (mounted) setState(() => (_st = st, _error = null));
    } on FlygoIdException catch (e) {
      if (mounted) setState(() => _error = e.status == 404 ? tr('Máy chủ chưa hỗ trợ passkey.') : e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(AppPageRoute(builder: (_) => PasskeyScreen(api: _api!, initial: _st!, onLogout: () {}, dismissible: true, keySupported: widget.keySupported)));
    _load();
  }

  Future<void> _approve(Map r) async {
    await Navigator.of(context).push(AppPageRoute(builder: (_) => VerifyPage(id: '${r['verify_id']}', flygoId: _api!.id)));
    _load();
  }

  Future<void> _revoke(Map d) async {
    final m = ScaffoldMessenger.of(context);
    final ok = await confirmCountdown(context,
        title: tr('Thu hồi "{0}"?', ['${d['name']}']),
        body: tr('Máy đó bị đăng xuất và mất passkey; dùng lại phải đăng ký và được duyệt lại.'),
        action: tr('Thu hồi'));
    if (!ok) return;
    try {
      await _api!.id.request('POST', '/v1/me/devices/${d['device_id']}/revoke');
      m.showSnackBar(toast(Text(tr('Đã thu hồi thiết bị'))));
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final st = _st;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, title: Text(tr('Passkey'))),
      body: st == null
          ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub))) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    _thisDevice(pal, st),
                    for (final r in (st.raw['to_approve'] as List? ?? const []))
                      if (r is Map) _approveCard(pal, r),
                    _section(pal, tr('Thiết bị của tôi')),
                    for (final d in (st.raw['devices'] as List? ?? const []))
                      if (d is Map) _device(pal, d),
                    const SizedBox(height: 12),
                    Text(
                      tr('Passkey là khoá nằm trong chip bảo mật của máy (điện thoại, Mac), mỗi lần dùng phải qua Face ID / Touch ID / vân tay / mật khẩu máy, không sao chép sang máy khác được. Máy đầu tiên tự đăng ký; khi công ty bắt buộc passkey, máy mới phải được duyệt trên một máy đã có passkey.'),
                      style: TextStyle(fontSize: 12.5, color: pal.sub),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _section(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
      );

  Widget _thisDevice(Pal pal, PasskeyStatus st) {
    final dev = st.raw['device'] as Map?;
    final trusted = dev?['trusted'] == true, hasKey = dev?['has_key'] == true;
    final desktop = !hasKey && !(widget.keySupported ?? _localOk ?? DeviceKey.platformSupported);
    final (IconData icon, Color color, String title, String body, String action) = desktop
        ? (Icons.laptop_mac_rounded, pal.accent, tr('Máy này không dùng passkey'),
            tr('Passkey dùng trên điện thoại (iPhone / Android) và máy Mac có Secure Enclave. Máy này dùng bình thường.'), '')
        : st.sessionOk
        ? (Icons.verified_user_rounded, const Color(0xFF14B8A6), tr('Máy này đã xác thực passkey'), tr('Phiên đăng nhập này đã được xác nhận.'), tr('Xác thực lại'))
        : trusted
            ? (Icons.fingerprint_rounded, const Color(0xFF14B8A6), tr('Máy này có passkey'),
                st.required ? tr('Xác thực để xác nhận phiên đăng nhập này.') : tr('Passkey đã sẵn sàng.'), tr('Xác thực'))
            : hasKey
                ? (Icons.hourglass_top_rounded, const Color(0xFFF5B544), tr('Passkey chờ duyệt'),
                    tr('Duyệt máy này trên một máy khác đã có passkey của bạn (bấm đúng số).'), tr('Xin duyệt'))
                : (Icons.fingerprint_rounded, pal.accent, tr('Máy này chưa có passkey'),
                    st.required ? tr('Công ty yêu cầu passkey. Đăng ký ngay để lần đăng nhập sau không bị chặn.') : tr('Đăng ký để sẵn sàng khi công ty bật passkey.'),
                    tr('Đăng ký passkey'));
    return Material(
      key: const ValueKey('passkey-this-device'),
      color: pal.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .14)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 3),
              Text(body, style: TextStyle(fontSize: 13, color: pal.sub)),
              if (st.required && !desktop) ...[
                const SizedBox(height: 6),
                Text(tr('Công ty đang bắt buộc passkey'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.accentText)),
              ],
              if (action.isNotEmpty) ...[
                const SizedBox(height: 10),
                FilledButton.tonal(key: const ValueKey('passkey-this-action'), onPressed: _open, child: Text(action)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _approveCard(Pal pal, Map r) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          color: const Color(0xFFF5B544).withValues(alpha: .14),
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            key: ValueKey('approve-${r['verify_id']}'),
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            leading: const Icon(Icons.phonelink_lock_rounded, color: Color(0xFFF5B544)),
            title: Text(tr('"{0}" xin dùng tài khoản của bạn', ['${r['device_name']}']), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Chỉ duyệt nếu đó đúng là máy của bạn. Bấm đúng số đang hiện trên máy kia.')),
            trailing: FilledButton(onPressed: () => _approve(r), child: Text(tr('Xem'))),
          ),
        ),
      );

  Widget _device(Pal pal, Map d) {
    final plat = '${d['platform']}'.toLowerCase();
    final phone = plat == 'ios' || plat == 'android';
    final (String label, Color c) = d['trusted'] == true
        ? (tr('Passkey đã duyệt'), const Color(0xFF14B8A6))
        : d['has_key'] == true
            ? (tr('Passkey chờ duyệt'), const Color(0xFFF5B544))
            : (phone ? tr('Chưa có passkey') : tr('Máy tính (không cần passkey)'), pal.sub);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: Icon(phone ? Icons.smartphone_rounded : Icons.laptop_mac_rounded, color: pal.text),
          title: Row(children: [
            Flexible(child: Text('${d['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (d['current'] == true) ...[
              const SizedBox(width: 6),
              Text(tr('· máy này'), style: TextStyle(fontSize: 12.5, color: pal.accentText)),
            ],
          ]),
          subtitle: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12.5)),
          trailing: d['current'] == true
              ? null
              : TextButton(style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B)), onPressed: () => _revoke(d), child: Text(tr('Thu hồi'))),
        ),
      ),
    );
  }
}
