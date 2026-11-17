// Drive: hàng đợi tải lên. Lưu trạng thái xuống đĩa (tệp, đích, mã phiên chia khúc) nên đóng app hay mất mạng vẫn tải
// tiếp từ khúc chưa xong. Tệp lớn hơn chunk_size đi theo phiên chia khúc của drive-gw (Nextcloud chunking v2).
// Android: dịch vụ nền (foreground service, kênh "flygo/drive_upload") giữ app chạy và hiện tiến độ khi tắt màn hình.
// iPhone / máy tính: chạy khi app còn mở; lần mở sau tải nốt. Tự tải ảnh (tắt sẵn) quét ảnh mới khi mở app và mỗi 15 phút.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../i18n/i18n.dart';
import 'api.dart';

enum UploadState { queued, running, waiting, paused, done, failed, cancelled }

class UploadJob {
  UploadJob({required this.id, required this.src, required this.name, required this.dir, required this.size, this.mtime, this.origin = 'manual', this.temp = false});

  final String id, src, name, dir;
  final int size;
  final int? mtime;
  /// manual | share | camera
  final String origin;
  /// Tệp nguồn là bản sao riêng của hàng đợi: xoá khi xong.
  final bool temp;
  UploadState state = UploadState.queued;
  int sent = 0;
  String? session, target, error;
  /// Đã gửi hết, đang chờ máy chủ ghép / ghi tệp (không lưu).
  bool finishing = false;
  int doneAt = 0, retries = 0;
  DriveItem? result;

  bool get active => state == UploadState.queued || state == UploadState.running || state == UploadState.waiting;
  double get progress => size <= 0 ? (state == UploadState.done ? 1 : 0) : (sent / size).clamp(0, 1).toDouble();

  Map<String, Object?> toJson() => {
        'id': id, 'src': src, 'name': name, 'dir': dir, 'size': size, 'mtime': mtime, 'origin': origin, 'temp': temp, 'state': state.name, 'sent': sent,
        'session': session, 'target': target, 'error': error, 'done_at': doneAt, 'result': result?.toJson(),
      };

  factory UploadJob.fromJson(Map j) {
    final u = UploadJob(
      id: '${j['id']}', src: '${j['src']}', name: '${j['name']}', dir: '${j['dir'] ?? '/'}', size: (j['size'] as num?)?.toInt() ?? 0,
      mtime: (j['mtime'] as num?)?.toInt(), origin: '${j['origin'] ?? 'manual'}', temp: j['temp'] == true,
    );
    u.state = UploadState.values.firstWhere((s) => s.name == j['state'], orElse: () => UploadState.queued);
    // App bị tắt giữa chừng: việc đang chạy thành đang chờ.
    if (u.state == UploadState.running || u.state == UploadState.waiting) u.state = UploadState.queued;
    u.sent = (j['sent'] as num?)?.toInt() ?? 0;
    u.session = j['session'] as String?;
    u.target = j['target'] as String?;
    u.error = j['error'] as String?;
    u.doneAt = (j['done_at'] as num?)?.toInt() ?? 0;
    if (j['result'] is Map) u.result = DriveItem.fromJson(j['result'] as Map);
    return u;
  }
}

/// Các khúc cần gửi cho tệp [size] byte, mỗi khúc [chunk] byte: (số thứ tự từ 1, offset, độ dài). Bỏ các khúc đã có đủ.
List<(int, int, int)> chunkPlan(int size, int chunk, [Map<int, int> have = const {}]) {
  final out = <(int, int, int)>[];
  final n = size == 0 ? 1 : (size + chunk - 1) ~/ chunk;
  for (var i = 0; i < n; i++) {
    final off = i * chunk, len = (size - off) < chunk ? size - off : chunk;
    if (have[i + 1] == len) continue;
    out.add((i + 1, off, len));
  }
  return out;
}

class CameraBackup {
  bool enabled = false, wifiOnly = true, video = false;
  int since = 0, count = 0;
  String folder = '/Ảnh từ điện thoại';
  Map<String, Object?> toJson() => {'enabled': enabled, 'wifi_only': wifiOnly, 'video': video, 'since': since, 'count': count, 'folder': folder};
  void load(Map j) {
    enabled = j['enabled'] == true;
    wifiOnly = j['wifi_only'] != false;
    video = j['video'] == true;
    since = (j['since'] as num?)?.toInt() ?? 0;
    count = (j['count'] as num?)?.toInt() ?? 0;
    folder = '${j['folder'] ?? folder}';
  }
}

