// Bảng tin: ai đã xem / chưa xem, đã xác nhận / chưa xác nhận một bài (tác giả và quản trị Bảng tin).
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../common.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart';

/// Điện thoại: danh sách đã xem trong bottom sheet (Sếp).
Future<void> showReceiptsSheet(BuildContext context, BangTinApi api, String postId, String title) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      clipBehavior: Clip.antiAlias,
      builder: (c) => FractionallySizedBox(heightFactor: .85, child: BangTinReceiptsPage(api: api, postId: postId, title: title, onClose: () => Navigator.pop(c))),
    );

class BangTinReceiptsPage extends StatefulWidget {
    const BangTinReceiptsPage({super.key, required this.api, required this.postId, required this.title, this.onClose});
  final BangTinApi api;
  final String postId, title;

  /// Nằm trong cột phải / bottom sheet: nút đóng thay nút quay lại.
  final VoidCallback? onClose;

  @override
  State<BangTinReceiptsPage> createState() => _BangTinReceiptsPageState();
}

class _BangTinReceiptsPageState extends State<BangTinReceiptsPage> {
  Map<String, dynamic>? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/api/posts/${widget.postId}/receipts');
      if (mounted) setState(() => (_r = r, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static List<Map<String, dynamic>> _maps(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final r = _r;
    if (r == null) {
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(title: Text(tr('Đã xem')), automaticallyImplyLeading: widget.onClose == null, actions: [if (widget.onClose != null) IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: widget.onClose)]),
        body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: TextStyle(color: pal.sub))),
      );
    }
    final ack = r['require_ack'] == true;
    final tabs = <(String, List<Map<String, dynamic>>, bool)>[
      if (ack) (tr('Chưa xác nhận'), _maps(r['unacked']), false),
      if (ack) (tr('Đã xác nhận'), _maps(r['acked']), true),
      (tr('Chưa xem'), _maps(r['unread']), false),
      (tr('Đã xem'), _maps(r['read']), true),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          automaticallyImplyLeading: widget.onClose == null,
          actions: [if (widget.onClose != null) IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: widget.onClose)],
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Đã xem')),
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.sub)),
          ]),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: '${t.$1} (${t.$2.length})')]),
        ),
        body: Column(children: [
          if (ack && r['ack_deadline'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                Icon(Icons.event_outlined, size: 16, color: pal.sub),
                const SizedBox(width: 6),
                Text(tr('Hạn xác nhận: {0}', [bangTinTime((r['ack_deadline'] as num).toInt())]), style: TextStyle(color: pal.sub, fontSize: 13)),
              ]),
            ),
          Expanded(
            child: TabBarView(children: [
              for (final (_, people, timed) in tabs)
                RefreshIndicator(
                  onRefresh: _load,
                  child: people.isEmpty
                      ? ListView(children: [const SizedBox(height: 80), Center(child: Text(tr('Không có ai'), style: TextStyle(color: pal.sub)))])
                      : ListView.builder(
                          itemCount: people.length,
                          itemBuilder: (_, i) {
                            final p = people[i];
                            return ListTile(
                              leading: Avatar(userId: '${p['id']}', name: '${p['name']}', size: 36, status: false),
                              title: Text('${p['name']}'),
                              trailing: timed && p['at'] != null
                                  ? Text(bangTinTime((p['at'] as num).toInt()), style: TextStyle(color: pal.sub, fontSize: 12.5))
                                  : null,
                            );
                          },
                        ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
