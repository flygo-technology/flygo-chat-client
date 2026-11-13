part of 'show_page.dart';

// Phần dùng chung cho bố cục máy tính của app Trình chiếu: phím tắt, thẻ ảnh trang, hộp Bắt đầu trình chiếu, đồng hồ buổi,
// và bố cục 3 cột của màn điều khiển (trang bên trái, slide + ghi chú ở giữa, Màn hình / Bình luận / Phụ đề bên phải).

/// Đang gõ trong một ô nhập: phím tắt một chữ (← → Space B…) để cho ô nhập.
bool _typing() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
}

/// Vùng nhận phím tắt: [node] giữ focus của vùng (bấm chuột vào vùng là lấy lại focus). Đang gõ thì chỉ Esc được bắt:
/// thoát ô nhập, trả focus về vùng.
class _KeyScope extends StatelessWidget {
  final FocusNode node;
  final Map<ShortcutActivator, VoidCallback> keys;
  final Widget child;
  const _KeyScope({required this.node, required this.keys, required this.child});

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: node,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          if (_typing()) {
            if (e.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
            node.requestFocus();
            return KeyEventResult.handled;
          }
          for (final k in keys.entries) {
            if (k.key.accepts(e, HardwareKeyboard.instance)) {
              k.value();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => _typing() ? null : node.requestFocus(), child: child),
      );
}

/// Bảng phím tắt (phím ?): [rows] = (phím, việc).
void _showKeys(BuildContext context, String title, List<(String, String)> rows) {
  final pal = Pal.of(context);
  showDialog(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 170, child: Wrap(spacing: 4, runSpacing: 4, children: [for (final x in k.split(' ')) _Kbd(x)])),
                Expanded(child: Text(v, style: TextStyle(color: pal.text))),
              ]),
            ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text(tr('Đóng')))],
    ),
  );
}

/// Một phím vẽ như nút bàn phím.
class _Kbd extends StatelessWidget {
  final String k;
  final bool onFill;
  const _Kbd(this.k, {this.onFill = false});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: onFill ? Colors.white.withValues(alpha: .18) : pal.bg,
        border: Border.all(color: onFill ? Colors.white.withValues(alpha: .4) : pal.divider),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(k, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: onFill ? Colors.white : pal.sub)),
    );
  }
}

/// Hai màu của thẻ ảnh trang, cố định theo bộ slide (để các bộ dễ phân biệt khi không có ảnh thật).
const _deckColors = [
  (Color(0xFF0B1F3D), Color(0xFF1E6FE0)),
  (Color(0xFF1D1238), Color(0xFF6D4FE8)),
  (Color(0xFF0D2B25), Color(0xFF1D9B6E)),
  (Color(0xFF2B1708), Color(0xFFD07A22)),
  (Color(0xFF2A0F1A), Color(0xFFD03F72)),
  (Color(0xFF10232E), Color(0xFF2794B8)),
];
(Color, Color) _deckColor(String id) => _deckColors[id.codeUnits.fold(0, (a, b) => a + b) % _deckColors.length];

