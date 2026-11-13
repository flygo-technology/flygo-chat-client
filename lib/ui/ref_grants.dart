import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'ref_picker.dart' show RefItem;
import 'schedules_view.dart' show openChatWith;
import 'sub_channel.dart' show openPrivateThread;
import 'theme.dart';

// Vé tag chat / luồng cho trợ lý (props.flygo_refs) — gửi tin không chờ trạm đẩy:
// app tự sinh grant_id + ref_id, gửi tin kèm vé ngay, đồng thời xin trạm cấp (POST /ref/grants với đúng các id đó).
// Runner đọc vé trong tin như cũ; trạm chờ vé đang cấp nếu bot hỏi sớm. Cấp lỗi: chip trên tin báo lỗi, bấm để thử lại
// (cùng grant_id, trạm trả về đúng vé nếu đã cấp).

enum GrantStatus { pending, ok, failed }

class GrantJob {
  final String token;
  final Map<String, dynamic> body;
  GrantStatus status = GrantStatus.pending;
  String? error;
  int? expiresAt;
  GrantJob(this.token, this.body);
}

typedef GrantPoster = Future<Map<String, dynamic>> Function(String token, Map<String, dynamic> body);

final _rnd = Random.secure();

/// Id ngẫu nhiên 16 ký tự base64url (đủ cho grant_id / ref_id của trạm: 12..32 ký tự).
String newRefId() => base64Url.encode(List.generate(12, (_) => _rnd.nextInt(256))).replaceAll('=', '');

class RefGrants {
  RefGrants._();

  /// Gọi trạm đẩy; kiểm thử thay bằng hàm giả.
  static GrantPoster poster = _httpPost;
  static final _jobs = <String, GrantJob>{};

  /// Tăng mỗi khi trạng thái một vé đổi (chip trên tin nghe để vẽ lại).
  static final version = ValueNotifier<int>(0);
  static GrantJob? job(String grantId) => _jobs[grantId];

  /// Vé cho từng trợ lý: trả về props.flygo_refs NGAY (không chờ mạng); trạm cấp chạy nền.
  static Map<String, dynamic> start(String token, List<MmUser> bots, List<RefItem> refs, int ttl, bool write,
      {String? server}) {
    final exp = DateTime.now().millisecondsSinceEpoch + ttl * 1000;
    final grants = <Map<String, dynamic>>[];
    for (final b in bots) {
      final gid = newRefId();
      final items = [
        for (final r in refs)
          {'ref_id': newRefId(), 'kind': r.kind, 'channel_id': r.channelId, 'root_id': ?r.rootId, 'name': r.name},
      ];
      _jobs[gid] = GrantJob(token, {
        'grant_id': gid,
        'bot_id': b.id,
        'ttl_sec': ttl,
        'write': write,
        'refs': [
          for (final it in items) {'ref_id': it['ref_id'], 'channel_id': it['channel_id'], 'root_id': ?it['root_id']},
        ],
      });
      grants.add({'grant_id': gid, 'expires_at': exp, 'write': write, 'server': server ?? kServerUrl, 'bot_id': b.id, 'items': items});
      unawaited(_run(gid));
    }
    return grants.length == 1 ? grants.first : {'grants': grants};
  }

  /// Xin lại vé lỗi (cùng grant_id).
  static Future<void> retry(String grantId) => _run(grantId);

  static Future<void> _run(String gid) async {
    final j = _jobs[gid];
    if (j == null) return;
    j
      ..status = GrantStatus.pending
      ..error = null;
    version.value++;
    try {
      final r = await poster(j.token, j.body);
      // Trạm bản cũ bỏ qua grant_id của app: vé trong tin không dùng được.
      if (r['grant_id'] != gid) throw Exception(tr('Trạm đẩy chưa cập nhật'));
      j
        ..expiresAt = (r['expires_at'] as num?)?.toInt()
        ..status = GrantStatus.ok;
    } catch (e) {
      j
        ..status = GrantStatus.failed
        ..error = '$e'.replaceFirst('Exception: ', '');
    }
    version.value++;
  }

