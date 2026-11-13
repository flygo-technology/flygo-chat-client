import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import 'flow_cond.dart' show condTrue;
import 'flow_table.dart' show tableSummary;

/// Phần thuần của Flows (kiểm thử được, không cần mạng): số tiền, kiểm form, nhãn trạng thái.

/// 35000000 → "35.000.000".
String vnNumber(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return neg ? '-$b' : '$b';
}

/// Số có phần lẻ kiểu Việt Nam: 1234.5 → "1.234,50" (2 số lẻ).
String vnDecimal(num n, [int digits = 2]) {
  final neg = n < 0;
  final s = n.abs().toStringAsFixed(digits);
  final parts = s.split('.');
  final int0 = vnNumber(int.parse(parts[0]));
  return '${neg ? '-' : ''}$int0${digits > 0 ? ',${parts[1]}' : ''}';
}

/// Tiền theo loại: đồng "1.500.000 đ", ngoại tệ "1.234,50 USD".
String moneyText(num n, String currency) => currency.isEmpty ? '${vnNumber(n)} đ' : '${vnDecimal(n)} $currency';

/// Đọc số ngoại tệ gõ tay: "1.234,56" / "1,234.56" / "1234.56" → 1234.56.
num? parseDecimal(String s) {
  var t = s.replaceAll(RegExp(r'[\s_]'), '');
  if (t.isEmpty) return null;
  final lastComma = t.lastIndexOf(','), lastDot = t.lastIndexOf('.');
  if (lastComma > lastDot) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '');
  }
  return num.tryParse(t);
}

/// Trường có hiện không (theo "Chỉ hiện khi").
bool fieldVisible(FlowField f, Map<String, dynamic> data) => f.showIf.isEmpty || condTrue(f.showIf, {'form': data});

/// Đọc số tiền gõ tay: "35.000.000", "35,000,000", "35000000" → 35000000. Không phải số: null.
int? parseMoney(String s) {
  final t = s.replaceAll(RegExp(r'[.,\s_đ]'), '');
  if (t.isEmpty || !RegExp(r'^-?\d+$').hasMatch(t)) return null;
  return int.tryParse(t);
}

