import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'agent_config.dart' show engineName;

/// Bot trợ lý AI của mình (bot của máy chủ chat có mốc "[flygo-agent engine=…]" trong mô tả).
class AgentBot {
  final String id; // user_id của bot
  final String username;
  final String displayName;
  final String engine; // codex | claude | agy (Antigravity CLI)
  /// Người khác được gọi bot (ngoài chủ bot), lưu trong mốc mô tả: allow=id1,id2.
  final List<String> allow;
  /// Máy mà trợ lý gắn cố định (mốc host=…); null = chưa gắn máy nào.
  final String? host;
  /// Vai trò / chuyên môn (phần đầu mô tả bot, trước " · chạy …"), vd. "Kế toán – xử lý hoá đơn VAT".
  final String role;
  /// Chủ trợ lý tạm tắt (mốc paused=1): runner không nhận việc mới.
  final bool paused;
  /// Toàn bộ mô tả bot (để đọc danh sách mô hình / mức suy nghĩ).
  final String description;
  AgentBot(this.id, this.username, this.displayName, this.engine,
      [this.allow = const [], this.host, this.role = '', this.paused = false, this.description = '']);
}

/// Trạng thái runner chạy trong app cho một bot.
class RunnerState {
  String phase = 'stopped'; // stopped | starting | running | error
  String? errorCode;
  String? errorMessage;
  String? errorEngine;
  int activeRuns = 0;
  Process? process;
}

/// Điều khiển runner flygo-agent (máy tính): kiểm tra máy, bot của tôi, bật/tắt runner, dịch vụ nền.
/// Mỗi bot gắn cố định một engine; mỗi bot một tiến trình runner.
class AgentService extends ChangeNotifier {
  AgentService._();
  static final instance = AgentService._();

  /// Mốc trong mô tả bot: "[flygo-agent engine=codex allow=id1,id2]".
  static final _marker = RegExp(r'\[flygo-agent([^\]]*)\]');
  static String? _attr(String attrs, String key) => RegExp('$key=([\\w,]+)').firstMatch(attrs)?.group(1);
  /// Runner tải từ máy chủ đang dùng.
  static String get downloadBase => staticBase('flygo-agent');

  final Map<String, RunnerState> runners = {};
  Map<String, dynamic>? doctor;

  static String get _home => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  static String get _sep => Platform.pathSeparator;
  static String get binPath =>
      '$_home$_sep.local${_sep}share${_sep}flygo-agent${_sep}flygo-agent${Platform.isWindows ? '.exe' : ''}';
  static String configPath(String botUsername) => '$_home$_sep.config${_sep}flygo-agent${_sep}config-$botUsername.json';

  static Future<String> _platformName() async {
    if (Platform.isWindows) return 'windows-x64.exe';
    final arch = (await Process.run('uname', ['-m'])).stdout.toString().trim();
    final a = arch == 'arm64' || arch == 'aarch64' ? 'arm64' : 'x64';
    return '${Platform.isMacOS ? 'darwin' : 'linux'}-$a';
  }

  /// File chạy runner đóng gói sẵn trong app (cạnh file chạy của app; macOS: Contents/Resources) và file
  /// ghi phiên bản đi kèm "flygo-agent.version". null nếu bản app này không đóng gói runner.
  static String? get bundledPath {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = 'flygo-agent${Platform.isWindows ? '.exe' : ''}';
    return [
      '$exeDir$_sep$name',
      if (Platform.isMacOS) '$exeDir$_sep..${_sep}Resources$_sep$name',
      if (Platform.isLinux) '$exeDir${_sep}lib$_sep$name',
    ].where((p) => File(p).existsSync()).firstOrNull;
  }