  static Future<Map<String, dynamic>> _httpPost(String token, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('${pushUrlFor(kServerUrl)}/ref/grants'),
            headers: {
              'Authorization': 'Bearer $token',
              'X-MM-Server': kServerUrl,
              'Content-Type': 'application/json',
              'User-Agent': kUserAgent,
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    final j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'ref/grants ${r.statusCode}');
    return j;
  }
}

/// Một chat / luồng đã cấp cho trợ lý (gộp các vé của nhiều trợ lý trong cùng tin).
class GrantChipData {
  final String kind;
  final String channelId;
  final String? rootId;
  final String name;
  final bool write;
  final int expiresAt;
  final List<String> grantIds;
  const GrantChipData(this.kind, this.channelId, this.rootId, this.name, this.write, this.expiresAt, this.grantIds);
}

/// Đọc props.flygo_refs của tin: {grant_id, …, items} hoặc {grants:[…]} (có thể là chuỗi JSON).
List<GrantChipData> grantChipsOf(Map<String, dynamic> props) {
  var raw = props['flygo_refs'];
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (raw is! Map) return const [];
  final grants = raw['grants'] is List ? (raw['grants'] as List) : [raw];
  final out = <String, GrantChipData>{};
  for (final g in grants) {
    if (g is! Map || g['items'] is! List) continue;
    final gid = '${g['grant_id'] ?? ''}';
    final exp = (RefGrants.job(gid)?.expiresAt) ?? (g['expires_at'] as num?)?.toInt() ?? 0;
    for (final it in g['items'] as List) {
      if (it is! Map || it['channel_id'] is! String) continue;
      final root = (it['root_id'] as String?)?.isNotEmpty == true ? it['root_id'] as String : null;
      final key = '${it['channel_id']}/${root ?? ''}';
      final old = out[key];
      out[key] = GrantChipData(
        '${it['kind'] ?? (root != null ? 'thread' : 'chat')}',
        it['channel_id'] as String,
        root,
        '${it['name'] ?? it['channel_id']}',
        (old?.write ?? false) || g['write'] == true,
        old == null ? exp : min(old.expiresAt, exp),
        [...?old?.grantIds, if (gid.isNotEmpty) gid],
      );
    }
  }
  return out.values.toList();
}

/// Chip phía trên tin có tag: chat / luồng nào đã cấp cho trợ lý, quyền gì, tới khi nào. Bấm để mở chat / luồng đó.
/// Danh sách trong props (List, hoặc chuỗi JSON từ client khác).
List<Map> _propList(Object? raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  return raw is List ? [for (final x in raw) if (x is Map) x] : const [];
}

/// Phiên được nối A2A vào tin (props.flygo_a2a_peers).
List<Map> peerChipsOf(Map<String, dynamic> props) => [for (final p in _propList(props['flygo_a2a_peers'])) if (p['session_id'] is String) p];

/// Người được tag bằng nút @ (props.flygo_tag_people).
List<Map> peopleChipsOf(Map<String, dynamic> props) => [for (final p in _propList(props['flygo_tag_people'])) if (p['username'] is String) p];

/// Chip tag phía trên tin: chat / luồng đã cấp (flygo_refs), phiên được nối A2A, người được tag.
class RefGrantChips extends StatefulWidget {
  final MmPost post;
  final bool alignEnd;
  const RefGrantChips({super.key, required this.post, this.alignEnd = false});

  static bool has(Map<String, dynamic> props) =>
      props['flygo_refs'] != null || peerChipsOf(props).isNotEmpty || peopleChipsOf(props).isNotEmpty;
  @override
  State<RefGrantChips> createState() => _RefGrantChipsState();
}

