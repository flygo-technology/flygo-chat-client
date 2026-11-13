// Điều khiển máy tính từ xa: giao thức thao tác (chuột / phím / chữ) đi qua RTCDataChannel giữa hai máy.
// Phần thuần Dart (không gọi nền tảng) để kiểm thử: mã hoá / giải mã, kiểm tra giới hạn, đổi toạ độ, bảng phím.
//
// Mỗi tin là một mảng JSON ngắn:
//   ["m", x, y]              di chuột tới (x, y) chuẩn hoá 0..65535 trên màn hình đang chia sẻ
//   ["b", nút, xuống, x, y]  nút 0 = trái, 1 = phải, 2 = giữa; xuống 1 / nhả 0
//   ["w", dx, dy]            cuộn (điểm ảnh, dy > 0 = cuộn xuống), mỗi chiều tối đa ±[kRcMaxWheel]
//   ["k", hid, xuống]        phím vật lý theo mã USB HID (trang bàn phím 0x07)
//   ["t", "chữ"]             gõ chữ (bộ gõ, dán chữ), tối đa [kRcMaxText] ký tự
//   ["q", "auto|high|low"]   chất lượng hình
//   ["r"]                    nhả hết phím / nút đang giữ (máy điều khiển mất tiêu điểm)
//   ["d", "id"]              chọn màn hình [id] (một id trong danh sách "s" máy kia gửi)
//
// Chiều ngược lại (máy bị điều khiển gửi máy điều khiển, [RcHostMessage]):
//   ["s", "id đang chia sẻ", [["id", "tên", rộng, cao, chính 1|0], ...]]   danh sách màn hình
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

const kRcWire = 65535;
const kRcMaxWheel = 2400;
const kRcMaxText = 1000;
const kRcMaxMessage = 4096;
const kRcQualities = {'auto', 'high', 'low'};
const kRcMaxScreens = 16;
const kRcMaxScreenId = 128;
const kRcMaxScreenName = 64;
const kRcMaxScreenSide = 1 << 16;

/// Một thao tác từ máy điều khiển.
sealed class RcInput {
  const RcInput();
  List<Object> toWire();
  String encode() => jsonEncode(toWire());

