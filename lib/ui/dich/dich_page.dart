import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../api/translate.dart';
import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../theme.dart';

/// Màn hình native của mini app "Dịch thuật" (manifest native.screen = "dich", app vn.flygo.dich).
const kDichScreen = 'dich';

/// Hàm dịch: [text] sang [to], trả về bản dịch và mã ngôn ngữ gốc đoán được (như [translateText]).
typedef DichTranslate = Future<({String text, String from})> Function(String text, String to);

/// Ngôn ngữ bên trái "Tự nhận diện" (dịch vụ dịch tự đoán ngôn ngữ gốc).
const kDichAuto = 'auto';

/// Giới hạn độ dài một lần dịch (như máy chủ, relay/translate.mjs).
const kDichMaxChars = 4000;

/// Tên các ngôn ngữ dịch vụ dịch nhận (cùng bộ với bản web), viết bằng chính ngôn ngữ đó.
const kDichLangNames = {
  'vi': 'Tiếng Việt',
  'en': 'English',
  'zh': '中文',
  'ko': '한국어',
  'ja': '日本語',
  'th': 'ไทย',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'ru': 'Русский',
};

/// Mở Dịch thuật: dịch bằng dịch vụ dịch dùng chung của máy chủ chat (`POST <trạm>/translate`, phiên chat), cùng
/// giới hạn lượt và nhật ký với nút "Dịch AI" trong chat.
Future<void> openDich(BuildContext context, MiniApp app) async {
  final tab = DeskTabScope.of(context);
  await Navigator.of(context).push(AppPageRoute(builder: (_) => DichPage(title: app.name)));
  // Đóng Dịch thuật trong một tab máy tính: tab về lại tên ứng dụng.
  tab?.onTitle?.call(null);
}

/// "Dịch thuật": hai ô sửa được, chọn ngôn ngữ trái / phải, đổi chiều. Ctrl + Enter (⌘ + Enter trên Mac) hoặc nút
/// Dịch thì dịch sang ô kia; Enter thường là xuống dòng. Dán vào ô nào thì ô kia tự dịch. Màn rộng: hai ô trái phải;
/// điện thoại: ô trên, ô dưới.
class DichPage extends StatefulWidget {
  final String title;
  /// Chỉ cho kiểm thử: thay hàm dịch thật / danh sách ngôn ngữ của máy chủ.
  final DichTranslate? translate;
  final Future<List<String>> Function()? langs;
  const DichPage({super.key, this.title = 'Dịch thuật', this.translate, this.langs});

  @override
  State<DichPage> createState() => _DichPageState();
}

/// Một ô: trái (L) hoặc phải (R).
class _Pane {
  final ctrl = TextEditingController();
  final focus = FocusNode();
  /// Nội dung lần trước (để biết vừa chèn bao nhiêu chữ).
  String last = '';
  /// Lúc vừa bấm dán (Ctrl/⌘ + V, nút Dán của menu): thay đổi kế tiếp là nội dung dán.
  DateTime? pasteAt;
  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}

class _DichPageState extends State<DichPage> with TickerProviderStateMixin {
  final _p = {'L': _Pane(), 'R': _Pane()};
  late final _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final _fade = {
    'L': AnimationController(vsync: this, duration: const Duration(milliseconds: 350), value: 1),
    'R': AnimationController(vsync: this, duration: const Duration(milliseconds: 350), value: 1),
  };
  List<String> _langs = kDichLangNames.keys.toList();
  String _from = kDichAuto, _to = 'en';
  /// Ô đang được dịch từ đó (null = không dịch).
  String? _busy;
  int _seq = 0;
  /// Ngôn ngữ gốc dịch vụ đoán được ở lần dịch gần nhất từ ô trái khi trái là "Tự nhận diện".
  String _detected = '';
  String? _error;
  /// Đang tự đặt nội dung (kết quả dịch, đổi chiều, xoá): không coi là người dùng gõ / dán.
  bool _quiet = false;
  double _turns = 0;

