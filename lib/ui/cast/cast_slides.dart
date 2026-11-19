// Dựng bộ slide PDF 16:9 cho màn hình lớn từ nội dung app (bài Bảng tin, trang Wiki): chữ to, tự sang trang khi dài,
// mỗi ảnh một trang nền đen. Chiếu bằng castPdfToScreen nên có sẵn chuyển trang, laser, màn đen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _w = 1280.0, _h = 720.0;
final _fmt = PdfPageFormat(_w, _h, marginAll: 0);
const _ink = PdfColor.fromInt(0xFF0F172A), _sub = PdfColor.fromInt(0xFF475569), _accent = PdfColor.fromInt(0xFF2563EB);

/// Một dòng nội dung đã phân loại từ Markdown đơn giản.
class _Line {
  final String kind; // h1 | h2 | h3 | li | code | p | blank
  final String text;
  const _Line(this.kind, this.text);
}

/// Bỏ ký hiệu Markdown trong dòng: **đậm**, *nghiêng*, `mã`, [chữ](link), ![ảnh](…).
String plainInline(String s) => s
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!)
    .replaceAllMapped(RegExp(r'(?<![\w*])[*_](\S.*?)[*_](?![\w*])'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!)
    .trimRight();

List<_Line> _parse(String md) {
  final out = <_Line>[];
  var code = false;
  for (final raw in md.replaceAll('\r', '').split('\n')) {
    if (raw.trimLeft().startsWith('```')) {
      code = !code;
      continue;
    }
    if (code) {
      out.add(_Line('code', raw));
      continue;
    }
    final t = raw.trim();
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
    final li = RegExp(r'^([-*+]|\d+[.)])\s+(.*)$').firstMatch(t);
    if (t.isEmpty) {
      out.add(const _Line('blank', ''));
    } else if (h != null) {
      out.add(
        _Line(
          h[1]!.length == 1
              ? 'h1'
              : h[1]!.length == 2
              ? 'h2'
              : 'h3',
          plainInline(h[2]!),
        ),
      );
    } else if (li != null) {
      out.add(_Line('li', plainInline(li[2]!)));
    } else if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(t)) {
      out.add(const _Line('blank', ''));
    } else {
      out.add(_Line('p', plainInline(t.startsWith('>') ? t.substring(1).trim() : t)));
    }
  }
  return out;
}

/// Một phần của bộ slide: trang chữ rồi mỗi ảnh một trang. Mỗi phần bắt đầu ở trang mới.
class CastSection {
  final String title, subtitle, body;
  final List<Uint8List> images;
  const CastSection({required this.title, this.subtitle = '', this.body = '', this.images = const []});
}

/// PDF 16:9 lưu vào thư mục tạm: trang chữ ([title], [subtitle], [body] dạng Markdown đơn giản) rồi mỗi ảnh trong [images] một trang.
Future<File> buildCastSlides({required String title, String subtitle = '', String body = '', List<Uint8List> images = const [], String fileName = 'slides'}) =>
    saveCastPdf(castSlidesPdf([CastSection(title: title, subtitle: subtitle, body: body, images: images)], docTitle: title), fileName);

/// Ghi PDF vào thư mục tạm (tên tệp có dấu thời gian).
Future<File> saveCastPdf(Future<Uint8List> pdf, String fileName) async {
  final bytes = await pdf;
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/cast-${DateTime.now().millisecondsSinceEpoch}-${fileName.replaceAll(RegExp(r'[^\w-]+'), '_')}.pdf');
  await f.writeAsBytes(bytes);
  return f;
}

/// Nội dung PDF của các [sections]. [maxPagesEach]: giới hạn số trang chữ mỗi phần (bảng tin xoay vòng: 1).
Future<Uint8List> castSlidesPdf(List<CastSection> sections, {String docTitle = '', int maxPagesEach = 60}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
  final mono = pw.Font.ttf(await rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: docTitle,
  );

  pw.Widget line(_Line l) => switch (l.kind) {
    'h1' => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
      child: pw.Text(
        l.text,
        style: pw.TextStyle(font: bold, fontSize: 38, color: _ink),
      ),
    ),
    'h2' => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(
        l.text,
        style: pw.TextStyle(font: bold, fontSize: 32, color: _ink),
      ),
    ),
    'h3' => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Text(
        l.text,
        style: pw.TextStyle(font: bold, fontSize: 28, color: _ink),
      ),
    ),
    'li' => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6, left: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 10,
            height: 10,
            margin: const pw.EdgeInsets.only(top: 12, right: 16),
            decoration: const pw.BoxDecoration(color: _accent, shape: pw.BoxShape.circle),
          ),
          pw.Expanded(
            child: pw.Text(l.text, style: const pw.TextStyle(fontSize: 26, color: _ink, lineSpacing: 6)),
          ),
        ],
      ),
    ),
    'code' => pw.Container(
      color: const PdfColor.fromInt(0xFFF1F5F9),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: pw.Text(
        l.text.isEmpty ? ' ' : l.text,
        style: pw.TextStyle(font: mono, fontSize: 20, color: _ink),
      ),
    ),
    'blank' => pw.SizedBox(height: 10),
    _ => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(l.text, style: const pw.TextStyle(fontSize: 26, color: _ink, lineSpacing: 6)),
    ),
  };

  for (final sec in sections) {
    var lines = _parse(sec.body);
    final hasText = lines.any((l) => l.kind != 'blank');
    var title = sec.title;
    // Một trang mỗi phần (bảng tin xoay vòng): tiêu đề ≤ 90 ký tự, nội dung ≤ 6 dòng / 320 ký tự cho vừa một trang.
    if (maxPagesEach == 1) {
      if (title.length > 90) title = '${title.substring(0, 89)}…';
      final kept = <_Line>[];
      var n = 0;
      for (final l in lines.where((l) => l.kind != 'blank' && l.kind != 'code')) {
        if (kept.length >= 6 || n >= 320) break;
        final t = l.text.length > 320 - n ? '${l.text.substring(0, 320 - n)}…' : l.text;
        kept.add(_Line(l.kind.startsWith('h') ? 'p' : l.kind, t));
        n += t.length;
      }
      lines = kept;
    }
    doc.addPage(
      pw.MultiPage(
        pageFormat: _fmt,
        margin: const pw.EdgeInsets.fromLTRB(72, 56, 72, 48),
        maxPages: maxPagesEach,
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 16),
                child: pw.Text(title, style: const pw.TextStyle(fontSize: 16, color: _sub)),
              ),
        build: (ctx) => [
          pw.Container(width: 96, height: 8, margin: const pw.EdgeInsets.only(bottom: 22), color: _accent),
          pw.Text(
            title,
            style: pw.TextStyle(font: bold, fontSize: hasText ? 48 : 64, color: _ink, lineSpacing: 4),
          ),
          if (sec.subtitle.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 14),
              child: pw.Text(sec.subtitle, style: const pw.TextStyle(fontSize: 22, color: _sub)),
            ),
          pw.SizedBox(height: 28),
          for (final l in lines) line(l),
        ],
      ),
    );
    for (final b in sec.images) {
      pw.MemoryImage img;
      try {
        img = pw.MemoryImage(b);
      } catch (_) {
        continue; // ảnh hỏng / định dạng PDF không đọc được: bỏ qua
      }
      doc.addPage(
        pw.Page(
          pageFormat: _fmt,
          build: (_) => pw.Container(
            color: PdfColors.black,
            alignment: pw.Alignment.center,
            child: pw.Image(img, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
  }
  return doc.save();
}
