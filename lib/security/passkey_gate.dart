// Passkey bắt buộc theo thiết bị (Sếp duyệt 2026-11-17). Passkey = khoá thiết bị (device_key.dart: Secure Enclave /
// Android Keystore, mỗi lần ký qua vân tay / khuôn mặt). Flygo ID: GET /v1/me/passkey, POST /v1/me/passkey/challenge,
// /verify, /request-approval (flygo-id/id/src/passkey.ts).
//
// - Phiên mới (enforced): chặn app tới khi chứng minh passkey; máy chủ thu hồi phiên sau 10 phút nếu không chứng minh.
// - Phiên cũ (có trước khi bị bắt buộc): KHÔNG chặn, chỉ nhắc đăng ký một lần mỗi lần mở app.
// - Máy mới: khoá phải được duyệt trên một điện thoại đã duyệt của chính mình (bấm số + vân tay) hoặc bởi quản trị viên.
// Lỗi mạng / máy chủ chưa có tính năng: cho vào app (máy chủ vẫn tự thu hồi phiên chưa đạt).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../browser/flygo_id.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import 'device_key.dart';

/// Trạng thái passkey của phiên đang dùng (GET /v1/me/passkey).
class PasskeyStatus {
  final Map<String, dynamic> raw;
  const PasskeyStatus(this.raw);
  bool get required => raw['required'] == true;
  bool get sessionOk => raw['session_ok'] == true;
  bool get enforced => raw['enforced'] == true;
  /// none | enroll | approve | verify
  String get needs => '${raw['needs'] ?? 'none'}';
  bool get blocking => required && !sessionOk && enforced;
  bool get prompt => required && !sessionOk && !enforced;
  int get trustedPhones => (raw['trusted_phones'] as num?)?.toInt() ?? 0;
  Map? get pending => raw['pending_approval'] as Map?;
}

/// Máy chủ có passkey (GET /v1/me/passkey trả lời được): mục Cá nhân › Passkey chỉ hiện khi true.
final passkeySupported = ValueNotifier<bool>(false);

/// Gọi Flygo ID cho passkey; tách ra để thử nghiệm thay được.
class PasskeyApi {
  final FlygoId id;
  final String chatToken;
  PasskeyApi(this.id, this.chatToken);

  Future<PasskeyStatus> status() async => PasskeyStatus(await id.request('GET', '/v1/me/passkey'));

  Future<void> enroll(String deviceName) => DeviceKey.enroll(chatToken: chatToken, name: deviceName);

  Future<PasskeyStatus> verify() async {
    final c = await id.request('POST', '/v1/me/passkey/challenge');
    final sig = await DeviceKey.sign(Uint8List.fromList(utf8.encode('${c['message']}')),
        title: tr('Xác thực passkey'), subtitle: tr('Mở Flygo Chat trên máy này'));
    return PasskeyStatus(await id.request('POST', '/v1/me/passkey/verify', {'challenge': c['challenge'], 'sig': sig}));
  }

  /// {verify_id, code, expires_at} hoặc ném FlygoIdException (409 need_admin khi chưa có điện thoại đã duyệt).
  Future<Map<String, dynamic>> requestApproval() => id.request('POST', '/v1/me/passkey/request-approval');
}

/// Bọc màn hình chính: chặn khi phiên mới chưa chứng minh passkey, nhắc khi phiên cũ chưa đăng ký.
class PasskeyGate extends StatefulWidget {
  final Widget child;
  final VoidCallback onLogout;
  /// Thử nghiệm: thay Flygo ID.
  final PasskeyApi? api;
  const PasskeyGate({super.key, required this.child, required this.onLogout, this.api});
  @override
  State<PasskeyGate> createState() => _PasskeyGateState();
}

