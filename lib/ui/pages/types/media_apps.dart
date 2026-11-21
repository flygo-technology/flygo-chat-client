import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../../meet/meet_ink.dart' show inkColor, inkColors, inkTools;
import '../../meet/meet_present.dart' show PresentControl, pickPresentPdf;
import '../app_kit.dart';
import '../page_thumb.dart' show PdfThumb;
import '../page_types.dart';
import '../pages_api.dart' show PagesApi, pageAssetUrl;

// App Tài liệu và Video (mockup "mỗi trang là một app", bảng 06 và 09): phần của người xem và điều khiển của chủ trang
// trong vỏ app chung. Hình trên sân khấu vẫn là phần xem cũ (MeetPresentView / trình phát video).

// ------------------------------------------------------------------ Tài liệu
// content: file {id, url, name, pages}, viewer_flip (người xem tự lật, mặc định bật), allow_download (cho tải về, mặc định tắt).

bool _presenting(PageCtx ctx) => ctx.call.roomPresent?['page_id'] == ctx.page.id;
bool _flipOk(PageCtx ctx) => ctx.page.content['viewer_flip'] != false;

/// Hình sân khấu trong vỏ app nhận chạm khi đang vẽ chú thích / chỉ laser trên tài liệu đang chiếu.
bool docStageInput(PageCtx ctx) {
  final pc = PresentControl.of(ctx.call);
  return _presenting(ctx) && (pc.ink || pc.laser);
}

/// Người xem: theo người trình bày hoặc tự lật, về trang đang trình bày, dải trang, tải về (khi chủ trang cho).
class DocPanel extends StatelessWidget {
  final PageCtx ctx;
  const DocPanel(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final pc = PresentControl.of(ctx.call);
    return ListenableBuilder(listenable: pc, builder: (context, _) => _body(context, pc));
  }

