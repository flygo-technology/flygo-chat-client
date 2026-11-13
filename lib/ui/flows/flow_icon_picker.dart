import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../flygo_card.dart' show cardKeywordIcon;
import '../theme.dart';

/// Biểu tượng quy trình: các nhóm emoji (Unicode) kèm từ khoá tiếng Việt để lọc nhanh.
/// Mỗi dòng: tên nhóm, rồi các cặp (emoji, từ khoá).
const _groups = <(String, List<(String, String)>)>[
  ('Công việc', [
    ('📋', 'danh sách bảng kẹp hồ sơ'), ('📝', 'ghi chép viết đơn'), ('✅', 'xong duyệt đồng ý'), ('☑️', 'đánh dấu chọn'), ('✔️', 'đúng xác nhận'),
    ('📌', 'ghim'), ('📍', 'vị trí ghim'), ('📎', 'kẹp tệp đính kèm'), ('🖇️', 'kẹp giấy'), ('📁', 'thư mục hồ sơ'), ('📂', 'thư mục mở'),
    ('🗂️', 'phân loại hồ sơ'), ('🗃️', 'hộp hồ sơ lưu trữ'), ('🗄️', 'tủ hồ sơ'), ('📑', 'tab tài liệu'), ('📄', 'trang tài liệu'), ('📃', 'văn bản'),
    ('📜', 'cuộn giấy hợp đồng'), ('🧾', 'hoá đơn biên lai'), ('📊', 'biểu đồ báo cáo'), ('📈', 'tăng trưởng doanh thu'), ('📉', 'giảm'),
    ('🗒️', 'sổ ghi chú'), ('🗓️', 'lịch kế hoạch'), ('📅', 'lịch ngày'), ('📆', 'lịch tháng'), ('⏰', 'báo thức hạn'), ('⏳', 'chờ thời gian'),
    ('⌛', 'đồng hồ cát hết hạn'), ('🕒', 'giờ'), ('⏱️', 'bấm giờ'), ('📨', 'thư đến'), ('📩', 'thư gửi'), ('📧', 'email'), ('✉️', 'phong bì thư'),
    ('📬', 'hộp thư'), ('📮', 'bưu điện'), ('📤', 'gửi đi'), ('📥', 'nhận về'), ('📦', 'gói hàng'), ('🔖', 'nhãn đánh dấu'), ('🏷️', 'nhãn giá'),
    ('🖊️', 'bút ký'), ('✍️', 'ký tên'), ('🖋️', 'bút mực'), ('✏️', 'bút chì sửa'), ('🔍', 'tìm kiếm kiểm tra'), ('🔎', 'soi kiểm tra'),
    ('💼', 'cặp công việc'), ('🗳️', 'bỏ phiếu'), ('📇', 'danh thiếp'), ('🪪', 'thẻ căn cước'), ('📢', 'thông báo loa'), ('📣', 'loa thông báo'),
    ('🔔', 'chuông nhắc'), ('💬', 'tin nhắn chat'), ('🗨️', 'trao đổi'), ('🤝', 'bắt tay hợp tác ký kết'), ('🎯', 'mục tiêu kpi'), ('🏆', 'thành tích'),
  ]),
  ('Tài chính', [
    ('💰', 'túi tiền'), ('💵', 'tiền đô tạm ứng'), ('💴', 'tiền yên'), ('💶', 'tiền euro'), ('💷', 'tiền bảng'), ('💸', 'chi tiền thanh toán'),
    ('💳', 'thẻ thanh toán'), ('🪙', 'đồng xu'), ('🏦', 'ngân hàng'), ('🏧', 'atm'), ('💲', 'giá'), ('💹', 'chứng khoán tỷ giá'), ('🧮', 'bàn tính kế toán'),
    ('📒', 'sổ cái'), ('📓', 'sổ'), ('📔', 'sổ tay'), ('📕', 'sách đỏ'), ('📗', 'sổ xanh'), ('📘', 'sổ xanh dương'), ('📙', 'sổ cam'), ('🧾', 'chứng từ hoá đơn'),
    ('🏛️', 'thuế nhà nước'), ('⚖️', 'cân pháp lý'), ('🔐', 'khoá bảo mật'), ('🪪', 'giấy tờ'), ('📊', 'tài chính báo cáo'), ('🤑', 'lãi'),
    ('🎁', 'quà thưởng'), ('🛍️', 'mua sắm'), ('🛒', 'mua hàng giỏ'), ('🧧', 'lì xì thưởng tết'), ('💎', 'tài sản kim cương'), ('🏠', 'nhà bất động sản'),
  ]),
  ('Nhân sự', [
    ('👤', 'người'), ('👥', 'nhóm người'), ('🧑‍💼', 'nhân viên văn phòng'), ('👨‍💼', 'nam nhân viên'), ('👩‍💼', 'nữ nhân viên'), ('🧑‍🔧', 'kỹ thuật viên'),
    ('👷', 'công nhân'), ('👷‍♀️', 'nữ công nhân'), ('🧑‍🏭', 'công nhân nhà máy'), ('🧑‍💻', 'lập trình it'), ('🧑‍🏫', 'đào tạo giáo viên'), ('🧑‍⚕️', 'y tế'),
    ('🧑‍🍳', 'bếp ăn'), ('🧑‍✈️', 'phi công'), ('🧑‍⚖️', 'pháp chế'), ('🕵️', 'kiểm tra giám sát'), ('💂', 'bảo vệ'), ('🙋', 'đề xuất giơ tay'),
    ('🙋‍♀️', 'đề nghị'), ('🙏', 'xin cảm ơn'), ('👋', 'chào nghỉ việc'), ('🤒', 'ốm nghỉ bệnh'), ('🤰', 'thai sản'), ('👶', 'con nhỏ'), ('🎂', 'sinh nhật'),
    ('🎉', 'chúc mừng sự kiện'), ('🎊', 'tiệc'), ('🌴', 'nghỉ phép du lịch'), ('🏖️', 'nghỉ mát'), ('🏝️', 'đảo nghỉ'), ('🛌', 'nghỉ ngơi'),
    ('🏥', 'bệnh viện'), ('💊', 'thuốc'), ('🩺', 'khám sức khoẻ'), ('🎓', 'bằng cấp đào tạo'), ('📚', 'sách học'), ('🧠', 'kiến thức'),
    ('🪪', 'hồ sơ nhân sự'), ('🆔', 'mã số'), ('🧳', 'công tác'), ('🎽', 'đồng phục'), ('🍱', 'cơm trưa'), ('☕', 'cà phê giải lao'),
  ]),
  ('Kho vận', [
    ('📦', 'kho hàng gói'), ('🏭', 'nhà máy sản xuất'), ('🏗️', 'công trình xây dựng'), ('🏢', 'toà nhà văn phòng'), ('🏬', 'cửa hàng'), ('🏪', 'tạp hoá'),
    ('🛒', 'mua hàng'), ('🛍️', 'bán hàng'), ('🧰', 'hộp đồ nghề'), ('🔧', 'cờ lê sửa chữa'), ('🔩', 'ốc vít linh kiện'), ('🪛', 'tua vít'),
    ('🛠️', 'bảo trì'), ('⚙️', 'bánh răng cài đặt'), ('🧱', 'gạch vật tư'), ('🪵', 'gỗ'), ('🔌', 'điện'), ('💡', 'đèn ý tưởng'), ('🔋', 'pin'),
    ('🪜', 'thang'), ('🛗', 'thang máy'), ('🚪', 'cửa'), ('🪟', 'cửa sổ'), ('🧯', 'bình cứu hoả pccc'), ('🦺', 'áo bảo hộ an toàn'), ('⛑️', 'mũ bảo hộ'),
    ('🏷️', 'mã hàng nhãn'), ('📏', 'thước đo'), ('📐', 'thước kỹ thuật'), ('⚖️', 'cân hàng'), ('🧪', 'thí nghiệm kiểm định'), ('🔬', 'kiểm nghiệm'),
    ('🗜️', 'kẹp'), ('⛓️', 'xích'), ('🪝', 'móc'), ('🧲', 'nam châm'), ('🛢️', 'thùng dầu'), ('⛽', 'xăng'), ('🧹', 'vệ sinh'), ('🧺', 'giỏ'),
  ]),
  ('Giao thông', [
    ('🚚', 'xe tải giao hàng'), ('🚛', 'xe container'), ('🚐', 'xe van'), ('🚗', 'ô tô'), ('🚙', 'xe suv'), ('🚕', 'taxi'), ('🚌', 'xe buýt'),
    ('🚑', 'cấp cứu'), ('🚒', 'cứu hoả'), ('🚓', 'cảnh sát'), ('🏍️', 'xe máy'), ('🛵', 'xe tay ga'), ('🚲', 'xe đạp'), ('🛴', 'xe trượt'),
    ('🚜', 'máy kéo'), ('🏎️', 'xe đua'), ('✈️', 'máy bay công tác'), ('🛫', 'cất cánh'), ('🛬', 'hạ cánh'), ('🚁', 'trực thăng'), ('🚢', 'tàu thuỷ'),
    ('⛴️', 'phà'), ('🚤', 'ca nô'), ('⚓', 'mỏ neo cảng'), ('🚆', 'tàu hoả'), ('🚇', 'tàu điện'), ('🚉', 'ga'), ('🛣️', 'đường cao tốc'),
    ('🗺️', 'bản đồ'), ('🧭', 'la bàn'), ('📍', 'địa điểm'), ('🚦', 'đèn giao thông'), ('🚧', 'công trường'), ('🅿️', 'bãi đỗ xe'), ('⛽', 'đổ xăng'),
  ]),
  ('Đồ vật', [
    ('💻', 'máy tính'), ('🖥️', 'màn hình'), ('⌨️', 'bàn phím'), ('🖱️', 'chuột'), ('🖨️', 'máy in'), ('📱', 'điện thoại'), ('☎️', 'điện thoại bàn'),
    ('📞', 'gọi'), ('📠', 'fax'), ('📷', 'máy ảnh'), ('📹', 'camera'), ('🎥', 'quay phim'), ('📺', 'tivi'), ('📻', 'radio'), ('🎙️', 'micro'),
    ('🎧', 'tai nghe'), ('💾', 'lưu'), ('💿', 'đĩa'), ('🗝️', 'chìa khoá cũ'), ('🔑', 'chìa khoá'), ('🔒', 'khoá'), ('🔓', 'mở khoá'),
    ('🪑', 'ghế'), ('🛋️', 'sofa'), ('🛏️', 'giường'), ('🚿', 'vòi sen'), ('🧴', 'chai'), ('🧼', 'xà phòng'), ('🪣', 'xô'), ('🧻', 'giấy'),
    ('✂️', 'kéo'), ('📏', 'thước'), ('🖌️', 'cọ vẽ'), ('🖍️', 'bút màu'), ('🎨', 'thiết kế màu'), ('🧵', 'chỉ'), ('🪡', 'kim'), ('👕', 'áo'),
    ('👔', 'cà vạt'), ('👟', 'giày'), ('🎒', 'ba lô'), ('👜', 'túi xách'), ('☂️', 'ô'), ('⌚', 'đồng hồ'), ('💍', 'nhẫn'), ('🕶️', 'kính'),
  ]),
  ('Ăn uống', [
    ('☕', 'cà phê'), ('🍵', 'trà'), ('🧋', 'trà sữa'), ('🥤', 'nước'), ('🍺', 'bia'), ('🍷', 'rượu'), ('🥂', 'cụng ly'), ('🍱', 'cơm hộp'),
    ('🍜', 'phở bún'), ('🍚', 'cơm'), ('🍞', 'bánh mì'), ('🍕', 'pizza'), ('🍔', 'burger'), ('🍰', 'bánh ngọt'), ('🎂', 'bánh sinh nhật'),
    ('🍎', 'táo'), ('🍊', 'cam'), ('🍉', 'dưa hấu'), ('🍌', 'chuối'), ('🍇', 'nho'), ('🥗', 'salad'), ('🍳', 'nấu ăn'), ('🍽️', 'bữa ăn'),
  ]),
  ('Thiên nhiên', [
    ('☀️', 'nắng'), ('🌤️', 'trời'), ('🌧️', 'mưa'), ('⛈️', 'bão'), ('❄️', 'lạnh tuyết'), ('🌈', 'cầu vồng'), ('🔥', 'lửa gấp'), ('💧', 'nước giọt'),
    ('🌊', 'sóng'), ('🌱', 'mầm khởi đầu'), ('🌿', 'lá'), ('🍀', 'may mắn'), ('🌳', 'cây'), ('🌲', 'thông'), ('🌵', 'xương rồng'), ('🌸', 'hoa'),
    ('🌻', 'hướng dương'), ('🌷', 'tulip'), ('🍁', 'lá phong'), ('🌍', 'trái đất'), ('🌏', 'châu á'), ('🌙', 'trăng đêm'), ('⭐', 'sao'), ('⚡', 'sét nhanh'),
    ('🐶', 'chó'), ('🐱', 'mèo'), ('🐝', 'ong'), ('🐟', 'cá'), ('🐔', 'gà'), ('🐄', 'bò'),
  ]),
  ('Biểu tượng', [
    ('⭐', 'sao quan trọng'), ('🌟', 'nổi bật'), ('✨', 'mới'), ('❗', 'chú ý'), ('❓', 'câu hỏi'), ('⚠️', 'cảnh báo'), ('🚫', 'cấm'), ('⛔', 'dừng'),
    ('❌', 'sai huỷ'), ('⭕', 'tròn'), ('🔴', 'đỏ'), ('🟠', 'cam'), ('🟡', 'vàng'), ('🟢', 'xanh lá'), ('🔵', 'xanh dương'), ('🟣', 'tím'),
    ('⚫', 'đen'), ('⚪', 'trắng'), ('🟥', 'vuông đỏ'), ('🟩', 'vuông xanh'), ('🟦', 'vuông lam'), ('🟨', 'vuông vàng'), ('❤️', 'tim'),
    ('💯', 'trăm điểm'), ('🔄', 'lặp lại'), ('🔁', 'định kỳ'), ('🔀', 'rẽ nhánh'), ('➡️', 'tiếp'), ('⬅️', 'trước'), ('⬆️', 'lên'), ('⬇️', 'xuống'),
    ('↩️', 'trả lại'), ('🔃', 'đồng bộ'), ('➕', 'thêm'), ('➖', 'bớt'), ('✖️', 'nhân'), ('➗', 'chia'), ('#️⃣', 'số'), ('🔢', 'đánh số'),
    ('🔤', 'chữ'), ('🆕', 'mới'), ('🆗', 'ok'), ('🆘', 'khẩn cấp'), ('🔝', 'đầu'), ('🔜', 'sắp tới'), ('♻️', 'tái chế'), ('🛡️', 'bảo vệ'),
    ('🔗', 'liên kết'), ('🧩', 'tích hợp mảnh ghép'), ('🤖', 'robot ai tự động'), ('🧠', 'ai trí tuệ'), ('💡', 'ý tưởng'), ('🚀', 'triển khai'),
    ('🏁', 'về đích hoàn tất'), ('🚩', 'cờ'), ('🎌', 'cờ'), ('🇻🇳', 'việt nam'),
  ]),
];

