import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../clip.dart' show readClipboardMedia;
import '../location.dart' show currentPosition;
import '../media_picker.dart' show CameraCapturePage, MediaPickResult;
import '../theme.dart';
import 'flow_delegations.dart' show DelegationField;
import 'flow_logic.dart';
import 'flow_location.dart';
import 'flow_lookup.dart';
import 'flow_table.dart';
import 'flow_task_action.dart' show FlowNotice;
import 'package:flygo_chat/ui/app_route.dart';
import '../common.dart' show pickFilesOrReport;

/// Form sinh từ định nghĩa flow: nộp đơn mới, sửa và nộp lại, hoặc điền form của một bước.
class FlowFormPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final String title;
  final List<FlowField> fields;
  final Map<String, dynamic> initial;
  /// Hiện ô "Tiêu đề đơn" (chỉ khi nộp đơn mới); [initialTitle]: tiêu đề điền sẵn.
  final bool askTitle;
  final String initialTitle;
  final String submitLabel;
  /// Quy trình (để tra danh mục). [lookupPath]: đường dẫn trường khi tra danh mục (mặc định = khoá trường).
  final String? flowId;
  final String Function(FlowField f)? lookupPath;
  /// Gửi đi; ném lỗi thì form hiện lỗi và giữ nguyên dữ liệu.
  final Future<void> Function(Map<String, dynamic> data, String title) onSubmit;
  /// Gửi xong: mặc định đóng trang (trả về true); có [onDone] thì để nó điều hướng (vd thay bằng trang chi tiết việc).
  final void Function(BuildContext context)? onDone;
  /// Dòng nhắc ở đầu form (vd `Bị trả lại: <lý do>` khi bước Điền thông tin bị trả lại).
  final String notice;
  /// Nhúng trong trang khác (vd trang tiến trình): chỉ ô nhập + nút Gửi, không thanh tiêu đề, không tự đóng trang.
  final bool embedded;
  const FlowFormPage({
    super.key,
    required this.app,
    required this.api,
    required this.title,
    required this.fields,
    required this.onSubmit,
    this.initial = const {},
    this.askTitle = false,
    this.initialTitle = '',
    this.submitLabel = '',
    this.flowId,
    this.lookupPath,
    this.onDone,
    this.notice = '',
    this.embedded = false,
  });
  @override
  State<FlowFormPage> createState() => _FlowFormPageState();
}

