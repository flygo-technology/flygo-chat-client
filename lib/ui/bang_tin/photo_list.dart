// Bảng tin (điện thoại): ảnh của bài xếp dọc, tràn chiều ngang, đúng tỉ lệ (Sếp, 17/11). Chụm hai ngón hoặc bấm đúp
// một ảnh để phóng to xem chi tiết (kéo để di chuyển); thu nhỏ hết cỡ (hoặc bấm đúp lần nữa, nút X, nút quay lại) là
// về lại danh sách ảnh dọc, đúng chỗ đang cuộn. Bấm giữ ảnh: Lưu ảnh, Sao chép ảnh, Xem toàn màn hình.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/image_disk_cache.dart';
import '../../i18n/i18n.dart';
import '../clip.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart';
import 'gallery.dart';

/// Lớp phủ phóng to ảnh, bọc vùng có [PhotoColumn]. [builder] nhận `locked` = đang chụm / phóng to: danh sách bên
/// trong phải tắt cuộn (physics NeverScrollableScrollPhysics) để hai ngón không vừa cuộn vừa phóng.
class PhotoZoomScope extends StatefulWidget {
  const PhotoZoomScope({super.key, required this.api, required this.builder});
  final BangTinApi api;
  final Widget Function(BuildContext context, bool locked) builder;

  @override
  State<PhotoZoomScope> createState() => PhotoZoomScopeState();
}

class _Entry {
  _Entry(this.key, this.id, this.ids, this.index);
  final GlobalKey key;
  String id;
  List<String> ids;
  int index;
}

class PhotoZoomScopeState extends State<PhotoZoomScope> with SingleTickerProviderStateMixin {
  static const maxScale = 6.0;
  final _entries = <_Entry>[];
  final _pointers = <int, Offset>{};
  final _tc = TransformationController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _tween;
  VoidCallback? _afterAnim;

  /// Ảnh đang phóng to và khung của nó (toạ độ trong lớp phủ) lúc bắt đầu.
  _Entry? _zoom;
  Rect _rect = Rect.zero;

  /// Đang chụm bằng hai ngón đặt trên danh sách (lớp phủ không nhận được các ngón này, tự tính ma trận).
  bool _pinching = false;
  Offset _f0 = Offset.zero;
  double _s0 = 1;