/// Thẻ ảnh một trang (hoặc ảnh bìa bộ slide): nền theo màu bộ, tiêu đề trang; [number] ở góc, [selected] viền xanh,
/// [hidden] mờ đi. Dùng ở danh sách, lưới trang và trang tiếp theo khi không dựng webview.
class _SlideCard extends StatelessWidget {
  final String deckId, title;
  final int? number;
  final bool selected, hidden;
  final VoidCallback? onTap;
  final double radius;
  const _SlideCard({required this.deckId, required this.title, this.number, this.selected = false, this.hidden = false, this.onTap, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final (a, b) = _deckColor(deckId);
    final card = AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (_, box) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
          ),
          padding: EdgeInsets.fromLTRB(box.maxWidth * .07, box.maxWidth * .08, box.maxWidth * .07, 4),
          // Thẻ nhỏ (danh sách, cột trang): chữ quá bé để đọc, chỉ để màu (+ số trang ở góc).
          child: box.maxWidth < 130
              ? (number == null ? Center(child: Icon(Icons.slideshow_rounded, color: Colors.white.withValues(alpha: .45), size: box.maxWidth * .3)) : null)
              : Text(title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: (box.maxWidth * .075).clamp(7, 40), height: 1.2)),
        ),
      ),
    );
    return Opacity(
      opacity: hidden ? .4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius + 3),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius + 3),
              border: Border.all(color: selected ? pal.accent : Colors.transparent, width: 2.5),
            ),
            child: Stack(children: [
              card,
              if (number != null)
                Positioned(
                  left: 5,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
                    child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (hidden)
                const Positioned(right: 6, top: 5, child: Icon(Icons.visibility_off_outlined, size: 16, color: Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Đồng hồ buổi trình chiếu (mm:ss, quá 1 giờ thì h:mm:ss) tính từ [since].
class _Clock extends StatefulWidget {
  final DateTime since;
  const _Clock(this.since);
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = DateTime.now().difference(widget.since);
    String two(int n) => n.toString().padLeft(2, '0');
    final s = d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
    return Tooltip(
      message: tr('Thời gian trình bày'),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 20, color: pal.sub),
        const SizedBox(width: 4),
        Text(s, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// Hộp Bắt đầu trình chiếu trên máy tính: chọn chiếu lên TV (nhập mã 8 ký tự hiện trên TV) hoặc chỉ điều khiển.
/// [open] mở buổi (trả presentation_id); ghép hỏng thì dừng buổi vừa mở. Trả presentation_id khi xong.
class _StartDialog extends StatefulWidget {
  final ShowClient client;
  final Future<String> Function() open;
  final String subtitle;
  const _StartDialog({required this.client, required this.open, required this.subtitle});
  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  final _code = TextEditingController();
  bool _tv = true, _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _tvUrl => '${widget.client.base}/tv';

  Future<void> _go() async {
    if (_busy) return;
    final code = pairCodeOf(_code.text);
    if (_tv && code == null) return setState(() => _error = tr('Mã gồm 8 ký tự, hiện trên màn hình TV'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pid = await widget.open();
      if (_tv) {
        try {
          await widget.client.call('screen_pair', {'presentation_id': pid, 'code': code});
        } catch (_) {
          // Ghép hỏng: bỏ buổi vừa mở, không để buổi trống chạy.
          unawaited(widget.client.call('show_stop', {'presentation_id': pid}).catchError((_) => <String, dynamic>{}));
          rethrow;
        }
      }
      if (mounted) Navigator.pop(context, pid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _err(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget opt(bool tv, IconData icon, String title, String sub) => Expanded(
          child: Material(
            color: _tv == tv ? pal.accent.withValues(alpha: .07) : pal.bg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14), side: BorderSide(color: _tv == tv ? pal.accent : pal.divider, width: 1.5)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy ? null : () => setState(() => _tv = tv),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 28, color: pal.accent),
                  const SizedBox(height: 8),
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                ]),
              ),
            ),
          ),
        );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _go},
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Bắt đầu trình chiếu'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text)),
                    Text(widget.subtitle, style: TextStyle(color: pal.sub)),
                  ]),
                ),
                IconButton(tooltip: tr('Đóng (Esc)'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  opt(true, Icons.tv_rounded, tr('Chiếu lên TV / máy chiếu'), tr('Nhập mã hiện trên màn hình TV')),
                  const SizedBox(width: 10),
                  opt(false, Icons.settings_remote_rounded, tr('Chỉ điều khiển'), tr('Ghép màn hình sau, trong tab Màn hình')),
                ]),
              ),
              if (_tv) ...[
                const SizedBox(height: 18),
                Row(children: [
                  Flexible(child: Text(tr('1. Trên TV mở trình duyệt, vào '), style: TextStyle(color: pal.text))),
                  SelectableText(_tvUrl, style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w700)),
                  IconButton(
                    tooltip: tr('Copy link'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _tvUrl));
                      _toast(context, tr('Đã copy link màn hình: {0}', [_tvUrl]));
                    },
                  ),
                ]),
                Text(tr('2. Gõ mã 8 ký tự hiện trên TV (dán cả link /pair/… cũng được):'), style: TextStyle(color: pal.text)),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  autofocus: true,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 8, color: pal.text),
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(
                    hintText: 'XXXX XXXX',
                    hintStyle: TextStyle(color: pal.sub.withValues(alpha: .4), letterSpacing: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFE53935))),
                ),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('Huỷ'))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _go,
                  icon: const Icon(Icons.slideshow_rounded),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_tv ? tr('Kết nối và bắt đầu') : tr('Bắt đầu')),
                    const SizedBox(width: 8),
                    const _Kbd('Enter', onFill: true),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Danh sách bộ slide và buổi đang chạy (cột trái trên máy tính, cả màn hình trên điện thoại): tìm, lọc Tất cả / Của tôi /