  Widget _body(BuildContext context, PresentControl pc) {
    final s = AppScope.of(context);
    final t = s.theme;
    final f = ctx.page.file;
    final pr = ctx.call.roomPresent;
    final total = pc.pages > 0 && _presenting(ctx) ? pc.pages : (f?['pages'] as num?)?.toInt() ?? 0;
    final download = ctx.page.content['allow_download'] == true && '${f?['url'] ?? ''}'.isNotEmpty
        ? AppButton(tr('Tải về'), key: const ValueKey('doc-download'), icon: Icons.download_rounded, onPressed: () async {
            await launchUrl(Uri.parse(pageAssetUrl('${f!['url']}')), mode: LaunchMode.externalApplication);
          })
        : null;
    if (f == null) return AppCard(child: AppEmpty(icon: Icons.slideshow_rounded, title: tr('Chưa chọn tài liệu'), sub: ctx.control ? tr('Chọn tài liệu ở phần điều khiển bên dưới') : null));
    if (!_presenting(ctx) || pr == null) {
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.description_outlined, color: t.sub),
            const SizedBox(width: 10),
            Expanded(child: Text('${f['name'] ?? ctx.page.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(total > 0 ? tr('{0} trang · chưa trình chiếu', [total]) : tr('Chưa trình chiếu'), style: TextStyle(color: t.sub, fontSize: 13)),
          if (download != null) ...[const SizedBox(height: 10), download],
        ]),
      );
    }
    final presenter = '${pr['by'] ?? ''}' == ctx.call.myId();
    final byName = '${pr['by_name'] ?? ''}';
    final roomPage = (pr['page'] as num?)?.toInt() ?? 1;
    final page = (pc.free && !presenter ? pc.myPage : roomPage).clamp(1, total < 1 ? 1 : total);
    final status = presenter
        ? tr('Bạn đang trình bày · trang {0} / {1}', [page, total])
        : pc.free
            ? tr('Bạn đang tự xem trang {0} / {1}', [page, total])
            : tr('Đang theo {0} · trang {1} / {2}', [byName, page, total]);
    void go(int to) {
      to = to.clamp(1, total < 1 ? 1 : total);
      if (presenter) {
        ctx.call.presentPage(to);
      } else {
        pc.myPage = to;
        pc.free = true;
      }
    }

    final canFlip = presenter || _flipOk(ctx);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(status, key: const ValueKey('doc-status'), style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (!presenter)
          Row(children: [
            SizedBox(width: 52, child: AppButton('‹', key: const ValueKey('doc-prev'), onPressed: canFlip && page > 1 ? () async => go(page - 1) : null)),
            const SizedBox(width: 8),
            Expanded(
              child: pc.free
                  ? AppButton(tr('Về trang đang trình bày'), key: const ValueKey('doc-follow'), kind: AppButtonKind.primary, icon: Icons.undo_rounded, onPressed: () async => pc.free = false)
                  : AppButton(tr('Tự lật'), key: const ValueKey('doc-free'), onPressed: canFlip ? () async => go(page) : null),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 52, child: AppButton('›', key: const ValueKey('doc-next'), onPressed: canFlip && page < total ? () async => go(page + 1) : null)),
          ]),
        if (!presenter && !canFlip) ...[
          const SizedBox(height: 6),
          Text(tr('Chủ trang đang để mọi người theo người trình bày'), style: TextStyle(color: t.sub, fontSize: 12.5)),
        ],
        if (canFlip && total > 1) ...[const SizedBox(height: 12), _strip(context, f, page, total, go)],
        if (download != null) ...[const SizedBox(height: 10), download],
      ]),
    );
  }

  /// Dải trang nhỏ để nhảy nhanh (trang đang xem có viền nhấn).
  Widget _strip(BuildContext context, Map<String, dynamic> f, int page, int total, void Function(int) go) {
    final t = AppScope.of(context).theme;
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: total.clamp(0, 300),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => InkWell(
          key: ValueKey('doc-thumb-${i + 1}'),
          onTap: () => go(i + 1),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: i + 1 == page ? t.accent : Colors.transparent, width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Positioned.fill(child: PdfThumb(file: f, page: i + 1)),
              Positioned(
                right: 3,
                bottom: 2,
                child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF5B6676), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Chủ trang / người trình bày: chọn / đổi tài liệu, trình chiếu, lật trang cho cả phòng, bút vẽ / laser ngay trên trang,
/// cho người xem tự lật / tải về, dừng trình chiếu.
class DocControls extends StatefulWidget {
  final PageCtx ctx;
  const DocControls(this.ctx, {super.key});
  @override
  State<DocControls> createState() => _DocControlsState();
}

class _DocControlsState extends State<DocControls> {
  bool _busy = false;
  PageCtx get ctx => widget.ctx;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final r = await pickPresentPdf(context, ctx.call);
      if (r != null) {
        await ctx.api.upload(ctx.page.id, r.$1, r.$2, r.$3);
        await ctx.reload();
      }
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _flag(String k, bool v) async {
    try {
      await ctx.api.patch(ctx.page.id, {'content': {...ctx.page.content, k: v}});
      await ctx.reload();
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  Future<void> _ink(String action, int page) async {
    try {
      await PagesApi(ctx.call).act(ctx.page.id, action, {'page': page});
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = PresentControl.of(ctx.call);
    return ListenableBuilder(listenable: pc, builder: (context, _) => _body(context, pc));
  }

  Widget _body(BuildContext context, PresentControl pc) {
    final t = AppScope.of(context).theme;
    final f = ctx.page.file;
    final owner = ctx.data.role == 'owner' || ctx.data.role == 'manager';
    final toggles = [
      if (owner) ...[
        AppToggleRow(tr('Cho người xem tự lật'), key: const ValueKey('doc-flip-toggle'), value: _flipOk(ctx), onChanged: (v) => _flag('viewer_flip', v)),
        AppToggleRow(tr('Cho tải về'), key: const ValueKey('doc-dl-toggle'), value: ctx.page.content['allow_download'] == true, onChanged: (v) => _flag('allow_download', v)),
      ],
    ];
    if (!_presenting(ctx)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Điều khiển')),
        if (owner)
          AppButton(f == null ? tr('Chọn tài liệu') : tr('Đổi tài liệu'), key: const ValueKey('doc-pick'), icon: Icons.upload_file_rounded, onPressed: _busy ? null : _pick),
        if (f != null) ...[
          const SizedBox(height: 8),
          AppButton(tr('Trình chiếu'), key: const ValueKey('doc-show'), kind: AppButtonKind.primary, icon: Icons.play_arrow_rounded, onPressed: () async {
            final e = await ctx.call.stageAct('show', {'page': ctx.page.id});
            if (e != null && context.mounted) meetToast(context, e);
          }),
        ],
        ...toggles,
      ]);
    }
    final total = pc.pages > 0 ? pc.pages : (f?['pages'] as num?)?.toInt() ?? 1;
    final page = ((ctx.call.roomPresent?['page'] as num?)?.toInt() ?? 1).clamp(1, total < 1 ? 1 : total);
    Widget tool(String key, IconData icon, String tip, bool on, VoidCallback onTap) => Tooltip(
          message: tip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: ValueKey('doc-tool-$key'),
              onPressed: onTap,
              icon: Icon(icon, color: on ? Colors.white : t.text, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: on ? t.accent : (t.light ? const Color(0xFFE3E7EE) : const Color(0xFF262B33)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Điều khiển · cả phòng theo')),
      Row(children: [
        SizedBox(width: 52, child: AppButton('‹', key: const ValueKey('doc-room-prev'), onPressed: page > 1 ? () => ctx.call.presentPage(page - 1) : null)),
        const SizedBox(width: 8),
        Expanded(child: AppButton(tr('Trang {0} / {1}', [page, total]), kind: AppButtonKind.primary, onPressed: () async {})),
        const SizedBox(width: 8),
        SizedBox(width: 52, child: AppButton('›', key: const ValueKey('doc-room-next'), onPressed: page < total ? () => ctx.call.presentPage(page + 1) : null)),
      ]),
      const SizedBox(height: 12),
      // Bút vẽ chú thích / laser: vẽ thẳng lên hình trang ở trên (và ô sân khấu của màn họp).
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in inkTools.entries)
          if (e.key != 'text')
            tool(e.key, e.value, switch (e.key) { 'pen' => tr('Bút'), 'rect' => tr('Hình chữ nhật'), 'circle' => tr('Hình tròn'), _ => tr('Mũi tên') }, pc.ink && pc.tool == e.key, () {
              if (pc.ink && pc.tool == e.key) {
                pc.ink = false;
              } else {
                pc.laser = false;
                pc.tool = e.key;
                pc.ink = true;
              }
            }),
        tool('laser', Icons.highlight_alt_rounded, tr('Bút laser'), pc.laser, () {
          if (!pc.laser) pc.ink = false;
          pc.laser = !pc.laser;
        }),
        tool('undo', Icons.undo_rounded, tr('Hoàn tác'), false, () => _ink('ink_undo', page)),
      ]),
      if (pc.ink) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in inkColors)
            InkWell(
              key: ValueKey('doc-color-$c'),
              customBorder: const CircleBorder(),
              onTap: () => pc.color = c,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: inkColor(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: pc.color == c ? t.text : t.sub.withValues(alpha: .4), width: pc.color == c ? 3 : 1),
                ),
              ),
            ),
        ]),
      ],
      const SizedBox(height: 10),
      AppButton(tr('Xoá nét trang này'), key: const ValueKey('doc-clear'), kind: AppButtonKind.danger, confirm: true, onPressed: () => _ink('ink_clear', page)),
      ...toggles,
      const SizedBox(height: 8),
      AppButton(tr('Dừng trình chiếu'), key: const ValueKey('doc-stop'), kind: AppButtonKind.danger, confirm: true, icon: Icons.stop_screen_share_outlined, onPressed: () async {
        final e = await ctx.call.presentStop();
        if (e != null && context.mounted) meetToast(context, e);
      }),
    ]);
  }
}

