import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';

// Sân khấu của cuộc họp (chủ trì / phó phòng), phần đầu của bảng "Quản lý cuộc họp": chọn một chế độ sân khấu, ngôi sao,
// khoá bố cục. Máy chủ lưu (layout {mode, stars, locked}) và mọi máy, kể cả TV, theo.
//   speaker = Tự động đưa lên sân khấu người trình chiếu (mặc định) · stars = Chỉ cho lên sân khấu người chỉ định ·
//   grid = Lưới. Đặt ngôi sao đầu tiên tự chuyển sang "chỉ người chỉ định" và chỉ ngôi sao được trình chiếu.

class MeetStageSection extends StatelessWidget {
  final CallService call;
  const MeetStageSection({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final mode = '${call.roomLayout['mode'] ?? 'speaker'}';
        final locked = call.roomLayout['locked'] == true;
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
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(tr('SÂN KHẤU (CHỌN MỘT)'), style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
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
              run(call.setRoomLayout(mode: v));
            },
            child: Column(children: [
              opt('speaker', tr('Tự động đưa lên sân khấu người trình chiếu (mặc định)'),
                  tr('Ai chia sẻ màn hình / trình chiếu tài liệu thì lên đầu (mới nhất trước)')),
              opt('stars', tr('Chỉ cho lên sân khấu người chỉ định'), tr('Chỉ ngôi sao lên sân khấu; người khác ở dải dưới, kể cả khi chia sẻ màn hình')),
              opt('grid', tr('Lưới'), tr('Mọi người bằng nhau')),
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
            onChanged: (v) => run(call.setRoomLayout(locked: v)),
            title: Text(tr('Khoá bố cục'), style: const TextStyle(color: Colors.white)),
            subtitle: Text(tr('Mọi người không tự đổi cách xem trên máy mình'), style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5)),
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