  /// Giải mã và kiểm tra một tin; sai dạng / vượt giới hạn thì trả về null (bỏ qua, không làm gì).
  static RcInput? decode(String raw) {
    if (raw.length > kRcMaxMessage) return null;
    Object? v;
    try {
      v = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (v is! List || v.isEmpty || v.first is! String) return null;
    final list = v;
    int? i(int k, int lo, int hi) {
      if (k >= list.length) return null;
      final x = list[k];
      if (x is! int || x < lo || x > hi) return null;
      return x;
    }
    switch (v.first as String) {
      case 'm':
        if (v.length != 3) return null;
        final x = i(1, 0, kRcWire), y = i(2, 0, kRcWire);
        return x == null || y == null ? null : RcMove(x, y);
      case 'b':
        if (v.length != 5) return null;
        final b = i(1, 0, 2), d = i(2, 0, 1), x = i(3, 0, kRcWire), y = i(4, 0, kRcWire);
        return b == null || d == null || x == null || y == null ? null : RcButton(b, d == 1, x, y);
      case 'w':
        if (v.length != 3) return null;
        final dx = i(1, -kRcMaxWheel, kRcMaxWheel), dy = i(2, -kRcMaxWheel, kRcMaxWheel);
        return dx == null || dy == null ? null : RcWheel(dx, dy);
      case 'k':
        if (v.length != 3) return null;
        final hid = i(1, 0, 0xFFFF), d = i(2, 0, 1);
        if (hid == null || d == null || !rcKnownKey(hid)) return null;
        return RcKey(hid, d == 1);
      case 't':
        if (v.length != 2 || v[1] is! String) return null;
        final s = sanitizeRcText(v[1] as String);
        return s.isEmpty ? null : RcText(s);
      case 'q':
        if (v.length != 2 || !kRcQualities.contains(v[1])) return null;
        return RcQuality(v[1] as String);
      case 'r':
        return v.length == 1 ? const RcRelease() : null;
      case 'd':
        if (v.length != 2 || !_validScreenId(v[1])) return null;
        return RcSelectScreen(v[1] as String);
    }
    return null;
  }
}

bool _validScreenId(Object? id) => id is String && id.isNotEmpty && id.length <= kRcMaxScreenId;

class RcMove extends RcInput {
  final int x, y;
  const RcMove(this.x, this.y);
  @override
  List<Object> toWire() => ['m', x, y];
}

class RcButton extends RcInput {
  final int button, x, y;
  final bool down;
  const RcButton(this.button, this.down, this.x, this.y);
  @override
  List<Object> toWire() => ['b', button, down ? 1 : 0, x, y];
}

class RcWheel extends RcInput {
  final int dx, dy;
  const RcWheel(this.dx, this.dy);
  @override
  List<Object> toWire() => ['w', dx, dy];
}

class RcKey extends RcInput {
  /// Mã USB HID của phím (trang 0x07, vd. 0x04 = A).
  final int hid;
  final bool down;
  const RcKey(this.hid, this.down);
  @override
  List<Object> toWire() => ['k', hid, down ? 1 : 0];
}

class RcText extends RcInput {
  final String text;
  const RcText(this.text);
  @override
  List<Object> toWire() => ['t', text];
}

class RcQuality extends RcInput {
  final String level;
  const RcQuality(this.level);
  @override
  List<Object> toWire() => ['q', level];
}

class RcRelease extends RcInput {
  const RcRelease();
  @override
  List<Object> toWire() => ['r'];
}

/// Máy điều khiển chọn màn hình [id] để xem / điều khiển.
class RcSelectScreen extends RcInput {
  final String id;
  const RcSelectScreen(this.id);
  @override
  List<Object> toWire() => ['d', id];
}

// ------------------------------------------------------------------ danh sách màn hình (máy bị điều khiển gửi sang)

/// Một màn hình của máy bị điều khiển như máy điều khiển thấy: id nguồn chụp, tên, kích thước, có phải màn hình chính.
class RcDisplay {
  final String id;
  final String name;
  final int width, height;
  final bool primary;
  const RcDisplay({required this.id, this.name = '', required this.width, required this.height, this.primary = false});

  List<Object> toWire() => [id, name, width, height, primary ? 1 : 0];

  static RcDisplay? fromWire(Object? v) {
    if (v is! List || v.length != 5) return null;
    final id = v[0], name = v[1], w = v[2], h = v[3], p = v[4];
    if (!_validScreenId(id) || name is! String || w is! int || h is! int || p is! int) return null;
    if (w < 0 || h < 0 || w > kRcMaxScreenSide || h > kRcMaxScreenSide || (p != 0 && p != 1)) return null;
    final clean = sanitizeRcText(name, max: kRcMaxScreenName).replaceAll(RegExp(r'\s+'), ' ').trim();
    return RcDisplay(id: id as String, name: clean, width: w, height: h, primary: p == 1);
  }

  @override
  bool operator ==(Object other) =>
      other is RcDisplay && other.id == id && other.name == name && other.width == width && other.height == height && other.primary == primary;
  @override
  int get hashCode => Object.hash(id, name, width, height, primary);
}

/// Tin từ máy bị điều khiển: danh sách màn hình kèm màn hình đang chia sẻ.
class RcHostMessage {
  final String current;
  final List<RcDisplay> screens;
  const RcHostMessage(this.current, this.screens);

  String encode() => jsonEncode([
        's',
        current,
        [for (final s in screens.take(kRcMaxScreens)) s.toWire()],
      ]);