class _RefGrantChipsState extends State<RefGrantChips> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Vẽ lại đúng lúc chip gần nhất hết hạn.
  void _schedule(List<GrantChipData> chips, int now) {
    _tick?.cancel();
    final next = chips.map((c) => c.expiresAt).where((e) => e > now).fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (next == null) return;
    _tick = Timer(Duration(milliseconds: (next - now).clamp(500, 86400000) + 200), () {
      if (mounted) setState(() {});
    });
  }

  void _open(BuildContext context, GrantChipData c) {
    final app = context.read<AppState>();
    final ch = app.channels[c.channelId];
    if (ch == null) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Bạn không ở trong chat này.'))));
      return;
    }
    if (ch.isSub) return openPrivateThread(context, c.channelId);
    openChatWith(context, c.channelId, rootId: c.rootId);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RefGrants.version,
      builder: (context, _, _) {
        final chips = grantChipsOf(widget.post.props);
        final peers = peerChipsOf(widget.post.props);
        final people = peopleChipsOf(widget.post.props);
        if (chips.isEmpty && peers.isEmpty && people.isEmpty) return const SizedBox.shrink();
        final now = DateTime.now().millisecondsSinceEpoch;
        _schedule(chips, now);
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: widget.alignEnd ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (final c in chips) _chip(context, c, now),
              for (final p in peers)
                _plainChip(
                  context,
                  Icons.swap_horiz_rounded,
                  '${p['title'] ?? ''}'.trim().isEmpty ? '@${p['username'] ?? ''}' : '${p['title']}',
                  p['username'] == null ? '' : '@${p['username']}',
                  tr('Nối phiên này qua A2A: hai phiên nói chuyện trực tiếp, hiện ở cả hai chat'),
                  () => _open(context, GrantChipData('chat', p['session_id'] as String, null, '', false, 0, const [])),
                ),
              for (final p in people)
                _plainChip(context, Icons.alternate_email_rounded, '${p['name'] ?? ''}'.trim().isEmpty ? '${p['username']}' : '${p['name']}', '',
                    '@${p['username']}', null),
            ],
          ),
        );
      },
    );
  }

  Widget _plainChip(BuildContext context, IconData icon, String name, String sub, String tip, VoidCallback? onTap) {
    final pal = Pal.of(context);
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: pal.accentText),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.text)),
        ),
        if (sub.isNotEmpty) Text(' · $sub', style: TextStyle(fontSize: 12, color: pal.accentText)),
      ]),
    );
    return Tooltip(
      message: tip,
      child: onTap == null ? chip : InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: chip),
    );
  }

  Widget _chip(BuildContext context, GrantChipData c, int now) {
    final pal = Pal.of(context);
    final jobs = [for (final id in c.grantIds) ?RefGrants.job(id)];
    final failed = jobs.where((j) => j.status == GrantStatus.failed).firstOrNull;
    final pending = failed == null && jobs.any((j) => j.status == GrantStatus.pending);
    final expired = c.expiresAt <= now;
    const red = Color(0xFFE53935);
    final fg = failed != null ? red : (expired ? pal.sub.withValues(alpha: .7) : pal.accentText);
    final end = DateTime.fromMillisecondsSinceEpoch(c.expiresAt);
    final today = DateTime.now();
    final until = end.year == today.year && end.month == today.month && end.day == today.day
        ? hhmm(end)
        : '${hhmm(end)} ${two(end.day)}/${two(end.month)}';
    final status = failed != null
        ? tr('Lỗi cấp quyền · Thử lại')
        : pending
            ? tr('Đang cấp quyền…')
            : expired
                ? tr('hết hạn')
                : tr('đến {0}', [until]);
    final icon = c.kind == 'chat'
        ? Icons.chat_bubble_outline_rounded
        : (c.rootId == null ? Icons.lock_outline_rounded : Icons.forum_outlined);
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: failed != null
            ? red.withValues(alpha: .10)
            : expired
                ? pal.surface2.withValues(alpha: .6)
                : pal.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: failed != null ? red.withValues(alpha: .5) : pal.divider.withValues(alpha: expired ? .6 : 0)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pending)
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg))
        else
          Icon(failed != null ? Icons.error_outline_rounded : icon, size: 13, color: fg),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: expired && failed == null ? pal.sub : pal.text,
                  decoration: expired && failed == null ? TextDecoration.lineThrough : null,
                  decorationColor: pal.sub)),
        ),
        Text(' · ${c.write ? tr('đọc + gửi') : tr('chỉ đọc')} · $status', style: TextStyle(fontSize: 12, color: fg)),
      ]),
    );
    return Tooltip(
      message: failed?.error ?? c.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: failed != null
            ? () {
                for (final j in c.grantIds) {
                  if (RefGrants.job(j)?.status == GrantStatus.failed) RefGrants.retry(j);
                }
              }
            : () => _open(context, c),
        child: chip,
      ),
    );
  }
}
