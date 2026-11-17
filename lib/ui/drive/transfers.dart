// Drive: tiến độ tải xuống / tải lên ở góc dưới màn hình.
// - Tải xuống: tên tệp đang tải, %, tốc độ, "2/5 mục", "Đang nén thư mục…"; xong thì "Mở thư mục" (Finder / Explorer)
//   và "Mở tệp" (máy tính), "Mở" / "Chia sẻ" (điện thoại).
// - Tải lên: từng tệp + tổng, huỷ từng tệp; xong thì trang Drive tự chọn và cuộn tới các tệp vừa tải lên.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../i18n/i18n.dart';
import '../open_file.dart' show openLocalFile, revealInFileManager;
import 'api.dart';
import 'look.dart';
import 'session.dart';
import 'uploads.dart';

enum DownloadState { running, done, failed }

class DriveDownload {
  DriveDownload(this.count);
  final int count;
  int done = 0;
  String name = '';
  bool zipping = false;
  int got = 0, total = 0;
  double speed = 0; // byte/s
  DownloadState state = DownloadState.running;
  String? error;
  String? dir;
  final files = <File>[];

  int _lastAt = 0, _lastGot = 0;
  void progress(int g, int t) {
    got = g;
    total = t;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastAt == 0) {
      _lastAt = now;
      _lastGot = g;
    } else if (now - _lastAt >= 400) {
      final inst = (g - _lastGot) * 1000 / (now - _lastAt);
      speed = speed == 0 ? inst : speed * .6 + inst * .4;
      _lastAt = now;
      _lastGot = g;
    }
  }

  void next(String n, {bool zip = false}) {
    name = n;
    zipping = zip;
    got = total = 0;
    _lastAt = 0;
  }
}

/// Các lượt tải xuống của một phiên Drive.
class DriveDownloads extends ChangeNotifier {
  final list = <DriveDownload>[];
  void changed() => notifyListeners();
  void remove(DriveDownload d) {
    list.remove(d);
    notifyListeners();
  }
}

bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Tải [items] (tệp nguyên bản, thư mục thành `<tên>.zip`): máy tính vào thư mục Tải về, điện thoại vào thư mục tạm.
/// Tiến độ hiện ở bảng dưới màn hình ([TransfersPanel]).
Future<DriveDownload> startDownload(DriveSession s, List<DriveItem> items) async {
  final d = DriveDownload(items.length);
  s.downloads.list.add(d);
  s.downloads.changed();
  try {
    final dir = _desktop
        ? (await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory()).path
        : '${(await getTemporaryDirectory()).path}/drive_dl/${DateTime.now().millisecondsSinceEpoch}';
    await Directory(dir).create(recursive: true);
    d.dir = dir;
    final used = <String>{};
    for (final it in items) {
      final name = freeLocalName(dir, it.dir ? '${it.name}.zip' : it.name, used, check: true);
      final dest = File('$dir/$name');
      d.next(name, zip: it.dir);
      s.downloads.changed();
      void prog(int g, int t) {
        d.progress(g, t);
        s.downloads.changed();
      }

      if (it.dir) {
        d.files.add(await s.api.downloadZip(it.parent, [it.name], dest, onProgress: prog));
      } else {
        final off = s.offline.localFile(it);
        d.files.add(off != null ? await off.copy(dest.path) : await s.api.download(it.path, dest, onProgress: prog));
      }
      d.done++;
      s.downloads.changed();
    }
    d.state = DownloadState.done;
  } catch (e) {
    d.state = DownloadState.failed;
    d.error = '$e';
  }
  s.downloads.changed();
  return d;
}

/// Tên chưa có trong [dir] (và chưa dùng trong lượt này): "a.txt" → "a (1).txt".
String freeLocalName(String dir, String name, Set<String> used, {required bool check}) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name, ext = dot > 0 ? name.substring(dot) : '';
  var n = name;
  for (var i = 1; used.contains(n.toLowerCase()) || (check && File('$dir/$n').existsSync()); i++) {
    n = '$stem ($i)$ext';
  }
  used.add(n.toLowerCase());
  return n;
}

