// Giao diện kiểu Chrome của cửa sổ Ký số, theo trình duyệt Magic Sign 1.2.7 (apps/desktop/ui/profile.* của
// vietnam-usb-token-signer): dải tab 40px (nút công ty, các tab, nút + ngay sau tab cuối), thanh công cụ 44px
// (lùi / tiến / tải lại / trang đầu, ô địa chỉ bo tròn, ghim, chip công ty · MST, trạng thái ký), thanh dấu trang.
// Màu công ty: FNV-1a của tên (bỏ dấu, bỏ "Công ty TNHH…") ra sắc độ, OKLCH cố định độ sáng (company-color.js).
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kMiddleMouseButton, kPrimaryMouseButton;
import 'package:flutter/material.dart';

/// Màu nền tảng của trình duyệt (sáng / tối), như style.css của Magic Sign.
class ChromeColors {
  const ChromeColors({
    required this.tab,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.brand,
    required this.brandSoft,
  });
  final Color tab, surface, text, muted, line, brand, brandSoft;

  /// [brand]: màu của công ty do Flygo ID cho (cùng màu ô Ký số trên màn hình chính); không có thì tính từ tên.
  static ChromeColors of(BuildContext context, String company, {Color? brand}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = brand != null ? HSLColor.fromColor(brand).hue.round() : companyHue(company);
    return dark
        ? ChromeColors(
            tab: const Color(0xFF232A36),
            surface: const Color(0xFF1A1F28),
            text: const Color(0xFFE8ECF3),
            muted: const Color(0xFF9AA6BA),
            line: const Color(0xFF2B3240),
            brand: oklch(0.74, 0.13, hue),
            brandSoft: oklch(0.31, 0.06, hue),
          )
        : ChromeColors(
            tab: const Color(0xFFE9EDF5),
            surface: Colors.white,
            text: const Color(0xFF17202F),
            muted: const Color(0xFF5D6B82),
            line: const Color(0xFFDFE4EE),
            brand: brand ?? oklch(0.50, 0.15, hue),
            brandSoft: oklch(0.95, 0.035, hue),
          );
  }
}

const _accents = {
  'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a', 'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
  'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a', 'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
  'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e', 'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
  'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o', 'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
  'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o', 'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
  'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u', 'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
  'đ': 'd',
};

/// Sắc độ (0–359) của công ty, giống company-color.js để màu khớp giữa các app.
int companyHue(String name) {
  final lower = name.toLowerCase().split('').map((c) => _accents[c] ?? c).join();
  final key = lower
      .replaceAll(RegExp(r'^ký số\s+|^ky so\s+'), '')
      .replaceAll(RegExp(r'\b(cong ty|cty|tnhh|trach nhiem huu han|co phan|cp|mot thanh vien|mtv|hai thanh vien)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  var hash = 0x811c9dc5;
  for (final c in key.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash % 360;
}

/// OKLCH → sRGB.
Color oklch(double l, double c, int hueDeg) {
  final h = hueDeg * math.pi / 180;
  final a = c * math.cos(h), b = c * math.sin(h);
  final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
  final ll = l_ * l_ * l_, mm = m_ * m_ * m_, ss = s_ * s_ * s_;
  double gamma(double x) {
    final v = x <= 0.0031308 ? 12.92 * x : 1.055 * math.pow(x, 1 / 2.4) - 0.055;
    return v.clamp(0.0, 1.0).toDouble();
  }

  final r = gamma(4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss);
  final g = gamma(-1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss);
  final bl = gamma(-0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss);
  return Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (bl * 255).round());
}

/// Dữ liệu một tab cho dải tab.
class ChromeTab {
  const ChromeTab({required this.title, required this.url, required this.loading});
  final String title;
  final String url;
  final bool loading;
}

/// Biểu tượng trang: favicon.ico của origin, lỗi thì quả địa cầu.
class Favicon extends StatelessWidget {
  const Favicon({super.key, required this.url, required this.color, this.size = 16});
  final String url;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = Uri.tryParse(url);
    final globe = Icon(Icons.public_rounded, size: size, color: color);
    if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) return globe;
    return Image.network(
      '${u.origin}/favicon.ico',
      width: size,
      height: size,
      errorBuilder: (_, _, _) => globe,
    );
  }
}

