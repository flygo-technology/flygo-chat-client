// Thiết bị (mục Cá nhân): các máy đang đăng nhập tài khoản này, lấy từ Flygo ID (/v1/me/devices). Mỗi máy ghi rõ
// mức an toàn: có khoá bảo mật trong chip, mở bằng vân tay / khuôn mặt = "Đạt an toàn" (dùng cho xác thực từ xa).
// Thu hồi máy / gỡ khoá không cần xác thực (Sếp): chỉ hộp xác nhận đếm ngược 10 giây.
import '../update/build_label.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../browser/flygo_id.dart';
import '../config.dart';
import '../i18n/i18n.dart';
import '../security/device_key.dart';
import '../state/app_state.dart';
import 'theme.dart';

String get _platform => Platform.isIOS
    ? 'ios'
    : Platform.isAndroid
        ? 'android'
        : Platform.isMacOS
            ? 'macos'
            : Platform.isWindows
                ? 'windows'
                : 'linux';

String get _defaultName => switch (_platform) {
      'ios' => 'iPhone',
      'android' => 'Android',
      _ => Platform.localHostname,
    };


class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  /// Ghi nhận máy đang dùng với Flygo ID (mở app và mỗi 6 giờ): danh sách Thiết bị luôn có máy này, Flygo ID biết
  /// máy nào nhận được push xác thực.
  static DateTime? _beat;
  static Future<void> heartbeat(String chatToken) async {
    if (_beat != null && DateTime.now().difference(_beat!) < const Duration(hours: 6)) return;
    _beat = DateTime.now();
    try {
      final id = await FlygoId.current(chatToken);
      if (id == null) return;
      final info = await PackageInfo.fromPlatform();
      await id.request('POST', '/v1/me/devices/register', {
        'device_id': await FlygoId.deviceId(),
        'name': _defaultName,
        'platform': _platform,
        'os': Platform.operatingSystemVersion,
        'app_version': '${info.version}+${info.buildNumber}',
        'push': !isDesktop,
      });
    } catch (_) {
      _beat = null;
    }
  }

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  FlygoId? _id;
  List<Map<String, dynamic>> _devices = const [];
  List<Map<String, dynamic>> _others = const [];
  String? _error;
  bool _loading = true;
  DeviceKeyStatus? _local;

  @override
  void initState() {
    super.initState();
    _load(register: true);
  }

  Future<void> _load({bool register = false}) async {
    setState(() => (_loading = true, _error = null));
    try {
      final id = _id ??= await FlygoId.current(context.read<AppState>().token);
      if (id == null) throw tr('Máy chủ này chưa có Flygo ID.');
      if (register) {
        // Ghi nhận máy đang dùng (tên chỉ dùng khi máy mới; đổi tên ở trang này).
        final info = await PackageInfo.fromPlatform();
        await id.request('POST', '/v1/me/devices/register', {
          'device_id': await FlygoId.deviceId(),
          'name': _defaultName,
          'platform': _platform,
          'os': Platform.operatingSystemVersion,
          'app_version': '${info.version}+${info.buildNumber}',
          'push': !isDesktop,
        }).catchError((_) => <String, dynamic>{});
      }
      _local = await DeviceKey.status().catchError((_) => const DeviceKeyStatus(
          supported: false, biometric: 'unavailable', enrolled: false, hwBacked: false, biometricBound: false));
      final j = await id.request('GET', '/v1/me/devices');
      if (!mounted) return;
      setState(() {
        _devices = [for (final d in (j['devices'] as List? ?? const [])) if (d is Map && d['revoked_at'] == null) Map<String, dynamic>.from(d)]
          ..sort((a, b) => (a['current'] == true ? 0 : 1).compareTo(b['current'] == true ? 0 : 1));
        _others = [for (final s in (j['other_sessions'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _loading = false));
    }
  }

  Future<void> _act(Future<Object?> Function() f, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      m.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  Future<void> _rename(Map<String, dynamic> d) async {
    final ctl = TextEditingController(text: '${d['name'] ?? ''}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đổi tên thiết bị')),
        content: TextField(controller: ctl, autofocus: true, maxLength: 60, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await _act(() => _id!.request('PATCH', '/v1/me/devices/${d['device_id']}', {'name': name.trim()}), tr('Đã đổi tên'));
  }

  Future<void> _revoke(Map<String, dynamic> d) async {
    final current = d['current'] == true;
    final ok = await confirmCountdown(
      context,
      title: tr('Thu hồi "{0}"?', ['${d['name'] ?? ''}']),
      body: current
          ? tr('Máy này sẽ bị đăng xuất ngay và mất khoá bảo mật.')
          : tr('Máy đó sẽ bị đăng xuất khỏi tài khoản và mất khoá bảo mật.'),
      action: tr('Thu hồi'),
    );
    if (!ok) return;
    await _act(() => _id!.request('POST', '/v1/me/devices/${d['device_id']}/revoke'), tr('Đã thu hồi thiết bị'));
  }

  Future<void> _enroll(Map<String, dynamic> d) async {
    await _act(() => DeviceKey.enroll(chatToken: context.read<AppState>().token, name: '${d['name'] ?? _defaultName}'),
        tr('Đã bật khoá bảo mật cho máy này'));
  }

  Future<void> _removeKey(Map<String, dynamic> d) async {
    final token = context.read<AppState>().token;
    final ok = await confirmCountdown(context,
        title: tr('Gỡ khoá bảo mật?'), body: tr('Máy này sẽ không còn dùng được để xác thực từ xa.'), action: tr('Gỡ khoá'));
    if (!ok) return;
    await _act(
        () => d['current'] == true
            ? DeviceKey.remove(chatToken: token)
            : _id!.request('DELETE', '/v1/me/devices/${d['device_id']}/key'),
        tr('Đã gỡ khoá bảo mật'));
  }

  Future<void> _revokeSession(Map<String, dynamic> s) async {
    final ok = await confirmCountdown(context,
        title: tr('Đăng xuất phiên này?'), body: _sessionLabel(s), action: tr('Đăng xuất'));
    if (!ok) return;
    await _act(() => _id!.request('POST', '/v1/me/sessions/${s['id']}/revoke'), tr('Đã đăng xuất phiên'));
  }

  static String _sessionLabel(Map<String, dynamic> s) {
    final p = (s['props'] as Map?) ?? const {};
    final parts = ['${p['os'] ?? ''}', '${p['browser'] ?? ''}'].where((x) => x.trim().isNotEmpty).toList();
    return parts.isEmpty ? tr('Phiên đăng nhập') : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: Text(tr('Thiết bị')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: tr('Tải lại'))],
      ),
      body: _loading && _devices.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _devices.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: TextStyle(color: pal.sub)),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: () => _load(register: true), child: Text(tr('Thử lại'))),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                      child: Text(
                          tr('Các máy đang đăng nhập tài khoản của bạn. Máy "Đạt an toàn" có khoá bảo mật trong chip, mở bằng vân tay hoặc khuôn mặt, dùng để xác thực từ xa.'),
                          style: TextStyle(fontSize: 13, color: pal.sub)),
                    ),
                    for (final d in _devices)
                      _DeviceCard(
                        d: d,
                        local: d['current'] == true ? _local : null,
                        onEnroll: d['current'] == true && d['key'] == null && (_local?.available ?? false) ? () => _enroll(d) : null,
                        onRename: () => _rename(d),
                        onRevoke: () => _revoke(d),
                        onRemoveKey: d['key'] == null ? null : () => _removeKey(d),
                      ),
                    if (_others.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                        child: Text(tr('PHIÊN ĐĂNG NHẬP KHÁC'),
                            style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
                      ),
                      for (final s in _others)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.language_rounded),
                            title: Text(_sessionLabel(s)),
                            subtitle: Text(_ago(s['last_activity_at'])),
                            trailing: TextButton(onPressed: () => _revokeSession(s), child: Text(tr('Đăng xuất'))),
                          ),
                        ),
                    ],
                  ]),
                ),
    );
  }
}

