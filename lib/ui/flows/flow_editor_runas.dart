import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange, kFlowRed;

/// Chế độ chạy của quy trình (`run_as` ở gốc: danh tính khi gọi công cụ) và cho bước ghi dữ liệu chạy không cần duyệt
/// (`allow_without_approval` của bước). Cả hai chỉ quản trị là người thật bật được (máy chủ ghi `enabled_by` / `by`).

/// Các chế độ chạy: (mã, tên, giải thích).
const runAsModes = [
  ('requester', 'Theo người tạo tiến trình', 'Mặc định. Công cụ chạy bằng quyền của người tạo tiến trình (tiến trình tự chạy: người đứng tên ở bước Bắt đầu).'),
  ('creator', 'Theo người soạn quy trình', 'Công cụ chạy bằng quyền của người bật chế độ này (quản trị). Người đó phải còn hoạt động và còn quyền.'),
  ('custom', 'Quy trình là một chủ thể riêng', 'Quy trình có danh tính riêng, được cấp quyền từng app trong Phân quyền (dịch vụ trên Flygo Gateway). Dùng cho quy trình tự chạy như đồng bộ hoá đơn.'),
];

/// Lỗi của máy chủ khi bot / agent đặt trường chỉ quản trị là người thật đặt được.
bool isAdminOnlyError(String msg) => msg.contains('chỉ quản trị là người thật');

/// Lời giải thích cho lỗi [isAdminOnlyError].
String adminOnlyHelp(String msg) => tr(
    'Chế độ chạy và "Cho phép chạy không cần duyệt" chỉ quản trị quy trình là người thật bật được, không phải bot hay trợ lý AI. Hãy mở quy trình trong app bằng tài khoản quản trị của mình, đặt lại rồi bấm Lưu.\n\nMáy chủ báo: {0}',
    [msg]);