/// Mở bảng chọn biểu tượng (emoji); trả về emoji được chọn, null nếu đóng.
/// [keywords]: có thêm nhóm biểu tượng của thẻ (invoice, debt, task…) — dùng cho tiến trình, thẻ vẽ đúng hình.
Future<String?> pickFlowIcon(BuildContext context, {String current = '', bool keywords = false}) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _IconPicker(current: current, keywords: keywords)),
    );

/// Từ khoá biểu tượng của thẻ → tên (như `docs/flygo-card.md`).
const cardIconKeywords = {
  'invoice': 'Hoá đơn',
  'debt': 'Công nợ',
  'incident': 'Sự cố',
  'sign': 'Ký số',
  'report': 'Báo cáo',
  'order': 'Đơn hàng',
  'attendance': 'Chấm công',
  'event': 'Lịch hẹn',
  'task': 'Công việc',
  'info': 'Thông báo',
};

/// Biểu tượng của quy trình / tiến trình: từ khoá thẻ (invoice…) vẽ thành hình, còn lại là emoji.
Widget flowIconView(String icon, {double size = 26, Color? color}) {
  final k = cardKeywordIcon(icon);
  if (k != null) return Icon(k, size: size * 1.05, color: color);
  return Text(icon, style: TextStyle(fontSize: size));
}