  /// Đang phóng to (để kiểm thử).
  bool get zoomed => _zoom != null;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_tween != null) _tc.value = _tween!.value;
    });
    _anim.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      final f = _afterAnim;
      _afterAnim = null;
      f?.call();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _register(_Entry e) => _entries.add(e);
  void _unregister(_Entry e) => _entries.remove(e);

  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  Rect? _rectOf(_Entry e) {
    final b = e.key.currentContext?.findRenderObject() as RenderBox?;
    final me = _box;
    if (b == null || me == null || !b.attached) return null;
    return me.globalToLocal(b.localToGlobal(Offset.zero)) & b.size;
  }

  _Entry? _hit(Offset local) {
    for (final e in _entries) {
      if (_rectOf(e)?.contains(local) == true) return e;
    }
    return null;
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _open(_Entry e) {
    final r = _rectOf(e);
    if (r == null) return;
    setState(() => (_zoom = e, _rect = r));
  }

  void _close() {
    _anim.stop();
    _afterAnim = null;
    _pinching = false;
    _tc.value = Matrix4.identity();
    if (mounted) setState(() => _zoom = null);
  }

  void _animateTo(Matrix4 m, {VoidCallback? then}) {
    _tween = Matrix4Tween(begin: _tc.value.clone(), end: m).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _afterAnim = then;
    _anim.forward(from: 0);
  }

  /// Thu về cỡ gốc rồi trở lại danh sách ảnh dọc.
  void zoomOut() => _animateTo(Matrix4.identity(), then: _close);

  static Matrix4 _about(Offset from, Offset to, double s) => Matrix4.identity()
    ..translateByDouble(to.dx, to.dy, 0, 1)
    ..scaleByDouble(s, s, 1, 1)
    ..translateByDouble(-from.dx, -from.dy, 0, 1);

  /// Bấm đúp ảnh trong danh sách: phóng to 2,5 lần quanh chỗ bấm.
  void _doubleTap(_Entry e, Offset global) {
    final me = _box;
    if (me == null || _zoom != null) return;
    final p = me.globalToLocal(global);
    _open(e);
    _animateTo(_about(p, p, 2.5));
  }

  // Ngón tay trên danh sách (Listener không tranh cử cử chỉ: danh sách vẫn cuộn bằng một ngón như thường).
  void _down(PointerDownEvent ev) {
    final me = _box;
    if (me == null || _zoom != null) return;
    _pointers[ev.pointer] = me.globalToLocal(ev.position);
    if (_pointers.length != 2) return;
    final ps = _pointers.values.toList();
    final e = _hit(ps[0]) ?? _hit(ps[1]);
    if (e == null) return;
    _f0 = (ps[0] + ps[1]) / 2;
    _s0 = math.max((ps[0] - ps[1]).distance, 1);
    _pinching = true;
    _open(e);
  }

  void _move(PointerMoveEvent ev) {
    final me = _box;
    if (me == null || !_pointers.containsKey(ev.pointer)) return;
    _pointers[ev.pointer] = me.globalToLocal(ev.position);
    if (!_pinching || _pointers.length < 2) return;
    final ps = _pointers.values.take(2).toList();
    final s = ((ps[0] - ps[1]).distance / _s0).clamp(.7, maxScale);
    _tc.value = _about(_f0, (ps[0] + ps[1]) / 2, s);
  }

  void _up(PointerEvent ev) {
    _pointers.remove(ev.pointer);
    if (!_pinching || _pointers.length >= 2) return;
    _pinching = false;
    // Thả tay: chưa phóng to thì về danh sách; đang phóng to thì ở lại lớp phủ (kéo, chụm tiếp bằng InteractiveViewer).
    if (_scale <= 1.05) {
      zoomOut();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _interactionEnd(ScaleEndDetails _) {
    if (_scale <= 1.01) zoomOut();
  }

  @override
  Widget build(BuildContext context) {
    final z = _zoom;
    return PopScope(
      canPop: z == null,
      onPopInvokedWithResult: (did, _) {
        if (!did) zoomOut();
      },
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: Stack(
          children: [
            Positioned.fill(
              child: _ScopeData(state: this, child: widget.builder(context, z != null)),
            ),
            if (z != null) Positioned.fill(child: _layer(context, z)),
          ],
        ),
      ),
    );
  }

  Widget _layer(BuildContext context, _Entry z) => LayoutBuilder(
    builder: (context, c) {
      final size = c.biggest;
      // Ảnh chỉ hiện một phần (bị cuộn khuất): cho kéo tới cả phần khuất khi đã phóng to.
      final margin = EdgeInsets.fromLTRB(
        math.max(0, -_rect.left),
        math.max(0, -_rect.top),
        math.max(0, _rect.right - size.width),
        math.max(0, _rect.bottom - size.height),
      );
      return AnimatedBuilder(
        animation: _tc,
        builder: (context, child) {
          final dim = ((_scale - 1) / .4).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.black.withValues(alpha: .96 * dim)),
                ),
              ),
              Positioned.fill(child: child!),
              if (dim > .5)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 6,
                  right: 6,
                  child: Opacity(
                    opacity: (dim - .5) * 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoundButton(
                          icon: Icons.download_rounded,
                          tooltip: tr('Lưu ảnh'),
                          onTap: () => saveBangTinImages(context, widget.api, [z.id]),
                        ),
                        const SizedBox(width: 8),
                        _RoundButton(icon: Icons.close_rounded, tooltip: tr('Thu nhỏ'), onTap: zoomOut),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
        child: GestureDetector(
          key: const ValueKey('bt-photo-zoom'),
          onDoubleTap: zoomOut,
          onLongPress: () => _photoMenu(context, widget.api, z.ids, z.index),
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: maxScale,
            boundaryMargin: margin,
            clipBehavior: Clip.none,
            panEnabled: !_pinching,
            scaleEnabled: !_pinching,
            onInteractionEnd: _interactionEnd,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: _rect,
                    // Giải mã ảnh to hơn khung để phóng to vẫn nét; chưa xong thì hiện ảnh của danh sách (đã có sẵn).
                    child: Image(
                      image: sizedImage(context, widget.api.image(z.id), math.min(_rect.width * 3, 3000)),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      frameBuilder: (_, child, frame, sync) =>
                          sync || frame != null ? child : BangTinImage(api: widget.api, fileId: z.id, fit: BoxFit.contain),
                      errorBuilder: (_, _, _) => BangTinImage(api: widget.api, fileId: z.id, fit: BoxFit.contain),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ScopeData extends InheritedWidget {
  const _ScopeData({required this.state, required super.child});
  final PhotoZoomScopeState state;
  @override
  bool updateShouldNotify(_ScopeData old) => old.state != state;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white),
      onPressed: onTap,
    ),
  );
}

/// Bấm giữ ảnh: Lưu ảnh, Sao chép ảnh, Xem toàn màn hình (trình xem ảnh của chat, vuốt giữa các ảnh của bài).
Future<void> _photoMenu(BuildContext context, BangTinApi api, List<String> ids, int index) async {
  final messenger = ScaffoldMessenger.of(context);
  final v = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.download_rounded), title: Text(tr('Lưu ảnh')), onTap: () => Navigator.pop(ctx, 'save')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: Text(tr('Sao chép ảnh')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(
            leading: const Icon(Icons.fullscreen_rounded),
            title: Text(tr('Xem toàn màn hình')),
            onTap: () => Navigator.pop(ctx, 'view'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (v) {
    case 'save':
      await saveBangTinImages(context, api, [ids[index]]);
    case 'copy':
      try {
        final ok = await copyImageToClipboard(await api.bytes(ids[index]));
        messenger.showSnackBar(toast(Text(ok ? tr('Đã sao chép ảnh') : tr('Không sao chép được ảnh'))));
      } catch (e) {
        messenger.showSnackBar(toast(Text('$e')));
      }
    case 'view':
      await openBangTinGallery(context, api, ids, index);
  }
}

/// Tỉ lệ ảnh đã biết (rộng / cao), giữ qua các lần mở bài để danh sách không nhảy khi ảnh tải xong.
final _aspects = <String, double>{};

/// Các ảnh [ids] xếp dọc, tràn chiều ngang, cách nhau [gap]. Phải nằm trong [PhotoZoomScope].
/// [keys] (tuỳ chọn): khoá cho từng ảnh, để trang bài cuộn tới ảnh vừa bấm trong bảng tin.
class PhotoColumn extends StatelessWidget {
  const PhotoColumn({super.key, required this.api, required this.ids, this.gap = 4, this.keys, this.onAspect});
  final BangTinApi api;
  final List<String> ids;
  final double gap;
  final List<GlobalKey>? keys;

  /// Một ảnh vừa biết tỉ lệ (chiều cao của nó đổi).
  final VoidCallback? onAspect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < ids.length; i++)
        Padding(
          key: keys != null && i < keys!.length ? keys![i] : null,
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: _Photo(api: api, ids: ids, index: i, onAspect: onAspect),
        ),
    ],
  );
}

class _Photo extends StatefulWidget {
  const _Photo({required this.api, required this.ids, required this.index, this.onAspect});
  final BangTinApi api;
  final List<String> ids;
  final int index;
  final VoidCallback? onAspect;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  final _key = GlobalKey();
  late final _entry = _Entry(_key, widget.ids[widget.index], widget.ids, widget.index);
  PhotoZoomScopeState? _scope;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Offset _tapAt = Offset.zero;

  String get _id => widget.ids[widget.index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.dependOnInheritedWidgetOfExactType<_ScopeData>()?.state;
    if (s != _scope) {
      _scope?._unregister(_entry);
      _scope = s;
      s?._register(_entry);
    }
    _resolve();
  }

  @override
  void didUpdateWidget(_Photo old) {
    super.didUpdateWidget(old);
    _entry
      ..id = _id
      ..ids = widget.ids
      ..index = widget.index;
    if (old.ids[old.index] != _id) _resolve();
  }

  /// Đọc kích thước ảnh (giải mã nhỏ, cùng bộ nhớ đệm đĩa với ảnh) để giữ đúng tỉ lệ.
  void _resolve() {
    if (_aspects.containsKey(_id)) return;
    _stopListening();
    final id = _id;
    _stream = sizedImage(context, widget.api.image(id), 480).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      final a = info.image.width / math.max(info.image.height, 1);
      info.dispose();
      if (!mounted || _aspects[id] == a) return;
      setState(() => _aspects[id] = a);
      widget.onAspect?.call();
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  void _stopListening() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
  }

  @override
  void dispose() {
    _stopListening();
    _scope?._unregister(_entry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // Ảnh quá dọc: cao tối đa gần bằng màn hình, hiện trọn ảnh (không cắt).
        final maxH = MediaQuery.sizeOf(context).height * .85;
        final h = math.min(c.maxWidth / (_aspects[_id] ?? 4 / 3), maxH);
        return GestureDetector(
          onDoubleTapDown: (d) => _tapAt = d.globalPosition,
          onDoubleTap: () => _scope?._doubleTap(_entry, _tapAt),
          onLongPress: () => _photoMenu(context, widget.api, widget.ids, widget.index),
          child: ColoredBox(
            key: _key,
            color: pal.surface2,
            child: SizedBox(
              width: c.maxWidth,
              height: h,
              child: BangTinImage(api: widget.api, fileId: _id, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }
}
