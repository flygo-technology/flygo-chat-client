// Biểu mẫu: lược đồ (mục, câu hỏi) giữ dạng Map như JSON của máy chủ (sửa rồi gửi lại không mất trường), kèm các hàm
// rẽ nhánh / kiểm câu trả lời làm đúng như máy chủ (flygo-chat-server forms/src/logic.ts).
import 'dart:math';

import 'package:flutter/material.dart';

typedef Json = Map<String, dynamic>;

const kQuestionTypes = ['short', 'paragraph', 'choice', 'checkbox', 'dropdown', 'scale', 'date', 'time', 'datetime', 'number', 'file', 'grid_choice', 'grid_checkbox'];

/// Tên + biểu tượng từng loại câu hỏi (trình soạn).
const kTypeInfo = <String, (String, IconData)>{
  'short': ('Câu trả lời ngắn', Icons.short_text),
  'paragraph': ('Đoạn', Icons.notes),
  'choice': ('Trắc nghiệm', Icons.radio_button_checked),
  'checkbox': ('Hộp kiểm', Icons.check_box_outlined),
  'dropdown': ('Menu thả xuống', Icons.arrow_drop_down_circle_outlined),
  'scale': ('Thang đo tuyến tính', Icons.linear_scale),
  'grid_choice': ('Lưới trắc nghiệm', Icons.grid_on),
  'grid_checkbox': ('Lưới hộp kiểm', Icons.apps),
  'date': ('Ngày', Icons.event_outlined),
  'time': ('Giờ', Icons.schedule),
  'datetime': ('Ngày và giờ', Icons.edit_calendar_outlined),
  'number': ('Số', Icons.pin_outlined),
  'file': ('Tải tệp lên', Icons.upload_file),
  'text': ('Tiêu đề và mô tả', Icons.title),
  'image': ('Ảnh', Icons.image_outlined),
};

const kFileTypes = <String, String>{
  'image': 'Ảnh', 'pdf': 'PDF', 'doc': 'Tài liệu', 'sheet': 'Bảng tính', 'slide': 'Trình chiếu', 'video': 'Video', 'audio': 'Âm thanh', 'archive': 'Tệp nén',
};
const kFileExts = <String, List<String>>{
  'image': ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'], 'pdf': ['pdf'], 'doc': ['doc', 'docx', 'odt', 'txt', 'rtf'], 'sheet': ['xls', 'xlsx', 'ods', 'csv'],
  'slide': ['ppt', 'pptx', 'odp'], 'video': ['mp4', 'mov', 'webm'], 'audio': ['mp3', 'm4a', 'wav', 'ogg'], 'archive': ['zip', 'rar', '7z'],
};

/// Màu chủ đề người soạn chọn.
const kThemeColors = ['#0F8B8D', '#1E7BFF', '#5B6CC4', '#7B4FB8', '#C2185B', '#D9534F', '#E4A11B', '#2E7D32', '#455A64', '#6D4C41'];