/// Ô chọn chế độ chạy. Sửa trực tiếp [meta] (`run_as`), rồi gọi [onChanged].
class RunAsField extends StatelessWidget {
  final Map<String, dynamic> meta;
  final String Function(String id) userName;
  final VoidCallback onChanged;
  const RunAsField({super.key, required this.meta, required this.userName, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final ra = (meta['run_as'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mode = runAsModes.any((m) => m.$1 == ra['mode']) ? '${ra['mode']}' : 'requester';
    final by = '${ra['enabled_by'] ?? ''}';
    final user = '${ra['user'] ?? ''}';
    final id = '${meta['id'] ?? ''}';
    void pick(String m) {
      if (m == mode) return;
      // Đổi chế độ: máy chủ ghi lại người bật / người soạn khi lưu.
      m == 'requester' ? meta.remove('run_as') : meta['run_as'] = <String, dynamic>{'mode': m};
      onChanged();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Chế độ chạy'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 4),
      Text(tr('Danh tính khi quy trình gọi công cụ (ngân hàng, hoá đơn, ERP…). Chỉ quản trị là người thật bật được chế độ khác mặc định.'),
          style: TextStyle(color: pal.sub, fontSize: 12.5)),
      const SizedBox(height: 4),
      RadioGroup<String>(
        groupValue: mode,
        onChanged: (v) => pick(v ?? 'requester'),
        child: Column(children: [
          for (final (m, label, help) in runAsModes)
            RadioListTile<String>(
              key: ValueKey('run-as-$m'),
              contentPadding: EdgeInsets.zero,
              value: m,
              title: Text(tr(label)),
              subtitle: Text(tr(help), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ),
        ]),
      ),
      if (mode == 'custom')
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${tr('Chủ thể')}: ', style: TextStyle(color: pal.sub, fontSize: 12.5)),
            WidgetSpan(child: SelectableText('flow:$id', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text, fontSize: 12.5))),
            TextSpan(text: ' · ${tr('cấp quyền cho chủ thể này trong app Phân quyền / dịch vụ Flygo Gateway')}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ])),
        ),
      if (mode != 'requester')
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Text(
            by.isEmpty
                ? tr('Chưa lưu: bấm Lưu bằng tài khoản quản trị để bật')
                : [
                    tr('Đã bật bởi {0}', [userName(by)]),
                    if (mode == 'creator' && user.isNotEmpty) tr('chạy bằng quyền của {0}', [userName(user)]),
                  ].join(' · '),
            style: TextStyle(color: by.isEmpty ? kFlowOrange : pal.sub, fontSize: 12.5),
          ),
        ),
    ]);
  }
}

/// Bước gọi công cụ có thể ghi dữ liệu: bước tự động gọi MCP, chờ sự kiện hỏi công cụ (như lint
/// `write_without_approval` của máy chủ). Công cụ chỉ đọc (theo danh sách công cụ máy chủ trả về) thì không.
/// [serverOf]: khoá máy chủ / app của tham số công cụ.
bool mayWrite(Map n, Map integ, String Function(Map) serverOf) {
  final Map? p = switch (n['type']) {
    'auto' when n['action'] == 'mcp' => n['params'] as Map?,
    'wait_event' when n['match'] == null => n,
    _ => null,
  };
  if (p == null) return false;
  final tool = '${p['tool'] ?? ''}';
  if (tool.isEmpty) return false;
  final srv = [for (final m in (integ['mcp'] as List? ?? const [])) if (m is Map && m['name'] == serverOf(p)) m].firstOrNull;
  final t = [for (final x in (srv?['tools'] as List? ?? const [])) if (x is Map && x['name'] == tool) x].firstOrNull;
  return t?['read_only'] != true;
}

/// Ô "Cho phép chạy không cần duyệt" của bước ghi dữ liệu: bật thì bắt buộc ghi lý do. Sửa trực tiếp [n].
class WaiverField extends StatefulWidget {
  final Map<String, dynamic> n;
  final String Function(String id) userName;
  final VoidCallback onChanged;
  const WaiverField({super.key, required this.n, required this.userName, required this.onChanged});
  @override
  State<WaiverField> createState() => _WaiverFieldState();
}

class _WaiverFieldState extends State<WaiverField> {
  Map<String, dynamic>? get w {
    final v = widget.n['allow_without_approval'];
    if (v == true) return widget.n['allow_without_approval'] = <String, dynamic>{'reason': ''};
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cur = w;
    final reason = '${cur?['reason'] ?? ''}';
    final by = '${cur?['by'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CheckboxListTile(
        key: const ValueKey('waiver'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: cur != null,
        title: Text(tr('Cho phép chạy không cần duyệt')),
        subtitle: Text(tr('Bước này có thể ghi dữ liệu mà không có bước duyệt nào đứng trước. Chỉ quản trị là người thật đặt được.'),
            style: TextStyle(fontSize: 12.5, color: pal.sub)),
        onChanged: (v) => _set(() => v == true ? widget.n['allow_without_approval'] = <String, dynamic>{'reason': ''} : widget.n.remove('allow_without_approval')),
      ),
      if (cur != null) ...[
        TextFormField(
          key: const ValueKey('waiver-reason'),
          initialValue: reason,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: tr('Lý do (bắt buộc)'),
            hintText: tr('vd Tạo nháp hoá đơn, kế toán ký tay trên M-Invoice'),
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: reason.trim().isEmpty ? tr('Ghi lý do để lưu được') : null,
          ),
          onChanged: (v) => _set(() {
            final m = <String, dynamic>{'reason': v.trim()};
            // Giữ người đã đặt khi lý do không đổi (máy chủ cũng giữ như vậy).
            if (by.isNotEmpty && v.trim() == reason) m['by'] = by;
            widget.n['allow_without_approval'] = m;
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            by.isEmpty ? tr('Chưa lưu: bấm Lưu bằng tài khoản quản trị để áp dụng') : tr('Đã cho phép bởi {0}', [widget.userName(by)]),
            style: TextStyle(fontSize: 12.5, color: by.isEmpty ? kFlowOrange : pal.sub),
          ),
        ),
      ],
    ]);
  }
}

/// Hộp báo lỗi chỉ quản trị là người thật (403 khi lưu).
Future<void> showAdminOnlyError(BuildContext context, String msg) => showDialog(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined, color: kFlowRed),
        title: Text(tr('Cần quản trị là người thật')),
        content: Text(adminOnlyHelp(msg)),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text(tr('Đã hiểu')))],
      ),
    );
