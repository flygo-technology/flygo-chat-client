import 'package:flutter/material.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Nhãn trên tin người dùng gửi trong lúc trợ lý đang làm (runner 0.7.27+, đọc từ cảm xúc của bot trên tin):
/// ⏳ hourglass_flowing_sand = "Đã vào hàng chờ" (chưa đọc), 🔀 twisted_rightwards_arrows = "Đã điều hướng" (agent đã đọc, chèn vào lượt).
const kQueuedEmoji = 'hourglass_flowing_sand';
const kSteeredEmoji = 'twisted_rightwards_arrows';

enum SteerState { queued, steered }

bool _byBot(AppState app, MmPost post, String emoji) =>
    (post.reactions[emoji] ?? const []).any((u) => app.users[u]?.isBot == true || app.isMyBot(u));

/// Trạng thái hàng chờ của [post] (chỉ tin của người, không phải tin của bot); null = không có nhãn.
SteerState? steerStateOf(AppState app, MmPost post) {
  if (app.users[post.userId]?.isBot == true) return null;
  if (_byBot(app, post, kSteeredEmoji)) return SteerState.steered;
  if (_byBot(app, post, kQueuedEmoji)) return SteerState.queued;
  return null;
}

/// Bỏ cảm xúc nhãn hàng chờ của bot khỏi dải cảm xúc (đã hiện thành nhãn ở đầu tin).
Map<String, List<String>> withoutSteerReactions(AppState app, MmPost post, Map<String, List<String>> reactions) {
  if (!reactions.containsKey(kQueuedEmoji) && !reactions.containsKey(kSteeredEmoji)) return reactions;
  final out = Map.of(reactions);
  for (final e in const [kQueuedEmoji, kSteeredEmoji]) {
    final people = (out[e] ?? const <String>[]).where((u) => !(app.users[u]?.isBot == true || app.isMyBot(u))).toList();
    if (people.isEmpty) {
      out.remove(e);
    } else {
      out[e] = people;
    }
  }
  return out;
}

/// Nhãn nhỏ ở đầu tin: "Đã vào hàng chờ" / "Đã điều hướng".
class SteerLabel extends StatelessWidget {
  final SteerState state;
  const SteerLabel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final queued = state == SteerState.queued;
    final color = queued ? pal.sub : pal.accentText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        key: ValueKey(queued ? 'steer-queued' : 'steer-steered'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(queued ? Icons.schedule_rounded : Icons.alt_route_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(queued ? tr('Đã vào hàng chờ') : tr('Đã điều hướng'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