Color colorOf(String? hex, [Color d = const Color(0xFF0F8B8D)]) {
  final h = (hex ?? '').replaceAll('#', '');
  return h.length == 6 ? Color(int.parse('FF$h', radix: 16)) : d;
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Nền nhạt theo màu chủ đề (trang soạn / điền).
Color tintOf(Color c, bool dark) => Color.lerp(c, dark ? Colors.black : Colors.white, dark ? .78 : .9)!;

final _rnd = Random();
String newId([int n = 8]) {
  const a = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(n, (_) => a[_rnd.nextInt(a.length)]).join();
}

/// Bỏ dấu tiếng Việt: "Kết quả xử lý" → "ket_qua_xu_ly" (như máy chủ).
String slugKey(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  var k = b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  if (k.length > 40) k = k.substring(0, 40).replaceAll(RegExp(r'_+$'), '');
  return RegExp(r'^[a-z]').hasMatch(k) ? k : 'q_${k.isEmpty ? 'cau' : k}';
}

bool isQuestion(Json it) => it['type'] != 'text' && it['type'] != 'image';

List<Json> sectionsOf(Json schema) => [for (final s in (schema['sections'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
List<Json> itemsOf(Json section) => [for (final i in (section['items'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
List<Json> questionsOf(Json schema) => [for (final s in sectionsOf(schema)) ...itemsOf(s).where(isQuestion)];
List<String> optionLabels(Json it) => [for (final o in (it['options'] as List? ?? const [])) '${(o as Map)['label']}'];
List<String> lineLabels(Json it, String k) => [for (final o in (it[k] as List? ?? const [])) '${(o as Map)['label']}'];

/// Bản sao sâu của JSON (sửa không đụng bản gốc).
T deepCopy<T>(T v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': deepCopy(e.value)} as T;
  if (v is List) return [for (final x in v) deepCopy(x)] as T;
  return v;
}

/// Câu hỏi mới theo loại (mặc định giống máy chủ làm sạch).
Json newItem(String type, {String title = ''}) {
  final it = <String, dynamic>{'id': newId(), 'type': type, 'title': title};
  switch (type) {
    case 'choice' || 'checkbox' || 'dropdown':
      it['options'] = [{'id': newId(), 'label': 'Lựa chọn 1'}];
    case 'scale':
      it['scale'] = {'min': 1, 'max': 5};
    case 'grid_choice' || 'grid_checkbox':
      it['rows'] = [{'id': newId(), 'label': 'Hàng 1'}];
      it['cols'] = [{'id': newId(), 'label': 'Cột 1'}];
    case 'file':
      it['file'] = {'max_files': 1, 'max_mb': 10};
  }
  return it;
}

/// Đổi loại câu hỏi, giữ những gì dùng lại được (tiêu đề, lựa chọn).
Json changeType(Json it, String type) {
  final n = newItem(type, title: '${it['title'] ?? ''}')..['id'] = it['id'];
  for (final k in ['key', 'description', 'required']) {
    if (it[k] != null) n[k] = it[k];
  }
  if (n.containsKey('options') && it['options'] is List && (it['options'] as List).isNotEmpty) {
    n['options'] = [for (final o in it['options'] as List) {'id': (o as Map)['id'] ?? newId(), 'label': o['label'], if (type != 'checkbox' && o['goto'] != null) 'goto': o['goto']}];
    if (it['other'] == true && type != 'dropdown') n['other'] = true;
  }
  if (!isQuestion(n)) n.remove('required');
  return n;
}

// ---------------------------------------------------------------- rẽ nhánh, kiểm câu trả lời (như logic.ts)

bool _empty(Object? v) => v == null || v == '' || (v is List && v.isEmpty) || (v is Map && v.isEmpty);

/// Các mục (chỉ số) người điền đi qua với các câu trả lời [a].
List<int> sectionPath(Json schema, Json a) {
  final secs = sectionsOf(schema);
  final out = <int>[], seen = <int>{};
  var i = 0;
  while (i >= 0 && i < secs.length && !seen.contains(i)) {
    seen.add(i);
    out.add(i);
    String? go;
    for (final it in itemsOf(secs[i])) {
      if (it['type'] != 'choice' && it['type'] != 'dropdown') continue;
      final v = a[it['key']];
      if (v is! String) continue;
      for (final o in (it['options'] as List? ?? const [])) {
        if ((o as Map)['label'] == v && o['goto'] != null && '${o['goto']}'.isNotEmpty) go = '${o['goto']}';
      }
    }
    go ??= (secs[i]['next'] as String?) ?? 'next';
    if (go == 'submit') break;
    i = go == 'next' ? i + 1 : secs.indexWhere((x) => x['id'] == go);
  }
  return out;
}

/// Chuẩn hoá giá trị thô theo loại câu hỏi.
Object? normalize(Json it, Object? v) {
  if (v == null) return null;
  switch (it['type']) {
    case 'number' || 'scale':
      if (v is num) return v;
      final s = '$v'.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
      if (s.isEmpty) return null;
      return num.tryParse(s) ?? '$v';
    case 'checkbox' || 'file':
      final arr = (v is List ? v : [v]).map((x) => '$x'.trim()).where((x) => x.isNotEmpty).toSet().toList();
      return arr.isEmpty ? null : arr;
    case 'grid_choice' || 'grid_checkbox':
      if (v is! Map) return v;
      final out = <String, dynamic>{};
      v.forEach((k, x) {
        if (x is List) {
          final a = x.map((e) => '$e').where((e) => e.isNotEmpty).toSet().toList();
          if (a.isNotEmpty) out['$k'] = a;
        } else if (x != null && '$x'.isNotEmpty) {
          out['$k'] = '$x';
        }
      });
      return out.isEmpty ? null : out;
    default:
      final s = v is String ? v.trim() : '$v';
      return s.isEmpty ? null : s;
  }
}

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _url = RegExp(r'^https?://[^\s/$.?#].[^\s]*$', caseSensitive: false);
final _phone = RegExp(r'^(0|\+84)\d{9,10}$');

/// Lỗi của một câu trả lời (đã normalize) hoặc null.
String? checkAnswer(Json it, Object? v) {
  final req = it['required'] == true;
  if (_empty(v)) return req ? 'Đây là câu hỏi bắt buộc' : null;
  final val = it['validation'] is Map ? Map<String, dynamic>.from(it['validation'] as Map) : null;
  String msg(String d) => (val?['message'] as String?)?.isNotEmpty == true ? val!['message'] as String : d;
  num? mn = val?['min'] as num?, mx = val?['max'] as num?;
  String range() => mn != null && mx != null ? 'Cần trong khoảng $mn – $mx' : mn != null ? 'Cần lớn hơn hoặc bằng $mn' : 'Cần nhỏ hơn hoặc bằng $mx';
  switch (it['type']) {
    case 'short' || 'paragraph':
      if (v is! String) return 'Câu trả lời không hợp lệ';
      if (val == null) return null;
      switch (val['kind']) {
        case 'email':
          if (!_email.hasMatch(v)) return msg('Email chưa đúng');
        case 'url':
          if (!_url.hasMatch(v)) return msg('Đường dẫn chưa đúng (bắt đầu bằng http:// hoặc https://)');
        case 'phone':
          if (!_phone.hasMatch(v.replaceAll(RegExp(r'[\s.\-()]'), ''))) return msg('Số điện thoại chưa đúng (10 chữ số, bắt đầu bằng 0)');
        case 'length':
          if ((mn != null && v.length < mn) || (mx != null && v.length > mx)) {
            return msg(mn != null && mx != null ? 'Cần từ $mn đến $mx ký tự' : mn != null ? 'Cần ít nhất $mn ký tự' : 'Tối đa $mx ký tự');
          }
        case 'regex':
          try {
            if (!RegExp('${val['pattern'] ?? ''}', unicode: true).hasMatch(v)) return msg('Câu trả lời chưa đúng định dạng');
          } catch (_) {}
        case 'range':
          final n = num.tryParse(v.replaceAll(',', '.'));
          if (n == null) return msg('Cần nhập một số');
          if ((mn != null && n < mn) || (mx != null && n > mx)) return msg(range());
      }
      return null;
    case 'number':
      if (v is! num) return msg('Cần nhập một số');
      if (val?['integer'] == true && v != v.roundToDouble()) return msg('Cần nhập số nguyên');
      if ((mn != null && v < mn) || (mx != null && v > mx)) return msg(range());
      return null;
    case 'choice' || 'dropdown':
      if (v is! String) return 'Câu trả lời không hợp lệ';
      return optionLabels(it).contains(v) || it['other'] == true ? null : 'Lựa chọn không có trong danh sách';
    case 'checkbox':
      if (v is! List) return 'Câu trả lời không hợp lệ';
      if (val?['kind'] == 'count') {
        if (mn != null && v.length < mn) return msg('Chọn ít nhất $mn');
        if (mx != null && v.length > mx) return msg('Chọn nhiều nhất $mx');
      }
      return null;
    case 'scale':
      final sc = it['scale'] as Map? ?? const {'min': 1, 'max': 5};
      return v is num && v >= (sc['min'] as num) && v <= (sc['max'] as num) ? null : 'Câu trả lời không hợp lệ';
    case 'date':
      return v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ? null : 'Ngày chưa đúng';
    case 'time':
      return v is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v) ? null : 'Giờ chưa đúng';
    case 'datetime':
      return v is String && RegExp(r'^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d$').hasMatch(v) ? null : 'Ngày giờ chưa đúng';
    case 'file':
      final max = (it['file'] as Map?)?['max_files'] as int? ?? 1;
      return v is List && v.length > max ? 'Tối đa $max tệp' : null;
    case 'grid_choice' || 'grid_checkbox':
      if (v is! Map) return 'Câu trả lời không hợp lệ';
      if (req && lineLabels(it, 'rows').any((r) => _empty(v[r]))) return 'Cần trả lời mọi hàng';
      return null;
  }
  return null;
}

/// Câu trả lời thành chữ (danh sách, lưới).
String answerText(Json it, Object? v, {String Function(String id)? fileName}) {
  if (v == null) return '';
  if (it['type'] == 'file' && v is List) return v.map((x) => fileName?.call('$x') ?? '$x').join(', ');
  if (v is List) return v.join(', ');
  if (v is Map) return v.entries.map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}').join('; ');
  if (v is double && v == v.roundToDouble()) return '${v.toInt()}';
  return '$v';
}

/// Kiểu trường Flows tương ứng câu hỏi (Tự động hoá: form của quy trình gắn biểu mẫu).
Json flowsField(Json it) {
  final t = switch (it['type']) {
    'paragraph' => 'textarea',
    'number' || 'scale' => 'number',
    'date' => 'date',
    'choice' || 'dropdown' => 'select',
    'checkbox' => 'text',
    'file' => 'file',
    _ => 'text',
  };
  return {
    'key': it['key'], 'label': '${it['title'] ?? it['key']}', 'type': t,
    if (it['required'] == true && it['type'] != 'file') 'required': true,
    if (t == 'select') 'options': optionLabels(it),
  };
}

final _dt = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
String fmtDate(String iso) {
  final m = _dt.firstMatch(iso);
  return m == null ? iso : '${m[3]}/${m[2]}/${m[1]}';
}

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)} ${two(d.day)}/${two(d.month)}/${d.year}';
}

String ago(int ms) {
  final d = DateTime.now().millisecondsSinceEpoch - ms;
  if (d < 60000) return 'vừa xong';
  if (d < 3600000) return '${d ~/ 60000} phút trước';
  if (d < 86400000) return '${d ~/ 3600000} giờ trước';
  if (d < 7 * 86400000) return '${d ~/ 86400000} ngày trước';
  return fmtTime(ms).substring(6);
}