class DriveUploads extends ChangeNotifier {
  DriveUploads._(this.api, this.key);
  static final _all = <String, DriveUploads>{};
  static const _fg = MethodChannel('flygo/drive_upload');

  /// Hàng đợi của một tài khoản ([key] = máy chủ + người dùng). Tạo lần đầu thì nạp lại việc dở từ đĩa và chạy tiếp.
  static DriveUploads of(DriveApi api, String key) => _all.putIfAbsent(key, () => DriveUploads._(api, key).._init());

  DriveApi api;
  final String key;
  final jobs = <UploadJob>[];
  final camera = CameraBackup();
  bool paused = false;
  /// Không chạy hàng đợi (ảnh chụp màn hình trong test).
  @visibleForTesting
  bool hold = false;
  bool _running = false, _loaded = false;
  Timer? _retry, _cameraTimer;
  int _chunk = 10 * 1024 * 1024;
  void Function(UploadJob)? onDone;

  Future<File> get _file async => File('${(await getApplicationSupportDirectory()).path}/drive/uploads_$key.json');
  Future<Directory> get _staging async => Directory('${(await getApplicationSupportDirectory()).path}/drive/staging');

  Future<void> _init() async {
    try {
      final f = await _file;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        jobs.addAll([for (final x in (j['jobs'] as List? ?? const [])) UploadJob.fromJson(x as Map)]);
        if (j['camera'] is Map) camera.load(j['camera'] as Map);
        paused = j['paused'] == true;
      }
    } catch (_) {}
    _loaded = true;
    _prune();
    notifyListeners();
    try {
      _chunk = (await api.me()).chunkSize;
    } catch (_) {}
    _pump();
    _startCamera();
  }

  Future<void> _save() async {
    try {
      final f = await _file;
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'jobs': [for (final j in jobs) j.toJson()], 'camera': camera.toJson(), 'paused': paused}));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Giữ việc đã xong trong 3 ngày (tối đa 200).
  void _prune() {
    final cut = DateTime.now().millisecondsSinceEpoch - 3 * 86400000;
    jobs.removeWhere((j) => (j.state == UploadState.done || j.state == UploadState.cancelled) && j.doneAt < cut);
    final done = jobs.where((j) => !j.active).toList();
    if (done.length > 200) jobs.removeWhere((j) => done.take(done.length - 200).contains(j));
  }

  List<UploadJob> get pending => jobs.where((j) => j.active || j.state == UploadState.paused || j.state == UploadState.failed).toList();
  List<UploadJob> get finished => jobs.where((j) => j.state == UploadState.done).toList().reversed.toList();
  int get activeCount => jobs.where((j) => j.active).length;
  double get overall {
    final a = jobs.where((j) => j.active).toList();
    final total = a.fold<int>(0, (s, j) => s + j.size), sent = a.fold<int>(0, (s, j) => s + j.sent);
    return total <= 0 ? 0 : sent / total;
  }

  /// Thêm tệp vào hàng đợi. [copy]: chép tệp vào thư mục riêng trước (tệp nguồn tạm thời, vd từ bảng chia sẻ).
  Future<void> add(List<(String path, String name)> files, String dir, {String origin = 'manual', bool copy = false}) async {
    for (final (path, name) in files) {
      final f = File(path);
      if (!await f.exists()) continue;
      var src = path;
      if (copy) {
        final st = await _staging;
        await st.create(recursive: true);
        src = '${st.path}/${DateTime.now().microsecondsSinceEpoch}_${name.replaceAll(RegExp(r'[/\\]'), '_')}';
        await f.copy(src);
      }
      final stat = await File(src).stat();
      jobs.add(UploadJob(
        id: '${DateTime.now().microsecondsSinceEpoch}${jobs.length}', src: src, name: name, dir: dir, size: stat.size,
        mtime: stat.modified.millisecondsSinceEpoch ~/ 1000, origin: origin, temp: copy,
      ));
    }
    await _save();
    notifyListeners();
    _pump();
  }

  void cancel(UploadJob j) {
    j.state = UploadState.cancelled;
    j.doneAt = DateTime.now().millisecondsSinceEpoch;
    final s = j.session;
    if (s != null) api.uploadAbort(s).catchError((_) {});
    _cleanup(j);
    _save();
    notifyListeners();
  }

  void retry(UploadJob j) {
    j.state = UploadState.queued;
    j.error = null;
    j.retries = 0;
    _save();
    notifyListeners();
    _pump();
  }

  void setPaused(bool v) {
    paused = v;
    _save();
    notifyListeners();
    if (!v) _pump();
  }

  void clearFinished() {
    jobs.removeWhere((j) => j.state == UploadState.done || j.state == UploadState.cancelled);
    _save();
    notifyListeners();
  }

  Future<void> _cleanup(UploadJob j) async {
    if (j.temp) await File(j.src).delete().catchError((_) => File(j.src));
  }

  Future<void> _fgStart() async {
    if (!Platform.isAndroid) return;
    try {
      await _fg.invokeMethod('start', {'title': tr('Đang tải lên Drive'), 'text': tr('{0} tệp', ['$activeCount'])});
    } catch (_) {}
  }

  Future<void> _fgUpdate(UploadJob j) async {
    if (!Platform.isAndroid) return;
    try {
      await _fg.invokeMethod('update', {'title': tr('Đang tải lên {0} tệp', ['$activeCount']), 'text': j.name, 'progress': (overall * 100).round()});
    } catch (_) {}
  }

  Future<void> _fgStop() async {
    if (!Platform.isAndroid) return;
    try {
      await _fg.invokeMethod('stop');
    } catch (_) {}
  }

  DateTime _lastNotify = DateTime(0);
  void _tick(UploadJob j) {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(milliseconds: 250)) return;
    _lastNotify = now;
    notifyListeners();
    _fgUpdate(j);
  }

  Future<void> _pump() async {
    if (_running || paused || hold || !_loaded) return;
    _running = true;
    var fgOn = false;
    try {
      while (!paused) {
        final j = jobs.where((x) => x.state == UploadState.queued).firstOrNull;
        if (j == null) break;
        if (!fgOn) {
          fgOn = true;
          await _fgStart();
        }
        try {
          await _run(j);
        } on _Stop {
          break;
        }
      }
    } finally {
      _running = false;
      if (fgOn) await _fgStop();
      notifyListeners();
    }
  }

  /// Mỗi request tải lên tối đa 2 MB: đường mạng chập chờn (mất gói tới Cloudflare) làm request 10 MB hay bị cắt giữa
  /// chừng; khúc nhỏ hỏng thì chỉ gửi lại khúc đó.
  static const maxRequest = 2 * 1024 * 1024;

  /// Tiến độ một request: phần đang gửi chỉ tính 90% (byte vào bộ đệm chưa chắc tới máy chủ), đủ khi máy chủ trả lời.
  static int inflight(int base, int s) => base + (s * 9) ~/ 10;

  Future<void> _run(UploadJob j) async {
    j.state = UploadState.running;
    j.finishing = false;
    j.error = null;
    notifyListeners();
    final f = File(j.src);
    try {
      if (!await f.exists()) throw DriveException(410, tr('Không còn tệp trên máy'));
      final path = joinPath(j.dir, j.name);
      final chunk = _chunk < maxRequest ? _chunk : maxRequest;
      if (j.size <= chunk && j.session == null) {
        j.sent = 0;
        j.result = await api.putSmall(path, f, mtime: j.mtime, onSent: (s) {
          j.sent = inflight(0, s);
          j.finishing = s >= j.size;
          _tick(j);
        });
      } else {
        Map<int, int>? have;
        if (j.session != null) have = await api.uploadParts(j.session!);
        if (have == null) {
          final s = await api.uploadStart(path, j.size);
          j.session = s.id;
          j.target = s.path;
          if (s.chunkSize > 0) _chunk = s.chunkSize;
          have = {};
          await _save();
        }
        // Phiên dở từ bản cũ (khúc 10 MB): giữ đúng cỡ khúc cũ để đánh số khúc khớp.
        final size = have[1] != null && have[1]! > chunk && have[1]! < j.size ? have[1]! : chunk;
        final plan = chunkPlan(j.size, size, have);
        var base = have.values.fold<int>(0, (a, b) => a + b);
        j.sent = base;
        for (final (n, off, len) in plan) {
          if (paused || j.state == UploadState.cancelled) return;
          await api.uploadChunk(j.session!, n, j.target!, j.size, f, off, len, onSent: (s) {
            j.sent = inflight(base, s);
            _tick(j);
          });
          base += len;
          j.sent = base;
          _tick(j);
          await _save();
        }
        j.finishing = true;
        notifyListeners();
        j.result = await api.uploadDone(j.session!, j.target!, j.size, mtime: j.mtime);
      }
      if (j.state == UploadState.cancelled) return;
      j.state = UploadState.done;
      j.finishing = false;
      j.sent = j.size;
      j.doneAt = DateTime.now().millisecondsSinceEpoch;
      j.retries = 0;
      await _cleanup(j);
      onDone?.call(j);
    } catch (e) {
      j.finishing = false;
      if (j.state == UploadState.cancelled) return;
      if (paused) {
        j.state = UploadState.queued;
      } else if (DriveApi.isTransient(e)) {
        // Mất mạng / máy chủ bận: chờ rồi tự thử lại (5 s, 15 s, 45 s… tối đa 5 phút).
        j.state = UploadState.waiting;
        j.error = tr('Mất kết nối, sẽ tự thử lại');
        final wait = Duration(seconds: (5 * (1 << (j.retries.clamp(0, 6)))).clamp(5, 300));
        j.retries++;
        _retry?.cancel();
        _retry = Timer(wait, () {
          for (final x in jobs) {
            if (x.state == UploadState.waiting) x.state = UploadState.queued;
          }
          _pump();
        });
        // Các việc sau cũng chờ mạng.
        await _save();
        notifyListeners();
        throw _Stop();
      } else {
        j.state = UploadState.failed;
        j.error = '$e';
        if (e is DriveException && e.status == 404 && j.session != null) j.session = null;
      }
    } finally {
      await _save();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- tự tải ảnh
  void _startCamera() {
    _cameraTimer?.cancel();
    if (!(Platform.isAndroid || Platform.isIOS) || !camera.enabled) return;
    scanCamera();
    _cameraTimer = Timer.periodic(const Duration(minutes: 15), (_) => scanCamera());
  }

  Future<void> setCamera({bool? enabled, bool? wifiOnly, bool? video}) async {
    if (enabled == true && !camera.enabled) {
      final p = await PhotoManager.requestPermissionExtend();
      if (!p.hasAccess) throw DriveException(403, tr('Chưa có quyền xem ảnh trên máy'));
      // Chỉ tải ảnh chụp từ lúc bật trở đi (không đẩy cả thư viện cũ lên).
      camera.since = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    if (enabled != null) camera.enabled = enabled;
    if (wifiOnly != null) camera.wifiOnly = wifiOnly;
    if (video != null) camera.video = video;
    await _save();
    notifyListeners();
    _startCamera();
  }

  bool _scanning = false;
  Future<void> scanCamera() async {
    if (_scanning || !camera.enabled) return;
    _scanning = true;
    try {
      if (camera.wifiOnly && (await NetworkInfo().getWifiIP().catchError((_) => null)) == null) return;
      final p = await PhotoManager.getPermissionState(requestOption: const PermissionRequestOption());
      if (!p.hasAccess) return;
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: camera.video ? RequestType.common : RequestType.image,
          filterOption: FilterOptionGroup(createTimeCond: DateTimeCond(min: DateTime.fromMillisecondsSinceEpoch(camera.since * 1000 + 1000), max: DateTime.now())));
      if (paths.isEmpty) return;
      final all = await paths.first.getAssetListRange(start: 0, end: 500);
      all.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
      final files = <(String, String)>[];
      var newest = camera.since;
      for (final a in all) {
        final f = await a.originFile;
        if (f == null) continue;
        files.add((f.path, (await a.titleAsync).isNotEmpty ? await a.titleAsync : f.uri.pathSegments.last));
        newest = a.createDateTime.millisecondsSinceEpoch ~/ 1000;
      }
      if (files.isEmpty) return;
      await add(files, camera.folder, origin: 'camera', copy: Platform.isIOS);
      camera.since = newest;
      camera.count += files.length;
      await _save();
      notifyListeners();
    } catch (_) {
    } finally {
      _scanning = false;
    }
  }

}

/// Mất mạng: dừng vòng chạy, chờ hẹn giờ thử lại.
class _Stop implements Exception {}