  /// Giải mã và kiểm tra; sai dạng, quá nhiều màn hình, id trùng hoặc màn hình đang chia sẻ không có trong danh sách
  /// thì trả về null.
  static RcHostMessage? decode(String raw) {
    if (raw.length > kRcMaxMessage) return null;
    Object? v;
    try {
      v = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (v is! List || v.length != 3 || v[0] != 's' || !_validScreenId(v[1]) || v[2] is! List) return null;
    final list = v[2] as List;
    if (list.isEmpty || list.length > kRcMaxScreens) return null;
    final out = <RcDisplay>[];
    final ids = <String>{};
    for (final e in list) {
      final d = RcDisplay.fromWire(e);
      if (d == null || !ids.add(d.id)) return null;
      out.add(d);
    }
    final cur = v[1] as String;
    return ids.contains(cur) ? RcHostMessage(cur, out) : null;
  }
}

/// Màn hình bắt đầu chia sẻ: màn hình chính, không có thì màn hình đầu tiên; null nếu danh sách rỗng.
RcDisplay? rcDefaultDisplay(List<RcDisplay> list) =>
    list.isEmpty ? null : list.firstWhere((d) => d.primary, orElse: () => list.first);

/// Chữ gửi sang máy kia: bỏ ký tự điều khiển (trừ xuống dòng, tab), cắt tối đa [max] ký tự.
String sanitizeRcText(String s, {int max = kRcMaxText}) {
  final out = StringBuffer();
  var n = 0;
  for (final r in s.replaceAll('\r\n', '\n').runes) {
    if (n >= max) break;
    if (r == 0x0A || r == 0x09 || (r >= 0x20 && r != 0x7F && !(r >= 0x80 && r < 0xA0))) {
      out.writeCharCode(r);
      n++;
    }
  }
  return out.toString();
}

/// Chia chữ dài (dán) thành nhiều tin, mỗi tin tối đa [kRcMaxText] ký tự.
List<String> chunkRcText(String s) {
  final runes = sanitizeRcText(s, max: 1 << 30).runes.toList();
  return [
    for (var i = 0; i < runes.length; i += kRcMaxText) String.fromCharCodes(runes.sublist(i, math.min(runes.length, i + kRcMaxText))),
  ];
}

// ------------------------------------------------------------------ giới hạn tần suất

/// Thùng token: tối đa [ratePerSecond] tin mỗi giây, dồn tối đa [burst]. Vượt thì bỏ tin.
class RcRateLimiter {
  final double ratePerSecond;
  final double burst;
  double _tokens;
  int? _last;
  RcRateLimiter({this.ratePerSecond = 300, this.burst = 600}) : _tokens = burst;

