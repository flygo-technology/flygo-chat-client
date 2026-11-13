import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'flow_cond.dart' show CondVar;
import 'flow_editor.dart' show TemplateField;

/// Điểm gắn của Magic Sign (trình duyệt ký số trong app). Mô-đun Magic Sign đăng ký khi khởi động; Quy trình chỉ gọi.
/// Chưa đăng ký (null) thì nút ký số mở link như thường.
class MagicSignHooks {
  /// Mở [url] bằng trình duyệt ký số với token công ty [token] (mã hoặc tên), máy chủ ký số [server] nếu có.
  static Future<void> Function(BuildContext context, {required String token, required String url, String? server})? openSignBrowser;

  /// Các token công ty có trên app này (cho trình sửa quy trình chọn).
  static Future<List<({String id, String name, String company})>> Function()? signTokens;
}

/// Nút link của quy trình (`{label, url, sign?: {token, server?}}`): có `sign` thì mở bằng trình duyệt ký số; chưa cài
/// ký số thì mở link như thường kèm thông báo nhỏ. Trả về true nếu đã xử lý (nút có `sign`); false = để nơi gọi mở
/// link như cũ.
Future<bool> openFlowSignButton(BuildContext context, Map b) async {
  final sign = b['sign'];
  final url = '${b['url'] ?? ''}'.trim();
  if (sign is! Map || url.isEmpty) return false;
  final token = '${sign['token'] ?? ''}'.trim();
  final server = '${sign['server'] ?? ''}'.trim();
  final hook = MagicSignHooks.openSignBrowser;
  if (hook != null && token.isNotEmpty) {
    await hook(context, token: token, url: url, server: server.isEmpty ? null : server);
    return true;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final u = Uri.tryParse(url);
  if (u != null && (u.scheme == 'https' || u.scheme == 'http')) await launchUrl(u, mode: LaunchMode.externalApplication);
  messenger?.showSnackBar(toast(Text(tr('Chưa cài ký số trên app này'))));
  return true;
}

/// Trình sửa: nút "chỉ mở link" thêm tuỳ chọn "Mở bằng trình duyệt ký số" (token công ty: chọn từ danh sách token của
/// app nếu có, hoặc gõ / chèn thông tin; máy chủ ký số tuỳ chọn).
class FlowSignEditor extends StatefulWidget {
  /// Nút đang sửa (Map của JSON quy trình); bật thì có `sign`.
  final Map<String, dynamic> button;
  final List<CondVar> vars;
  final VoidCallback onChanged;
  const FlowSignEditor({super.key, required this.button, required this.vars, required this.onChanged});
  @override
  State<FlowSignEditor> createState() => _FlowSignEditorState();
}

class _FlowSignEditorState extends State<FlowSignEditor> {
  List<({String id, String name, String company})> _tokens = const [];
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    final f = MagicSignHooks.signTokens;
    if (f != null) {
      f().then((l) {
        if (mounted) setState(() => _tokens = l);
      }).catchError((_) {});
    }
  }

  Map<String, dynamic>? get _sign => widget.button['sign'] is Map ? (widget.button['sign'] as Map).cast<String, dynamic>() : null;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final sign = _sign;
    final token = '${sign?['token'] ?? ''}';
    final picked = _tokens.where((t) => t.id == token || t.name == token).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        key: const ValueKey('sign-toggle'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(tr('Mở bằng trình duyệt ký số')),
        value: sign != null,
        onChanged: (v) => _set(() => v ? widget.button['sign'] = <String, dynamic>{'token': ''} : widget.button.remove('sign')),
      ),
      if (sign != null) ...[
        if (_tokens.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('sign-pick-$_rev'),
            initialValue: picked?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Token công ty'), isDense: true, border: const OutlineInputBorder()),
            items: [
              for (final t in _tokens)
                DropdownMenuItem(value: t.id, child: Text(t.company.isEmpty ? t.name : '${t.name} · ${t.company}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _set(() {
              sign['token'] = v ?? '';
              widget.button['sign'] = sign;
              _rev++;
            }),
          ),
          const SizedBox(height: 6),
        ],
        TemplateField(
          key: ValueKey('sign-token-$_rev'),
          label: _tokens.isEmpty ? tr('Token công ty (mã, tên hoặc chèn thông tin)') : tr('Hoặc gõ token (mã, tên hoặc chèn thông tin)'),
          raw: token,
          vars: widget.vars,
          lines: 1,
          onChanged: (v) {
            sign['token'] = v.trim();
            widget.button['sign'] = sign;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 6),
        TemplateField(
          key: ValueKey('sign-server-$_rev'),
          label: tr('Máy chủ ký số (không bắt buộc)'),
          raw: '${sign['server'] ?? ''}',
          vars: widget.vars,
          lines: 1,
          onChanged: (v) {
            v.trim().isEmpty ? sign.remove('server') : sign['server'] = v.trim();
            widget.button['sign'] = sign;
            widget.onChanged();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('Nút mở link không rẽ nhánh: nên thêm một nút "Đã ký xong" (rẽ nhánh) để chạy tiếp quy trình sau khi ký.'),
              style: TextStyle(fontSize: 12, color: pal.sub)),
        ),
      ],
    ]);
  }
}
