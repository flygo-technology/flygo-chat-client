import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../i18n/i18n.dart';
import 'theme.dart';
import 'common.dart' show pickFilesOrReport;

/// Sửa biểu tượng nhóm: tab "Ảnh" (chọn ảnh rồi kéo / phóng to để cắt vừa khung tròn) và tab "Biểu tượng"
/// (chọn một emoji, dùng luôn làm biểu tượng nhóm).
Future<void> showGroupIconEditor(
  BuildContext context, {
  required Future<void> Function(String name, Uint8List bytes) onImage,
  required Future<void> Function(String emoji) onEmoji,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
          child: _GroupIconEditor(onImage: onImage, onEmoji: onEmoji),
        ),
      ),
    );

class _GroupIconEditor extends StatelessWidget {
  final Future<void> Function(String name, Uint8List bytes) onImage;
  final Future<void> Function(String emoji) onEmoji;
  const _GroupIconEditor({required this.onImage, required this.onEmoji});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(children: [
            Expanded(child: Text(tr('Biểu tượng nhóm'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text))),
            IconButton(tooltip: tr('Đóng'), onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        TabBar(tabs: [
          Tab(icon: const Icon(Icons.image_outlined), text: tr('Ảnh')),
          Tab(icon: const Icon(Icons.emoji_emotions_outlined), text: tr('Biểu tượng')),
        ]),
        Expanded(
          child: TabBarView(children: [
            _PhotoTab(onImage: onImage),
            _EmojiTab(onEmoji: onEmoji),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------------------------------------ tab Ảnh
class _PhotoTab extends StatefulWidget {
  final Future<void> Function(String name, Uint8List bytes) onImage;
  const _PhotoTab({required this.onImage});
  @override
  State<_PhotoTab> createState() => _PhotoTabState();
}

class _PhotoTabState extends State<_PhotoTab> {
  static const _box = 280.0;
  Uint8List? _bytes;
  final _ctl = TransformationController();
  final _key = GlobalKey();
  bool _busy = false;
  double _zoom = 1;

  Future<void> _pick() async {
    final files = await pickFilesOrReport(context, type: FileType.image);
    final f = files.firstOrNull;
    if (f == null || f.path == null) return;
    final bytes = await File(f.path!).readAsBytes();
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _ctl.value = Matrix4.identity();
      _zoom = 1;
    });
  }

  void _setZoom(double z) {
    // Phóng quanh tâm khung.
    const c = _box / 2;
    final m = Matrix4.identity()
      ..translateByDouble(c, c, 0, 1)
      ..scaleByDouble(z, z, 1, 1)
      ..translateByDouble(-c, -c, 0, 1);
    setState(() {
      _zoom = z;
      _ctl.value = m;
    });
  }

  Future<void> _save() async {
    final b = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final img = await b.toImage(pixelRatio: 512 / _box);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      await widget.onImage('group-icon.png', png!.buffer.asUint8List());
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('Đã đổi biểu tượng nhóm'))));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('Không đổi được ảnh. Bạn có thể không có quyền.'))));
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final bytes = _bytes;
    if (bytes == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_photo_alternate_outlined, size: 56, color: pal.sub),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_rounded), label: Text(tr('Chọn ảnh'))),
          const SizedBox(height: 8),
          Text(tr('Chọn xong thì kéo và phóng to để cắt vừa khung tròn.'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
        ]),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        SizedBox(
          width: _box,
          height: _box,
          child: Stack(children: [
            RepaintBoundary(
              key: _key,
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _ctl,
                  minScale: 1,
                  maxScale: 8,
                  boundaryMargin: const EdgeInsets.all(_box),
                  onInteractionEnd: (_) => setState(() => _zoom = _ctl.value.getMaxScaleOnAxis()),
                  child: SizedBox(width: _box, height: _box, child: Image.memory(bytes, fit: BoxFit.cover)),
                ),
              ),
            ),
            // Khung tròn: phần ngoài tối đi để thấy đúng vùng sẽ hiện ở biểu tượng nhóm.
            IgnorePointer(child: CustomPaint(size: const Size(_box, _box), painter: _CircleMask(pal.bg))),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.zoom_out_rounded, color: pal.sub),
          Expanded(child: Slider(value: _zoom.clamp(1, 8), min: 1, max: 8, onChanged: _setZoom)),
          Icon(Icons.zoom_in_rounded, color: pal.sub),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          TextButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.refresh_rounded), label: Text(tr('Chọn ảnh khác'))),
          const Spacer(),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? tr('Đang lưu…') : tr('Lưu'))),
        ]),
      ]),
    );
  }
}

