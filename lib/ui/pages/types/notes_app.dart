import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';
import 'timer.dart' show fmtClock;

// Ghi chú theo mockup "mỗi trang là một app" (21/11/2026). Trong cuộc họp, ghi chú nằm trong bảng của cuộc họp ở app Ghi chú.
// - NotesPanel (người xem): mỗi lần một cột (chạm tab để đổi), chạm ghi chú để +1 (pha bỏ phiếu), nhấn giữ: chuyển cột, sửa /
//   xoá ghi chú của mình; ô "Viết ghi chú…" vào cột đang xem.
// - NotesControls (chủ trang): pha Viết -> Bỏ phiếu -> Bàn, hẹn giờ viết (+2 phút), ẩn tên người viết, che ghi chú người khác
//   khi đang viết, mỗi người mấy lần +1, ghi Biên bản. Ghim ghi chú lên TV: menu nhấn giữ của ghi chú.

const noteFill = {
  'yellow': Color(0xFFFFE68A),
  'green': Color(0xFFB9F0C9),
  'blue': Color(0xFFCFE3FF),
  'pink': Color(0xFFFFC9C2),
  'purple': Color(0xFFE2D4FF),
  'orange': Color(0xFFFFD8A8),
};

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}

List<Map<String, dynamic>> _cols(Map<String, dynamic> v) => [for (final c in (v['columns'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
List<Map<String, dynamic>> _notes(Map<String, dynamic> v) => [for (final n in (v['notes'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];

/// Còn bao lâu để viết (0 = không hẹn giờ / hết giờ), vẽ lại mỗi giây.
mixin _WriteClock<T extends StatefulWidget> on State<T> {
  Map<String, dynamic> get v;
  Timer? _tick;
  int _skew = 0;
  void startClock() {
    final now = (v['now'] as num?)?.toInt();
    if (now != null) _skew = now - DateTime.now().millisecondsSinceEpoch;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ((v['write_until'] as num?) ?? 0) > 0) setState(() {});
    });
  }

  int get leftMs {
    final until = (v['write_until'] as num?)?.toInt() ?? 0;
    return until == 0 ? 0 : (until - DateTime.now().millisecondsSinceEpoch - _skew).clamp(0, 1 << 40);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

String _phaseLine(Map<String, dynamic> v, int left) {
  final phase = '${v['phase'] ?? ''}';
  final n = _notes(v).length;
  return switch (phase) {
    'write' => left > 0 ? tr('Đang viết · còn {0} · {1} ghi chú', [fmtClock(left), n]) : tr('Đang viết · {0} ghi chú', [n]),
    'vote' => v['votes_left'] == null ? tr('Bỏ phiếu · chạm ghi chú để +1') : tr('Bỏ phiếu · bạn còn {0} lần +1', [v['votes_left']]),
    'discuss' => tr('Đang bàn · {0} ghi chú', [n]),
    _ => tr('{0} ghi chú', [n]),
  };
}

class NotesPanel extends StatefulWidget {
  final PageCtx ctx;
  const NotesPanel(this.ctx, {super.key});
  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> with _WriteClock<NotesPanel> {
  String? _col;
  final _text = TextEditingController();
  String? _editing;
  bool _sending = false;

  @override
  Map<String, dynamic> get v => widget.ctx.view;
  PageCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    startClock();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Cột đang xem (chưa chọn: cột đầu).
  String? _curCol() {
    final cols = _cols(v);
    return cols.isEmpty ? null : (cols.any((c) => c['id'] == _col) ? _col : '${cols.first['id']}');
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await _run(context, () async {
      if (_editing != null) {
        await ctx.act('edit', {'id': _editing, 'text': text});
      } else {
        await ctx.act('add', {'text': text, 'col': ?_curCol()});
      }
      _text.clear();
      _editing = null;
    });
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _menu(Map<String, dynamic> n, Offset? at) async {
    final cols = _cols(v);
    await showAppMenu(context, at: at, items: [
      for (final c in cols)
        if (c['id'] != n['col']) PageMenuItem(label: tr('Chuyển sang "{0}"', [c['name']]), icon: Icons.drive_file_move_outline, onTap: () => _run(context, () => ctx.act('move', {'id': n['id'], 'col': c['id']}))),
      if (ctx.control && v['mode'] == 'todo')
        PageMenuItem(
          label: n['pinned'] == true ? tr('Bỏ ghim khỏi TV') : tr('Ghim lên TV'),
          icon: Icons.push_pin_outlined,
          color: const Color(0xFF7FD8CC),
          onTap: () => _run(context, () => ctx.act('pin', {'id': n['pinned'] == true ? null : n['id']})),
        ),
      if (n['mine'] == true) ...[
        PageMenuItem(label: tr('Sửa ghi chú'), icon: Icons.edit_outlined, onTap: () async => setState(() => (_editing = '${n['id']}', _text.text = '${n['text']}'))),
        PageMenuItem(label: tr('Xoá ghi chú'), icon: Icons.delete_outline_rounded, danger: true, onTap: () => _run(context, () => ctx.act('delete', {'id': n['id']}))),
      ],
    ]);
  }

  Widget _note(Map<String, dynamic> n, AppScope s) {
    final t = s.theme;
    final canVote = v['mode'] != 'todo' || v['phase'] == 'vote' || ctx.control;
    final concealed = n['concealed'] == true;
    return GestureDetector(
      key: ValueKey('note-${n['id']}'),
      onTap: canVote && !concealed && ctx.data.role != 'viewer' ? () => _run(context, () => ctx.act('vote', {'id': n['id']})) : null,
      onLongPressStart: (e) => _menu(n, e.globalPosition),
      onSecondaryTapDown: (e) => _menu(n, e.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: concealed ? t.surface2 : (noteFill['${n['color']}'] ?? noteFill['yellow']),
          borderRadius: BorderRadius.circular(10),
          border: n['pinned'] == true ? Border.all(color: const Color(0xFFE5343D), width: 2) : (n['voted'] == true ? Border.all(color: t.accent, width: 2) : null),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(concealed ? tr('Ghi chú đang viết (che tới khi hết giờ)') : '${n['text']}',
              style: TextStyle(color: concealed ? t.sub : const Color(0xFF1B1F26), fontSize: 15, height: 1.35, fontWeight: FontWeight.w500, fontStyle: concealed ? FontStyle.italic : null)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(n['mine'] == true ? tr('Bạn') : ('${n['by_name'] ?? ''}'.isEmpty ? tr('Ẩn danh') : '${n['by_name']}'), style: TextStyle(color: concealed ? t.sub : const Color(0xFF4A5160), fontSize: 12))),
            if (!concealed && (((n['votes'] as num?) ?? 0) > 0 || n['voted'] == true))
              Text('+${n['votes'] ?? 0}', style: TextStyle(color: n['voted'] == true ? const Color(0xFF1F5FD6) : const Color(0xFF1B1F26), fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    final cols = _cols(v);
    final notes = _notes(v);
    final cur = _curCol();
    List<Map<String, dynamic>> inCol(String? id) =>
        (cols.isEmpty ? notes : notes.where((n) => id == null ? !cols.any((c) => c['id'] == n['col']) : n['col'] == id).toList())
          ..sort((a, b) => ((b['votes'] as num?) ?? 0).compareTo((a['votes'] as num?) ?? 0));
    final shown = inCol(cur);
    final canWrite = ctx.data.role != 'viewer' && (v['mode'] != 'todo' || v['phase'] == 'write' || ctx.control) && v['offline'] != true;
    final colName = cols.where((c) => c['id'] == cur).map((c) => '${c['name']}').firstOrNull;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_phaseLine(v, leftMs), style: TextStyle(color: v['phase'] == 'write' && leftMs > 0 && leftMs < 60000 ? const Color(0xFFF0646A) : t.sub, fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (cols.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final c in cols)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AppChip('${c['name']} · ${inCol('${c['id']}').length}', key: ValueKey('col-${c['id']}'), selected: c['id'] == cur, onTap: () => setState(() => _col = '${c['id']}')),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        if (shown.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(tr('Chưa có ghi chú'), textAlign: TextAlign.center, style: TextStyle(color: t.sub)))
        else
          for (final n in shown.take(s.compact ? 4 : 30)) _note(n, s),
        if (canWrite) ...[
          if (colName != null && _editing == null) Text(tr('vào cột "{0}"', [colName]), style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('note-text'),
                controller: _text,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(color: t.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: t.surface2,
                  hintText: _editing != null ? tr('Sửa ghi chú…') : tr('Viết ghi chú…'),
                  hintStyle: TextStyle(color: t.sub),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(key: const ValueKey('note-send'), tooltip: tr('Dán'), onPressed: _sending ? null : _send, icon: Icon(_editing != null ? Icons.check_rounded : Icons.add_rounded, color: t.accent)),
          ]),
        ],
      ]),
    );
  }
}

class NotesControls extends StatefulWidget {
  final PageCtx ctx;
  const NotesControls(this.ctx, {super.key});
  @override
  State<NotesControls> createState() => _NotesControlsState();
}

class _NotesControlsState extends State<NotesControls> with _WriteClock<NotesControls> {
  @override
  Map<String, dynamic> get v => widget.ctx.view;

  @override
  void initState() {
    super.initState();
    startClock();
  }

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) => _run(context, () => widget.ctx.act(a, b));

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    if (v['mode'] != 'todo') {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Bảng ghi chú')),
        Text(tr('Chủ trang sửa cột, ẩn tên và số +1 trong menu Sửa của trang.'), style: TextStyle(color: t.sub, fontSize: 13)),
      ]);
    }
    final phase = '${v['phase'] ?? 'write'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(_phaseLine(v, leftMs)),
      AppSegmented<String>(
        items: [('write', tr('Viết')), ('vote', tr('Bỏ phiếu')), ('discuss', tr('Bàn'))],
        value: phase,
        onChanged: (x) => _act('phase', {'phase': x, if (x == 'write') 'minutes': 5}),
      ),
      if (phase == 'write') ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AppButton(tr('Dừng viết'), key: const ValueKey('notes-stop'), onPressed: () => _act('phase', {'phase': 'vote'}))),
          const SizedBox(width: 8),
          Expanded(child: AppButton(tr('+2 phút'), key: const ValueKey('notes-more'), kind: AppButtonKind.warn, onPressed: () => _act('add_time', {'ms': 120000}))),
        ]),
      ] else if (phase == 'vote') ...[
        const SizedBox(height: 10),
        AppButton(tr('Sang bàn luận'), kind: AppButtonKind.primary, onPressed: () => _act('phase', {'phase': 'discuss'})),
      ],
      const SizedBox(height: 6),
      AppToggleRow(tr('Ẩn tên người viết'), value: v['hide_names'] == true, onChanged: (x) => _act('settings', {'hide_names': x})),
      AppToggleRow(tr('Che ghi chú người khác khi đang viết'), value: v['conceal'] == true, onChanged: (x) => _act('settings', {'conceal': x})),
      Row(children: [
        Expanded(child: Text(tr('Mỗi người được +1'), style: TextStyle(color: t.text))),
        AppNumberStepper(
          value: (v['votes_per_person'] as num?)?.toInt() ?? 3,
          min: 0,
          max: 20,
          format: (x) => x == 0 ? tr('không giới hạn') : tr('{0} lần', [x]),
          onChanged: (x) => _act('settings', {'votes_per_person': x}),
        ),
      ]),
      if (widget.ctx.page.meeting != null) ...[
        const SizedBox(height: 8),
        AppButton(tr('Ghi vào Biên bản'), icon: Icons.note_add_outlined, onPressed: () async {
          await _act('to_minutes');
          if (context.mounted) meetToast(context, tr('Đã ghi vào Biên bản'));
        }),
      ],
    ]);
  }
}