String fmtSpeed(double bps) => '${fmtSize(bps.round())}/s';

/// Bảng tiến độ ở góc dưới (máy tính: góc phải; điện thoại: ngang màn hình). Ẩn khi không có gì.
class TransfersPanel extends StatefulWidget {
  const TransfersPanel({super.key, required this.session, required this.wide});
  final DriveSession session;
  final bool wide;
  @override
  State<TransfersPanel> createState() => _TransfersPanelState();
}

class _TransfersPanelState extends State<TransfersPanel> {
  bool _open = true;
  /// Tệp tải lên xong trước thời điểm này không hiện nữa (bấm đóng bảng).
  int _since = DateTime.now().millisecondsSinceEpoch;

  DriveSession get s => widget.session;

  List<UploadJob> get _ups => [
        for (final j in s.uploads.jobs)
          if (j.active || j.state == UploadState.paused || ((j.state == UploadState.done || j.state == UploadState.failed) && j.doneAt >= _since)) j,
      ];

  void _dismiss() {
    setState(() => _since = DateTime.now().millisecondsSinceEpoch);
    for (final d in [...s.downloads.list]) {
      if (d.state != DownloadState.running) s.downloads.remove(d);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([s.uploads, s.downloads]),
        builder: (context, _) {
          final l = DriveLook.of(context);
          final ups = _ups, downs = s.downloads.list;
          if (ups.isEmpty && downs.isEmpty) return const SizedBox.shrink();
          final upActive = ups.where((j) => j.active).length;
          final downActive = downs.where((d) => d.state == DownloadState.running).length;
          final busy = upActive + downActive > 0;
          final title = [
            if (upActive > 0) tr('Đang tải lên {0} tệp · {1}%', ['$upActive', '${(s.uploads.overall * 100).round()}']),
            if (upActive == 0 && ups.isNotEmpty) tr('Đã tải lên {0} tệp', ['${ups.where((j) => j.state == UploadState.done).length}']),
            if (downActive > 0) tr('Đang tải xuống'),
            if (downActive == 0 && downs.isNotEmpty) tr('Đã tải xuống'),
          ].join(' · ');
          return Material(
            elevation: 8,
            color: l.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: l.surface2,
                padding: const EdgeInsets.only(left: 14),
                height: 46,
                child: Row(children: [
                  if (busy) SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: l.accent)) else Icon(Icons.check_circle_rounded, size: 18, color: l.ok),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: l.text))),
                  IconButton(
                    tooltip: _open ? tr('Thu gọn') : tr('Mở rộng'),
                    icon: Icon(_open ? Icons.expand_more_rounded : Icons.expand_less_rounded, color: l.muted),
                    onPressed: () => setState(() => _open = !_open),
                  ),
                  if (!busy) IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: l.muted), onPressed: _dismiss),
                ]),
              ),
              if (upActive > 0) LinearProgressIndicator(value: s.uploads.overall == 0 ? null : s.uploads.overall, minHeight: 3, color: l.accent, backgroundColor: l.line),
              if (_open)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
                    for (final d in downs) _download(l, d),
                    for (final j in ups) _upload(l, j),
                  ]),
                ),
            ]),
          );
        },
      );

  Widget _row(DriveLook l, {required Widget icon, required String name, required String sub, double? value, Widget? trailing, List<Widget> actions = const []}) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 13.5)),
              const SizedBox(height: 3),
              if (value != null || sub.isNotEmpty) ...[
                if (value != null && value >= 0 && value < 1)
                  Padding(padding: const EdgeInsets.only(bottom: 3), child: LinearProgressIndicator(value: value == 0 ? null : value, minHeight: 3, color: l.accent, backgroundColor: l.line)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.muted, fontSize: 12)),
              ],
              if (actions.isNotEmpty) Wrap(spacing: 4, children: actions),
            ]),
          ),
          ?trailing,
        ]),
      );

  Widget _download(DriveLook l, DriveDownload d) {
    final pct = d.total > 0 ? d.got / d.total : 0.0;
    final counter = d.count > 1 ? tr('{0}/{1} mục', ['${d.done + (d.state == DownloadState.running ? 1 : 0)}', '${d.count}']) : '';
    switch (d.state) {
      case DownloadState.running:
        final parts = [
          if (counter.isNotEmpty) counter,
          if (d.zipping && d.total == 0) tr('Đang nén thư mục… {0}', [fmtSize(d.got)]) else if (d.total > 0) '${(pct * 100).round()}% · ${fmtSize(d.got)} / ${fmtSize(d.total)}' else fmtSize(d.got),
          if (d.speed > 0) fmtSpeed(d.speed),
        ];
        return _row(l, icon: Icon(Icons.file_download_outlined, color: l.accent), name: d.name, sub: parts.join(' · '), value: d.total > 0 ? pct : 0);
      case DownloadState.failed:
        return _row(l,
            icon: Icon(Icons.error_outline_rounded, color: l.danger),
            name: d.name,
            sub: tr('Không tải được: {0}', [d.error ?? '']),
            trailing: IconButton(icon: Icon(Icons.close_rounded, size: 18, color: l.muted), onPressed: () => s.downloads.remove(d)));
      case DownloadState.done:
        final one = d.files.length == 1 ? d.files.first : null;
        final label = one != null ? one.uri.pathSegments.last : tr('{0} mục', ['${d.files.length}']);
        return _row(l,
            icon: Icon(Icons.download_done_rounded, color: l.ok),
            name: label,
            sub: _desktop ? tr('Đã lưu vào {0}', [d.dir ?? '']) : tr('Đã tải xong'),
            actions: [
              if (_desktop) ...[
                TextButton.icon(onPressed: () => revealInFileManager(d.files.first.path), icon: const Icon(Icons.folder_open_rounded, size: 18), label: Text(tr('Mở thư mục'))),
                if (one != null) TextButton.icon(onPressed: () => openLocalFile(one.path), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text(tr('Mở tệp'))),
              ] else ...[
                if (one != null) TextButton.icon(onPressed: () => openLocalFile(one.path), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text(tr('Mở'))),
                TextButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(files: [for (final f in d.files) XFile(f.path)])),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(tr('Chia sẻ / Lưu')),
                ),
              ],
            ],
            trailing: IconButton(icon: Icon(Icons.close_rounded, size: 18, color: l.muted), onPressed: () => s.downloads.remove(d)));
    }
  }

  Widget _upload(DriveLook l, UploadJob j) {
    final (icon, sub) = switch (j.state) {
      UploadState.done => (Icon(Icons.cloud_done_rounded, color: l.ok), tr('Đã tải lên · {0}', [fmtSize(j.size)])),
      UploadState.failed => (Icon(Icons.error_outline_rounded, color: l.danger), tr('Lỗi: {0}', [j.error ?? ''])),
      UploadState.paused => (Icon(Icons.pause_circle_outline_rounded, color: l.muted), tr('Tạm dừng')),
      UploadState.queued || UploadState.waiting => (Icon(Icons.schedule_rounded, color: l.muted), tr('Đang chờ · {0}', [fmtSize(j.size)])),
      _ => (Icon(Icons.cloud_upload_outlined, color: l.accent), '${(j.progress * 100).round()}% · ${fmtSize(j.sent)} / ${fmtSize(j.size)}'),
    };
    return _row(l,
        icon: icon,
        name: j.name,
        sub: sub,
        value: j.state == UploadState.running ? j.progress : null,
        trailing: j.active ? IconButton(tooltip: tr('Huỷ'), icon: Icon(Icons.close_rounded, size: 18, color: l.muted), onPressed: () => s.uploads.cancel(j)) : null);
  }
}