class _IconPicker extends StatefulWidget {
  final String current;
  final bool keywords;
  const _IconPicker({required this.current, this.keywords = false});
  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _q.trim().toLowerCase();
    final groups = [
      for (final (name, items) in _groups)
        (name, <String>{for (final (e, k) in items) if (q.isEmpty || k.contains(q) || tr(name).toLowerCase().contains(q) || e == q) e}.toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(child: Text(tr('Chọn biểu tượng'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
          if (widget.current.isNotEmpty) flowIconView(widget.current, color: pal.accentText),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm: tiền, xe, nghỉ phép, kho...'), isDense: true, border: const OutlineInputBorder()),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: groups.isEmpty
            ? Center(child: Text(tr('Không thấy biểu tượng nào'), style: TextStyle(color: pal.sub)))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
                if (widget.keywords && q.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(tr('Biểu tượng thẻ').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: pal.sub)),
                  ),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final e in cardIconKeywords.entries)
                      InkWell(
                        key: ValueKey('icon-kw-${e.key}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(context, e.key),
                        child: Container(
                          width: 76,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: e.key == widget.current ? BoxDecoration(color: pal.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)) : null,
                          child: Column(children: [
                            flowIconView(e.key, size: 24, color: pal.accentText),
                            const SizedBox(height: 2),
                            Text(tr(e.value), style: TextStyle(fontSize: 11, color: pal.sub), overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                  ]),
                ],
                for (final (name, items) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(tr(name).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: pal.sub)),
                  ),
                  Wrap(children: [
                    for (final e in items)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(context, e),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: e == widget.current ? BoxDecoration(color: pal.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)) : null,
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                  ]),
                ],
              ]),
      ),
    ]);
  }
}