// ------------------------------------------------------------------ Video
// content: url, poster, subtitles (đường dẫn .vtt, tuỳ chọn), chapters [{t (giây), title}], auto_next (hết video tự sang
// trang kế), allow_seek (người xem tua riêng). view: playing, pos, at, asks [{id, t, text, name, mine}].

/// Trạng thái riêng trên máy này của trang video [id]: xem riêng (không theo phòng) tới vị trí nào, bật phụ đề.
class VideoLocal extends ChangeNotifier {
  static final _all = <String, VideoLocal>{};
  static VideoLocal of(String id) => _all.putIfAbsent(id, VideoLocal.new);

  bool _free = false, _subs = false;
  double? _seek;

  /// Xem riêng (tua riêng, không theo phòng).
  bool get free => _free;
  set free(bool v) {
    _free = v;
    notifyListeners();
  }

  bool get subs => _subs;
  set subs(bool v) {
    _subs = v;
    notifyListeners();
  }

  /// Vị trí cần tua tới (xem riêng), trình phát lấy rồi xoá.
  double? takeSeek() {
    final s = _seek;
    _seek = null;
    return s;
  }

  void seek(double t) {
    _free = true;
    _seek = t;
    notifyListeners();
  }

  /// Phụ đề WebVTT đã tải: (bắt đầu, kết thúc, chữ) theo giây.
  List<(double, double, String)>? cues;
}

