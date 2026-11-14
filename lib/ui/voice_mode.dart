// Trò chuyện bằng giọng nói với trợ lý (chat với trợ lý → nút sóng âm / menu "+"): nói → tự dừng khi im lặng →
// nhận diện giọng (kSttUrl, lib/api/stt.dart) → gửi như tin nhắn (props.flygo_voice) → chờ trợ lý trả lời xong →
// đọc to câu trả lời (giọng tiếng Việt của trạm: POST /meet/<kênh>/tts, play=false) → nghe tiếp. Bản đầu là luân phiên
// nói / nghe (không song công).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../api/stt.dart';
import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'agent_view.dart';
import 'theme.dart';

enum VoicePhase { listening, transcribing, waiting, speaking, paused }

const _accent = Color(0xFFD97757);

/// Bỏ ký hiệu markdown / link trước khi đọc.
String speakableText(String md) => md
    .replaceAll(RegExp(r'```[\s\S]*?```'), ' (đoạn mã) ')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'https?://\S+'), ' ')
    .replaceAll(RegExp(r'[*_`#>|]'), '')
    .replaceAll(RegExp(r'\n{2,}'), '\n')
    .trim();

class VoiceModePage extends StatefulWidget {
  final String channelId;
  const VoiceModePage({super.key, required this.channelId});

  /// Chỉ cho ảnh xem trước: không ghi âm, giữ nguyên trạng thái.
  static VoicePhase? debugPhase;
  static String? debugHeard;

  @override
  State<VoiceModePage> createState() => _VoiceModePageState();
}

class _VoiceModePageState extends State<VoiceModePage> with SingleTickerProviderStateMixin {
  // Tạo khi cần (ảnh xem trước / kiểm thử không có plugin ghi âm, phát âm thanh).
  AudioRecorder? _recI;
  AudioPlayer? _playerI;
  AudioRecorder get _rec => _recI ??= AudioRecorder();
  AudioPlayer get _player => _playerI ??= (AudioPlayer()
    ..onPlayerComplete.listen((_) {
      if (mounted && _phase == VoicePhase.speaking) _listen();
    }));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  StreamSubscription<Amplitude>? _amp;
  VoicePhase _phase = VoiceModePage.debugPhase ?? VoicePhase.listening;
  bool _speak = true;
  bool _captions = true;
  double _level = 0; // 0..1 theo âm lượng giọng
  String _heard = VoiceModePage.debugHeard ?? '';
  String _reply = '';
  String? _err;
  String? _path;
  DateTime? _lastVoice;
  bool _spoke = false;
  int _sentAt = 0;
  AppState? _app;

  @override
  void initState() {
    super.initState();
    if (VoiceModePage.debugPhase == null) _listen();
  }

  @override
  void dispose() {
    _amp?.cancel();
    _recI?.dispose();
    _playerI?.dispose();
    _pulse.dispose();
    _app?.removeListener(_onApp);
    super.dispose();
  }

