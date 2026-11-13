// Màn hình "Xác thực": một yêu cầu xác thực từ xa (Flygo ID, devices-verify.md) tới điện thoại này. Người dùng xem nội
// dung, chọn đúng mã số đang hiện ở nơi yêu cầu (1 trong 3), rồi xác nhận bằng vân tay / khuôn mặt: máy ký bằng khoá
// thiết bị và gửi chữ ký. Từ chối thì không cần ký. Mở từ thông báo (kể cả lúc khoá máy) hoặc sự kiện websocket.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../browser/flygo_id.dart';
import 'device_key.dart';

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key, required this.id, required this.flygoId});
  final String id;
  final FlygoId flygoId;

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  Map<String, dynamic>? _req;
  String? _error;
  String? _done; // approved | denied | failed | expired
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _req != null && _done == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.flygoId.verifyRequest(widget.id);
      if (!mounted) return;
      setState(() {
        _req = r;
        if (r['status'] != null && r['status'] != 'pending') _done = '${r['status']}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  DateTime? get _expires {
    final v = _req?['expires_at'];
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 1e12 ? v.toInt() : (v * 1000).toInt());
    return DateTime.tryParse('$v');
  }

  int get _secondsLeft {
    final e = _expires;
    return e == null ? 0 : e.difference(DateTime.now()).inSeconds;
  }

  Future<void> _approve(String code) async {
    final r = _req;
    if (r == null || _busy) return;
    setState(() => _busy = true);
    try {
      final message = DeviceKey.verifyMessage(widget.id, '${r['details_json'] ?? ''}', code);
      final sig = await DeviceKey.sign(message, title: 'Xác thực', subtitle: '${r['title'] ?? ''}');
      final res = await widget.flygoId.respondVerify(widget.id, approve: true, code: code, sig: sig);
      if (mounted) setState(() => _done = '${res['status'] ?? 'approved'}');
    } on DeviceKeyException catch (e) {
      if (mounted && e.code != 'cancelled') setState(() => _error = e.message);
    } on FlygoIdException catch (e) {
      if (mounted) setState(() => e.status == 409 ? _done = 'expired' : _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deny() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.flygoId.respondVerify(widget.id, approve: false);
      if (mounted) setState(() => _done = 'denied');
    } on FlygoIdException catch (e) {
      if (mounted) setState(() => e.status == 409 ? _done = 'expired' : _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nội dung yêu cầu: details_json là chuỗi JSON; hiện từng dòng khoá: giá trị.
  List<(String, String)> get _details {
    try {
      final d = jsonDecode('${_req?['details_json'] ?? ''}');
      if (d is Map) return [for (final e in d.entries) ('${e.key}', e.value is String ? e.value as String : jsonEncode(e.value))];
      if (d != null) return [('', '$d')];
    } catch (_) {}
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _req;
    final requester = r?['requester'] is Map ? Map<String, dynamic>.from(r!['requester'] as Map) : const <String, dynamic>{};
    final left = _secondsLeft;
    final expired = r != null && _done == null && _expires != null && left <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Xác thực'), automaticallyImplyLeading: true),
      body: SafeArea(
        child: _error != null && r == null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
            : r == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Icon(Icons.verified_user_rounded, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('${r['title'] ?? 'Yêu cầu xác thực'}', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if ('${requester['label'] ?? requester['app'] ?? ''}'.isNotEmpty) '${requester['label'] ?? requester['app']}',
                          if ('${requester['device_name'] ?? ''}'.isNotEmpty) 'từ ${requester['device_name']}',
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (_details.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              for (final (k, v) in _details)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Text.rich(TextSpan(children: [
                                    if (k.isNotEmpty) TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    TextSpan(text: v),
                                  ])),
                                ),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (_done != null)
                        _Result(status: _done!)
                      else if (expired)
                        const _Result(status: 'expired')
                      else ...[
                        Text('Chọn mã số đang hiện ở nơi yêu cầu', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (final c in [for (final x in (r['codes'] as List? ?? const [])) '$x'])
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 84,
                                height: 72,
                                child: FilledButton.tonal(
                                  onPressed: _busy ? null : () => _approve(c),
                                  child: Text(c, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 10),
                        Text('Còn ${left.clamp(0, 3600)} giây · chọn mã rồi xác nhận bằng vân tay / khuôn mặt',
                            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error))),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _deny,
                          icon: const Icon(Icons.block_rounded),
                          label: const Text('Không phải tôi · Từ chối'),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (status) {
      'approved' => (Icons.check_circle_rounded, Colors.green, 'Đã xác thực'),
      'denied' => (Icons.cancel_rounded, Colors.orange, 'Đã từ chối'),
      'failed' => (Icons.error_rounded, Colors.red, 'Sai mã số: yêu cầu đã bị huỷ'),
      _ => (Icons.timer_off_rounded, Colors.grey, 'Yêu cầu đã hết hạn hoặc đã được xử lý'),
    };
    return Column(children: [
      Icon(icon, color: color, size: 48),
      const SizedBox(height: 8),
      Text(text, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Xong')),
    ]);
  }
}
