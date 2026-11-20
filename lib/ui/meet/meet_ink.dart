import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../i18n/i18n.dart';

// Nét vẽ chú thích trên trang tài liệu (Họp mới): bút, chữ nhật, tròn, mũi tên, chữ. Toạ độ tỉ lệ 0..1 của trang, lưu theo
// từng trang trong trạng thái trang Tài liệu (relay: act ink / ink_undo / ink_clear); mọi máy và TV vẽ cùng nét.
//   {t: pen|rect|circle|arrow|text, c: '#rrggbb', w: độ dày (tỉ lệ bề rộng trang), p: [[x, y], …], s?: chữ}

const inkColors = ['#FF3B30', '#FFCC00', '#34C759', '#0A84FF', '#FFFFFF', '#111111'];
const inkTools = <String, IconData>{
  'pen': Icons.edit_rounded,
  'rect': Icons.crop_square_rounded,
  'circle': Icons.circle_outlined,
  'arrow': Icons.north_east_rounded,
  'text': Icons.title_rounded,
};

Color inkColor(String hex) => Color(int.tryParse('FF${hex.replaceFirst('#', '')}', radix: 16) ?? 0xFFFF3B30);

/// Vẽ các nét [strokes] (và nét đang vẽ [current]) trong khung kích thước [size].
void paintInk(Canvas canvas, Size size, List strokes, {Map? current}) {
  for (final k in [...strokes, ?current]) {
    if (k is! Map) continue;
    final pts = [for (final x in (k['p'] as List? ?? const [])) Offset(((x as List)[0] as num).toDouble() * size.width, (x[1] as num).toDouble() * size.height)];
    if (pts.isEmpty) continue;
    final paint = Paint()
      ..color = inkColor('${k['c'] ?? '#FF3B30'}')
      ..strokeWidth = math.max(2, ((k['w'] as num?)?.toDouble() ?? .004) * size.width)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final a = pts.first, b = pts.last;
    switch ('${k['t']}') {
      case 'text':
        final tp = TextPainter(
          text: TextSpan(text: '${k['s'] ?? ''}', style: TextStyle(color: paint.color, fontSize: size.height * .045, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);
        tp.paint(canvas, a - Offset(0, tp.height * .8));
      case 'rect':
        canvas.drawRect(Rect.fromPoints(a, b), paint);
      case 'circle':
        canvas.drawOval(Rect.fromPoints(a, b), paint);
      case 'arrow':
        canvas.drawLine(a, b, paint);
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx), l = paint.strokeWidth * 4;
        canvas.drawLine(b, b - Offset(l * math.cos(ang - .5), l * math.sin(ang - .5)), paint);
        canvas.drawLine(b, b - Offset(l * math.cos(ang + .5), l * math.sin(ang + .5)), paint);
      default:
        final path = Path()..moveTo(a.dx, a.dy);
        for (final q in pts.skip(1)) {
          path.lineTo(q.dx, q.dy);
        }
        if (pts.length == 1) path.lineTo(a.dx + .1, a.dy + .1);
        canvas.drawPath(path, paint);
    }
  }
}

class InkPainter extends CustomPainter {
  final List strokes;
  final Map? current;
  InkPainter(this.strokes, this.current);
  @override
  void paint(Canvas canvas, Size size) => paintInk(canvas, size, strokes, current: current);
  @override
  bool shouldRepaint(InkPainter old) => true;
}

/// Bản PDF mới có nét chú thích (bản gốc giữ nguyên): mỗi trang vẽ thành ảnh rồi vẽ nét lên trên.
/// [ink]: `{"số trang": [nét…]}`. Trang không có nét vẫn giữ (ảnh trang gốc).
Future<Uint8List> annotatedPdf(PdfDocument doc, Map ink, {double width = 1600}) async {
  final out = pw.Document(title: tr('Tài liệu có chú thích'));
  for (var i = 0; i < doc.pages.length; i++) {
    final pg = doc.pages[i];
    final h = width * pg.height / pg.width;
    final img = await pg.renderForDisplay(fullWidth: width, fullHeight: h, backgroundColor: 0xFFFFFFFF);
    if (img == null) continue;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(img, Offset.zero, Paint());
    paintInk(c, Size(width, h), (ink['${i + 1}'] as List?) ?? const []);
    final pic = await rec.endRecording().toImage(width.round(), h.round());
    final png = (await pic.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    img.dispose();
    pic.dispose();
    out.addPage(pw.Page(
      pageFormat: PdfPageFormat(pg.width, pg.height),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
    ));
  }
  return out.save();
}