/// Vị trí phát chung của phòng (giây) theo trạng thái {playing, pos, at}.
double videoRoomPos(Map view) {
  final playing = view['playing'] == true;
  final pos = (view['pos'] as num?)?.toDouble() ?? 0;
  final at = (view['at'] as num?)?.toInt() ?? 0;
  return playing && at > 0 ? pos + (DateTime.now().millisecondsSinceEpoch - at) / 1000 : pos;
}

String fmtClock(double s) {
  final n = s.isFinite ? s.round().clamp(0, 359999) : 0;
  final h = n ~/ 3600, m = (n % 3600) ~/ 60, sec = n % 60;
  String two(int x) => x.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

List<Map<String, dynamic>> videoChapters(Map content) =>
    [for (final x in (content['chapters'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()]..sort((a, b) => ((a['t'] as num?) ?? 0).compareTo((b['t'] as num?) ?? 0));

/// Đọc WebVTT đơn giản: các khối "00:01.000 --> 00:04.000" + chữ.
List<(double, double, String)> parseVtt(String src) {
  double ts(String x) {
    final p = x.trim().split(':');
    var s = 0.0;
    for (final v in p) {
      s = s * 60 + (double.tryParse(v.replaceAll(',', '.')) ?? 0);
    }
    return s;
  }

  final out = <(double, double, String)>[];
  final blocks = src.replaceAll('\r', '').split(RegExp(r'\n\s*\n'));
  for (final b in blocks) {
    final lines = b.split('\n');
    final i = lines.indexWhere((l) => l.contains('-->'));
    if (i < 0) continue;
    final parts = lines[i].split('-->');
    final end = parts[1].trim().split(RegExp(r'\s+')).first;
    final text = lines.sublist(i + 1).join('\n').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (text.isNotEmpty) out.add((ts(parts[0]), ts(end), text));
  }
  return out;
}

/// Tải phụ đề của trang (một lần) vào [VideoLocal.cues].
Future<void> loadVideoSubs(PageCtx ctx) async {
  final l = VideoLocal.of(ctx.page.id);
  final u = '${ctx.page.content['subtitles'] ?? ''}';
  if (u.isEmpty || l.cues != null) return;
  try {
    final r = await http.get(Uri.parse(pageAssetUrl(u))).timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      l.cues = parseVtt(r.body);
      l.subs = l.subs;
    }
  } catch (_) {}
}

/// Người xem: đang xem cùng phòng / xem riêng, mốc chương (bấm để xem riêng từ mốc), phụ đề, hỏi tại mốc đang xem.
class VideoPanel extends StatefulWidget {
  final PageCtx ctx;
  const VideoPanel(this.ctx, {super.key});
  @override
  State<VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<VideoPanel> {
  Timer? _tick;
  final _q = TextEditingController();
  bool _asking = false;
  PageCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ctx.view['playing'] == true) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = VideoLocal.of(ctx.page.id);
    return ListenableBuilder(listenable: l, builder: (context, _) => _body(context, l));
  }

  Widget _body(BuildContext context, VideoLocal l) {
    final s = AppScope.of(context);
    final t = s.theme;
    final c = ctx.page.content;
    if ('${c['url'] ?? ''}'.isEmpty) return AppCard(child: AppEmpty(icon: Icons.smart_display_outlined, title: tr('Chưa có video'), sub: ctx.control ? tr('Bấm "Sửa" để thêm đường dẫn video') : null));
    final pos = videoRoomPos(ctx.view);
    final chapters = videoChapters(c);
    final cur = chapters.lastIndexWhere((x) => ((x['t'] as num?) ?? 0) <= pos);
    final seekOk = c['allow_seek'] == true || ctx.control;
    final hasSubs = '${c['subtitles'] ?? ''}'.isNotEmpty;
    final mine = [for (final a in (ctx.view['asks'] as List? ?? const [])) if (a is Map && a['mine'] == true) a];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          l.free ? tr('Bạn đang xem riêng') : tr('Đang xem cùng phòng · {0}', [fmtClock(pos)]),
          key: const ValueKey('video-status'),
          style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (chapters.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final (i, ch) in chapters.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1F232B),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: ValueKey('video-chapter-$i'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: seekOk ? () => l.seek(((ch['t'] as num?) ?? 0).toDouble()) : null,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: i == cur ? Border.all(color: t.accent, width: 1.5) : null),
                    child: Row(children: [
                      SizedBox(
                        width: 52,
                        child: Text(fmtClock(((ch['t'] as num?) ?? 0).toDouble()),
                            style: TextStyle(color: t.light ? t.accent : const Color(0xFF9DBBFF), fontSize: 12.5, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                      Expanded(child: Text('${ch['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 13.5))),
                      if (i == cur) Text(tr('ĐANG XEM'), style: TextStyle(color: t.light ? t.accent : const Color(0xFF9DBBFF), fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (hasSubs)
            AppButton(tr('Phụ đề'), key: const ValueKey('video-subs'), expand: false, kind: l.subs ? AppButtonKind.primary : AppButtonKind.tonal, icon: Icons.closed_caption_outlined, onPressed: () async {
              l.subs = !l.subs;
              if (l.subs) await loadVideoSubs(ctx);
            }),
          if (l.free)
            AppButton(tr('Về xem cùng phòng'), key: const ValueKey('video-follow'), expand: false, icon: Icons.undo_rounded, onPressed: () async => l.free = false)
          else if (seekOk)
            AppButton(tr('Xem lại riêng'), key: const ValueKey('video-free'), expand: false, onPressed: () async => l.free = true),
        ]),
        const SizedBox(height: 10),
        if (_asking) ...[
          TextField(
            key: const ValueKey('video-ask-text'),
            controller: _q,
            maxLength: 200,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(hintText: tr('Câu hỏi tại {0}…', [fmtClock(pos)]), hintStyle: TextStyle(color: t.sub), counterText: '', isDense: true),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AppButton(tr('Huỷ'), onPressed: () async => setState(() => _asking = false))),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(tr('Gửi'), key: const ValueKey('video-ask-send'), kind: AppButtonKind.primary, onPressed: () async {
                await ctx.act('ask', {'t': pos, 'text': _q.text.trim()});
                _q.clear();
                if (mounted) setState(() => _asking = false);
              }),
            ),
          ]),
        ] else
          AppButton(tr('Hỏi ở {0}', [fmtClock(pos)]), key: const ValueKey('video-ask'), kind: AppButtonKind.warn, icon: Icons.help_outline_rounded, onPressed: () async => setState(() => _asking = true)),
        if (mine.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(tr('Bạn đã hỏi {0} lần', [mine.length]), style: TextStyle(color: t.sub, fontSize: 12.5)),
        ],
      ]),
    );
  }
}