/// Dải tab 40px: nút công ty (màu công ty, chấm trạng thái), các tab (co giãn tới 360px, tối thiểu 120px), nút +
/// ngay sau tab cuối. Bấm giữa chuột để đóng tab.
class ChromeTabStrip extends StatelessWidget {
  const ChromeTabStrip({
    super.key,
    required this.colors,
    required this.tabs,
    required this.active,
    required this.connected,
    required this.companyInitial,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
    required this.onCompany,
  });
  final ChromeColors colors;
  final List<ChromeTab> tabs;
  final int active;
  final bool connected;
  final String companyInitial;
  final void Function(int i) onSelect;
  final void Function(int i) onClose;
  final VoidCallback onNew;
  final VoidCallback onCompany;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: colors.tab,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(builder: (context, box) {
        // Chỗ cho các tab: trừ nút công ty, nút + và khoảng cách.
        final room = math.max(0.0, box.maxWidth - 30 - 28 - 6 * 3);
        final each = tabs.isEmpty ? 0.0 : (room / tabs.length).clamp(120.0, 360.0);
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Tooltip(
              message: 'Công ty và trạng thái ký số',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCompany,
                child: Stack(clipBehavior: Clip.none, children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: colors.brand,
                    child: Text(companyInitial, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: connected ? const Color(0xFF22A55B) : const Color(0xFFE0A100),
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.tab, width: 2),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (i, t) in tabs.indexed) ...[
                  _TabChip(colors: colors, tab: t, active: i == active, width: each, onSelect: () => onSelect(i), onClose: () => onClose(i)),
                  const SizedBox(width: 2),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tooltip(
              message: 'Tab mới (Ctrl/Cmd+T)',
              child: Material(
                color: colors.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onNew,
                  child: const SizedBox(width: 28, height: 28, child: Icon(Icons.add_rounded, size: 18, color: Colors.white)),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({required this.colors, required this.tab, required this.active, required this.width, required this.onSelect, required this.onClose});
  final ChromeColors colors;
  final ChromeTab tab;
  final bool active;
  final double width;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final bg = widget.active ? c.surface : (_hover ? c.surface.withValues(alpha: 0.5) : Colors.transparent);
    final fg = widget.active ? c.text : c.muted;
    final title = widget.tab.title.trim().isEmpty ? 'Tab mới' : widget.tab.title;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        // Chọn tab ngay lúc nhấn chuột trái; nút giữa thì đóng tab.
        onPointerDown: (e) {
          if (e.buttons == kPrimaryMouseButton) widget.onSelect();
          if (e.buttons == kMiddleMouseButton) widget.onClose();
        },
        child: Tooltip(
          message: widget.tab.url.isEmpty ? title : '$title\n${widget.tab.url}',
          waitDuration: const Duration(milliseconds: 600),
          child: Container(
            width: widget.width,
            height: 34,
            padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
            decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
            child: Row(children: [
              widget.tab.loading
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.brand))
                  : Favicon(url: widget.tab.url, color: fg),
              const SizedBox(width: 8),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: fg))),
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  tooltip: 'Đóng tab',
                  onPressed: widget.onClose,
                  icon: Icon(Icons.close_rounded, color: fg),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Nút biểu tượng 32px bo 8 của thanh công cụ.
class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.tooltip, required this.onPressed, required this.colors, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final ChromeColors colors;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 19,
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              backgroundColor: active ? colors.brandSoft : null,
            ),
            icon: Icon(icon, color: onPressed == null ? colors.muted.withValues(alpha: 0.4) : (active ? colors.brand : colors.text)),
          ),
        ),
      );
}

/// Ô địa chỉ: bo tròn, ổ khoá, chọn hết khi bấm vào; đang gõ thì không bị ghi đè.
class Omnibox extends StatefulWidget {
  const Omnibox({super.key, required this.controller, required this.focusNode, required this.colors, required this.secure, required this.onSubmit});
  final TextEditingController controller;
  final FocusNode focusNode;
  final ChromeColors colors;
  final bool secure;
  final void Function(String text) onSubmit;

