import 'dart:async';

import 'package:flutter/material.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import 'pages_api.dart';
import 'types/all.dart';

// Danh sách loại trang của Họp (mới). Mỗi loại trang (có sẵn ở types/builtin.dart, thêm ở types/<loại>.dart, đăng ký trong
// types/all.dart) cho biết: tên, biểu tượng, cách tạo, cách hiện trên sân khấu, cách soạn trong bảng kéo lên.

/// Phần khởi tạo khi tạo trang mới.
class PageDraft {
  final String title;
  final Map<String, dynamic> content;
  final Map<String, dynamic> init;
  final int seconds;
  const PageDraft({required this.title, this.content = const {}, this.init = const {}, this.seconds = 0});
}

/// Những gì một loại trang cần để hiện / soạn một trang.
class PageCtx {
  final PageData data;
  final PagesApi api;
  final CallService call;
  /// Mình đang trình chiếu trang này trên sân khấu.
  final bool presenting;
  /// Đang hiện trên sân khấu (khung lớn) hay xem trước / soạn trong bảng.
  final bool onStage;
  /// Gửi một hành động của loại trang; lỗi hiện thông báo, phần xem tự cập nhật.
  final Future<void> Function(String action, [Map<String, dynamic> body]) act;
  /// Tải lại trang (sau khi sửa nội dung).
  final Future<void> Function() reload;
  const PageCtx({required this.data, required this.api, required this.call, required this.presenting, required this.onStage, required this.act, required this.reload});
  MeetPage get page => data.page;
  Map<String, dynamic> get view => data.view;
  /// Chủ trang / chủ trì / người trình chiếu: điều khiển được trang.
  bool get control => data.manage || presenting;
}

class PageTypeSpec {
  final String type;
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  /// Tạo trang mới (có thể hỏi người dùng); null = huỷ. Mặc định: chỉ tiêu đề.
  final Future<PageDraft?> Function(BuildContext context, CallService call)? create;
  /// Hiện trang (sân khấu, xem trước).
  final Widget Function(BuildContext context, PageCtx ctx) view;
  /// Soạn nội dung trong bảng kéo lên; null = chỉ sửa tiêu đề / thời lượng / công khai.
  final Widget Function(BuildContext context, PageCtx ctx)? editor;
  /// Thời lượng mặc định (giây) khi tự chạy.
  final int seconds;
  /// Ảnh xem trước riêng trên thẻ trang (page_thumb.dart); null = thu nhỏ phần [view] trên sân khấu. [data] null = chưa tải.
  final Widget Function(BuildContext context, CallService call, MeetPage page, PageData? data)? thumb;
  /// Trên sân khấu: trang tự vẽ nền kín khung (Chào mừng), thanh đầu / cuối của khung chung nổi lên trên.
  final bool stageBleed;
  /// Thanh cuối của khung sân khấu (tiến độ, số người trả lời…); null = mặc định (giờ còn lại, cách tham gia).
  final List<Widget> Function(BuildContext context, PageCtx ctx)? stageFooter;
  /// Trang đã vẽ theo bảng màu sân khấu (StageMetrics.themeOf). Chưa: ở chế độ Sáng, khung đặt trang trong một ô tối cho đọc được.
  final bool stageThemed;
  const PageTypeSpec({
    required this.type,
    required this.label,
    this.desc = '',
    required this.icon,
    required this.color,
    this.create,
    required this.view,
    this.editor,
    this.seconds = 0,
    this.thumb,
    this.stageBleed = false,
    this.stageFooter,
    this.stageThemed = false,
  });
}

final _types = <String, PageTypeSpec>{};
bool _ready = false;

/// Đăng ký một loại trang (gọi từ types/all.dart).
void registerPageType(PageTypeSpec s) => _types[s.type] = s;

List<PageTypeSpec> get pageTypes {
  if (!_ready) {
    _ready = true;
    registerAllPageTypes();
  }
  return _types.values.toList();
}

PageTypeSpec? pageTypeOf(String type) {
  pageTypes;
  return _types[type];
}

/// Trang chưa có loại trên máy này (app cũ hơn máy chủ).
Widget unknownPageView(PageCtx ctx) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(tr('Trang "{0}" cần bản app mới hơn để hiện.', [ctx.page.title]), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      ),
    );

/// Tải một trang (theo id, hoặc khoá sân khấu), theo dõi thay đổi (tin fx_page trong cuộc họp) và dựng bằng [builder].
class PageHost extends StatefulWidget {
  final CallService call;
  final String id;
  final String? stageKey;
  final bool onStage;
  final Widget Function(BuildContext context, PageCtx ctx, PageTypeSpec? spec) builder;
  const PageHost({super.key, required this.call, required this.id, this.stageKey, this.onStage = false, required this.builder});

  @override
  State<PageHost> createState() => _PageHostState();
}

class _PageHostState extends State<PageHost> {
  late final api = PagesApi(widget.call);
  PageData? _d;
  String? _err;
  StreamSubscription? _sub, _sse;
  Timer? _debounce;

  void _changed(int rev) {
    if (_d != null && rev <= _d!.rev) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  /// Ngoài cuộc họp của trang (app Bình chọn / Hỏi đáp, cuộc họp khác): theo dõi qua SSE thay cho tin fx_page.
  void _watch(MeetPage p) {
    final code = widget.call.meetingInfo?.code ?? '';
    final here = p.meeting != null && widget.call.channelId != null && (code.isEmpty || code == p.meeting);
    if (here || _sse != null || widget.call.myId().isEmpty) return;
    _sse = api.events(widget.id).listen(_changed);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.call.fxEvents.stream.listen((m) {
      if (m['t'] != 'fx_page' || m['page'] != widget.id) return;
      _changed((m['rev'] as num?)?.toInt() ?? 0);
    });
  }

  @override
  void didUpdateWidget(PageHost old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _d = null;
      _sse?.cancel();
      _sse = null;
      _load();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sse?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      PageData d;
      try {
        d = await api.get(widget.id);
      } on PagesError catch (e) {
        if (widget.stageKey == null || e.status != 404) rethrow;
        d = await api.byKey(widget.stageKey!);
      }
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
        if (widget.stageKey == null) _watch(d.page);
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _act(String action, [Map<String, dynamic> body = const {}]) async {
    try {
      final (v, rev) = await api.act(widget.id, action, body);
      if (mounted && _d != null) setState(() => _d = _d!.withView(v, rev));
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Center(
        child: _err != null
            ? Text(_err!, style: const TextStyle(color: Colors.white70))
            : const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final st = widget.call.roomStage;
    final presenting = st != null && st['page'] == d.page.id && st['presenter'] == widget.call.myId();
    final ctx = PageCtx(data: d, api: api, call: widget.call, presenting: presenting, onStage: widget.onStage, act: _act, reload: _load);
    return widget.builder(context, ctx, pageTypeOf(d.page.type));
  }
}