  Future<void> _listen() async {
    if (!mounted) return;
    setState(() { _phase = VoicePhase.listening; _err = null; _spoke = false; _lastVoice = null; });
    if (!await _rec.hasPermission()) {
      setState(() { _phase = VoicePhase.paused; _err = tr('Chưa có quyền dùng micro.'); });
      return;
    }
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}${Platform.pathSeparator}flygo-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: _path!);
    await _amp?.cancel();
    final started = DateTime.now();
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      final db = a.current.isFinite ? a.current : -60.0;
      final lv = ((db + 50) / 40).clamp(0.0, 1.0);
      if (mounted) setState(() => _level = lv);
      final now = DateTime.now();
      if (db > -32) {
        _spoke = true;
        _lastVoice = now;
      }
      // Đã nói rồi im lặng 1,6 giây → gửi; chưa nói gì sau 30 giây → tạm dừng.
      if (_spoke && _lastVoice != null && now.difference(_lastVoice!) > const Duration(milliseconds: 1600)) _finish();
      if (!_spoke && now.difference(started) > const Duration(seconds: 30)) _pause();
    });
  }

  Future<void> _pause() async {
    await _amp?.cancel();
    _amp = null;
    if (await _rec.isRecording()) await _rec.stop();
    await _playerI?.stop();
    if (mounted) setState(() => _phase = VoicePhase.paused);
  }

  Future<void> _finish() async {
    if (_phase != VoicePhase.listening) return;
    await _amp?.cancel();
    _amp = null;
    final path = await _rec.stop() ?? _path;
    if (!mounted || path == null) return;
    setState(() { _phase = VoicePhase.transcribing; _level = 0; });
    final app = context.read<AppState>();
    try {
      final text = await transcribeAudio(app.api, path);
      if (!mounted) return;
      if (text.isEmpty) {
        await _listen();
        return;
      }
      setState(() { _heard = text; _phase = VoicePhase.waiting; _reply = ''; });
      _sentAt = DateTime.now().millisecondsSinceEpoch - 2000;
      _app = app..addListener(_onApp);
      await app.send(widget.channelId, text, props: {'flygo_voice': true});
    } catch (e) {
      if (mounted) setState(() { _err = tr('Không nhận diện được giọng nói.'); _phase = VoicePhase.paused; });
    }
  }

  /// Chờ câu trả lời của trợ lý: tin của bot mới hơn lúc gửi, đã viết xong.
  void _onApp() {
    if (_phase != VoicePhase.waiting) return;
    final app = context.read<AppState>();
    MmPost? done;
    for (final p in app.postsOf(widget.channelId)) {
      if (p.createAt < _sentAt) break;
      if (app.users[p.userId]?.isBot != true || p.rootId.isNotEmpty) continue;
      final run = agentRunOf(p);
      final streaming = agentMessageOf(p)?['streaming'] == true || (run != null && agentRunActive(run));
      final text = agentDisplayText(p).trim();
      if (streaming) {
        if (text.isNotEmpty && mounted) setState(() => _reply = text);
        return;
      }
      if (text.isNotEmpty) { done = p; break; }
    }
    if (done == null) return;
    app.removeListener(_onApp);
    final text = agentDisplayText(done).trim();
    setState(() => _reply = text);
    _say(app, text);
  }

  Future<void> _say(AppState app, String text) async {
    if (!_speak) return _listen();
    setState(() => _phase = VoicePhase.speaking);
    try {
      var plain = speakableText(text);
      if (plain.length > 2500) plain = '${plain.substring(0, 2500)}…';
      final r = await http
          .post(Uri.parse('${pushUrlFor(kServerUrl)}/meet/${widget.channelId}/tts'),
              headers: {'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
              body: jsonEncode({'text': plain, 'play': false}))
          .timeout(const Duration(seconds: 60));
      final url = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['url'] as String?;
      if (r.statusCode != 200 || url == null) throw Exception('TTS ${r.statusCode}');
      await _player.play(UrlSource(url));
    } catch (_) {
      if (mounted) setState(() => _err = tr('Không đọc được câu trả lời, tiếp tục nghe.'));
      await _listen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final label = switch (_phase) {
      VoicePhase.listening => _spoke ? tr('Đang nghe…') : tr('Mời bạn nói'),
      VoicePhase.transcribing => tr('Đang nhận diện…'),
      VoicePhase.waiting => tr('Trợ lý đang trả lời…'),
      VoicePhase.speaking => tr('Đang đọc câu trả lời'),
      VoicePhase.paused => tr('Đã tạm dừng · chạm để nói'),
    };
    Widget round(IconData i, String t, Color bg, VoidCallback onTap) => Column(children: [
          Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 62, height: 62, child: Icon(i, color: Colors.white))),
          ),
          const SizedBox(height: 6),
          Text(t, style: TextStyle(fontSize: 12.5, color: pal.sub)),
        ]);
    return Scaffold(
      backgroundColor: const Color(0xFF151413),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white), onPressed: () => Navigator.maybePop(context)),
              Expanded(child: Text(tr('Trò chuyện bằng giọng nói'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))),
              IconButton(
                tooltip: tr('Phụ đề'),
                icon: Icon(_captions ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined, color: Colors.white),
                onPressed: () => setState(() => _captions = !_captions),
              ),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: () => _phase == VoicePhase.listening ? _finish() : (_phase == VoicePhase.paused || _phase == VoicePhase.speaking) ? (_playerI?.stop(), _listen()) : null,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) {
                  final breathe = _phase == VoicePhase.listening ? _level : (_phase == VoicePhase.paused ? 0.0 : .35 + .25 * sin(_pulse.value * 2 * pi));
                  final size = 150 + 70 * breathe;
                  return SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [_phase == VoicePhase.paused ? Colors.white24 : _accent, _accent.withValues(alpha: .3), Colors.transparent],
                            stops: const [.45, .75, 1],
                          ),
                        ),
                        child: _phase == VoicePhase.transcribing || _phase == VoicePhase.waiting
                            ? const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(label, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
            if (_captions) ...[
              const SizedBox(height: 12),
              if (_heard.isNotEmpty)
                Text('“$_heard”', textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.45, color: Colors.white70)),
              if (_reply.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(speakableText(_reply), textAlign: TextAlign.center, maxLines: 5, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, height: 1.45, color: Color(0xFFF0C8B8))),
              ],
            ],
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: Colors.redAccent))),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              round(_phase == VoicePhase.paused ? Icons.mic_rounded : Icons.mic_off_rounded, _phase == VoicePhase.paused ? tr('Nói tiếp') : tr('Tạm dừng'),
                  Colors.white.withValues(alpha: .14), () => _phase == VoicePhase.paused ? _listen() : _pause()),
              round(_speak ? Icons.volume_up_rounded : Icons.volume_off_rounded, tr('Đọc trả lời'), _speak ? _accent.withValues(alpha: .45) : Colors.white.withValues(alpha: .14),
                  () => setState(() => _speak = !_speak)),
              round(Icons.close_rounded, tr('Kết thúc'), const Color(0xFFD32F2F), () => Navigator.maybePop(context)),
            ]),
          ]),
        ),
      ),
    );
  }
}