class _PasskeyGateState extends State<PasskeyGate> with WidgetsBindingObserver {
  PasskeyApi? _api;
  PasskeyStatus? _st;
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _st != null && _st!.required && !_st!.sessionOk) _check();
  }

  Future<void> _check() async {
    try {
      if (_api == null) {
        final token = context.read<AppState>().token;
        final id = widget.api?.id ?? await FlygoId.current(token);
        if (id == null) return;
        _api = widget.api ?? PasskeyApi(id, token);
      }
      final st = await _api!.status();
      passkeySupported.value = true;
      if (!mounted) return;
      setState(() => _st = st);
      if (st.prompt && !_prompted) {
        _prompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _offer());
      }
    } catch (_) {
      // Máy chủ chưa có passkey / lỗi mạng: không chặn.
    }
  }

  Future<void> _offer() async {
    if (!mounted || _api == null) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.fingerprint_rounded, size: 48, color: Color(0xFF14B8A6)),
            const SizedBox(height: 10),
            Text(tr('Đăng ký passkey cho máy này'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(tr('Công ty đã bật passkey bắt buộc. Máy này vẫn dùng bình thường, nhưng lần đăng nhập sau sẽ cần passkey. Đăng ký ngay chỉ mất vài giây.'),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đăng ký ngay'))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Để sau'))),
          ]),
        ),
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PasskeyScreen(api: _api!, initial: _st!, onLogout: widget.onLogout, dismissible: true)));
      _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    // Máy tính (không có khoá thiết bị) chỉ bị chặn khi phạm vi là "mọi thiết bị" (máy chủ cũng kiểm như vậy).
    if (st != null && st.blocking && _api != null && (DeviceKey.platformSupported || st.raw['scope'] == 'all')) {
      return PasskeyScreen(api: _api!, initial: st, onLogout: widget.onLogout, onDone: (s) => setState(() => _st = s));
    }
    return widget.child;
  }
}

/// Màn đăng ký / xác thực / xin duyệt passkey.
class PasskeyScreen extends StatefulWidget {
  final PasskeyApi api;
  final PasskeyStatus initial;
  final VoidCallback onLogout;
  final ValueChanged<PasskeyStatus>? onDone;
  /// Mở từ lời nhắc (phiên cũ): có nút quay lại.
  final bool dismissible;
  /// Thử nghiệm / ảnh xem trước: máy có khoá thiết bị không.
  final bool? keySupported;
  const PasskeyScreen({super.key, required this.api, required this.initial, required this.onLogout, this.onDone, this.dismissible = false, this.keySupported});
  @override
  State<PasskeyScreen> createState() => _PasskeyScreenState();
}

class _PasskeyScreenState extends State<PasskeyScreen> {
  late PasskeyStatus _st = widget.initial;
  bool _busy = false, _help = false, _needAdmin = false;
  String? _error;
  Map<String, dynamic>? _approval;
  Timer? _poll;

  bool get _keyOk => widget.keySupported ?? DeviceKey.platformSupported;

  /// Việc cần làm, suy từ trạng thái khoá của máy (không chỉ theo needs: khi không bắt buộc needs là "none").
  /// Máy tính không có khoá thiết bị: không bao giờ bắt xác thực; chỉ phải xin duyệt khi phiên này bị bắt buộc
  /// (phạm vi "mọi thiết bị").
  String get _mode {
    final d = _st.raw['device'] as Map?;
    if (d?['has_key'] != true) return _keyOk ? 'enroll' : (_st.blocking ? 'approve' : 'desktop');
    return d?['trusted'] == true ? 'verify' : 'approve';
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _set(PasskeyStatus s) {
    if (!mounted) return;
    setState(() => _st = s);
    if (s.sessionOk) {
      _poll?.cancel();
      widget.onDone?.call(s);
      if (widget.dismissible) Navigator.of(context).maybePop();
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => (_busy = true, _error = null));
    try {
      await f();
    } on DeviceKeyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FlygoIdException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _enroll() => _run(() async {
        await widget.api.enroll(Platform.isIOS ? 'iPhone' : Platform.isAndroid ? 'Android' : Platform.localHostname);
        final s = await widget.api.status();
        _set(s);
        // Máy cũ được tin ngay: xác thực luôn cho đỡ một bước.
        if (s.needs == 'verify') _set(await widget.api.verify());
      });

  Future<void> _verify() => _run(() async => _set(await widget.api.verify()));

  Future<void> _requestApproval() => _run(() async {
        try {
          final a = await widget.api.requestApproval();
          setState(() => (_approval = a, _needAdmin = false));
        } on FlygoIdException catch (e) {
          if (e.status == 409) {
            setState(() => _needAdmin = true);
            return;
          }
          rethrow;
        }
        _poll?.cancel();
        _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
          try {
            final s = await widget.api.status();
            _set(s);
            if (s.needs == 'verify') {
              _poll?.cancel();
              setState(() => _approval = null);
            } else if (s.pending == null && !s.sessionOk) {
              _poll?.cancel();
              setState(() => (_approval = null, _error = tr('Yêu cầu bị từ chối hoặc hết hạn. Thử lại.')));
            }
          } catch (_) {}
        });
      });