/// Được chia sẻ, buổi LIVE ở trên cùng.
class _DeckBrowser extends StatelessWidget {
  final _ShowHomeState home;
  final bool wide;
  const _DeckBrowser({required this.home, required this.wide});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final h = home;
    final decks = h._shown;
    Widget sec(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: .4, fontWeight: FontWeight.w700, color: pal.sub)),
        );
    final search = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: TextField(
        controller: h._search,
        focusNode: h._searchFocus,
        onChanged: (_) => h._refresh(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: wide ? pal.bg : pal.surface,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: h._search.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    h._search.clear();
                    h._refresh();
                  })
              : (wide ? const Padding(padding: EdgeInsets.all(12), child: _Kbd('Ctrl K')) : null),
          hintText: tr('Tìm bộ slide…'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: pal.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: pal.divider)),
        ),
      ),
    );
    final filters = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 6, children: [
        for (final (i, t) in [tr('Tất cả'), tr('Của tôi'), tr('Được chia sẻ')].indexed)
          ChoiceChip(
            label: Text(t),
            selected: h._filter == i,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => h._setFilter(i),
          ),
      ]),
    );
    final items = <Widget>[
      search,
      filters,
      if (h._live.isNotEmpty) ...[
        sec(tr('Đang trình chiếu')),
        for (final p in h._live) _LiveBox(p: p, onTap: () => h._openLive(p)),
      ],
      sec(h._decks == null ? tr('Bộ slide') : tr('Bộ slide · {0}', ['${decks.length}'])),
      if (h._error != null && h._decks == null)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(h._error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
            TextButton(onPressed: h._reload, child: Text(tr('Thử lại'))),
          ]),
        )
      else if (h._decks == null)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else if (decks.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(children: [
            Icon(Icons.slideshow_outlined, size: 44, color: pal.sub),
            const SizedBox(height: 10),
            Text(h._search.text.isNotEmpty || h._filter != 0 ? tr('Không có bộ slide nào khớp') : tr('Chưa có bài trình chiếu'),
                textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('Nhắn trợ lý AI để tạo bộ slide, ví dụ báo cáo, giới thiệu sản phẩm, đào tạo.'),
                textAlign: TextAlign.center, style: TextStyle(color: pal.sub, fontSize: 13)),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(icon: const Icon(Icons.auto_awesome_rounded), label: Text(tr('Tạo bằng trợ lý AI')), onPressed: h._howToCreate),
          ]),
        )
      else
        for (final d in decks) _DeckRow(home: h, d: d, wide: wide),
      const SizedBox(height: 16),
    ];
    return RefreshIndicator(onRefresh: h._reload, child: ListView(padding: EdgeInsets.zero, children: items));
  }
}