  static String? _readVersion(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.readAsStringSync().trim() : null;
    } catch (_) {
      return null;
    }
  }

  static String _bundledVersionOf(String bin) =>
      _readVersion('${File(bin).parent.path}${_sep}flygo-agent.version') ?? '';

  /// So sánh phiên bản "a.b.c": > 0 nếu [a] mới hơn [b].
  static int _cmpVer(String a, String b) {
    List<int> p(String v) => v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// Đảm bảo có file chạy runner ở chỗ cố định (dịch vụ nền chạy từ đây). Ưu tiên bản đóng gói trong app:
  /// chưa có hoặc bản đóng gói mới hơn bản đã cài thì chép sang (file tạm + đổi tên — chép đè lên file đang chạy
  /// trên macOS sẽ làm tiến trình bị giết). App không đóng gói runner thì mới tải về.
  /// Trả về đường dẫn; [onUpdated] được gọi nếu vừa thay bằng bản mới hơn.
  Future<String> ensureBinary({void Function(String)? onStatus, void Function()? onUpdated}) async {
    final installed = File(binPath);
    final verFile = '$binPath.version';
    final bundled = bundledPath;
    final bVer = bundled == null ? '' : _bundledVersionOf(bundled);
    final iVer = _readVersion(verFile) ?? '';
    final needCopy = bundled != null && (!installed.existsSync() || (bVer.isNotEmpty && _cmpVer(bVer, iVer) > 0));
    if (installed.existsSync() && !needCopy) return binPath;
    await installed.parent.create(recursive: true);
    final tmp = File('$binPath.tmp');
    if (bundled != null) {
      await File(bundled).copy(tmp.path);
    } else {
      onStatus?.call('download');
      final r = await http.get(Uri.parse('$downloadBase/flygo-agent-${await _platformName()}'));
      if (r.statusCode != 200 || r.bodyBytes.length < 1000000) {
        throw Exception('Không tải được trình chạy trợ lý (HTTP ${r.statusCode}).');
      }
      await tmp.writeAsBytes(r.bodyBytes, flush: true);
    }
    if (!Platform.isWindows) await Process.run('chmod', ['755', tmp.path]);
    final existed = installed.existsSync();
    if (Platform.isWindows && existed) {
      // Windows không đổi tên đè lên file đang chạy: dời file cũ sang bên cạnh trước.
      final old = File('$binPath.old');
      try {
        if (old.existsSync()) old.deleteSync();
        installed.renameSync(old.path);
      } catch (_) {}
    }
    await tmp.rename(binPath);
    if (bVer.isNotEmpty) await File(verFile).writeAsString(bVer);
    if (existed) onUpdated?.call();
    return binPath;
  }

  /// Mở app (máy tính): runner đóng gói trong app mới hơn bản đang cài → thay, rồi khởi động lại các trợ lý
  /// đang chạy nền trên máy này để dùng bản mới. Không cần cài gì bên ngoài.
  Future<void> syncBundledRunner() async {
    if (!isDesktop || bundledPath == null) return;
    var updated = false;
    try {
      await ensureBinary(onUpdated: () => updated = true);
    } catch (e) {
      debugPrint('[agent] sync runner: $e');
      return;
    }
    if (updated) {
      // Runner chung: cài lại dịch vụ = khởi động lại với bản mới (mọi bot của máy, một lần).
      if (await _machineInstalled()) await Process.run(binPath, ['install-machine-service', '--config', machineConfigPath]);
      // Dịch vụ một-bot kiểu cũ còn sót (vd. bot chưa gộp được): khởi động lại như trước.
      final dir = Directory('$_home$_sep.config${_sep}flygo-agent');
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>().where((f) => RegExp(r'config-.+\.json$').hasMatch(f.path))) {
          try {
            final st = await Process.run(binPath, ['service-status', '--config', f.path]);
            final j = jsonDecode(st.stdout.toString().trim().split('\n').last);
            if (j is Map && j['installed'] == true) await Process.run(binPath, ['install-service', '--config', f.path]);
          } catch (_) {}
        }
      }
    }
    try {
      await _migrateLegacy(binPath);
    } catch (e) {
      debugPrint('[agent] gộp runner: $e');
    }
  }

  // ---------------------------------------------------------------- kiểm tra máy
  Future<Map<String, dynamic>?> loadDoctor() async {
    try {
      final bin = await ensureBinary();
      final r = await Process.run(bin, ['doctor', '--json']).timeout(const Duration(seconds: 40));
      doctor = (jsonDecode(r.stdout.toString().trim().split('\n').last) as Map).cast<String, dynamic>();
    } catch (e) {
      debugPrint('[agent] doctor: $e');
      doctor = null;
    }
    notifyListeners();
    return doctor;
  }

  /// Đăng nhập Codex / Claude trên máy này (mở trình duyệt). Antigravity (agy) chỉ đăng nhập được trong giao diện
  /// dòng lệnh của nó: runner mở cửa sổ Terminal chạy `agy` (chọn Google OAuth, dán mã từ trình duyệt).
  Future<void> login(String engine) async {
    if (engine == 'agy') {
      final r = await Process.run(await ensureBinary(), ['login-engine', 'agy']);
      if (r.exitCode != 0) throw Exception(_lastJsonError(r) ?? tr('Không mở được cửa sổ đăng nhập.'));
      return;
    }
    final args = engine == 'claude' ? ['auth', 'login'] : ['login'];
    final exe = (doctor?[engine] as Map?)?['path'] as String? ?? engine;
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  }

  /// Cài bộ máy AI lên máy này bằng bộ cài chính thức (hiện chỉ Antigravity CLI: `flygo-agent install-engine agy`),
  /// rồi kiểm tra lại máy.
  Future<void> installEngine(String engine) async {
    final r = await Process.run(await ensureBinary(), ['install-engine', engine]).timeout(const Duration(minutes: 11));
    await loadDoctor();
    if (r.exitCode != 0) throw Exception(_lastJsonError(r) ?? tr('Cài đặt không thành công.'));
  }

  static String? _lastJsonError(ProcessResult r) {
    try {
      final j = jsonDecode(r.stdout.toString().trim().split('\n').last);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    final e = r.stderr.toString().trim();
    return e.isEmpty ? null : e.split('\n').last;
  }

  // ---------------------------------------------------------------- bot của tôi
  Future<List<AgentBot>> myBots(AppState app) async {
    final r = await app.api.get('/bots', {'per_page': '200'}) as List;
    final out = <AgentBot>[];
    for (final e in r) {
      final m = (e as Map).cast<String, dynamic>();
      if (m['owner_id'] != app.me?.id || (m['delete_at'] as num? ?? 0) != 0) continue;
      final mk = _marker.firstMatch(m['description'] as String? ?? '');
      if (mk == null) continue;
      final attrs = mk.group(1) ?? '';
      out.add(AgentBot(m['user_id'] as String, m['username'] as String, m['display_name'] as String? ?? '',
          _attr(attrs, 'engine') ?? 'codex', (_attr(attrs, 'allow') ?? '').split(',').where((s) => s.isNotEmpty).toList(),
          _attr(attrs, 'host'), _roleOf(m['description'] as String? ?? ''), _attr(attrs, 'paused') == '1',
          m['description'] as String? ?? ''));
    }
    app.setMyAgents(out.map((b) => b.id));
    return out;
  }

  static String _roleOf(String desc) {
    final i = desc.indexOf(' · chạy ');
    if (i <= 0) return '';
    final r = desc.substring(0, i).trim();
    return r == 'Trợ lý AI' ? '' : r;
  }

  /// Kỹ năng của trợ lý trên máy này (CLI `flygo-agent skills --bot <id> --json`); null nếu không đọc được.
  Future<Map<String, dynamic>?> skillsOf(AgentBot bot) async {
    if (!isDesktop) return null;
    try {
      final bin = await ensureBinary();
      final cfg = File(configPath(bot.username));
      final r = await Process.run(bin, ['skills', '--bot', bot.id, if (cfg.existsSync()) ...['--config', cfg.path], '--json'])
          .timeout(const Duration(seconds: 20));
      return (jsonDecode(r.stdout.toString().trim().split('\n').last) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Đặt vai trò của trợ lý: phần đầu mô tả bot (trước " · chạy …") + mốc `role=<slug>`.
  Future<void> setRole(AppState app, AgentBot bot, String role) async {
    final b = (await app.api.get('/bots/${bot.id}') as Map).cast<String, dynamic>();
    final desc = b['description'] as String? ?? '';
    final r = role.trim();
    final i = desc.indexOf(' · chạy ');
    final rest = i > 0 ? desc.substring(i) : ' · ${desc.replaceAll(_marker, '').trim()}';
    final next = '${r.isEmpty ? 'Trợ lý AI' : r}$rest'.replaceAll(_marker, '').trim();
    final m = _marker.firstMatch(desc);
    await app.api.put('/bots/${bot.id}', {'description': '$next ${m?.group(0) ?? '[flygo-agent engine=${bot.engine}]'}'});
    final slug = r.isEmpty
        ? ''
        : r.split(RegExp(r'[—:,–-]')).first.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    await _setMarkerAttrs(app, bot, {'role': slug.length > 24 ? slug.substring(0, 24) : slug});
  }

  /// Tạo trợ lý: một máy có thể có nhiều trợ lý cùng loại AI, mỗi trợ lý một vai trò / kỹ năng riêng
  /// (vd. @ketoan xử lý hoá đơn, @android-dev phát hành APK). [role] ghi vào mốc `role=` và mô tả bot.
  Future<AgentBot> createBot(AppState app, String engine, {String? username, String? displayName, String? role}) async {
    final me = app.me!;
    final label = engineName(engine);
    var un = (username?.trim().isNotEmpty == true ? username! : '${me.username}-$engine')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '-');
    if (un.length > 22) un = un.substring(0, 22);
    final name = displayName?.trim().isNotEmpty == true ? displayName!.trim() : '$label của ${me.displayName}';
    final r = role?.trim() ?? '';
    final slug = r.isEmpty
        ? ''
        : r.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ỹđ]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final desc = '${r.isEmpty ? 'Trợ lý AI' : r} · chạy $label trên máy của ${me.displayName} '
        '[flygo-agent engine=$engine${slug.isEmpty ? '' : ' role=$slug'}]';
    final res = (await app.api.post('/bots', {'username': un, 'display_name': name, 'description': desc}) as Map)
        .cast<String, dynamic>();
    app.noteMyBot(res['user_id'] as String);
    return AgentBot(res['user_id'] as String, un, name, engine);
  }

  /// Sửa một vài thuộc tính trong mốc [flygo-agent …] của mô tả bot, giữ nguyên các thuộc tính khác
  /// (models, efforts, default…). Giá trị null/rỗng = bỏ thuộc tính.
  Future<void> _setMarkerAttrs(AppState app, AgentBot bot, Map<String, String?> attrs) async {
    final b = (await app.api.get('/bots/${bot.id}') as Map).cast<String, dynamic>();
    final desc = b['description'] as String? ?? '';
    final m = _marker.firstMatch(desc);
    final cur = <String, String>{'engine': bot.engine};
    for (final x in RegExp(r'([a-z_]+)=([^\s\]]+)').allMatches(m?.group(1) ?? '')) {
      cur[x.group(1)!] = x.group(2)!;
    }
    attrs.forEach((k, v) => v == null || v.isEmpty ? cur.remove(k) : cur[k] = v);
    final marker = '[flygo-agent ${cur.entries.map((e) => '${e.key}=${e.value}').join(' ')}]';
    final next = m != null ? desc.replaceFirst(_marker, marker) : '$desc $marker'.trim();
    await app.api.put('/bots/${bot.id}', {'description': next});
  }

  /// Đặt danh sách người được gọi bot (ngoài chủ bot): ghi vào mốc trong mô tả bot.
  Future<void> setAllowed(AppState app, AgentBot bot, List<String> userIds) =>
      _setMarkerAttrs(app, bot, {'allow': userIds.join(',')});

  /// Chuẩn hoá tên máy giống runner (normHost): bỏ khoảng trắng hai đầu, chữ thường, bỏ đuôi ".local",
  /// khoảng trắng / "]" thành "-".
  static String normHost(String h) =>
      h.trim().toLowerCase().replaceFirst(RegExp(r'\.local$'), '').replaceAll(RegExp(r'[\s\]]'), '-');

  /// Tên máy này dùng để gắn trợ lý.
  static String get thisHost => normHost(Platform.localHostname);

  /// Trợ lý gắn với máy này?
  static bool isHere(AgentBot b) => b.host != null && normHost(b.host!) == thisHost;

  /// Xoá trợ lý: gỡ chạy nền ở máy này (nếu có) rồi tắt bot trên máy chủ (máy chủ chat không xoá hẳn bot).
  Future<void> deleteBot(AppState app, AgentBot bot) async {
    if (isDesktop && await serviceInstalled(bot)) {
      try {
        await uninstallService(bot);
      } catch (_) {}
    }
    await app.api.post('/bots/${bot.id}/disable', {});
  }

  /// Bật / tạm tắt trợ lý (mốc paused=1 trong mô tả bot; runner ở máy nào cũng đọc được).
  Future<void> setPaused(AppState app, AgentBot bot, bool paused) => _setMarkerAttrs(app, bot, {'paused': paused ? '1' : null});

  /// Gắn cứng trợ lý với máy này (hoặc bỏ gắn khi [bind] = false).
  Future<void> bindHost(AppState app, AgentBot bot, bool bind) => _setMarkerAttrs(app, bot, {'host': bind ? thisHost : null});

  // Token của bot trên máy này (mỗi máy một token), lưu trong thư mục dữ liệu của app.
  Future<File> _tokenFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${_sep}agent_tokens_$serverKey.json');
  }

  Future<String> botToken(AppState app, AgentBot bot) async {
    final f = await _tokenFile();
    final all = f.existsSync() ? (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>() : <String, dynamic>{};
    final saved = all[bot.id] as String?;
    if (saved != null) return saved;
    final host = Platform.localHostname;
    final t = (await app.api.post('/users/${bot.id}/tokens', {'description': 'flygo-agent $host'}) as Map)
        .cast<String, dynamic>();
    all[bot.id] = t['token'] as String;
    await f.writeAsString(jsonEncode(all), flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', f.path]);
    return t['token'] as String;
  }

  Map<String, dynamic> _config(AppState app, AgentBot bot, String token) =>
      {'serverUrl': kServerUrl, 'botToken': token, 'ownerUserIds': [app.me!.id], 'engine': bot.engine};

  // ---------------------------------------------------------------- chạy trong app
  RunnerState stateOf(String botId) => runners.putIfAbsent(botId, RunnerState.new);

  Future<void> start(AppState app, AgentBot bot, {bool takeover = false}) async {
    final st = stateOf(bot.id);
    if (st.process != null) return;
    st
      ..phase = 'starting'
      ..errorCode = null
      ..errorMessage = null;
    notifyListeners();
    try {
      final bin = await ensureBinary();
      final token = await botToken(app, bot);
      final p = await Process.start(bin, ['run', '--config-stdin', '--json', if (takeover) '--takeover']);
      st.process = p;
      p.stdin.write(jsonEncode(_config(app, bot, token)));
      await p.stdin.close();
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) => _onEvent(st, line));
      p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[agent ${bot.username}] $l'));
      p.exitCode.then((_) {
        st.process = null;
        if (st.phase != 'error') st.phase = 'stopped';
        st.activeRuns = 0;
        notifyListeners();
      });
    } catch (e) {
      st
        ..phase = 'error'
        ..errorCode = 'fatal'
        ..errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void _onEvent(RunnerState st, String line) {
    Map<String, dynamic> e;
    try {
      e = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (e['event'] ?? e['type']) {
      case 'ready' || 'connected' || 'took_over':
        st.phase = 'running';
      case 'run_started':
        st.activeRuns++;
      case 'run_finished':
        st.activeRuns = (st.activeRuns - 1).clamp(0, 999);
      case 'stopped':
        st.phase = 'stopped';
      case 'error':
        st
          ..phase = 'error'
          ..errorCode = e['code'] as String?
          ..errorMessage = e['message'] as String?
          ..errorEngine = e['engine'] as String?;
    }
    notifyListeners();
  }

  Future<void> stop(String botId) async {
    final p = runners[botId]?.process;
    if (p == null) return;
    Platform.isWindows ? p.kill() : p.kill(ProcessSignal.sigterm);
    await p.exitCode.timeout(const Duration(seconds: 8), onTimeout: () {
      p.kill(ProcessSignal.sigkill);
      return -1;
    });
  }

  /// Thoát app: dừng mọi runner đang chạy trong app (runner tự đưa bot về offline).
  Future<void> stopAll() => Future.wait([for (final id in runners.keys) stop(id)]);

  // ---------------------------------------------------------------- chạy nền khi đăng nhập máy
  /// Có runner đang chạy cho bot này trên máy (khoá `runner-<id bot>.lock` còn tiến trình sống)?
  /// Dùng id thay vì tên: đổi tên bot thì dịch vụ cũ (đặt theo tên cũ) vẫn được nhận ra, không cài trùng.
  static bool runningLocally(AgentBot bot) {
    try {
      final f = File('$_home$_sep.config${_sep}flygo-agent${_sep}runner-${bot.id}.lock');
      if (!f.existsSync()) return false;
      final pid = int.tryParse(f.readAsStringSync().trim());
      if (pid == null) return false;
      if (Platform.isWindows) {
        final r = Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH']);
        return r.stdout.toString().contains('$pid');
      }
      return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- runner chung (một runner mỗi máy)
  /// Cấu hình runner chung: mọi trợ lý chạy nền trên máy này nằm trong một file, một dịch vụ nền.
  static String get machineConfigPath => '$_home$_sep.config${_sep}flygo-agent${_sep}runner.json';

  Map<String, dynamic> _readMachine() {
    try {
      final f = File(machineConfigPath);
      if (f.existsSync()) return (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
    } catch (_) {}
    return {'version': 2, 'machine': {'name': thisHost}, 'owners': <String, dynamic>{}, 'defaults': <String, dynamic>{}, 'servers': <String, dynamic>{}, 'bots': <dynamic>[]};
  }

  Future<void> _writeMachine(Map<String, dynamic> m) async {
    final f = File(machineConfigPath);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp-app');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(m), flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
    await tmp.rename(f.path);
  }

  static String _norm(String s) => s.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  /// Mục của bot trong runner.json (theo id bot, rồi theo tên: đổi tên bot vẫn nhận ra).
  static Map<String, dynamic>? _entryOf(Map<String, dynamic> m, AgentBot bot) {
    final bots = (m['bots'] as List? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>());
    return bots.where((e) => e['botId'] == bot.id).firstOrNull ??
        bots.where((e) => e['key'] == bot.username && _norm(e['serverUrl'] as String? ?? '') == _norm(kServerUrl)).firstOrNull;
  }

  /// Như [_entryOf], thêm: mục do `migrate` gộp từ cấu hình cũ (key = tên dịch vụ cũ, chưa có botId): hỏi runner
  /// đang chạy key nào là bot này.
  Future<Map<String, dynamic>?> _entryFor(Map<String, dynamic> m, AgentBot bot) async {
    final e = _entryOf(m, bot);
    if (e != null) return e;
    final st = await _json(['ctl', 'status'], timeout: const Duration(seconds: 10));
    final key = ((st?['bots'] as List?) ?? const []).whereType<Map>().where((b) => b['id'] == bot.id).map((b) => b['key']).firstOrNull;
    if (key == null) return null;
    return (m['bots'] as List? ?? []).whereType<Map>().map((x) => x.cast<String, dynamic>()).where((x) => x['key'] == key).firstOrNull;
  }

  Future<Map<String, dynamic>?> _json(List<String> args, {Duration timeout = const Duration(seconds: 40)}) async {
    try {
      final r = await Process.run(await ensureBinary(), args).timeout(timeout);
      final j = jsonDecode(r.stdout.toString().trim().split('\n').last);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _machineInstalled() async => (await _json(['machine-service-status']))?['installed'] == true;

  /// Dịch vụ một-bot kiểu cũ của bot này còn cài không (máy chưa gộp).
  Future<bool> _legacyInstalled(AgentBot bot) async {
    final j = await _json(['service-status', '--config', configPath(bot.username)]);
    return j != null && (j['installed'] == true || j['running'] == true);
  }

  Future<bool> serviceInstalled(AgentBot bot) async {
    if (runningLocally(bot)) return true;
    final e = await _entryFor(_readMachine(), bot);
    if (e != null && e['enabled'] != false && await _machineInstalled()) return true;
    return _legacyInstalled(bot);
  }

  /// Cho trợ lý chạy nền trên máy này: thêm vào runner chung (runner.json) rồi để runner nạp nóng.
  /// Runner thuộc MỘT người: máy chủ này đã có chủ runner khác thì không chạy bot của người khác.
  Future<void> installService(AppState app, AgentBot bot) async {
    final bin = await ensureBinary();
    final me = app.me!.id;
    final m = _readMachine();
    final owners = (m['owners'] as Map? ?? {}).cast<String, dynamic>();
    final key = _norm(kServerUrl);
    final cur = owners.entries.where((e) => _norm(e.key) == key).map((e) => e.value as String?).firstOrNull;
    if (cur != null && cur != me) {
      throw Exception(tr('Runner trên máy này thuộc tài khoản khác trên máy chủ này. Mỗi người một runner: chỉ chia sẻ trợ lý, không chia sẻ runner.'));
    }
    owners[kServerUrl] = me;
    m['owners'] = owners;
    final bots = (m['bots'] as List? ?? []).cast<dynamic>();
    final entry = await _entryFor(m, bot);
    final next = <String, dynamic>{
      ...?entry,
      'key': entry?['key'] ?? _freeKey(bots, bot.username),
      'botId': bot.id,
      'serverUrl': kServerUrl,
      'botToken': await botToken(app, bot),
      'ownerUserIds': [me],
      'engine': bot.engine,
      'enabled': true,
    };
    if (entry != null) {
      bots[bots.indexWhere((e) => identical(e, entry) || (e is Map && e['key'] == entry['key']))] = next;
    } else {
      bots.add(next);
    }
    m['bots'] = bots;
    await _writeMachine(m);
    // Bot còn dịch vụ kiểu cũ: gỡ trước để runner chung không bị "đã có runner khác chạy bot này".
    if (await _legacyInstalled(bot)) await Process.run(bin, ['uninstall-service', '--config', configPath(bot.username)]);
    if (await _machineInstalled()) {
      await _json(['ctl', 'reload']); // runner tự theo dõi runner.json; gọi thêm cho chắc
    } else {
      final r = await Process.run(bin, ['install-machine-service', '--config', machineConfigPath]);
      if (r.exitCode != 0) throw Exception(r.stderr.toString().trim().split('\n').last);
    }
  }

  static String _freeKey(List<dynamic> bots, String want) {
    final used = bots.whereType<Map>().map((e) => e['key']).toSet();
    final base = want.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    var k = base;
    for (var i = 2; used.contains(k); i++) {
      k = '$base-$i';
    }
    return k;
  }

  /// Không chạy trợ lý này trên máy này nữa: bỏ khỏi runner chung (và gỡ dịch vụ kiểu cũ nếu còn).
  Future<void> uninstallService(AgentBot bot) async {
    final m = _readMachine();
    final e = await _entryFor(m, bot);
    if (e != null) {
      (m['bots'] as List).removeWhere((x) => x is Map && x['key'] == e['key']);
      await _writeMachine(m);
      await _json(['ctl', 'reload']);
    }
    if (await _legacyInstalled(bot)) {
      final r = await Process.run(await ensureBinary(), ['uninstall-service', '--config', configPath(bot.username)]);
      if (r.exitCode != 0) throw Exception(r.stderr.toString().trim().split('\n').last);
    }
  }

  /// Máy còn dịch vụ một-bot kiểu cũ: gộp vào runner chung (Sếp 2026-11-16: "gộp luôn").
  /// `migrate` sao lưu cấu hình cũ, chỉ gộp bot của chủ runner và tự trả về dịch vụ cũ cho bot nào không lên.
  Future<void> _migrateLegacy(String bin) async {
    final plan = await _json(['migrate', '--dry-run', '--json']);
    final bots = ((plan?['plan'] as Map?)?['bots'] as List?) ?? const [];
    if (bots.isEmpty) return;
    final r = await Process.run(bin, ['migrate', '--json']).timeout(const Duration(minutes: 4));
    debugPrint('[agent] gộp runner: ${r.stdout.toString().trim().split('\n').last}');
  }
}
