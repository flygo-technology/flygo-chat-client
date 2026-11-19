import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';

// Sân khấu của cuộc họp (chủ trì / phó phòng), phần đầu của bảng "Quản lý cuộc họp": chọn một chế độ sân khấu, ngôi sao,
// khoá bố cục. Máy chủ lưu (layout {mode, stars, locked}) và mọi máy, kể cả TV, theo.
//   speaker = Tự động đưa lên sân khấu người trình chiếu (mặc định) · stars = Chỉ cho lên sân khấu người chỉ định ·
//   grid = Lưới. Đặt ngôi sao đầu tiên tự chuyển sang "chỉ người chỉ định" và chỉ ngôi sao được trình chiếu.

class MeetStageSection extends StatefulWidget {
  final CallService call;
  const MeetStageSection({super.key, required this.call});
  @override
  State<MeetStageSection> createState() => _MeetStageSectionState();
}

class _MeetStageSectionState extends State<MeetStageSection> {
  /// Phạm vi đang chỉnh: tv = màn hình phòng (TV / QR / hello), app = ứng dụng & khách.
  String _scope = 'tv';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final call = widget.call;
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final tv = _scope == 'tv';
        final lay = tv ? call.tvLayout : call.appLayout;
        final mode = '${lay['mode'] ?? (tv ? 'content' : 'speaker')}';
        final locked = lay['locked'] == true;
        final stars = call.roomStars;
        Future<void> run(Future<String?> f) async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final err = await f;
          if (err != null) messenger?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(err)));
        }

        Widget opt(String m, String t, String sub) => RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: m,
              title: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(sub, style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5)),
            );
        String nameOf(String id) {
          if (id.startsWith('device:') || id.startsWith('guest:')) return call.deviceNames[id] ?? id;
          return app.users[id]?.displayName ?? tr('Người dùng');
        }

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(tr('SÂN KHẤU (CHỌN MỘT)'), style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          // TV có thể chiếu kín màn hình; app / khách không phải lúc nào cũng muốn toàn màn hình: chỉnh riêng từng nơi.
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'tv', icon: const Icon(Icons.tv_rounded, size: 18), label: Text(tr('Màn hình phòng'))),
              ButtonSegment(value: 'app', icon: const Icon(Icons.phone_iphone_rounded, size: 18), label: Text(tr('Ứng dụng & khách'))),
            ],
            selected: {_scope},
            onSelectionChanged: (v) => setState(() => _scope = v.first),
          ),
          const SizedBox(height: 4),
          RadioGroup<String>(
            groupValue: mode == 'pin' ? 'stars' : mode,
            onChanged: (v) {
              if (v == null || v == mode) return;
              // "Chỉ người chỉ định" mà chưa có ngôi sao: chọn ngôi sao trước.
              if (v == 'stars' && stars.isEmpty) {
                _pickStar(context, app, call).then((id) {
                  if (id != null) run(call.setRoomLayout(stars: [id]));
                });
                return;
              }
              run(call.setRoomLayout(scope: _scope, mode: v));
            },
            child: Column(children: [
              if (tv) ...[
                opt('content', tr('Chỉ chiếu nội dung (mặc định)'),
                    tr('Màn hình chia sẻ / tài liệu / ngôi sao kín màn hình, không hiện ô người; không ai trình chiếu thì người đang nói')),
                opt('speaker', tr('Tự đưa người trình chiếu lên'), tr('Khung lớn kèm dải người')),
              ] else
                opt('speaker', tr('Tự đưa người trình chiếu lên (mặc định)'),
                    tr('Bài trình chiếu ở khung lớn, vẫn thấy dải người; mỗi người bấm để phóng to')),
              opt('stars', tr('Chỉ cho lên sân khấu người chỉ định'), tr('Chỉ ngôi sao lên sân khấu; người khác ở dải dưới, kể cả khi chia sẻ màn hình')),
              opt('grid', tr('Lưới'), tv ? tr('Mọi người bằng nhau') : tr('Mọi người bằng nhau, bài trình chiếu là một ô')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final id in stars)
                InputChip(
                  avatar: const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFD36B)),
                  label: Text(nameOf(id)),
                  onDeleted: () => run(call.setRoomLayout(stars: [for (final x in stars) if (x != id) x])),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(tr('Thêm ngôi sao')),
                onPressed: () async {
                  final id = await _pickStar(context, app, call);
                  if (id != null && !stars.contains(id)) run(call.setRoomLayout(stars: [...stars, id]));
                },
              ),
            ]),
          ),
          if (stars.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(tr('Đang có ngôi sao: chỉ ngôi sao (và chủ trì / phó phòng) được chia sẻ màn hình, trình chiếu tài liệu.'),
                  style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: locked,
            onChanged: (v) => run(call.setRoomLayout(scope: _scope, locked: v)),
            title: Text(tv ? tr('Khoá bố cục màn hình phòng') : tr('Khoá bố cục ứng dụng & khách'), style: const TextStyle(color: Colors.white)),
            subtitle: Text(tr('Không tự đổi cách xem trên máy'), style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(tr('TV chỉ chiếu nội dung, app hiện mọi người')),
              onPressed: () => run(call.setRoomLayout(stars: const [], tv: {'mode': 'content'}, app: {'mode': 'speaker'})),
            ),
          ),
        ]);
      },
    );
  }

  static Future<String?> _pickStar(BuildContext context, AppState app, CallService call) {
    final people = <String, String>{};
    for (final p in call.participants) {
      if (p.userId.isEmpty || people.containsKey(p.userId)) continue;
      people[p.userId] = p.userId.startsWith('device:') || p.userId.startsWith('guest:')
          ? (call.deviceNames[p.userId] ?? p.userId)
          : (app.users[p.userId]?.displayName ?? tr('Người dùng'));
    }
    final me = app.me;
    if (me != null) people.putIfAbsent(me.id, () => tr('{0} (Bạn)', [me.displayName]));
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(tr('Chọn ngôi sao'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          for (final e in people.entries)
            ListTile(
              leading: const Icon(Icons.star_border_rounded, color: Color(0xFFFFD36B)),
              title: Text(e.value, style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
  }
}