  bool allow([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (_last != null) _tokens = math.min(burst, _tokens + (now - _last!) * ratePerSecond / 1000);
    _last = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}

// ------------------------------------------------------------------ toạ độ

/// Khung hình video [video] đặt vừa (giữ tỉ lệ, viền đen) trong ô [box].
Rect rcFitRect(Size box, Size video) {
  if (video.width <= 0 || video.height <= 0 || box.width <= 0 || box.height <= 0) return Offset.zero & box;
  final s = math.min(box.width / video.width, box.height / video.height);
  final w = video.width * s, h = video.height * s;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

/// Điểm [p] trong ô [box] → toạ độ chuẩn hoá 0..[kRcWire] trên màn hình máy kia; ngoài khung hình thì null
/// (trừ khi [clamp]: kéo chuột ra ngoài vẫn giữ ở mép).
(int, int)? rcToWire(Offset p, Size box, Size video, {bool clamp = false}) {
  final r = rcFitRect(box, video);
  if (r.width <= 0 || r.height <= 0) return null;
  var fx = (p.dx - r.left) / r.width, fy = (p.dy - r.top) / r.height;
  if (!clamp && (fx < 0 || fy < 0 || fx > 1 || fy > 1)) return null;
  fx = fx.clamp(0.0, 1.0);
  fy = fy.clamp(0.0, 1.0);
  return ((fx * kRcWire).round(), (fy * kRcWire).round());
}

/// Một màn hình của máy bị điều khiển (toạ độ gốc của hệ điều hành: Windows = điểm ảnh thật trên màn hình ảo,
/// macOS = điểm (point) toàn cục, gốc ở góc trên trái màn hình chính; Linux X11 = điểm ảnh trên cửa sổ gốc).
class RcScreen {
  final String id;
  final String name;
  final double x, y, width, height;
  final bool primary;
  const RcScreen({required this.id, this.name = '', required this.x, required this.y, required this.width, required this.height, this.primary = false});

  factory RcScreen.fromMap(Map m) => RcScreen(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        width: (m['w'] as num?)?.toDouble() ?? 0,
        height: (m['h'] as num?)?.toDouble() ?? 0,
        primary: m['primary'] == true,
      );

  Rect get rect => Rect.fromLTWH(x, y, width, height);
}

/// Toạ độ chuẩn hoá → toạ độ tuyệt đối trên [s] (không vượt quá mép màn hình).
Offset rcWireToScreen(int x, int y, RcScreen s) => Offset(
      s.x + (x.clamp(0, kRcWire) / kRcWire) * math.max(0, s.width - 1),
      s.y + (y.clamp(0, kRcWire) / kRcWire) * math.max(0, s.height - 1),
    );

/// Windows SendInput (MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK): toạ độ điểm ảnh → 0..65535 trên màn hình ảo [virt].
(int, int) rcWinAbsolute(Offset p, Rect virt) {
  int f(double v, double o, double len) => len <= 1 ? 0 : (((v - o) * 65535) / (len - 1)).round().clamp(0, 65535);
  return (f(p.dx, virt.left, virt.width), f(p.dy, virt.top, virt.height));
}

/// Chọn màn hình gốc ứng với nguồn chụp [sourceId] của flutter_webrtc (macOS: id màn hình CGDirectDisplayID;
/// Windows: chỉ số thiết bị EnumDisplayDevices; Linux X11: atom tên màn hình XRandR). Không khớp id thì theo thứ tự [index], cuối cùng là màn hình chính.
RcScreen? rcMatchScreen(List<RcScreen> screens, String sourceId, int index) {
  if (screens.isEmpty) return null;
  for (final s in screens) {
    if (s.id == sourceId) return s;
  }
  if (index >= 0 && index < screens.length) return screens[index];
  return screens.firstWhere((s) => s.primary, orElse: () => screens.first);
}

/// Ghép các nguồn chụp màn hình [sourceIds] (theo thứ tự của flutter_webrtc) với màn hình gốc [screens]: danh sách gửi
/// máy điều khiển kèm màn hình gốc để đổi toạ độ. Bỏ id không hợp lệ / trùng, tối đa [kRcMaxScreens], chỉ một màn hình chính.
List<({RcDisplay display, RcScreen screen})> rcDisplaysOf(List<String> sourceIds, List<RcScreen> screens) {
  final out = <({RcDisplay display, RcScreen screen})>[];
  final ids = <String>{};
  var primary = false;
  for (var i = 0; i < sourceIds.length && out.length < kRcMaxScreens; i++) {
    final id = sourceIds[i];
    if (!_validScreenId(id) || !ids.add(id)) continue;
    final s = rcMatchScreen(screens, id, i);
    if (s == null) continue;
    final p = s.primary && !primary;
    primary |= p;
    final name = sanitizeRcText(s.name, max: kRcMaxScreenName).trim();
    out.add((
      display: RcDisplay(
        id: id,
        name: name,
        width: s.width.round().clamp(0, kRcMaxScreenSide),
        height: s.height.round().clamp(0, kRcMaxScreenSide),
        primary: p,
      ),
      screen: s,
    ));
  }
  return out;
}

/// Cuộn: Windows tính theo nấc WHEEL_DELTA (120 = một nấc, dương = cuộn lên); macOS theo điểm ảnh (dương = cuộn lên).
int rcWinWheel(int dy) => (-dy * 2.4).round().clamp(-kRcMaxWheel * 3, kRcMaxWheel * 3);
int rcMacWheel(int d) => -d;

/// Điện thoại: phóng to / kéo khung hình. Điểm chạm [p] trên màn hình → điểm trong ô chưa phóng to.
Offset rcUnzoom(Offset p, double scale, Offset pan) => (p - pan) / scale;

/// Giữ khung hình phóng to [scale] không bị kéo lệch khỏi ô [box].
Offset rcClampPan(Offset pan, double scale, Size box) {
  final minX = box.width - box.width * scale, minY = box.height - box.height * scale;
  return Offset(pan.dx.clamp(math.min(0.0, minX), 0.0), pan.dy.clamp(math.min(0.0, minY), 0.0));
}

// ------------------------------------------------------------------ nháy đúp (macOS cần số lần bấm)

/// Đếm số lần bấm liên tiếp (macOS: kCGMouseEventClickState). Windows tự nhận nháy đúp.
class RcClickCounter {
  final int intervalMs;
  final int slop;
  int _count = 0, _at = -1 << 30, _button = -1, _x = 0, _y = 0;
  RcClickCounter({this.intervalMs = 500, this.slop = 400});

  /// Gọi khi bấm xuống; trả về số lần bấm (1, 2, 3…).
  int down(int button, int x, int y, [int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final near = (x - _x).abs() <= slop && (y - _y).abs() <= slop;
    _count = button == _button && near && now - _at <= intervalMs ? _count + 1 : 1;
    _at = now;
    _button = button;
    _x = x;
    _y = y;
    return _count;
  }

  /// Số lần bấm của lần nhả nút (bằng lần bấm xuống gần nhất).
  int get current => _count == 0 ? 1 : _count;
}

// ------------------------------------------------------------------ bàn phím

/// Đổi Cmd ↔ Ctrl khi máy điều khiển và máy bị điều khiển khác "họ" (Mac ↔ Windows) để Cmd+C trên Mac thành
/// Ctrl+C trên Windows và ngược lại.
int rcSwapMeta(int hid) => switch (hid) {
      0xE0 => 0xE3,
      0xE3 => 0xE0,
      0xE4 => 0xE7,
      0xE7 => 0xE4,
      _ => hid,
    };

/// Mã USB HID đầy đủ của Flutter (PhysicalKeyboardKey.usbHidUsage, trang 0x07 ở 16 bit cao) → mã trong tin, hoặc
/// null nếu không phải phím bàn phím được hỗ trợ.
int? rcHidFromUsage(int usage) {
  if (usage >> 16 != 0x07) return null;
  final hid = usage & 0xFFFF;
  return rcKnownKey(hid) ? hid : null;
}

bool rcKnownKey(int hid) => _keys.containsKey(hid);

/// Mọi mã HID được hỗ trợ (kiểm thử bảng phím của từng hệ).
Iterable<int> get rcKnownKeys => _keys.keys;

/// Windows: mã quét (scancode set 1); phím mở rộng có 0xE000.
int? rcWinScan(int hid) {
  final v = _keys[hid]?.$1;
  return v == null || v < 0 ? null : v;
}

/// macOS: mã phím ảo (kVK_*).
int? rcMacKey(int hid) {
  final v = _keys[hid]?.$2;
  return v == null || v < 0 ? null : v;
}

/// Linux X11: mã phím X (keycode) = mã evdev của nhân Linux + 8 (Xorg dùng evdev / libinput), theo vị trí phím
/// vật lý như mã quét của Windows, không phụ thuộc kiểu bàn phím.
int? rcLinuxKey(int hid) {
  final v = _linuxEvdev[hid];
  return v == null ? null : v + 8;
}

bool rcIsModifier(int hid) => hid >= 0xE0 && hid <= 0xE7;

// HID → (Windows scancode, macOS kVK); -1 = không có trên hệ đó.
const Map<int, (int, int)> _keys = {
  // Chữ a..z
  0x04: (0x1E, 0x00), 0x05: (0x30, 0x0B), 0x06: (0x2E, 0x08), 0x07: (0x20, 0x02), 0x08: (0x12, 0x0E),
  0x09: (0x21, 0x03), 0x0A: (0x22, 0x05), 0x0B: (0x23, 0x04), 0x0C: (0x17, 0x22), 0x0D: (0x24, 0x26),
  0x0E: (0x25, 0x28), 0x0F: (0x26, 0x25), 0x10: (0x32, 0x2E), 0x11: (0x31, 0x2D), 0x12: (0x18, 0x1F),
  0x13: (0x19, 0x23), 0x14: (0x10, 0x0C), 0x15: (0x13, 0x0F), 0x16: (0x1F, 0x01), 0x17: (0x14, 0x11),
  0x18: (0x16, 0x20), 0x19: (0x2F, 0x09), 0x1A: (0x11, 0x0D), 0x1B: (0x2D, 0x07), 0x1C: (0x15, 0x10),
  0x1D: (0x2C, 0x06),
  // Số 1..9, 0
  0x1E: (0x02, 0x12), 0x1F: (0x03, 0x13), 0x20: (0x04, 0x14), 0x21: (0x05, 0x15), 0x22: (0x06, 0x17),
  0x23: (0x07, 0x16), 0x24: (0x08, 0x1A), 0x25: (0x09, 0x1C), 0x26: (0x0A, 0x19), 0x27: (0x0B, 0x1D),
  0x28: (0x1C, 0x24), // Enter
  0x29: (0x01, 0x35), // Esc
  0x2A: (0x0E, 0x33), // Backspace
  0x2B: (0x0F, 0x30), // Tab
  0x2C: (0x39, 0x31), // Space
  0x2D: (0x0C, 0x1B), 0x2E: (0x0D, 0x18), 0x2F: (0x1A, 0x21), 0x30: (0x1B, 0x1E), 0x31: (0x2B, 0x2A),
  0x33: (0x27, 0x29), 0x34: (0x28, 0x27), 0x35: (0x29, 0x32), 0x36: (0x33, 0x2B), 0x37: (0x34, 0x2F),
  0x38: (0x35, 0x2C),
  0x39: (0x3A, 0x39), // CapsLock
  // F1..F12
  0x3A: (0x3B, 0x7A), 0x3B: (0x3C, 0x78), 0x3C: (0x3D, 0x63), 0x3D: (0x3E, 0x76), 0x3E: (0x3F, 0x60),
  0x3F: (0x40, 0x61), 0x40: (0x41, 0x62), 0x41: (0x42, 0x64), 0x42: (0x43, 0x65), 0x43: (0x44, 0x6D),
  0x44: (0x57, 0x67), 0x45: (0x58, 0x6F),
  0x46: (0xE037, -1), // PrintScreen
  0x47: (0x46, -1), // ScrollLock
  0x49: (0xE052, 0x72), // Insert / Help
  0x4A: (0xE047, 0x73), // Home
  0x4B: (0xE049, 0x74), // PageUp
  0x4C: (0xE053, 0x75), // Delete
  0x4D: (0xE04F, 0x77), // End
  0x4E: (0xE051, 0x79), // PageDown
  0x4F: (0xE04D, 0x7C), // →
  0x50: (0xE04B, 0x7B), // ←
  0x51: (0xE050, 0x7D), // ↓
  0x52: (0xE048, 0x7E), // ↑
  0x53: (0xE045, 0x47), // NumLock / Clear
  0x54: (0xE035, 0x4B), 0x55: (0x37, 0x43), 0x56: (0x4A, 0x4E), 0x57: (0x4E, 0x45), 0x58: (0xE01C, 0x4C),
  // Bàn số 1..9, 0, dấu chấm
  0x59: (0x4F, 0x53), 0x5A: (0x50, 0x54), 0x5B: (0x51, 0x55), 0x5C: (0x4B, 0x56), 0x5D: (0x4C, 0x57),
  0x5E: (0x4D, 0x58), 0x5F: (0x47, 0x59), 0x60: (0x48, 0x5B), 0x61: (0x49, 0x5C), 0x62: (0x52, 0x52),
  0x63: (0x53, 0x41),
  0x64: (0x56, 0x0A), // phím \ cạnh Shift trái (bàn phím châu Âu)
  0x65: (0xE05D, -1), // Menu ngữ cảnh
  0x67: (0x59, 0x51), // = bàn số
  // F13..F24
  0x68: (0x64, 0x69), 0x69: (0x65, 0x6B), 0x6A: (0x66, 0x71), 0x6B: (0x67, 0x6A), 0x6C: (0x68, 0x40),
  0x6D: (0x69, 0x4F), 0x6E: (0x6A, 0x50), 0x6F: (0x6B, 0x5A), 0x70: (0x6C, -1), 0x71: (0x6D, -1),
  0x72: (0x6E, -1), 0x73: (0x76, -1),
  0x7F: (0xE020, 0x4A), 0x80: (0xE030, 0x48), 0x81: (0xE02E, 0x49), // tắt tiếng, to, nhỏ
  0x87: (0x73, 0x5E), 0x89: (0x7D, 0x5D), // phím Nhật Ro, Yen
  // Ctrl, Shift, Alt, Win/Cmd trái rồi phải
  0xE0: (0x1D, 0x3B), 0xE1: (0x2A, 0x38), 0xE2: (0x38, 0x3A), 0xE3: (0xE05B, 0x37),
  0xE4: (0xE01D, 0x3E), 0xE5: (0x36, 0x3C), 0xE6: (0xE038, 0x3D), 0xE7: (0xE05C, 0x36),
};

// HID → mã evdev (linux/input-event-codes.h, như bảng hid_keyboard của nhân); cùng tập phím với [_keys].
const Map<int, int> _linuxEvdev = {
  // Chữ a..z
  0x04: 30, 0x05: 48, 0x06: 46, 0x07: 32, 0x08: 18, 0x09: 33, 0x0A: 34, 0x0B: 35, 0x0C: 23, 0x0D: 36,
  0x0E: 37, 0x0F: 38, 0x10: 50, 0x11: 49, 0x12: 24, 0x13: 25, 0x14: 16, 0x15: 19, 0x16: 31, 0x17: 20,
  0x18: 22, 0x19: 47, 0x1A: 17, 0x1B: 45, 0x1C: 21, 0x1D: 44,
  // Số 1..9, 0
  0x1E: 2, 0x1F: 3, 0x20: 4, 0x21: 5, 0x22: 6, 0x23: 7, 0x24: 8, 0x25: 9, 0x26: 10, 0x27: 11,
  0x28: 28, 0x29: 1, 0x2A: 14, 0x2B: 15, 0x2C: 57, // Enter, Esc, Backspace, Tab, Space
  0x2D: 12, 0x2E: 13, 0x2F: 26, 0x30: 27, 0x31: 43, 0x33: 39, 0x34: 40, 0x35: 41, 0x36: 51, 0x37: 52,
  0x38: 53,
  0x39: 58, // CapsLock
  // F1..F12
  0x3A: 59, 0x3B: 60, 0x3C: 61, 0x3D: 62, 0x3E: 63, 0x3F: 64, 0x40: 65, 0x41: 66, 0x42: 67, 0x43: 68,
  0x44: 87, 0x45: 88,
  0x46: 99, 0x47: 70, // PrintScreen (SysRq), ScrollLock
  0x49: 110, 0x4A: 102, 0x4B: 104, 0x4C: 111, 0x4D: 107, 0x4E: 109, // Insert, Home, PageUp, Delete, End, PageDown
  0x4F: 106, 0x50: 105, 0x51: 108, 0x52: 103, // → ← ↓ ↑
  0x53: 69, 0x54: 98, 0x55: 55, 0x56: 74, 0x57: 78, 0x58: 96, // NumLock, bàn số / * - + Enter
  // Bàn số 1..9, 0, dấu chấm
  0x59: 79, 0x5A: 80, 0x5B: 81, 0x5C: 75, 0x5D: 76, 0x5E: 77, 0x5F: 71, 0x60: 72, 0x61: 73, 0x62: 82,
  0x63: 83,
  0x64: 86, 0x65: 127, 0x67: 117, // phím \ châu Âu, Menu, = bàn số
  // F13..F24
  0x68: 183, 0x69: 184, 0x6A: 185, 0x6B: 186, 0x6C: 187, 0x6D: 188, 0x6E: 189, 0x6F: 190, 0x70: 191,
  0x71: 192, 0x72: 193, 0x73: 194,
  0x7F: 113, 0x80: 115, 0x81: 114, // tắt tiếng, to, nhỏ
  0x87: 89, 0x89: 124, // Ro, Yen
  // Ctrl, Shift, Alt, Super trái rồi phải
  0xE0: 29, 0xE1: 42, 0xE2: 56, 0xE3: 125, 0xE4: 97, 0xE5: 54, 0xE6: 100, 0xE7: 126,
};

/// Linux X11: cuộn theo nấc (nút 4..7), một nấc ứng với [kRcLinuxWheelStep] điểm ảnh như Windows. Cộng dồn [acc]
/// điểm ảnh, trả về (số nấc, phần dư còn giữ lại cho lần sau); dương = xuống / sang phải.
const kRcLinuxWheelStep = 50;
(int, int) rcLinuxWheel(int acc) {
  final n = acc ~/ kRcLinuxWheelStep;
  return (n.clamp(-kRcMaxWheel, kRcMaxWheel), acc - n * kRcLinuxWheelStep);
}

/// Mã HID hay dùng (nút trên thanh công cụ / bàn phím ảo).
abstract final class RcHid {
  static const enter = 0x28, esc = 0x29, backspace = 0x2A, tab = 0x2B, delete = 0x4C;
  static const right = 0x4F, left = 0x50, down = 0x51, up = 0x52;
  static const ctrl = 0xE0, shift = 0xE1, alt = 0xE2, meta = 0xE3;
}

/// "Ctrl+Alt+Del": Windows chặn tổ hợp này (chỉ dịch vụ hệ thống mới gửi được), nên gửi thứ làm được: Windows mở
/// Trình quản lý tác vụ (Ctrl+Shift+Esc), macOS mở Thoát ứng dụng bắt buộc (Cmd+Option+Esc).
List<RcKey> rcSecureAttention({required bool macTarget}) {
  final mods = macTarget ? [RcHid.meta, RcHid.alt] : [RcHid.ctrl, RcHid.shift];
  return [
    for (final m in mods) RcKey(m, true),
    const RcKey(RcHid.esc, true),
    const RcKey(RcHid.esc, false),
    for (final m in mods.reversed) RcKey(m, false),
  ];
}

// ------------------------------------------------------------------ bàn phím ảo trên điện thoại

/// Ô nhập ẩn của bàn phím ảo luôn bắt đầu bằng chuỗi mồi này (để bấm xoá khi ô "trống" vẫn nhận được).
const kRcSentinel = '​​';

/// So chữ trước / sau một lần sửa của bàn phím ảo: số lần xoá lùi cần gửi và chữ mới cần gõ.
(int, String) rcTextDiff(String before, String after) {
  var i = 0;
  final n = math.min(before.length, after.length);
  while (i < n && before.codeUnitAt(i) == after.codeUnitAt(i)) {
    i++;
  }
  // Không cắt giữa cặp UTF-16 (emoji).
  if (i > 0 && i < before.length && _isLowSurrogate(before.codeUnitAt(i)) && _isHighSurrogate(before.codeUnitAt(i - 1))) i--;
  final removed = before.substring(i).runes.length;
  return (removed, after.substring(i));
}

bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;