/// Chủ trang / người trình bày: phát / dừng / ±10 giây cho cả phòng, thanh tua có mốc chương và chỗ có câu hỏi, câu hỏi
/// theo mốc, hết video tự sang trang kế, cho người xem tua riêng. Khi sửa: đường dẫn, phụ đề, mốc chương.
class VideoControls extends StatefulWidget {
  final PageCtx ctx;
  const VideoControls(this.ctx, {super.key});
  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  Timer? _tick;
  PageCtx get ctx => widget.ctx;
  // Bản nháp khi sửa tại chỗ.
  String? _url, _subs, _poster;
  List<Map<String, dynamic>>? _chapters;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ctx.view['playing'] == true) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _flag(String k, Object v) async {
    try {
      await ctx.api.patch(ctx.page.id, {'content': {...ctx.page.content, k: v}});
      await ctx.reload();
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  Future<bool> _save() async {
    final c = {...ctx.page.content};
    if (_url != null) c['url'] = _url!.trim();
    if (_subs != null) c['subtitles'] = _subs!.trim();
    if (_poster != null) c['poster'] = _poster!.trim();
    if (_chapters != null) c['chapters'] = [for (final x in _chapters!) if ('${x['title'] ?? ''}'.trim().isNotEmpty) {'t': x['t'], 'title': '${x['title']}'.trim()}];
    await ctx.api.patch(ctx.page.id, {'content': c});
    _url = _subs = _poster = null;
    _chapters = null;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.editing) s.registerEdit(_save);
    final t = s.theme;
    final c = ctx.page.content;
    final pos = videoRoomPos(ctx.view);
    final playing = ctx.view['playing'] == true;
    if (s.editing) return _editor(context, s, pos);
    final asks = [for (final a in (ctx.view['asks'] as List? ?? const [])) if (a is Map) a.cast<String, dynamic>()];
    final chapters = videoChapters(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Điều khiển · cả phòng theo')),
      _bar(context, pos, chapters, asks),
      const SizedBox(height: 6),
      Text(asks.isEmpty ? fmtClock(pos) : tr('{0} · {1} câu hỏi theo mốc', [fmtClock(pos), asks.length]), style: TextStyle(color: t.sub, fontSize: 12.5)),
      const SizedBox(height: 10),
      Row(children: [
        Tooltip(
          message: tr('Lùi 10 giây'),
          child: SizedBox(width: 56, child: AppButton('-10', key: const ValueKey('video-back'), onPressed: () => ctx.act('seek', {'pos': (pos - 10).clamp(0, 1e6)}))),
        ),
        const SizedBox(width: 8),
        Expanded(
          // Cột hẹp (điện thoại ngang): chữ ngắn.
          child: AppButton(s.compact ? (playing ? tr('Dừng') : tr('Phát')) : (playing ? tr('Dừng cho cả phòng') : tr('Phát cho cả phòng')),
              key: const ValueKey('video-play'), kind: AppButtonKind.primary, icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded, onPressed: () => ctx.act(playing ? 'pause' : 'play', {'pos': pos})),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: tr('Tới 10 giây'),
          child: SizedBox(width: 56, child: AppButton('+10', key: const ValueKey('video-fwd'), onPressed: () => ctx.act('seek', {'pos': pos + 10}))),
        ),
      ]),
      if (asks.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppSectionLabel(tr('Câu hỏi theo mốc'), trailing: TextButton(onPressed: () => ctx.act('ask_clear'), child: Text(tr('Xoá hết')))),
        for (final a in asks.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => ctx.act('seek', {'pos': a['t']}),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(children: [
                  SizedBox(width: 52, child: Text(fmtClock(((a['t'] as num?) ?? 0).toDouble()), style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12.5, fontWeight: FontWeight.w700))),
                  Expanded(
                    child: Text('${a['name'] ?? ''}${'${a['text'] ?? ''}'.isEmpty ? '' : ': ${a['text']}'}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 13)),
                  ),
                ]),
              ),
            ),
          ),
      ],
      AppToggleRow(tr('Hết video tự sang trang kế'), key: const ValueKey('video-autonext'), value: c['auto_next'] == true, onChanged: (v) => _flag('auto_next', v)),
      AppToggleRow(tr('Cho người xem tua riêng'), key: const ValueKey('video-allowseek'), value: c['allow_seek'] == true, onChanged: (v) => _flag('allow_seek', v)),
    ]);
  }

  /// Thanh tua: vạch vàng = mốc chương, vạch đỏ = chỗ có câu hỏi; bấm để tua cả phòng.
  Widget _bar(BuildContext context, double pos, List<Map<String, dynamic>> chapters, List<Map<String, dynamic>> asks) {
    final t = AppScope.of(context).theme;
    final dur = ((ctx.page.content['duration'] as num?) ?? 0).toDouble();
    final total = dur > 0 ? dur : [pos + 60, for (final x in chapters) ((x['t'] as num?) ?? 0) + 60, for (final a in asks) ((a['t'] as num?) ?? 0) + 30].reduce((a, b) => a > b ? a : b).toDouble();
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double x(num s) => (s / total).clamp(0, 1) * w;
      return GestureDetector(
        key: const ValueKey('video-bar'),
        onTapUp: (d) => ctx.act('seek', {'pos': (d.localPosition.dx / w).clamp(0.0, 1.0) * total}),
        child: SizedBox(
          height: 24,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 6, decoration: BoxDecoration(color: t.light ? const Color(0xFFE3E7EE) : const Color(0xFF2A2F38), borderRadius: BorderRadius.circular(3))),
            Container(width: x(pos), height: 6, decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(3))),
            for (final ch in chapters) Positioned(left: x(((ch['t'] as num?) ?? 0)) - 2, child: Container(width: 4, height: 12, decoration: BoxDecoration(color: const Color(0xFFF5B544), borderRadius: BorderRadius.circular(2)))),
            for (final a in asks) Positioned(left: x(((a['t'] as num?) ?? 0)) - 2, child: Container(width: 4, height: 12, decoration: BoxDecoration(color: const Color(0xFFFF7A7A), borderRadius: BorderRadius.circular(2)))),
            Positioned(left: x(pos) - 7, child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
          ]),
        ),
      );
    });
  }

  Widget _editor(BuildContext context, AppScope s, double pos) {
    final t = s.theme;
    final c = ctx.page.content;
    _chapters ??= [for (final x in videoChapters(c)) {...x}];
    InputDecoration dec(String label) => InputDecoration(labelText: label, labelStyle: TextStyle(color: t.sub), isDense: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Sửa video')),
      TextFormField(
        key: const ValueKey('video-url'),
        initialValue: '${c['url'] ?? ''}',
        style: TextStyle(color: t.text),
        decoration: dec(tr('Đường dẫn video (mp4, m3u8)')),
        onChanged: (v) => _url = v,
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: const ValueKey('video-poster'),
        initialValue: '${c['poster'] ?? ''}',
        style: TextStyle(color: t.text),
        decoration: dec(tr('Ảnh đại diện (tuỳ chọn)')),
        onChanged: (v) => _poster = v,
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: const ValueKey('video-subs-url'),
        initialValue: '${c['subtitles'] ?? ''}',
        style: TextStyle(color: t.text),
        decoration: dec(tr('Phụ đề .vtt (tuỳ chọn)')),
        onChanged: (v) => _subs = v,
      ),
      const SizedBox(height: 12),
      AppSectionLabel(tr('Mốc chương · bấm để sửa')),
      for (final (i, ch) in _chapters!.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 56, child: Text(fmtClock(((ch['t'] as num?) ?? 0).toDouble()), style: TextStyle(color: t.light ? t.accent : const Color(0xFF9DBBFF), fontWeight: FontWeight.w700))),
            Expanded(
              child: TextFormField(
                key: ValueKey('video-ch-$i'),
                initialValue: '${ch['title'] ?? ''}',
                style: TextStyle(color: t.text),
                decoration: dec(tr('Tên mốc')),
                onChanged: (v) => ch['title'] = v,
              ),
            ),
            IconButton(tooltip: tr('Bỏ mốc'), onPressed: () => setState(() => _chapters!.removeAt(i)), icon: Icon(Icons.close_rounded, color: t.sub)),
          ]),
        ),
      AppButton(tr('Đặt mốc tại {0}', [fmtClock(pos)]), key: const ValueKey('video-add-chapter'), icon: Icons.add_rounded, onPressed: () async {
        setState(() => _chapters!.add({'t': (pos * 10).round() / 10, 'title': tr('Mốc mới')}));
      }),
    ]);
  }
}

/// Phụ đề đang hiện tại vị trí [pos] (null = không có / tắt).
String? videoCaptionAt(String pageId, double pos) {
  final l = VideoLocal.of(pageId);
  if (!l.subs) return null;
  for (final (a, b, text) in l.cues ?? const <(double, double, String)>[]) {
    if (pos >= a && pos < b) return text;
  }
  return null;
}

/// Sao chép chữ (dùng cho link website) — catch lỗi máy không cho ghi clipboard.
Future<void> copyText(BuildContext context, String text, String done) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) meetToast(context, done);
  } catch (_) {}
}
