import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import '../../../state/app_state.dart';
import 'fx_api.dart';

// Báo cáo tham dự (chủ trì / phó phòng): ai vào / ra lúc nào, ở bao lâu, ai vắng. Họp xong Thư ký Họp tự nhắn riêng cho
// chủ trì; trong lúc họp xem ở đây (tính đến hiện tại), gửi bảng vào chat của cuộc họp hoặc sao chép.

String _hhmm(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Future<void> showAttendance(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AttendanceSheet(call: call),
    );

class _AttendanceSheet extends StatefulWidget {
  final CallService call;
  const _AttendanceSheet({required this.call});
  @override
  State<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends State<_AttendanceSheet> {
  Map<String, dynamic>? _rep;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await fxRequest(widget.call, 'GET', '/attendance');
      if (mounted) {
        setState(() {
          _rep = (j['report'] as Map?)?.cast<String, dynamic>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<String?> _markdown() async {
    try {
      return (await fxRequest(widget.call, 'GET', '/attendance?md=1'))['markdown'] as String?;
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
      return null;
    }
  }

  Future<void> _send() async {
    final ch = widget.call.channelId, md = await _markdown();
    if (ch == null || md == null || !mounted) return;
    await context.read<AppState>().send(ch, md);
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Đã gửi báo cáo vào chat của cuộc họp'))));
  }

  Future<void> _copy() async {
    final md = await _markdown();
    if (md == null) return;
    await Clipboard.setData(ClipboardData(text: md));
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Đã sao chép báo cáo'))));
  }

  @override
  Widget build(BuildContext context) {
    final rep = _rep;
    final rows = [for (final r in (rep?['rows'] as List? ?? const [])) (r as Map).cast<String, dynamic>()];
    final present = rows.where((r) => r['present'] == true).length;
    const head = TextStyle(color: Colors.white54, fontSize: 12);
    const cell = TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Báo cáo tham dự'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            if (rep != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Text(
                  tr('{0} phút · {1}/{2} người tham dự · tính đến bây giờ', [rep['minutes'], present, rows.length]),
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
              ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)))
            else if (rep == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Chưa có dữ liệu tham dự cho cuộc họp này.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
              )
            else ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Table(
                    columnWidths: const {0: FlexColumnWidth(2.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1.2)},
                    children: [
                      TableRow(children: [for (final h in [tr('Người'), tr('Vào'), tr('Ra'), tr('Thời lượng')]) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(h, style: head))]),
                      for (final r in rows)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              [
                                r['name'] as String? ?? '',
                                if (r['kind'] == 'guest') tr('(khách)'),
                                if (r['kind'] == 'device') tr('(thiết bị)'),
                              ].join(' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: cell,
                            ),
                          ),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(_hhmm((r['first_join'] as num?)?.toInt() ?? 0), style: cell)),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(_hhmm((r['last_leave'] as num?)?.toInt() ?? 0), style: cell)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: r['present'] == true
                                ? Text(tr('{0} phút', [r['minutes']]), style: cell)
                                : Text(tr('Vắng'), style: const TextStyle(color: Color(0xFFF28B82), fontSize: 13)),
                          ),
                        ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(tr('Họp xong, Thư ký Họp sẽ nhắn riêng báo cáo đầy đủ cho chủ trì.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: _send, icon: const Icon(Icons.send, size: 18), label: Text(tr('Gửi vào chat'))),
                OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy, size: 18), label: Text(tr('Sao chép'))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
