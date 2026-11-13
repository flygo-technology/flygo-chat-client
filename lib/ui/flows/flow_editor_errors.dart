import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_editor.dart' show WhoField, durLabel;

/// Khi bước lỗi (tự động, AI, chờ sự kiện, bắt đầu quy trình khác): dừng / bỏ qua / giao người làm tay / rẽ sang
/// nhánh Lỗi (`on_error: {"to"}`), cộng thời hạn mỗi lần gọi (`timeout`; chờ sự kiện: `call_timeout`).

/// Cách xử lý lỗi dùng được theo loại bước: fail, continue, assign, branch.
List<String> errorModes(String type) => switch (type) {
      'wait_event' || 'start_flow' || 'process_wait' || 'doc_render' => const ['fail', 'branch'],
      // Đọc hết trang: không giao việc tay (máy chủ không cho).
      'mcp_pages' => const ['fail', 'continue', 'branch'],
      _ => const ['fail', 'continue', 'assign', 'branch'],
    };

/// Cách xử lý lỗi hiện tại của [n].
String errorMode(Map n) {
  final e = n['on_error'];
  if (e is Map) return e.containsKey('to') ? 'branch' : 'assign';
  return e == 'continue' ? 'continue' : 'fail';
}

/// Mọi loại bước cùng một cách gọi: "Dừng luồng (mặc định)" / "Đi nhánh lỗi"; chỉ Chờ sự kiện hỏi công cụ và Chờ tiến
/// trình có mặc định riêng. [byKey]: Chờ sự kiện theo khoá (không hỏi công cụ) dùng mặc định chung.
String errorModeLabel(String type, String mode, {bool byKey = false}) => switch (mode) {
      'continue' => tr('Bỏ qua, đi tiếp'),
      'assign' => tr('Giao người làm tay'),
      'branch' => tr('Đi nhánh lỗi'),
      _ => switch (type) {
          'wait_event' when !byKey => tr('Hỏi lại lần sau (mặc định)'),
          'process_wait' => tr('Vẫn chờ tiếp (mặc định)'),
          _ => tr('Dừng luồng (mặc định)'),
        },
    };

/// Khoá thời hạn mỗi lần gọi: auto / ai `timeout`, wait_event `call_timeout`, start_flow (chờ một luồng con) `timeout`.
String? callTimeoutKey(Map n) => switch (n['type']) {
      'wait_event' when n['match'] == null => 'call_timeout',
      'auto' || 'ai' || 'mcp_pages' => 'timeout',
      // Chờ một luồng con: quá hạn thì nhánh Lỗi mã "timeout" (nhiều luồng con có ô Hạn chờ riêng).
      'start_flow' when n['wait'] == true && n['each'] == null && n['each_person'] == null => 'timeout',
      _ => null,
    };

/// Ô chọn cách xử lý lỗi + thời hạn mỗi lần gọi. Sửa trực tiếp [n].
class ErrorPolicyField extends StatelessWidget {
  final AppState app;
  final Map<String, dynamic> n;
  final Map<String, List<String>> roles;
  final VoidCallback onChanged;
  final String? label;
  const ErrorPolicyField({super.key, required this.app, required this.n, required this.onChanged, this.roles = const {}, this.label});

  void _setMode(String m) {
    switch (m) {
      case 'branch':
        n['on_error'] = <String, dynamic>{'to': ''};
      case 'assign':
        n['on_error'] = <String, dynamic>{'assign': r'$requester'};
      case 'continue':
        n['on_error'] = 'continue';
      default:
        // Chờ sự kiện / bắt đầu quy trình khác: mặc định là bỏ trống.
        const {'wait_event', 'start_flow', 'process_wait', 'doc_render'}.contains(n['type']) ? n.remove('on_error') : n['on_error'] = 'fail';
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final type = '${n['type']}';
    final modes = errorModes(type);
    final mode = errorMode(n);
    final tk = callTimeoutKey(n);
    final cur = '${tk == null ? '' : n[tk] ?? ''}';
    final presets = type == 'start_flow' ? const ['15m', '1h', '4h', '1d', '3d'] : const ['30s', '1m', '5m', '15m', '1h'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        key: ValueKey('on-error-$mode'),
        initialValue: modes.contains(mode) ? mode : modes.first,
        isExpanded: true,
        decoration: InputDecoration(labelText: label ?? tr('Khi bước lỗi'), border: const OutlineInputBorder()),
        items: [for (final m in modes) DropdownMenuItem(value: m, child: Text(errorModeLabel(type, m, byKey: type == 'wait_event' && n['match'] is Map)))],
        onChanged: (v) => _setMode(v ?? 'fail'),
      ),
      if (mode == 'assign') ...[
        const SizedBox(height: 8),
        WhoField(app: app, roles: roles, label: tr('Người làm tay'), value: (n['on_error'] as Map)['assign'], onChanged: (w) {
          n['on_error'] = <String, dynamic>{'assign': w};
          onChanged();
        }),
      ],
      if (mode == 'branch')
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            tr('Sơ đồ có thêm nhánh «Lỗi» (bên cạnh nhánh «Thành công»). Trong nhánh dùng «{0} › Lỗi › Nội dung / Mã» (mã: timeout, http_502, bad_output, child_failed…).',
                ['${n['name'] ?? ''}'.trim().isEmpty ? tr('bước này') : '${n['name']}'.trim()]),
            style: TextStyle(color: pal.sub, fontSize: 12.5),
          ),
        ),
      if (type == 'auto' || type == 'ai')
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Thử lại theo số lần thử lại trước; lần cuối vẫn lỗi mới xử lý như trên.'), style: TextStyle(color: pal.sub, fontSize: 12)),
        ),
      if (tk != null) ...[
        const SizedBox(height: 12),
        Text(type == 'start_flow' ? tr('Chờ luồng kia tối đa') : tr('Mỗi lần gọi tối đa'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(
            label: Text(tr('Không giới hạn')),
            selected: cur.isEmpty,
            onSelected: (_) {
              n.remove(tk);
              onChanged();
            },
          ),
          for (final d in {...presets, if (cur.isNotEmpty) cur})
            ChoiceChip(
              label: Text(durLabel(d)),
              selected: cur == d,
              onSelected: (_) {
                n[tk] = d;
                onChanged();
              },
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            type == 'start_flow' ? tr('Quá hạn thì đi tiếp với «Quá hạn chờ»; có nhánh Lỗi thì đi nhánh Lỗi (mã timeout).') : tr('Quá thời gian thì lần gọi đó tính là lỗi, mã "timeout".'),
            style: TextStyle(color: pal.sub, fontSize: 12),
          ),
        ),
      ],
    ]);
  }
}