  static const _prefKey = 'dich_pair';
  static const _err = Color(0xFFE5484D);

  static String _other(String k) => k == 'L' ? 'R' : 'L';
  static bool get _mac => !kIsWeb && (Platform.isMacOS || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _to = appLanguage.value == 'en' ? 'vi' : 'en';
    for (final k in _p.keys) {
      _p[k]!.ctrl.addListener(() => _onChanged(k));
    }
    final app = context.read<AppState>();
    app.uiPref<Map>(_prefKey).then((m) {
      if (!mounted || m == null) return;
      final from = '${m['from'] ?? ''}', to = '${m['to'] ?? ''}';
      setState(() {
        if (from == kDichAuto || _langs.contains(from)) _from = from;
        if (_langs.contains(to)) _to = to;
      });
    });
    (widget.langs ?? translateLangs)().then((l) {
      if (!mounted || l.isEmpty) return;
      setState(() {
        _langs = l;
        if (_from != kDichAuto && !l.contains(_from)) _from = kDichAuto;
        if (!l.contains(_to)) _to = l.contains('en') ? 'en' : l.first;
      });
    });
  }

  @override
  void dispose() {
    for (final p in _p.values) {
      p.dispose();
    }
    _shine.dispose();
    for (final c in _fade.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _savePair() => context.read<AppState>().setUiPref(_prefKey, {'from': _from, 'to': _to});

  void _set(String k, String text) {
    _quiet = true;
    _p[k]!.ctrl.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _p[k]!.last = text;
    _quiet = false;
  }

  void _onChanged(String k) {
    final p = _p[k]!;
    final now = p.ctrl.value;
    if (now.text == p.last) return;
    final added = now.text.length - p.last.length;
    p.last = now.text;
    if (_quiet) return;
    // Dán: vừa bấm dán (phím tắt, menu), hoặc bàn phím điện thoại chèn một khối dài một lần (gợi ý bảng nhớ tạm).
    final pasted = (p.pasteAt != null && DateTime.now().difference(p.pasteAt!) < const Duration(seconds: 2)) ||
        (added >= 25 && !now.composing.isValid);
    p.pasteAt = null;
    setState(() {});
    if (pasted && now.text.trim().isNotEmpty) Future.microtask(() => _translate(k));
  }

  /// Ngôn ngữ đích khi dịch từ ô [k] sang ô kia. Trái là "Tự nhận diện": dịch từ phải sang trái dùng ngôn ngữ vừa
  /// nhận diện, chưa có thì tiếng Việt (hoặc tiếng Anh nếu phải là tiếng Việt).
  String _target(String k) {
    if (k == 'L') return _to;
    if (_from != kDichAuto) return _from;
    if (_langs.contains(_detected) && _detected != _to) return _detected;
    return _to == 'vi' ? 'en' : 'vi';
  }

  Future<void> _translate(String k) async {
    final text = _p[k]!.ctrl.text.trim();
    if (text.isEmpty || _busy != null) return;
    if (text.length > kDichMaxChars) {
      setState(() => _error = tr('Tối đa {0} ký tự mỗi lần dịch.', [kDichMaxChars]));
      return;
    }
    final app = context.read<AppState>();
    // Nội dung gửi tới dịch vụ AI: hỏi đồng ý như nút "Dịch AI" (bản kiểm thử không hỏi).
    if (widget.translate == null && app.aiConsent != true && !await app.ensureAiConsent()) return;
    if (!mounted) return;
    final seq = ++_seq, dst = _other(k), to = _target(k);
    setState(() {
      _busy = k;
      _error = null;
    });
    _shine.repeat();
    try {
      final fn = widget.translate ?? (t, to) => translateText(app.token, t, to, myId: app.me?.id ?? '');
      final r = await fn(text, to);
      if (!mounted || seq != _seq) return;
      _set(dst, r.text.trim());
      _fade[dst]!.forward(from: 0);
      setState(() {
        if (k == 'L' && r.from.isNotEmpty) _detected = r.from;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = dichErrorText(e));
    } finally {
      if (mounted && seq == _seq) {
        _shine.stop();
        setState(() => _busy = null);
      }
    }
  }

  /// Đổi chiều: đổi hai ngôn ngữ và nội dung hai ô.
  void _swap() {
    final f = _from == kDichAuto ? (_langs.contains(_detected) ? _detected : (_to == 'vi' ? 'en' : 'vi')) : _from;
    final l = _p['L']!.ctrl.text, r = _p['R']!.ctrl.text;
    setState(() {
      _from = _to;
      _to = f;
      _detected = '';
      _error = null;
      _turns += .5;
    });
    _set('L', r);
    _set('R', l);
    _savePair();
  }

  void _clear(String k) {
    _set(k, '');
    setState(() {});
    _p[k]!.focus.requestFocus();
  }

  Future<void> _copy(String k) async {
    final t = _p[k]!.ctrl.text;
    if (t.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: t));
    messenger.showSnackBar(toast(Text(tr('Đã sao chép'))));
  }

  String _langName(String c) => c == kDichAuto ? tr('Tự nhận diện') : kDichLangNames[c] ?? c;

  Widget _langPicker(Pal pal, String k, {bool phone = false}) {
    final source = k == 'L', value = source ? _from : _to;
    final auto = source && value == kDichAuto && kDichLangNames.containsKey(_detected);
    final label = auto ? '${_langName(kDichAuto)} · ${kDichLangNames[_detected]}' : _langName(value);
    return PopupMenuButton<String>(
      key: ValueKey('dich-lang-$k'),
      tooltip: source ? tr('Ngôn ngữ bên trái') : tr('Ngôn ngữ bên phải'),
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220, maxHeight: 460),
      onSelected: (v) {
        setState(() {
          if (source) {
            _from = v;
            _detected = '';
          } else {
            _to = v;
          }
          _error = null;
        });
        _savePair();
      },
      itemBuilder: (_) => [
        for (final c in [if (source) kDichAuto, ..._langs])
          PopupMenuItem(
            value: c,
            height: 44,
            child: Row(children: [
              SizedBox(width: 26, child: c == value ? Icon(Icons.check_rounded, size: 18, color: pal.accent) : null),
              Flexible(child: Text(_langName(c), overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
      child: LayoutBuilder(builder: (context, c) => Container(
        height: 48,
        padding: EdgeInsets.only(left: phone ? 12 : 16, right: phone ? 6 : 10),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
        child: Row(children: [
          // Ô hẹp (điện thoại): "Tự nhận diện · Tiếng Việt" không vừa, chỉ hiện ngôn ngữ đã nhận diện kèm biểu tượng.
          if (auto && c.maxWidth < 240) ...[
            Icon(Icons.auto_awesome_rounded, size: 16, color: pal.accent),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(auto && c.maxWidth < 240 ? kDichLangNames[_detected]! : label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: phone ? 15 : 15.5, fontWeight: FontWeight.w600, color: pal.text)),
          ),
          Icon(Icons.expand_more_rounded, size: 20, color: pal.sub),
        ]),
      )),
    );
  }

  /// Menu chuột phải / giữ chữ: nút Dán còn đánh dấu "vừa dán" để ô kia tự dịch.
  Widget _menu(String k, BuildContext context, EditableTextState s) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: s.contextMenuAnchors,
        buttonItems: [
          for (final i in s.contextMenuButtonItems)
            if (i.type == ContextMenuButtonType.paste)
              i.copyWith(onPressed: () {
                _p[k]!.pasteAt = DateTime.now();
                i.onPressed?.call();
              })
            else
              i,
        ],
      );

  Widget _pane(Pal pal, String k, {required bool wide, required bool phone}) {
    final p = _p[k]!, n = p.ctrl.text.length, over = n > kDichMaxChars, has = p.ctrl.text.trim().isNotEmpty;
    final loading = _busy == _other(k), going = _busy == k;
    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final hw = HardwareKeyboard.instance, mod = hw.isControlPressed || hw.isMetaPressed;
        if (mod && (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _translate(k);
          return KeyEventResult.handled;
        }
        // Ctrl/⌘ + V: để ô chữ tự dán như thường, chỉ đánh dấu để ô kia tự dịch.
        if (mod && e.logicalKey == LogicalKeyboardKey.keyV) p.pasteAt = DateTime.now();
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: ValueKey('dich-$k'),
        controller: p.ctrl,
        focusNode: p.focus,
        autofocus: k == 'L' && !phone,
        minLines: phone ? 4 : 6,
        maxLines: phone ? 8 : 10,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        contextMenuBuilder: (c, s) => _menu(k, c, s),
        style: TextStyle(fontSize: 17, height: 1.45, color: loading ? Colors.transparent : pal.text),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          hintText: loading ? '' : (k == 'L' ? tr('Nhập hoặc dán nội dung') : tr('Bản dịch (cũng nhập hoặc dán được)')),
          hintStyle: TextStyle(fontSize: 17, color: pal.sub),
        ),
      ),
    );
    // Giữ font của theme (Linux đặt Noto Sans): textStyle của nút thay hẳn kiểu chữ mặc định.
    final label = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    final arrow = wide ? (k == 'L' ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded) : (k == 'L' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);
    final small = TextButton.styleFrom(
      foregroundColor: pal.sub,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: const StadiumBorder(),
      textStyle: label.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    );
    Widget btn(Key key, IconData icon, String label, VoidCallback? onTap) => Tooltip(
          message: label,
          child: phone
              ? TextButton(key: key, style: small, onPressed: onTap, child: Icon(icon, size: 20))
              : TextButton.icon(key: key, style: small, onPressed: onTap, icon: Icon(icon, size: 20), label: Text(label)),
        );
    final bar = Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.divider))),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      child: Row(children: [
        Expanded(
          child: Text('$n / $kDichMaxChars',
              style: TextStyle(fontSize: 12.5, color: over ? _err : pal.sub, fontWeight: over ? FontWeight.w600 : null)),
        ),
        if (n > 0) btn(ValueKey('dich-clear-$k'), Icons.close_rounded, tr('Xoá'), () => _clear(k)),
        btn(ValueKey('dich-copy-$k'), Icons.copy_rounded, tr('Sao chép'), has ? () => _copy(k) : null),
        const SizedBox(width: 4),
        Tooltip(
          message: k == 'L' ? tr('Dịch sang ô bên kia') : tr('Dịch ngược lại'),
          child: FilledButton.icon(
            key: ValueKey('dich-go-$k'),
            style: FilledButton.styleFrom(
              backgroundColor: pal.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: pal.accent.withValues(alpha: .4),
              disabledForegroundColor: Colors.white.withValues(alpha: .8),
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
              textStyle: label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onPressed: _busy != null || !has || over ? null : () => _translate(k),
            icon: going
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(arrow, size: 18),
            label: Text(tr('Dịch')),
          ),
        ),
      ]),
    );
    return AnimatedBuilder(
      animation: p.focus,
      builder: (context, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.focus.hasFocus ? pal.accent : pal.divider),
          boxShadow: p.focus.hasFocus ? [BoxShadow(color: pal.accent.withValues(alpha: .12), spreadRadius: 3)] : const [],
        ),
        child: child,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Stack(children: [
          FadeTransition(
            opacity: _fade[k]!,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(CurvedAnimation(parent: _fade[k]!, curve: Curves.easeOut)),
              child: field,
            ),
          ),
          if (loading) Positioned.fill(child: IgnorePointer(child: _Shimmer(anim: _shine, color: pal.accent))),
        ]),
        bar,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final phone = !isDesktop && MediaQuery.sizeOf(context).shortestSide < 600;
    final keys = isDesktop || !phone;
    final note = keys
        ? tr('{0} + Enter để dịch sang ô kia · Dán vào ô nào, ô kia tự dịch', [_mac ? '⌘' : 'Ctrl'])
        : tr('Dán vào ô nào, ô kia tự dịch');
    final detected = _from == kDichAuto && kDichLangNames.containsKey(_detected) ? '${tr('Nhận diện: {0}', [kDichLangNames[_detected]!])} · ' : '';
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 720;
          final left = _pane(pal, 'L', wide: wide, phone: phone), right = _pane(pal, 'R', wide: wide, phone: phone);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: _langPicker(pal, 'L', phone: phone)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: phone ? 4 : 8),
                      child: AnimatedRotation(
                        turns: _turns,
                        duration: const Duration(milliseconds: 250),
                        child: IconButton(
                          key: const ValueKey('dich-swap'),
                          tooltip: tr('Đổi chiều'),
                          style: IconButton.styleFrom(backgroundColor: pal.chipSelBg, fixedSize: const Size(48, 48)),
                          icon: Icon(Icons.swap_horiz_rounded, color: pal.accentText),
                          onPressed: _busy != null ? null : _swap,
                        ),
                      ),
                    ),
                    Expanded(child: _langPicker(pal, 'R', phone: phone)),
                  ]),
                  const SizedBox(height: 12),
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: left),
                      const SizedBox(width: 12),
                      Expanded(child: right),
                    ])
                  else ...[
                    left,
                    const SizedBox(height: 12),
                    right,
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _error ?? '$detected$note',
                    key: const ValueKey('dich-note'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: _error != null ? _err : pal.sub, fontWeight: _error != null ? FontWeight.w600 : null),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Hiệu ứng đang dịch trên ô đích: vệt sáng chạy ngang + ba chấm nhấp nhô ở góc trên.
class _Shimmer extends StatelessWidget {
  final Animation<double> anim;
  final Color color;
  const _Shimmer({required this.anim, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value;
          return Stack(children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 4 * t - 1.5, -.3),
                    end: Alignment(-1 + 4 * t, .3),
                    colors: [Colors.transparent, color.withValues(alpha: .10), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 20,
              child: Row(children: [
                for (var i = 0; i < 3; i++)
                  Builder(builder: (_) {
                    // Mỗi chấm lệch pha 0.15 chu kỳ: sáng dần + nhô lên rồi về.
                    final ph = ((t - i * .15) % 1 + 1) % 1, up = ph < .4 ? ph / .4 : (ph < .8 ? (.8 - ph) / .4 : 0.0);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Transform.translate(
                        offset: Offset(0, -4 * up),
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: color.withValues(alpha: .25 + .75 * up), shape: BoxShape.circle),
                        ),
                      ),
                    );
                  }),
              ]),
            ),
          ]);
        },
      );
}

/// Lỗi dịch dễ hiểu: hết lượt (429), quá dài (413), mất mạng…
String dichErrorText(Object e) {
  final s = '$e', low = s.toLowerCase();
  if (s.contains('429') || low.contains('rate') || low.contains('limit')) {
    return tr('Bạn đã dịch quá nhiều trong thời gian ngắn. Đợi một lát rồi thử lại.');
  }
  if (s.contains('413') || low.contains('too long') || low.contains('too large')) {
    return tr('Nội dung quá dài. Hãy chia nhỏ rồi dịch từng phần.');
  }
  if (e is TimeoutException || s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('Connection')) {
    return tr('Không kết nối được. Kiểm tra mạng rồi thử lại.');
  }
  final msg = s.replaceFirst(RegExp(r'^(HttpException|Exception|Bad state):\s*'), '').trim();
  return msg.isEmpty ? tr('Dịch không thành công. Thử lại sau.') : tr('Dịch không thành công: {0}', [msg]);
}
