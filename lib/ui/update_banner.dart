import '../i18n/i18n.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../update/build_label.dart';
import '../update/play_update.dart';
import '../update/updater.dart';
import 'theme.dart';

/// Dải "Có bản mới · Cập nhật" phía trên danh sách chat (Android, máy tính).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: Updater.available,
      builder: (_, u, _) => u == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: Listenable.merge([Updater.progress, PlayUpdate.progress, PlayUpdate.downloaded]),
              builder: (_, _) {
                // Bản Google Play: tiến độ tải nền của Play; tải xong thì "Khởi động lại để cập nhật".
                final p = u.play ? PlayUpdate.progress.value : Updater.progress.value;
                final ready = u.play && PlayUpdate.downloaded.value;
                return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.system_update, color: pal.accentText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          ready
                              ? tr('Đã tải xong bản mới')
                              : u.play
                                  ? tr('Có bản mới trên Google Play')
                                  : tr('Có bản mới {0}', [u.label]),
                          style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 14)),
                      if (p != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(value: p, color: pal.accent, backgroundColor: pal.surface2),
                        )
                      else if (u.notes.isNotEmpty)
                        Text(u.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.sub, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: pal.accent,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: p != null
                        ? null
                        : () => Updater.install().catchError((_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    toast(Text(tr('Không tải được bản cập nhật. Kiểm tra kết nối mạng.'))));
                              }
                            }),
                    child: Text(p != null
                        ? '${(p * 100).round()}%'
                        : ready
                            ? tr('Khởi động lại để cập nhật')
                            : tr('Cập nhật')),
                  ),
                ]),
              );
              },
            ),
    );
  }
}

/// Bấm "Phiên bản" ở trang cá nhân: kiểm tra bản mới rồi hiện ngay trong hộp thoại
/// (có bản mới thì cập nhật luôn, không thì báo đang dùng bản mới nhất).
Future<void> showUpdateDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _UpdateDialog());

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _loading = true;
  bool _failed = false;
  UpdateInfo? _update;
  PlayUpdateInfo? _playInfo;
  String _current = '';

  /// Bản Google Play (Android): hỏi Play có bản mới không.
  static bool get _play => Updater.playBuild;

  /// iPhone / iPad (hoặc bản cửa hàng khác) không tự cập nhật được: cập nhật qua TestFlight / App Store.
  static bool get _store => !kIsWeb && !_play && (Platform.isIOS || Updater.storeBuild);

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final info = await PackageInfo.fromPlatform();
    _current = info.buildNumber.isNotEmpty ? info.buildNumber : buildLabel(info.version);
    UpdateInfo? u;
    if (_play) {
      _playInfo = await Updater.checkPlay();
      _failed = _playInfo == null;
    } else if (!_store) {
      u = await Updater.check();
      _failed = u == null && Updater.lastCheckFailed;
    }
    if (!mounted) return;
    setState(() {
      _update = u;
      _loading = false;
    });
  }

  Widget _playDialog(Pal pal) {
    final i = _playInfo;
    if (i != null && i.available) {
      return ValueListenableBuilder<bool>(
        valueListenable: PlayUpdate.downloaded,
        builder: (_, ready, _) => AlertDialog(
          icon: Icon(Icons.system_update, color: pal.accentText, size: 36),
          title: Text(ready ? tr('Đã tải xong bản mới') : tr('Có bản mới trên Google Play'),
              textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontSize: 18)),
          content: Text(tr('Đang dùng bản {0}', [_current]), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Để sau'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: pal.accent, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(context).pop();
                Updater.install();
              },
              child: Text(ready ? tr('Khởi động lại để cập nhật') : tr('Cập nhật')),
            ),
          ],
        ),
      );
    }
    return AlertDialog(
      icon: Icon(_failed ? Icons.cloud_off_outlined : Icons.verified_outlined, color: _failed ? pal.sub : pal.accentText, size: 36),
      title: Text(tr('Đang dùng bản {0}', [_current]), textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontSize: 18)),
      content: Text(
          _failed
              ? tr('Không kiểm tra được với Google Play. Mở Google Play để xem có bản mới không.')
              : tr('Google Play chưa có bản mới hơn bản đang dùng (bản mới có thể đang chờ Google duyệt).'),
          textAlign: TextAlign.center,
          style: TextStyle(color: pal.sub)),
      actions: [
        TextButton(onPressed: PlayUpdate.openStore, child: Text(tr('Mở Google Play'))),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('OK'))),
      ],
    );
  }

  Future<void> _install() async {
    try {
      await Updater.install();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(toast(Text(tr('Không tải được bản cập nhật. Kiểm tra kết nối mạng.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_loading) {
      return AlertDialog(
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: pal.accent)),
          const SizedBox(width: 18),
          Expanded(child: Text(tr('Đang kiểm tra bản mới...'), style: TextStyle(color: pal.text))),
        ]),
      );
    }
    if (_play) return _playDialog(pal);
    final u = _update;
    if (u == null) {
      return AlertDialog(
        icon: Icon(_failed ? Icons.cloud_off_outlined : Icons.verified_outlined, color: _failed ? pal.sub : pal.accentText, size: 36),
        // Bản cửa hàng (TestFlight / App Store) không tự kiểm tra được: chỉ báo bản đang dùng, không khẳng định là mới nhất.
        title: Text(
            _failed
                ? tr('Không kiểm tra được bản mới')
                : _store
                    ? tr('Đang dùng bản {0}', [_current])
                    : tr('Bạn đang dùng bản mới nhất ({0})', [_current]),
            textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontSize: 18)),
        content: _store
            ? Text(tr('Cập nhật qua TestFlight / App Store'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub))
            : _failed
                ? Text(tr('Kiểm tra kết nối mạng rồi thử lại.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub))
                : null,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('OK')))],
      );
    }
    return ValueListenableBuilder<double?>(
      valueListenable: Updater.progress,
      builder: (_, p, _) => PopScope(
        canPop: p == null,
        child: AlertDialog(
          icon: Icon(Icons.system_update, color: pal.accentText, size: 36),
          title: Text(tr('Có bản mới {0}', [u.label]), textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontSize: 18)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Đang dùng bản {0}', [_current]), style: TextStyle(color: pal.sub, fontSize: 13)),
              if (u.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(child: Text(u.notes, style: TextStyle(color: pal.text, fontSize: 14.5))),
                ),
              ],
              if (p != null)
                ValueListenableBuilder<(int, int)>(
                  valueListenable: Updater.downloaded,
                  builder: (_, d, _) {
                    String mb(int b) => (b / 1048576).toStringAsFixed(1);
                    final known = d.$2 > 0;
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 14),
                      LinearProgressIndicator(value: known ? p : null, color: pal.accent, backgroundColor: pal.surface2),
                      const SizedBox(height: 6),
                      Text(
                        known
                            ? tr('Đang tải... {0}% ({1}/{2} MB)', [(p * 100).round(), mb(d.$1), mb(d.$2)])
                            : tr('Đang tải... {0} MB', [mb(d.$1)]),
                        style: TextStyle(color: pal.sub, fontSize: 12.5),
                      ),
                    ]);
                  },
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: p != null ? null : () => Navigator.of(context).pop(), child: Text(tr('Để sau'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: pal.accent, foregroundColor: Colors.white),
              onPressed: p != null ? null : _install,
              child: Text(tr('Cập nhật ngay')),
            ),
          ],
        ),
      ),
    );
  }
}
