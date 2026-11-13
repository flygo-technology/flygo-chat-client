// Điều khiển máy tính (thuần Dart, kiểm thử được): danh sách người trong cuộc gọi để "Yêu cầu điều khiển" /
// "Cho phép điều khiển máy tôi", cách nhận lời mời trên từng loại máy, tham số cửa sổ điều khiển, và danh sách
// "Máy tính" của chính mình (trạm trả về).

/// Một người trong cuộc gọi có thể chọn.
class RcPick {
  final String userId;
  final String name;
  const RcPick(this.userId, this.name);

  @override
  bool operator ==(Object other) => other is RcPick && other.userId == userId && other.name == name;

  @override
  int get hashCode => Object.hash(userId, name);

  @override
  String toString() => 'RcPick($userId, $name)';
}

/// Người đang trong cuộc gọi (id người dùng của từng phiên Calls, một người có thể vào bằng nhiều máy) thành danh
/// sách để chọn: bỏ chính mình, id trống, bot, tài khoản đã khoá; mỗi người một dòng; xếp theo tên.
List<RcPick> rcPickList(
  Iterable<String> participantUserIds, {
  required String myId,
  required String? Function(String userId) nameOf,
  bool Function(String userId)? isBot,
  bool Function(String userId)? isDeleted,
  String fallbackName = '',
}) {
  final seen = <String>{};
  final out = <RcPick>[];
  for (final id in participantUserIds) {
    if (id.isEmpty || id == myId || !seen.add(id)) continue;
    if (isBot?.call(id) ?? false) continue;
    if (isDeleted?.call(id) ?? false) continue;
    final n = (nameOf(id) ?? '').trim();
    out.add(RcPick(id, n.isEmpty ? fallbackName : n));
  }
  out.sort((a, b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.userId.compareTo(b.userId);
  });
  return out;
}

/// Bấm "Đồng ý" lời mời điều khiển:
/// - [handoff]: máy tính (cửa sổ chính) — trang điều khiển mở ở cửa sổ riêng (tiến trình khác), cửa sổ đó nhận phiên.
/// - [inline]: điện thoại, hoặc chính cửa sổ điều khiển — điều khiển ngay trong tiến trình này (toàn màn hình).
enum RcInviteAccept { handoff, inline }

RcInviteAccept rcInviteAcceptPlan({required bool desktop, required bool controllerWindow}) =>
    desktop && !controllerWindow ? RcInviteAccept.handoff : RcInviteAccept.inline;

/// Việc cửa sổ điều khiển (máy tính, `--rc=`) làm khi mở.
class RcWindowJob {
  /// Kênh (tin riêng / kênh của cuộc gọi); trống với máy tính của chính mình.
  final String channelId;
  /// Người có máy cần điều khiển (trống với máy tính của chính mình).
  final String userId;
  /// Phiên đã đồng ý lời mời ở cửa sổ chính: nhận phiên (claim) thay vì xin.
  final String? sid;
  final String? via;
  /// Máy tính của chính mình (cid của kết nối trên trạm).
  final String? device;
  /// Tên hiện trên đầu trang (tên người / tên máy).
  final String name;
  const RcWindowJob({this.channelId = '', this.userId = '', this.sid, this.via, this.device, this.name = ''});
}

final _idRe = RegExp(r'^[a-z0-9]{26}$');
final _hexRe = RegExp(r'^[0-9a-f]{32}$');

/// Tham số dòng lệnh mở cửa sổ điều khiển (máy tính).
List<String> rcWindowArgs(RcWindowJob j, {String server = ''}) => [
      '--rc=${j.channelId}',
      if (j.userId.isNotEmpty) '--rc-user=${j.userId}',
      if (j.sid != null && j.sid!.isNotEmpty) '--rc-sid=${j.sid}',
      if (j.via != null && j.via!.isNotEmpty) '--rc-via=${j.via}',
      if (j.device != null && j.device!.isNotEmpty) '--rc-device=${j.device}',
      if (j.name.isNotEmpty) '--rc-name=${j.name.replaceAll(RegExp(r'[\r\n]'), ' ')}',
      if (server.isNotEmpty) '--server=$server',
    ];