String _ago(Object? ms) {
  final t = ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
  if (t == null || ms == 0) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return tr('Đang hoạt động');
  if (d.inHours < 1) return tr('{0} phút trước', ['${d.inMinutes}']);
  if (d.inDays < 1) return tr('{0} giờ trước', ['${d.inHours}']);
  return tr('{0} ngày trước', ['${d.inDays}']);
}

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> d;
  final VoidCallback onRename, onRevoke;
  final VoidCallback? onRemoveKey, onEnroll;
  /// Máy đang dùng: trạng thái khoá trên chính máy (không hỗ trợ / chưa cài vân tay…).
  final DeviceKeyStatus? local;
  const _DeviceCard({required this.d, required this.onRename, required this.onRevoke, this.onRemoveKey, this.onEnroll, this.local});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final key = d['key'] as Map?;
    final safe = key != null && key['hw_backed'] == true && key['biometric_bound'] == true;
    final (badgeIcon, badgeColor, badgeText) = safe
        ? (Icons.verified_user_rounded, const Color(0xFF16A34A), tr('Đạt an toàn'))
        : key != null
            ? (Icons.shield_outlined, const Color(0xFFD97706), tr('Khoá chưa gắn vân tay'))
            : local != null && !local!.available
                ? (Icons.block_rounded, pal.sub, tr(local!.label))
                : (Icons.gpp_maybe_outlined, const Color(0xFFD97706), tr('Chưa có khoá bảo mật'));
    final icon = switch ('${d['platform']}') {
      'ios' || 'android' => Icons.smartphone_rounded,
      'macos' => Icons.laptop_mac_rounded,
      'windows' => Icons.laptop_windows_rounded,
      'web' => Icons.language_rounded,
      _ => Icons.computer_rounded,
    };
    final sub = [
      '${d['os'] ?? ''}',
      if ('${d['app_version'] ?? ''}'.isNotEmpty) 'Flygo ${buildLabel('${d['app_version']}')}',
    ].where((x) => x.trim().isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 34, color: pal.accentText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${d['name'] ?? ''}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
                if (d['current'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: pal.accent.withValues(alpha: .16), borderRadius: BorderRadius.circular(6)),
                    child: Text(tr('Thiết bị này'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: pal.accentText)),
                  ),
              ]),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 13, color: pal.sub)),
              Text(_ago(d['last_seen']), style: TextStyle(fontSize: 12.5, color: pal.sub)),
              const SizedBox(height: 6),
              Row(children: [
                Icon(badgeIcon, size: 17, color: badgeColor),
                const SizedBox(width: 4),
                Flexible(child: Text(badgeText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: badgeColor))),
              ]),
              if (onEnroll != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                      onPressed: onEnroll, icon: const Icon(Icons.fingerprint_rounded), label: Text(tr('Bật khoá bảo mật'))),
                ),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'rename' => onRename(),
              'key' => onRemoveKey?.call(),
              _ => onRevoke(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(tr('Đổi tên'))),
              if (onRemoveKey != null) PopupMenuItem(value: 'key', child: Text(tr('Gỡ khoá bảo mật'))),
              PopupMenuItem(value: 'revoke', child: Text(tr('Thu hồi thiết bị'), style: const TextStyle(color: Colors.redAccent))),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Hộp xác nhận cho thao tác khó hoàn tác (thu hồi máy, gỡ khoá…): nút xác nhận chỉ bấm được sau [seconds] giây.
Future<bool> confirmCountdown(BuildContext context,
    {required String title, required String body, required String action, int seconds = 10}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _CountdownDialog(title: title, body: body, action: action, seconds: seconds),
  );
  return r == true;
}

class _CountdownDialog extends StatefulWidget {
  final String title, body, action;
  final int seconds;
  const _CountdownDialog({required this.title, required this.body, required this.action, required this.seconds});
  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  late int _left = widget.seconds;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Text(widget.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Huỷ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _left > 0 ? null : () => Navigator.pop(context, true),
            child: Text(_left > 0 ? '${widget.action} ($_left)' : widget.action),
          ),
        ],
      );
}