  Future<void> _recheck() => _run(() async => _set(await widget.api.status()));

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final needs = _mode;
    final (IconData icon, Color color, String title, String body) = _help
        ? (Icons.phonelink_erase_rounded, const Color(0xFFF5B544), tr('Không xác thực được passkey'),
            tr('Đổi máy, cài lại app, thêm vân tay mới hoặc mất máy? Vì an toàn, chỉ quản trị viên mới duyệt lại được.'))
        : _needAdmin
            ? (Icons.admin_panel_settings_rounded, const Color(0xFFF5B544), tr('Cần quản trị viên duyệt'),
                tr('Bạn chưa có điện thoại nào đã duyệt để xác nhận máy này. Nhờ quản trị viên vào Quản trị › Người dùng › Thiết bị & passkey và bấm "Duyệt".'))
            : switch (needs) {
                'enroll' => (Icons.fingerprint_rounded, const Color(0xFF14B8A6), tr('Đăng ký passkey cho máy này'),
                    tr('Công ty yêu cầu mỗi điện thoại có passkey. Chỉ cần xác nhận bằng Face ID, vân tay hoặc mã mở máy.')),
                'desktop' => (Icons.laptop_mac_rounded, pal.accent, tr('Máy tính không cần passkey'),
                    tr('Passkey chỉ dùng trên điện thoại (iPhone / Android). Máy tính này dùng bình thường, không phải đăng ký.')),
                'approve' => (Icons.verified_user_outlined, pal.accent, tr('Máy này cần được duyệt'),
                    _keyOk
                        ? tr('Passkey đã tạo. Để chắc chắn là bạn, hãy duyệt máy này trên một điện thoại khác đã dùng passkey (bấm đúng số + vân tay).')
                        : tr('Xác nhận lần đăng nhập này trên điện thoại đã dùng passkey của bạn (bấm đúng số + vân tay).')),
                _ => (Icons.lock_person_rounded, pal.accent, tr('Xác thực để mở Flygo Chat'), tr('Dùng passkey của máy này (Face ID / vân tay / mã mở máy) để tiếp tục.')),
              };
    final code = _approval?['code'];
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: widget.dismissible ? AppBar(backgroundColor: pal.bg) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .14)),
                      child: Icon(icon, size: 56, color: color),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, height: 1.4, color: pal.sub)),
                  if (code != null && !_help) ...[
                    const SizedBox(height: 20),
                    Container(
                      key: const ValueKey('passkey-code'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        Text(tr('Trên điện thoại kia, chọn số'), style: TextStyle(color: pal.sub)),
                        Text('$code', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: pal.accent)),
                        Text(tr('Đang chờ duyệt…'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
                      ]),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, key: const ValueKey('passkey-error'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF6B6B))),
                  ],
                  const SizedBox(height: 28),
                  if (needs == 'desktop' && !_help) ...[
                    if (widget.dismissible) FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(tr('Đóng'))),
                  ] else if (_help) ...[
                    // Đường thoát: xin duyệt (điện thoại đã duyệt khác, hoặc báo cần quản trị viên) thay vì kẹt ở Xác thực.
                    FilledButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() => _help = false);
                                _requestApproval();
                              },
                        child: Text(tr('Xin duyệt lại máy này'))),
                    TextButton(onPressed: () => setState(() => _help = false), child: Text(tr('Thử lại'))),
                  ] else if (_needAdmin) ...[
                    FilledButton(onPressed: _busy ? null : _recheck, child: Text(tr('Kiểm tra lại'))),
                  ] else if (code == null)
                    FilledButton.icon(
                      key: const ValueKey('passkey-action'),
                      onPressed: _busy
                          ? null
                          : switch (needs) {
                              'enroll' => _enroll,
                              'approve' => _requestApproval,
                              _ => _verify,
                            },
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(needs == 'approve' ? Icons.send_to_mobile_rounded : Icons.fingerprint_rounded),
                      label: Text(switch (needs) {
                        'enroll' => tr('Tạo passkey'),
                        'approve' => tr('Xin duyệt trên điện thoại khác'),
                        _ => tr('Xác thực'),
                      }),
                    ),
                  const SizedBox(height: 8),
                  if (!_help && needs != 'desktop') TextButton(onPressed: () => setState(() => _help = true), child: Text(tr('Không xác thực được?'))),
                  if (!widget.dismissible) TextButton(onPressed: widget.onLogout, child: Text(tr('Đăng xuất'))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