  @override
  State<Omnibox> createState() => _OmniboxState();
}

class _OmniboxState extends State<Omnibox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_focus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_focus);
    super.dispose();
  }

  void _focus() {
    if (widget.focusNode.hasFocus) {
      widget.controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final focused = widget.focusNode.hasFocus;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: focused ? c.surface : c.tab,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focused ? c.brand : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        Icon(widget.secure ? Icons.lock_rounded : Icons.public_rounded, size: 14, color: c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            style: TextStyle(fontSize: 13.5, color: c.text),
            cursorColor: c.brand,
            onSubmitted: widget.onSubmit,
            decoration: InputDecoration.collapsed(
              hintText: 'Tìm trên Google hoặc nhập địa chỉ',
              hintStyle: TextStyle(fontSize: 13.5, color: c.muted),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Thanh dấu trang (trang đã ghim của công ty, lưu trên máy chủ ký số, cả công ty thấy như nhau).
class BookmarksBar extends StatelessWidget {
  const BookmarksBar({super.key, required this.colors, required this.bookmarks, required this.onOpen});
  final ChromeColors colors;
  final List<({String title, String url})> bookmarks;
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    if (bookmarks.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 30,
      decoration: BoxDecoration(color: colors.surface, border: Border(bottom: BorderSide(color: colors.line))),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final b in bookmarks)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  foregroundColor: colors.text,
                ),
                onPressed: () => onOpen(b.url),
                icon: Favicon(url: b.url, color: colors.muted, size: 14),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Trang đầu của tab trống: thẻ công ty + lưới trang đã ghim (tên + tên miền), gợi ý nhập địa chỉ.
class ChromeHome extends StatelessWidget {
  const ChromeHome({
    super.key,
    required this.colors,
    required this.company,
    required this.taxCode,
    required this.bookmarks,
    required this.canUnpin,
    required this.onOpen,
    required this.onUnpin,
  });
  final ChromeColors colors;
  final String company;
  final String? taxCode;
  final List<({String title, String url})> bookmarks;
  final bool canUnpin;
  final void Function(String url) onOpen;
  final void Function(String url) onUnpin;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: colors.brandSoft, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    CircleAvatar(radius: 22, backgroundColor: colors.brand, child: const Icon(Icons.draw_rounded, color: Colors.white)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(company, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.text)),
                        if (taxCode != null) Text('MST $taxCode', style: TextStyle(color: colors.muted)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                Text('Trang đã ghim', style: TextStyle(fontWeight: FontWeight.w600, color: colors.text)),
                const SizedBox(height: 10),
                if (bookmarks.isEmpty)
                  Text('Chưa ghim trang nào. Mở một trang rồi bấm biểu tượng ghim trên thanh địa chỉ.', style: TextStyle(color: colors.muted))
                else
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final b in bookmarks)
                      _PinTile(colors: colors, bookmark: b, canUnpin: canUnpin, onOpen: onOpen, onUnpin: onUnpin),
                  ]),
                const SizedBox(height: 24),
                Text('Nhập link vào thanh địa chỉ để mở trang của công ty.', style: TextStyle(color: colors.muted, fontSize: 12.5)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinTile extends StatelessWidget {
  const _PinTile({required this.colors, required this.bookmark, required this.canUnpin, required this.onOpen, required this.onUnpin});
  final ChromeColors colors;
  final ({String title, String url}) bookmark;
  final bool canUnpin;
  final void Function(String url) onOpen;
  final void Function(String url) onUnpin;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(bookmark.url)?.host ?? bookmark.url;
    return SizedBox(
      width: 200,
      child: Material(
        color: colors.tab,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(bookmark.url),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(children: [
              Favicon(url: bookmark.url, color: colors.muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bookmark.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: colors.text)),
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: colors.muted)),
                ]),
              ),
              if (canUnpin)
                IconButton(
                  iconSize: 14,
                  tooltip: 'Bỏ ghim',
                  onPressed: () => onUnpin(bookmark.url),
                  icon: Icon(Icons.close_rounded, color: colors.muted),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