class _CircleMask extends CustomPainter {
  final Color shade;
  _CircleMask(this.shade);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final path = Path()
      ..addRect(r)
      ..addOval(r.deflate(2))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = shade.withValues(alpha: .65));
    canvas.drawOval(r.deflate(2), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .9));
  }

  @override
  bool shouldRepaint(_CircleMask old) => old.shade != shade;
}

// ------------------------------------------------------------------------------------------------ tab Biểu tượng
class _EmojiTab extends StatefulWidget {
  final Future<void> Function(String emoji) onEmoji;
  const _EmojiTab({required this.onEmoji});
  @override
  State<_EmojiTab> createState() => _EmojiTabState();
}

class _EmojiTabState extends State<_EmojiTab> {
  bool _busy = false;

  static const _groups = <(String, String)>[
    ('Công việc', '💼 📊 📈 📉 📋 📁 🗂️ 📝 ✍️ 📌 📎 🧾 💰 💵 💳 🏦 🧮 📦 🚚 🏭 🏢 🏗️ 🛠️ 🔧 ⚙️ 🔩 🧰 🛗 ⚡ 🔌 💡 🖥️ 💻 📱 ☎️ 📞 📠 🖨️ 🗓️ ⏰ 🎯 🏆 🤝 📣 📢 🔔'),
    ('Nhóm & người', '👥 👪 🧑‍💼 👷 🧑‍🔧 🧑‍💻 🧑‍🏫 🧑‍⚕️ 🧑‍🍳 🧑‍🌾 💁 🙋 🤗 😊 😎 🥳 🤖 👑 ❤️ 💙 💚 💛 🧡 💜 🖤 🤍'),
    ('Nơi chốn', '🏠 🏡 🏬 🏪 🏨 🏫 🏥 ⛪ 🏛️ 🏟️ 🌆 🌃 🗺️ 🧭 🏝️ ⛰️ 🌋 🏕️ ✈️ 🚗 🚕 🚌 🚆 🚢 🛵 🚲'),
    ('Thiên nhiên', '🌳 🌴 🌵 🌷 🌸 🌻 🍀 🍁 🌈 ☀️ 🌙 ⭐ 🌟 🔥 💧 🌊 ❄️ ⛄ 🐶 🐱 🐼 🦁 🐯 🐻 🐨 🐸 🦊 🐝 🦋 🐬 🐳 🦄'),
    ('Ăn uống & vui chơi', '☕ 🍵 🍺 🍷 🍹 🍕 🍔 🍜 🍣 🍰 🎂 🍉 🍎 ⚽ 🏀 🏸 🎾 🏓 🎮 🎲 🎵 🎸 🎬 📷 🎨 🎁 🎉 🎄'),
    ('Ký hiệu', '✅ ❗ ❓ ⚠️ 🚨 🔒 🔑 🛡️ ♻️ 💯 🆕 🆗 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🇻🇳'),
  ];

  Future<void> _pick(String e) async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onEmoji(e);
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('Đã đổi biểu tượng nhóm'))));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('Không đổi được biểu tượng. Bạn có thể không có quyền.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), children: [
      for (final (title, list) in _groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(tr(title).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .4, color: pal.sub)),
        ),
        Wrap(children: [
          for (final e in list.split(' ').where((s) => s.isNotEmpty))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pick(e),
              child: SizedBox(width: 48, height: 48, child: Center(child: Text(e, style: const TextStyle(fontSize: 28)))),
            ),
        ]),
      ],
    ]);
  }
}