bool _isDate(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

bool _blank(Object? v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

/// Kiểm form như máy chủ: trả về lỗi theo khoá trường (rỗng = hợp lệ).
Map<String, String> validateFlowForm(List<FlowField> fields, Map<String, dynamic> data) {
  final errs = <String, String>{};
  for (final f in fields) {
    // Trường tự tính (máy chủ tính) và trường đang ẩn: không kiểm.
    if (f.calc != null || !fieldVisible(f, data)) continue;
    final v = data[f.key];
    if (_blank(v)) {
      if (f.required) errs[f.key] = tr('Chưa nhập');
      continue;
    }
    if (f.type == 'table') {
      // Bảng: lỗi đầu tiên theo dòng ("Dòng 2: Số lượng: Chưa nhập"); cột tự tính máy chủ tính.
      if (v is! List) {
        errs[f.key] = tr('Không đúng định dạng');
        continue;
      }
      final cols = [for (final c in f.columns) if (c.calc == null) c];
      for (var i = 0; i < v.length && !errs.containsKey(f.key); i++) {
        final row = v[i] is Map ? (v[i] as Map).cast<String, dynamic>() : <String, dynamic>{};
        final e = validateFlowForm(cols, row);
        if (e.isNotEmpty) {
          final c = cols.firstWhere((c) => e.containsKey(c.key));
          errs[f.key] = tr('Dòng {0}: {1}: {2}', [i + 1, c.label, e[c.key]]);
        }
      }
      continue;
    }
    final ok = switch (f.type) {
      'number' || 'money' => v is num || (v is String && (parseMoney(v) != null || parseDecimal(v) != null)),
      'bool' => v is bool,
      'files' => v is List && v.every((x) => x is String || (x is Map && x['id'] is String)),
      'select' => v is String && (f.options.isEmpty || f.options.contains(v)),
      'date' => v is String && _isDate(v),
      _ => v is String,
    };
    if (!ok) errs[f.key] = tr('Không đúng định dạng');
  }
  return errs;
}

/// Giá trị một trường để hiện (tiền có dấu chấm và "đ", tệp hiện số tệp).
String showFieldValue(FlowField f, Object? v) {
  if (v == null) return '';
  switch (f.type) {
    case 'money':
      final n = v is num ? v : (f.currency.isEmpty ? parseMoney('$v') : parseDecimal('$v'));
      return n == null ? '$v' : moneyText(n, f.currency);
    case 'bool':
      return v == true ? tr('Có') : tr('Không');
    case 'files':
      return v is List ? tr('{0} tệp', [v.length]) : '';
    case 'images' || 'photo':
      return v is List ? tr('{0} ảnh', [v.length]) : '';
    case 'location':
      if (v is! Map || v['lat'] is! num || v['lon'] is! num) return '';
      final acc = v['accuracy'] is num ? ' (±${(v['accuracy'] as num).round()} m)' : '';
      final at = v['at'] is num ? ' · ${_hm((v['at'] as num).toInt())}' : '';
      return '${(v['lat'] as num).toStringAsFixed(6)}, ${(v['lon'] as num).toStringAsFixed(6)}$acc$at';
    case 'wifi':
      if (v is! Map) return '';
      final at = v['at'] is num ? ' · ${_hm((v['at'] as num).toInt())}' : '';
      return [if ('${v['ssid'] ?? ''}'.isNotEmpty) '${v['ssid']}', if ('${v['bssid'] ?? ''}'.isNotEmpty) '(${v['bssid']})'].join(' ') + at;
    case 'table':
      return tableSummary(f, v);
    case 'delegation':
      final rows = [for (final r in (v is List ? v : const [])) if (r is Map && (r['flows'] as List? ?? const []).isNotEmpty) r];
      return tr('{0} người nhận thay · {1} quy trình', [rows.length, rows.fold<int>(0, (n, r) => n + (r['flows'] as List).length)]);
    case 'date':
      final s = '$v';
      return _isDate(s) ? '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}' : s;
    default:
      return '$v';
  }
}

/// Nhãn trạng thái đơn.
String flowStatusLabel(String status) => switch (status) {
      'running' => tr('Đang xử lý'),
      'returned' => tr('Bị trả lại'),
      'done' => tr('Hoàn tất'),
      'rejected' => tr('Bị từ chối'),
      'cancelled' => tr('Đã hủy'),
      'failed' => tr('Lỗi'),
      _ => status,
    };

/// Nhãn loại việc.
String flowTaskKindLabel(String kind) => switch (kind) {
      'approval' => tr('Cần duyệt'),
      'form' => tr('Cần điền'),
      'manual' => tr('Cần làm tay'),
      'resubmit' => tr('Sửa và nộp lại'),
      'action' => tr('Cần thao tác'),
      _ => kind,
    };

/// Một dòng nhật ký đơn dễ đọc, hoặc null nếu là chi tiết kỹ thuật không cần hiện.
/// [name] đổi id người thành tên, [step] đổi id node thành tên bước.
String? flowEventText(Map<String, dynamic> e, String Function(String) name, String Function(String) step, {String Function(String key)? field}) {
  final kind = '${e['kind']}';
  final node = '${e['node'] ?? ''}';
  final d = (e['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  final actor = '${e['actor'] ?? ''}';
  switch (kind) {
    case 'started':
      return tr('Đã nộp đơn');
    case 'enter':
      final t = '${d['type']}';
      if (t == 'approval' || t == 'approval_request') return tr('Chờ duyệt: {0}', [step(node)]);
      if (t == 'form_task') return tr('Chờ làm: {0}', [step(node)]);
      if (t == 'ai') return tr('AI đang làm: {0}', [step(node)]);
      return null;
    case 'decided':
      final who = name('${d['by']}');
      final c = '${d['comment'] ?? ''}'.trim();
      final r = switch ('${d['decision']}') {
        'approve' => tr('{0} đã duyệt: {1}', [who, step(node)]),
        'reject' => tr('{0} đã từ chối: {1}', [who, step(node)]),
        _ => tr('{0} đã trả lại: {1}', [who, step(node)]),
      };
      return c.isEmpty || c == 'null' ? r : '$r · “$c”';
    case 'claimed':
      return tr('{0} đã tiếp nhận: {1}', [name('${d['by']}'), step(node)]);
    case 'edited':
      // Tên khai báo của trường (không hiện khoá).
      final fields = [for (final c in (d['changes'] as List? ?? const [])) if (c is Map) field == null ? '${c['field']}' : field('${c['field']}')];
      return tr('{0} đã sửa {1} ở bước {2}', [name('${d['by']}'), fields.join(', '), step(node)]);
    case 'submitted':
      return tr('{0} đã hoàn thành: {1}', [name('${d['by']}'), step(node)]);
    case 'resubmitted':
      return tr('Đã sửa và nộp lại');
    case 'job_done':
      return tr('Đã xong: {0}', [step(node)]);
    case 'job_failed':
      return tr('AI lỗi ở {0}: {1}', [step(node), '${d['error'] ?? ''}']);
    case 'overdue':
      return tr('Quá hạn: {0}', [step(node)]);
    case 'escalated':
      final to = [for (final x in (d['to'] as List? ?? const [])) name('$x')];
      return to.isEmpty ? null : tr('Chuyển lên: {0}', [to.join(', ')]);
    case 'cancelled':
      return tr('{0} đã hủy đơn', [name(actor.isEmpty ? '${d['by']}' : actor)]);
    case 'finished':
      return tr('Kết thúc: {0}', [flowStatusLabel('${d['status']}')]);
    case 'error':
      return tr('Lỗi: {0}', ['${d['error'] ?? ''}']);
    default:
      return null;
  }
}

/// "HH:mm" của mốc ms (giờ máy).
String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