class _FlowFormPageState extends State<FlowFormPage> {
  // Giá trị mặc định của quy trình, rồi giá trị có sẵn (sửa đơn bị trả lại) đè lên.
  late final Map<String, dynamic> _data = {
    for (final f in widget.fields) if (f.defaultValue != null) f.key: f.defaultValue,
    ...widget.initial,
  };
  final _ctl = <String, TextEditingController>{};
  late final _titleCtl = TextEditingController(text: widget.initialTitle);
  Map<String, String> _errs = {};
  String? _serverErr;
  bool _busy = false;
  final _uploading = <String>{};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      // Ô chọn từ danh mục giữ giá trị trong _data (LookupField có ô chữ riêng); ô chữ thừa ở đây sẽ ghi đè bằng chuỗi rỗng khi gửi.
      if (f.type == 'text' && f.lookup != null && widget.flowId != null) continue;
      if (const {'text', 'textarea', 'number', 'money'}.contains(f.type)) {
        final v = _data[f.key];
        _ctl[f.key] = TextEditingController(
            text: v == null ? '' : (f.type == 'money' && v is num ? (f.currency.isEmpty ? vnNumber(v) : vnDecimal(v)) : '$v'))
          // Gõ thì tính lại trường tự tính / trường hiện theo điều kiện.
          ..addListener(() {
            if (mounted && _reactive) setState(() {});
          });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoCapture();
    });
  }

  /// Chỉ gồm trường app tự lấy (vị trí, Wi-Fi) — vd chấm công: người dùng chỉ bấm bắt đầu, không có ô nào để nhập
  /// hay sửa; lấy xong thì tự gửi.
  bool get _autoOnly {
    final shown = [for (final f in widget.fields) if (f.calc == null && fieldVisible(f, _data)) f];
    return shown.isNotEmpty && shown.every((f) => f.type == 'location' || f.type == 'wifi');
  }

  bool _autoSent = false;

  /// Đủ trường bắt buộc (Wi-Fi không bắt buộc thì đọc không được vẫn gửi) và không còn trường nào đang lấy: gửi luôn.
  void _maybeAutoSubmit() {
    if (!_autoOnly || _autoSent || _busy || _capturing.isNotEmpty) return;
    for (final f in widget.fields) {
      if (!fieldVisible(f, _data) || f.calc != null) continue;
      if (_data[f.key] == null && (f.required || !_captureErr.containsKey(f.key))) return;
    }
    _autoSent = true;
    _submit().then((_) {
      if (mounted && _serverErr != null) setState(() => _autoSent = false);
    });
  }

  /// Mở việc: tự lấy vị trí / Wi-Fi cho các trường đang hiện mà chưa có giá trị.
  void _autoCapture() {
    for (final f in widget.fields) {
      if (_data[f.key] != null || !fieldVisible(f, _data)) continue;
      if (f.type == 'location') _captureLocation(f);
      if (f.type == 'wifi') _captureWifi(f);
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _titleCtl.dispose();
    super.dispose();
  }

  /// Đọc lại các ô chữ vào dữ liệu form.
  void _collect() {
    for (final f in widget.fields) {
      final c = _ctl[f.key];
      if (c == null) continue;
      final t = c.text.trim();
      _data[f.key] = switch (f.type) {
        'money' when f.currency.isNotEmpty => t.isEmpty ? null : (parseDecimal(t) ?? t),
        'number' => t.isEmpty ? null : (parseMoney(t) ?? parseDecimal(t) ?? t),
        'money' => t.isEmpty ? null : (parseMoney(t) ?? t),
        _ => t.isEmpty ? null : t,
      };
    }
    _data.removeWhere((_, v) => v == null);
  }

  Future<void> _submit() async {
    _collect();
    for (final f in widget.fields) {
      if (f.calc != null || !fieldVisible(f, _data)) _data.remove(f.key);
    }
    final errs = validateFlowForm(widget.fields, _data);
    setState(() {
      _errs = errs;
      _serverErr = null;
    });
    if (errs.isNotEmpty || _uploading.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(Map.of(_data), _titleCtl.text.trim());
      if (mounted) {
        if (widget.onDone != null) {
          widget.onDone!(context);
        } else if (!widget.embedded) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _serverErr = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Trường tự lấy (vị trí, Wi-Fi) đang lấy / lỗi lần lấy gần nhất.
  final _capturing = <String>{};
  final _captureErr = <String, String>{};

  /// Vị trí GPS hiện tại → {lat, lon, accuracy, at}. Người dùng không gõ tay được.
  Future<void> _captureLocation(FlowField f) async {
    setState(() {
      _capturing.add(f.key);
      _captureErr.remove(f.key);
    });
    final p = await currentPosition(context);
    if (!mounted) return;
    setState(() {
      _capturing.remove(f.key);
      if (p == null) {
        _captureErr[f.key] = tr('Chưa lấy được vị trí');
      } else {
        _data[f.key] = {'lat': p.latitude, 'lon': p.longitude, 'accuracy': p.accuracy.round(), 'at': DateTime.now().millisecondsSinceEpoch};
      }
    });
    _maybeAutoSubmit();
  }

  /// Wi-Fi đang nối → {ssid, bssid, at}. Android / iOS / macOS chỉ cho đọc khi đã cho phép dùng vị trí.
  Future<void> _captureWifi(FlowField f) async {
    setState(() {
      _capturing.add(f.key);
      _captureErr.remove(f.key);
    });
    String? err;
    Map<String, dynamic>? value;
    try {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      }
      final info = NetworkInfo();
      final ssid = (await info.getWifiName())?.replaceAll('"', '').trim();
      final bssid = (await info.getWifiBSSID())?.trim();
      // Không đọc được thì Android trả "<unknown ssid>" / BSSID 02:00:00:00:00:00.
      final okSsid = ssid != null && ssid.isNotEmpty && ssid != '<unknown ssid>';
      final okBssid = bssid != null && bssid.isNotEmpty && bssid != '02:00:00:00:00:00';
      if (okSsid || okBssid) {
        value = {'ssid': okSsid ? ssid : null, 'bssid': okBssid ? bssid : null, 'at': DateTime.now().millisecondsSinceEpoch};
      } else {
        err = tr('Không đọc được Wi-Fi: máy chưa nối Wi-Fi hoặc chưa cho phép dùng vị trí');
      }
    } catch (e) {
      err = tr('Không đọc được Wi-Fi: {0}', ['$e']);
    }
    if (!mounted) return;
    setState(() {
      _capturing.remove(f.key);
      if (value != null) _data[f.key] = value;
      if (err != null) _captureErr[f.key] = err;
    });
    _maybeAutoSubmit();
  }

  /// Ảnh chụp tại chỗ: chỉ mở camera (không chọn từ bộ sưu tập). Máy tính không có camera của app thì báo.
  Future<void> _capturePhoto(FlowField f) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Ảnh chụp tại chỗ cần làm trên điện thoại'))));
      return;
    }
    final r = await Navigator.of(context).push<MediaPickResult>(AppPageRoute(builder: (_) => const CameraCapturePage()));
    if (r == null || !mounted) return;
    await _addImages(f, [for (final m in r.files) (m.name, await File(m.path).readAsBytes())]);
  }

  Widget _autoValue(Pal pal, FlowField f, IconData icon, VoidCallback retake) {
    final v = _data[f.key];
    final busy = _capturing.contains(f.key);
    final err = _captureErr[f.key];
    final text = v == null ? null : showFieldValue(f, v);
    return Row(children: [
      Icon(icon, size: 20, color: v == null ? pal.sub : pal.accentText),
      const SizedBox(width: 8),
      Expanded(
        child: busy
            ? Row(children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(tr('Đang lấy…'), style: TextStyle(color: pal.sub)),
              ])
            : Text(text ?? err ?? tr('Chưa có'), style: TextStyle(color: text != null ? pal.text : (err != null ? Colors.redAccent : pal.sub))),
      ),
      TextButton(onPressed: busy ? null : retake, child: Text(v == null ? tr('Lấy') : tr('Lấy lại'))),
    ]);
  }

  /// Ảnh vừa chọn / dán (theo id tệp đã tải lên) để hiện ô xem trước ngay, không phải tải lại.
  final _thumbs = <String, Uint8List>{};

  Future<void> _addImages(FlowField f, List<(String name, Uint8List bytes)> images) async {
    for (final (name, bytes) in images) {
      setState(() => _uploading.add(name));
      try {
        final info = await widget.api.upload(name, bytes);
        _thumbs['${info['id']}'] = bytes;
        setState(() => _data[f.key] = [...(_data[f.key] as List? ?? const []), info]);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tải được {0}: {1}', [name, '$e']))));
      }
      if (mounted) setState(() => _uploading.remove(name));
    }
  }

  Future<void> _pickImages(FlowField f) async {
    final picked = await pickFilesOrReport(context, type: FileType.image);
    await _addImages(f, [
      for (final p in picked)
        if (p.path != null) (p.name, await File(p.path!).readAsBytes()),
    ]);
  }

  Future<void> _pasteImages(FlowField f) async {
    const exts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'};
    final media = [for (final (path, name) in await readClipboardMedia()) if (exts.contains(name.split('.').last.toLowerCase())) (path, name)];
    if (media.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Bộ nhớ tạm không có ảnh'))));
      return;
    }
    await _addImages(f, [for (final (path, name) in media) (name, await File(path).readAsBytes())]);
  }

  Future<void> _pickFiles(FlowField f) async {
    final picked = await pickFilesOrReport(context);
    for (final p in picked) {
      if (p.path == null) continue;
      final bytes = await File(p.path!).readAsBytes();
      setState(() => _uploading.add(p.name));
      try {
        final info = await widget.api.upload(p.name, bytes);
        setState(() => _data[f.key] = [...(_data[f.key] as List? ?? const []), info]);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tải được {0}: {1}', [p.name, '$e']))));
      }
      if (mounted) setState(() => _uploading.remove(p.name));
    }
  }

  Future<void> _pickDate(FlowField f) async {
    final cur = DateTime.tryParse('${_data[f.key] ?? ''}') ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    final s = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() => _data[f.key] = s);
  }

  /// Có trường tự tính hoặc trường hiện theo điều kiện: cần dựng lại khi gõ.
  late final bool _reactive = widget.fields.any((f) => f.calc != null || f.showIf.isNotEmpty);

  num? _num(Object? v) => v is num ? v : (v is String ? (parseMoney(v) ?? parseDecimal(v)) : null);

  /// Dữ liệu hiện tại (kể cả ô đang gõ) và các trường tự tính, để ẩn / hiện và hiện số tự tính ngay.
  Map<String, dynamic> _live() {
    final d = Map<String, dynamic>.of(_data);
    for (final f in widget.fields) {
      final c = _ctl[f.key];
      if (c != null) d[f.key] = c.text.trim().isEmpty ? null : c.text.trim();
    }
    for (final f in widget.fields) {
      final k = f.calc;
      if (k == null) continue;
      num? get(String p) {
        if (!p.contains('.')) return _num(d[p]);
        final parts = p.split('.');
        final t = parts[0].replaceAll('__tong', '');
        final tf = widget.fields.where((x) => x.key == t).firstOrNull;
        if (tf == null) return null;
        return computeTable(tf, d[t]).$2[parts[1]];
      }
      final a = get('${k['a']}'), b = get('${k['b']}');
      d[f.key] = (a == null || b == null)
          ? null
          : switch ('${k['op']}') { 'add' => a + b, 'sub' => a - b, 'div' => b == 0 ? null : a / b, _ => a * b };
    }
    return d;
  }

  Widget _field(BuildContext context, FlowField f) {
    final pal = Pal.of(context);
    if (f.calc != null) {
      final v = _live()[f.key];
      return InputDecorator(
        decoration: InputDecoration(labelText: f.label, helperText: tr('Tự tính'), filled: true, border: const OutlineInputBorder()),
        child: Text(v is num ? (f.type == 'money' ? moneyText(f.currency.isEmpty ? v.round() : v, f.currency) : vnDecimal(v, v == v.roundToDouble() ? 0 : 2)) : '—',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    if (f.type == 'text' && f.lookup != null && widget.flowId != null) {
      return LookupField(
        api: widget.api,
        flowId: widget.flowId!,
        field: widget.lookupPath?.call(f) ?? f.key,
        label: f.required ? '${f.label} *' : f.label,
        value: _data[f.key] as String?,
        hint: f.hint,
        error: _errs[f.key],
        onPicked: (it) => setState(() {
          _data[f.key] = it['value'];
          // Điền thêm các ô khác theo cấu hình danh mục.
          for (final e in ((f.lookup!['fill'] as Map?) ?? const {}).entries) {
            final v = (it['data'] as Map?)?[e.value];
            if (v == null) continue;
            _data['${e.key}'] = v;
            _ctl['${e.key}']?.text = '$v';
          }
        }),
      );
    }
    final label = f.required ? '${f.label} *' : f.label;
    final err = _errs[f.key];
    final h = f.hint.isEmpty ? null : f.hint;
    InputDecoration deco([String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint ?? h,
          helperText: const {'select', 'date', 'user', 'files', 'bool'}.contains(f.type) ? h : null,
          errorText: err,
          border: const OutlineInputBorder(),
        );
    switch (f.type) {
      case 'textarea':
        return TextField(controller: _ctl[f.key], minLines: 3, maxLines: 8, decoration: deco());
      case 'number':
        return TextField(controller: _ctl[f.key], keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: deco());
      case 'money' when f.currency.isNotEmpty:
        return TextField(
          controller: _ctl[f.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: deco().copyWith(suffixText: f.currency),
        );
      case 'money':
        return TextField(
          controller: _ctl[f.key],
          keyboardType: TextInputType.number,
          inputFormatters: [MoneyInputFormatter()],
          decoration: deco().copyWith(suffixText: 'đ'),
        );
      case 'date':
        final v = _data[f.key];
        return InkWell(
          onTap: () => _pickDate(f),
          child: InputDecorator(
            decoration: deco().copyWith(suffixIcon: const Icon(Icons.event_rounded)),
            child: Text(v == null ? tr('Chọn ngày') : showFieldValue(f, v), style: TextStyle(color: v == null ? pal.sub : pal.text)),
          ),
        );
      case 'select':
        return DropdownButtonFormField<String>(
          initialValue: f.options.contains(_data[f.key]) ? _data[f.key] as String : null,
          isExpanded: true,
          decoration: deco(),
          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _data[f.key] = v),
        );
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: TextStyle(color: pal.text)),
          subtitle: err == null ? null : Text(err, style: const TextStyle(color: Colors.redAccent)),
          value: _data[f.key] == true,
          onChanged: (v) => setState(() => _data[f.key] = v),
        );
      case 'delegation':
        return DelegationField(
          app: widget.app,
          api: widget.api,
          label: label,
          hint: h,
          error: err,
          value: _data[f.key] as List?,
          onChanged: (v) => _data[f.key] = v,
        );
      case 'user':
        final people = widget.app.users.values.where((u) => !u.isBot && u.deleteAt == 0).toList()
          ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        final cur = _data[f.key] as String?;
        return DropdownButtonFormField<String>(
          initialValue: people.any((u) => u.id == cur) ? cur : null,
          isExpanded: true,
          decoration: deco(),
          items: [for (final u in people) DropdownMenuItem(value: u.id, child: Text(u.displayName, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _data[f.key] = v),
        );
      case 'files':
        final files = [for (final x in (_data[f.key] as List? ?? const [])) x];
        return InputDecorator(
          decoration: deco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (i, x) in files.indexed)
              Row(children: [
                Icon(Icons.description_outlined, size: 18, color: pal.sub),
                const SizedBox(width: 6),
                Expanded(child: Text(x is Map ? '${x['name']}' : '$x', overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text))),
                IconButton(
                  tooltip: tr('Bỏ tệp'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _data[f.key] = [...files]..removeAt(i)),
                ),
              ]),
            for (final n in _uploading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('Đang tải {0}…', [n]), overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.sub))),
                ]),
              ),
            TextButton.icon(onPressed: () => _pickFiles(f), icon: const Icon(Icons.attach_file_rounded), label: Text(tr('Đính kèm tệp'))),
          ]),
        );
      // Tự lấy khi mở việc; người dùng chỉ bấm "Lấy lại".
      case 'location':
        return FlowLocationView(
          label: label,
          value: _data[f.key],
          busy: _capturing.contains(f.key),
          error: err ?? _captureErr[f.key],
          onRetry: () => _captureLocation(f),
        );
      case 'wifi':
        return InputDecorator(decoration: deco(tr('Tự đọc Wi-Fi đang nối')), child: _autoValue(pal, f, Icons.wifi_rounded, () => _captureWifi(f)));
      case 'images' || 'photo':
        final images = [for (final x in (_data[f.key] as List? ?? const [])) x];
        return InputDecorator(
          decoration: deco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (images.isNotEmpty || _uploading.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (i, x) in images.indexed)
                  Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: switch (_thumbs[x is Map ? '${x['id']}' : '$x']) {
                          final Uint8List b => Image.memory(b, fit: BoxFit.cover),
                          _ => ColoredBox(color: pal.surface2, child: Icon(Icons.image_outlined, color: pal.sub)),
                        },
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: tr('Bỏ ảnh'),
                        iconSize: 16,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _data[f.key] = [...images]..removeAt(i)),
                      ),
                    ),
                  ]),
                for (final _ in _uploading)
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
                    child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ]),
            Wrap(spacing: 4, children: [
              if (f.type == 'photo')
                TextButton.icon(onPressed: () => _capturePhoto(f), icon: const Icon(Icons.photo_camera_outlined), label: Text(tr('Chụp ảnh')))
              else ...[
                TextButton.icon(onPressed: () => _pickImages(f), icon: const Icon(Icons.photo_library_outlined), label: Text(tr('Chọn ảnh'))),
                TextButton.icon(onPressed: () => _pasteImages(f), icon: const Icon(Icons.content_paste_rounded), label: Text(tr('Dán ảnh'))),
              ],
            ]),
          ]),
        );
      case 'table':
        return FlowTableInput(
          field: f,
          value: _data[f.key],
          error: err,
          api: widget.api,
          flowId: widget.flowId,
          onChanged: (rows) => _reactive ? setState(() => _data[f.key] = rows) : _data[f.key] = rows,
        );
      default:
        return TextField(controller: _ctl[f.key], decoration: deco());
    }
  }

  /// Chế độ chỉ bấm bắt đầu: hiện việc đang lấy / đã lấy, không có ô sửa; lỗi thì nêu lý do và "Thử lại".
  Widget _autoBody(Pal pal) {
    final fields = [for (final f in widget.fields) if (f.calc == null && fieldVisible(f, _data)) f];
    final failed = fields.any((f) => _captureErr.containsKey(f.key) && _data[f.key] == null && f.required) || _serverErr != null;
    Widget row(FlowField f) {
      final v = _data[f.key];
      final err = _captureErr[f.key];
      final busy = _capturing.contains(f.key);
      return ListTile(
        leading: Icon(f.type == 'wifi' ? Icons.wifi_rounded : Icons.place_rounded, color: v != null ? pal.accentText : pal.sub),
        title: Text(f.label),
        subtitle: Text(
          busy ? tr('Đang lấy…') : (v != null ? showFieldValue(f, v) : (err ?? tr('Chưa có'))),
          style: TextStyle(color: v == null && err != null ? (f.required ? Colors.redAccent : pal.sub) : pal.sub),
        ),
        trailing: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : v != null
                ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                : null,
      );
    }

    Widget item(FlowField f) => f.type == 'location'
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FlowLocationView(label: f.label, value: _data[f.key], busy: _capturing.contains(f.key), error: _captureErr[f.key], mapHeight: 180),
          )
        : Card(margin: const EdgeInsets.only(bottom: 10), child: row(f));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 24), children: [
      Icon(_busy || _autoSent ? Icons.cloud_upload_outlined : Icons.my_location_rounded, size: 56, color: pal.accentText),
      const SizedBox(height: 12),
      Text(
        _busy || (_autoSent && _serverErr == null) ? tr('Đang gửi…') : (failed ? tr('Chưa gửi được') : tr('Đang tự lấy thông tin, không cần nhập gì')),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text),
      ),
      const SizedBox(height: 16),
      for (final f in fields) item(f),
      if (_serverErr != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_serverErr!, style: const TextStyle(color: Colors.redAccent))),
      if (failed && !_busy) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _serverErr = null;
              _autoSent = false;
            });
            for (final f in fields) {
              if (_data[f.key] != null) continue;
              f.type == 'wifi' ? _captureWifi(f) : _captureLocation(f);
            }
            _maybeAutoSubmit();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: Text(tr('Thử lại')),
        ),
        const SizedBox(height: 8),
        Text(tr('Thông tin chấm công do app tự lấy, không nhập tay được. Kiểm tra đã bật GPS / Wi-Fi và cho phép Flygo Chat dùng vị trí.'),
            textAlign: TextAlign.center, style: TextStyle(color: pal.sub, fontSize: 12.5)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (widget.embedded) {
      return _autoOnly ? _autoBody(pal) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _body(pal));
    }
    if (_autoOnly) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _autoBody(pal)))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: _body(pal)),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(Pal pal) => [
        if (widget.notice.isNotEmpty) FlowNotice(text: widget.notice),
        if (widget.askTitle) ...[
          TextField(
            controller: _titleCtl,
            maxLength: 200,
            decoration: InputDecoration(labelText: tr('Tiêu đề đơn (không bắt buộc)'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
        ],
        for (final f in widget.fields)
          if (fieldVisible(f, _live())) ...[_field(context, f), const SizedBox(height: 14)],
        if (_serverErr != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_serverErr!, style: const TextStyle(color: Colors.redAccent)),
          ),
        FilledButton(
          onPressed: _busy || _uploading.isNotEmpty ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.submitLabel.isEmpty ? tr('Gửi') : widget.submitLabel),
        ),
        if (widget.fields.any((f) => f.required))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('* là trường bắt buộc'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ),
      ];
}

/// Ô nhập tiền: tự thêm dấu chấm ngăn cách hàng nghìn khi gõ.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final n = int.tryParse(digits.length > 15 ? digits.substring(0, 15) : digits) ?? 0;
    final s = vnNumber(n);
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}