/// Buổi đang chạy: ô viền đỏ nhạt với LIVE, người trình bày, trang.
class _LiveBox extends StatelessWidget {
  final Map<String, dynamic> p;
  final VoidCallback onTap;
  const _LiveBox({required this.p, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final viewOnly = p['can_control'] == false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Material(
        color: pal.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFFFD2D0))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              const _LiveDot(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                  Text(
                      viewOnly
                          ? tr('{0} · trang {1}/{2} · chỉ xem', ['${p['presenter_name'] ?? ''}', '${p['slide'] ?? 1}', '${p['total'] ?? 0}'])
                          : tr('{0} · trang {1}/{2} · {3} màn hình',
                              ['${p['presenter_name'] ?? ''}', '${p['slide'] ?? 1}', '${p['total'] ?? 0}', '${p['screens'] ?? 0}']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: pal.sub)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: pal.sub),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Một bộ slide trong danh sách: thẻ ảnh bìa, tiêu đề, số trang / người tạo / lúc sửa; chuột phải hoặc ⋮ mở menu.
class _DeckRow extends StatelessWidget {
  final _ShowHomeState home;
  final Map<String, dynamic> d;
  final bool wide;
  const _DeckRow({required this.home, required this.d, required this.wide});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final id = '${d['id']}';
    final on = wide && home._selected == id;
    final mine = home._mine.contains(id);
    final sub = [tr('{0} trang', ['${d['slides'] ?? 0}']), if (!mine && '${d['owner_name'] ?? ''}'.isNotEmpty) '${d['owner_name']}', _when(d['updated_at'])]
        .where((x) => x.isNotEmpty)
        .join(' · ');
    return GestureDetector(
      onSecondaryTapDown: (e) => home._deckMenu(context, d, e.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: on ? pal.bg : Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: on ? BorderSide(color: pal.accent, width: 1.5) : BorderSide.none),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: pal.bg,
            onTap: () => home._openDeck(d),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 2, 7),
              child: Row(children: [
                SizedBox(width: wide ? 92 : 104, child: _SlideCard(deckId: id, title: '${d['title'] ?? ''}', radius: 5)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${d['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                    const SizedBox(height: 2),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  ]),
                ),
                Builder(
                  builder: (b) => IconButton(
                    tooltip: tr('Thêm'),
                    icon: Icon(Icons.more_vert_rounded, size: 20, color: pal.sub),
                    onPressed: () {
                      final box = b.findRenderObject() as RenderBox;
                      home._deckMenu(context, d, box.localToGlobal(box.size.center(Offset.zero)));
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bố cục máy tính của màn điều khiển: cột trang bên trái, slide đang chiếu + trang tiếp theo + ghi chú ở giữa với thanh
/// điều khiển dính đáy, panel Tài liệu / Màn hình / Bình luận / Phụ đề bên phải.
extension _WideControl on _ShowControlPageState {
  /// Trang hiện kế tiếp theo thứ tự chạy (bỏ trang ẩn); ở màn chờ là trang hiện đầu tiên; hết trang: null.
  Map<String, dynamic>? get _nextPage {
    final pages = {
      for (final p in _pageList)
        if ('${p['scene'] ?? 'slide'}' == 'slide' && p['slide'] != null) (p['slide'] as num).toInt(): p,
    };
    final order = [for (final f in _flowItems) if (f['type'] == 'slide' && f['hidden'] != true) (f['slide'] as num?)?.toInt() ?? 0];
    if (_scene == 'waiting') return order.isEmpty ? null : pages[order.first] ?? {'slide': order.first};
    if (_scene != 'slide') return null;
    final i = order.indexOf(_slide);
    if (i < 0 || i + 1 >= order.length) return null;
    return pages[order[i + 1]] ?? {'slide': order[i + 1]};
  }

  Widget _wideLayout(Pal pal, Map<String, dynamic> st, int total, Map<String, dynamic>? cur, Widget tabBar, Widget tabs) {
    final next = _nextPage;
    final deckId = _deckId;
    final notes = _notes.trim();
    final rail = ListView(padding: const EdgeInsets.fromLTRB(4, 8, 4, 24), children: [
      if (_canControl) ..._contentRail(pal) else ..._viewerRail(pal),
    ]);
    final preview = _deck == null
        ? const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator()))
        : SlidePreview(
            key: ValueKey('${_deck!['id']}#${_deck!['rev']}#${_okLang(_hereSlide)}'),
            client: _c,
            deckId: '${_deck!['id']}',
            pid: _pid,
            lang: _languages.length > 1 ? _okLang(_hereSlide) : null,
            slide: _slide,
            frame: _frame,
            step: (st['step'] as num?)?.toInt() ?? 0,
            fallbackTitle: '${st['slide_title'] ?? ''}',
            fallbackText: '${st['summary'] ?? cur?['text'] ?? ''}',
          );
    final nextN = (next?['slide'] as num?)?.toInt();
    final nextCard = next == null || nextN == null
        ? Container(
            height: 112,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(8)),
            child: Text(tr('Hết trang'), style: TextStyle(color: pal.sub)),
          )
        : _webPreview && _deck != null
            ? SlidePreview(
                key: ValueKey('next#${_deck!['id']}#${_deck!['rev']}#${_okLang(_hereSlide)}'),
                client: _c,
                deckId: '${_deck!['id']}',
                lang: _languages.length > 1 ? _okLang(_hereSlide) : null,
                slide: nextN,
                animate: false,
              )
            : _SlideCard(deckId: deckId, title: '${next['title'] ?? ''}', number: nextN);
    final center = Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                preview,
                _statusLine(pal, total),
                if (total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                          value: _scene == 'slide' ? (_slide / total).clamp(0.0, 1.0) : (_scene == 'waiting' ? 0 : 1),
                          minHeight: 4,
                          backgroundColor: pal.surface),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 220,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('TIẾP THEO'), style: TextStyle(fontSize: 11.5, letterSpacing: .4, fontWeight: FontWeight.w700, color: pal.sub)),
                      const SizedBox(height: 6),
                      nextCard,
                      if (next != null && nextN != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('$nextN · ${next['title'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('GHI CHÚ NGƯỜI NÓI'), style: TextStyle(fontSize: 11.5, letterSpacing: .4, fontWeight: FontWeight.w700, color: pal.sub)),
                      const SizedBox(height: 6),
                      _canControl && notes.isNotEmpty
                          ? SelectableText(notes, style: TextStyle(fontSize: 17, height: 1.5, color: pal.text))
                          : Text(_canControl ? tr('Trang này chưa có ghi chú.') : tr('Chỉ người trình bày thấy ghi chú.'),
                              style: TextStyle(color: pal.sub)),
                    ]),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
      if (_canControl) _controlBar(pal),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 248, child: ColoredBox(color: pal.surface, child: rail)),
      VerticalDivider(width: 1, color: pal.divider),
      Expanded(child: center),
      VerticalDivider(width: 1, color: pal.divider),
      SizedBox(
        width: 340,
        child: _canControl
            ? Column(children: [tabBar, Divider(height: 1, color: pal.divider), Expanded(child: tabs)])
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [_hereRow(pal)]),
      ),
    ]);
  }

  /// Cột trang của người điều khiển: màn chờ, các trang theo thứ tự chạy (kéo tay cầm để đổi chỗ, 👁 ẩn / hiện),
  /// Hỏi & Đáp, Kết thúc, nút Nhảy và lặp.
  List<Widget> _contentRail(Pal pal) {
    final pages = {
      for (final p in _pageList)
        if ('${p['scene'] ?? 'slide'}' == 'slide' && p['slide'] != null) (p['slide'] as num).toInt(): p,
    };
    final system = [for (final p in _pageList) if ('${p['scene'] ?? 'slide'}' != 'slide') p];
    final flow = _flowItems;
    return [
      for (final p in system.where((p) => p['scene'] == 'waiting')) _pageTile(pal, p, compact: true),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: flow.length,
        onReorderItem: _onReorder,
        proxyDecorator: (child, _, _) => Material(elevation: 4, color: pal.bg, borderRadius: BorderRadius.circular(12), child: child),
        itemBuilder: (_, i) {
          final f = flow[i];
          final key = f['type'] == 'jump' ? 'j:${f['jump_id']}' : 's:${f['id'] ?? f['slide']}';
          return Row(key: ValueKey(key), children: [
            ReorderableDragStartListener(
              index: i,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.drag_indicator_rounded, size: 18, color: pal.sub)),
              ),
            ),
            Expanded(child: f['type'] == 'jump' ? _jumpRow(pal, f) : _slideRow(pal, f, pages, compact: true)),
          ]);
        },
      ),
      for (final p in system.where((p) => p['scene'] != 'waiting')) _pageTile(pal, p, compact: true),
      if (_flow != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.repeat_rounded),
            label: Text(tr('Nhảy và lặp')),
            onPressed: () => _deckCall('deck_jump', {'action': 'add', 'to': 1}),
          ),
        ),
    ];
  }

  List<Widget> _viewerRail(Pal pal) {
    final pages = {
      for (final p in _pageList)
        if ('${p['scene'] ?? 'slide'}' == 'slide' && p['slide'] != null) (p['slide'] as num).toInt(): p,
    };
    final system = [for (final p in _pageList) if ('${p['scene'] ?? 'slide'}' != 'slide') p];
    return [
      for (final p in system.where((p) => p['scene'] == 'waiting')) _pageTile(pal, p, readOnly: true, compact: true),
      for (final f in _flowItems)
        if (f['type'] == 'slide' && f['hidden'] != true)
          _pageTile(pal, pages[(f['slide'] as num?)?.toInt() ?? 0] ?? {'scene': 'slide', 'slide': f['slide'], 'title': f['title']},
              readOnly: true, compact: true),
      for (final p in system.where((p) => p['scene'] != 'waiting')) _pageTile(pal, p, readOnly: true, compact: true),
    ];
  }

  /// Thanh điều khiển dính đáy: Trước / Tiếp to, Tự chạy, Nhạc, Màn chờ, Tắt hình mọi màn hình, gợi ý phím.
  Widget _controlBar(Pal pal) {
    final running = _autopilot['running'] == true, paused = _autopilot['paused'] == true;
    final musicOn = _music['on'] == true;
    final blanked = _screens.isNotEmpty && !_anyShown;
    const big = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 48)), padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)));
    return LayoutBuilder(builder: (context, box) {
      // Hẹp: nút phụ chỉ còn biểu tượng (tên + phím trong tooltip).
      final icons = box.maxWidth < 800;
      Widget tool(IconData icon, String label, String key, VoidCallback? onTap, {bool active = false}) => Tooltip(
            message: '$label ($key)',
            child: icons
                ? (active
                    ? IconButton.filledTonal(onPressed: onTap, icon: Icon(icon))
                    : IconButton.outlined(onPressed: onTap, icon: Icon(icon)))
                : active
                    ? FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onTap, icon: Icon(icon), label: Text(label))
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onTap, icon: Icon(icon), label: Text(label)),
          );
      return _bar(pal, big, tool, running, paused, musicOn, blanked);
    });
  }

  Widget _bar(Pal pal, ButtonStyle big, Widget Function(IconData, String, String, VoidCallback?, {bool active}) tool, bool running, bool paused,
      bool musicOn, bool blanked) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(color: pal.bg, border: Border(top: BorderSide(color: pal.divider))),
      child: Row(children: [
        Tooltip(
          message: tr('Trang trước (←)'),
          child: OutlinedButton.icon(style: big, onPressed: () => _do('show_prev'), icon: const Icon(Icons.chevron_left_rounded, size: 26), label: Text(tr('Trước'))),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: tr('Trang tiếp (→ / Space)'),
          child: FilledButton(
            style: big.copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 32))),
            onPressed: () => _do('show_next'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Tiếp'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right_rounded, size: 26),
            ]),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            running
                ? (paused
                    ? tool(Icons.play_arrow_rounded, tr('Tiếp tục'), 'A', () => _do('show_autopilot', {'action': 'resume'}), active: true)
                    : tool(Icons.pause_rounded, tr('Tạm dừng'), 'A', () => _do('show_autopilot', {'action': 'pause'}), active: true))
                : tool(Icons.play_circle_outline_rounded, tr('Tự chạy'), 'A', _autoStart),
            if (running) tool(Icons.stop_rounded, tr('Dừng tự động'), 'A', () => _do('show_autopilot', {'action': 'stop'})),
            tool(musicOn ? Icons.music_note_rounded : Icons.music_off_rounded, tr('Nhạc'), 'M', () => _do('show_music', {'on': !musicOn}), active: musicOn),
            tool(Icons.hourglass_top_rounded, tr('Màn chờ'), 'W', _scene == 'waiting' ? null : () => _do('show_goto', {'scene': 'waiting'})),
            tool(blanked ? Icons.tv_rounded : Icons.tv_off_rounded, blanked ? tr('Bật hình') : tr('Tắt hình'), 'B', _screens.isEmpty ? null : _blankAll,
                active: blanked),
          ]),
        ),
        IconButton(tooltip: tr('Phím tắt (?)'), icon: Icon(Icons.keyboard_outlined, color: pal.sub), onPressed: _keysHelp),
      ]),
    );
  }
}