/// Đọc lại tham số của [rcWindowArgs]; null nếu không phải cửa sổ điều khiển hoặc tham số sai.
RcWindowJob? rcWindowArgsParse(List<String> args) {
  String? v(String k) => args.where((a) => a.startsWith('--$k=')).map((a) => a.substring(k.length + 3)).firstOrNull;
  final ch = v('rc');
  if (ch == null) return null;
  final name = (v('rc-name') ?? '').trim();
  final device = v('rc-device');
  if (device != null) {
    if (!_hexRe.hasMatch(device)) return null;
    return RcWindowJob(device: device, name: name.length > 80 ? name.substring(0, 80) : name);
  }
  final user = v('rc-user') ?? '';
  if (!_idRe.hasMatch(ch) || !_idRe.hasMatch(user)) return null;
  final sid = v('rc-sid');
  return RcWindowJob(
    channelId: ch,
    userId: user,
    sid: sid != null && _hexRe.hasMatch(sid) ? sid : null,
    via: v('rc-via') == 'call' ? 'call' : null,
    name: name.length > 80 ? name.substring(0, 80) : name,
  );
}

/// Một máy tính của chính mình (trạm trả về trong `devices`).
class RcDevice {
  /// Mã kết nối trên trạm (chỉ máy đang online); dùng để xin điều khiển.
  final String cid;
  /// Mã máy (app tự sinh, giữ cố định trên máy đó).
  final String deviceId;
  final String name;
  /// windows / macos / linux.
  final String platform;
  final String version;
  final bool online;
  /// Đang trong một phiên điều khiển khác.
  final bool busy;
  /// Chính máy đang xem danh sách.
  final bool self;
  final DateTime? lastSeen;
  final DateTime? since;

  const RcDevice({
    this.cid = '',
    this.deviceId = '',
    this.name = '',
    this.platform = '',
    this.version = '',
    this.online = false,
    this.busy = false,
    this.self = false,
    this.lastSeen,
    this.since,
  });

  /// Bấm vào để điều khiển được không.
  bool get canControl => online && !self && !busy && cid.isNotEmpty;

  static DateTime? _ms(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static RcDevice? fromJson(Object? j) {
    if (j is! Map) return null;
    String s(String k) => j[k] is String ? (j[k] as String).trim() : '';
    final online = j['online'] == true || (j['online'] == null && s('cid').isNotEmpty);
    return RcDevice(
      cid: s('cid'),
      deviceId: s('device_id'),
      name: s('name'),
      platform: s('platform'),
      version: s('version'),
      online: online,
      busy: j['busy'] == true,
      self: j['self'] == true,
      lastSeen: _ms(j['last_seen']),
      since: _ms(j['since']),
    );
  }
}

/// Danh sách máy tính để hiện: máy đang online trước (máy này đầu tiên), rồi máy ngoại tuyến theo lần cuối online
/// (mới nhất trước); máy trùng mã chỉ giữ một dòng (ưu tiên dòng online). [myDeviceId] đánh dấu "Máy này" khi trạm
/// chưa đánh dấu.
List<RcDevice> rcDeviceRows(Object? list, {String myDeviceId = ''}) {
  final all = <RcDevice>[];
  if (list is List) {
    for (final j in list) {
      final d = RcDevice.fromJson(j);
      if (d == null || (d.deviceId.isEmpty && d.cid.isEmpty)) continue;
      final self = d.self || (myDeviceId.isNotEmpty && d.deviceId == myDeviceId);
      all.add(self == d.self
          ? d
          : RcDevice(
              cid: d.cid,
              deviceId: d.deviceId,
              name: d.name,
              platform: d.platform,
              version: d.version,
              online: d.online,
              busy: d.busy,
              self: true,
              lastSeen: d.lastSeen,
              since: d.since,
            ));
    }
  }
  final byId = <String, RcDevice>{};
  final out = <RcDevice>[];
  for (final d in all) {
    if (d.deviceId.isEmpty) {
      out.add(d);
      continue;
    }
    final prev = byId[d.deviceId];
    if (prev == null || (!prev.online && d.online)) byId[d.deviceId] = d;
  }
  out.addAll(byId.values);
  int t(DateTime? x) => x?.millisecondsSinceEpoch ?? 0;
  out.sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    if (a.online) {
      if (a.self != b.self) return a.self ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return t(b.lastSeen).compareTo(t(a.lastSeen));
  });
  return out;
}
