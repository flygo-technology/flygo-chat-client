import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import 'theme.dart';

/// Thẻ chung (props.flygo_card, bản 1): bot / quy trình / MCP gửi dữ liệu theo mẫu là có thẻ, không cần bản app mới.
///
/// {v:1, icon, accent, title, subtitle?, status?:{label, tone}, hero?:{value, label?, tone?},
///  stats?:[{label, value, delta?, trend?: up|down, tone?}], fields?:[{label, value, kind?: text|money|copy|phone, tone?}],
///  items?:{title?, rows:[{title, sub?, value?, tone?}]}, progress?:{value 0..1, label?},
///  steps?:{title?, rows:[{title, state: done|active|pending|failed|skipped, sub?, note?}]},
///  note?, actions?:[{label, style?: primary|secondary, url? | copy? | reply? | id? | open?, confirm?, input?, select?}],
///  choices?:{id, title?, options:[{id, label}], min?, max?, submit_label?, done?}, process_id?, footer?}
/// `open`: {process, file?, name?} mở tiến trình (hoặc tệp của tiến trình); `input`: {label, required} hỏi lý do,
/// `select`: {label, options:[{id, label}]} chọn một mục (vd bước trả về) trước khi gửi.
/// Tài liệu đầy đủ: docs/flygo-card.md.
class FlygoCardData {
  final Map<String, dynamic> m;
  const FlygoCardData(this.m);
  static FlygoCardData? tryParse(Object? v) => v is Map && v['v'] == 1 && v['title'] is String ? FlygoCardData(v.cast<String, dynamic>()) : null;
}

FlygoCardData? flygoCardOf(MmPost p) => FlygoCardData.tryParse(p.props['flygo_card']);

/// props của trả lời trong luồng khi bấm nút `id` / `reply` hoặc gửi phần `choices` của thẻ:
/// `{flygo_card_action: {post_id, id, label, values?, reason?, value?}}` (values: id các lựa chọn đã tích; reason: chữ
/// nhập ở `input`; value: mục chọn ở `select`).
Map<String, dynamic> flygoCardActionProps(MmPost post, Map<String, dynamic> a) {
  String s(Object? v) => v == null ? '' : '$v'.trim();
  return {
    'flygo_card_action': {
      'post_id': post.id,
      'id': s(a['id']),
      'label': s(a['label']),
      if (a['values'] is List) 'values': [for (final v in a['values'] as List) '$v'],
      if (s(a['reason']).isNotEmpty) 'reason': s(a['reason']),
      if (s(a['value']).isNotEmpty) 'value': s(a['value']),
    },
  };
}

/// Nút có `input` (ô nhập lý do) và / hoặc `select` (chọn một mục, vd bước trả về): hỏi trong hộp thoại nhỏ.
/// Trả về `{reason?, value?}`, null nếu người dùng huỷ.
Future<Map<String, String>?> askFlygoCardInput(BuildContext context, Map<String, dynamic> a) {
  String s(Object? v) => v == null ? '' : '$v'.trim();
  final input = a['input'] is Map ? (a['input'] as Map).cast<String, dynamic>() : null;
  final select = a['select'] is Map ? (a['select'] as Map).cast<String, dynamic>() : null;
  final options = [for (final o in (select?['options'] as List? ?? const [])) if (o is Map && s(o['id']).isNotEmpty) o.cast<String, dynamic>()];
  final required = input != null && input['required'] != false;
  final ctl = TextEditingController();
  String? value = options.isEmpty ? null : s(options.first['id']);
  final label = s(a['label']);
  return showDialog<Map<String, String>>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) {
        final ok = (!required || ctl.text.trim().isNotEmpty) && (options.isEmpty || value != null);
        return AlertDialog(
          title: Text(label.isEmpty ? tr('Xác nhận') : label),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (options.isNotEmpty) ...[
                if (s(select?['label']).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s(select?['label']), style: const TextStyle(fontWeight: FontWeight.w600))),
                RadioGroup<String>(
                  groupValue: value,
                  onChanged: (v) => set(() => value = v),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final o in options)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: s(o['id']),
                        title: Text(s(o['label']).isEmpty ? s(o['id']) : s(o['label'])),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              if (input != null)
                TextField(
                  controller: ctl,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: s(input['label']).isEmpty ? tr('Lý do') : s(input['label']),
                    hintText: required ? tr('Lý do (bắt buộc)') : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => set(() {}),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: ok ? () => Navigator.pop(d, {if (ctl.text.trim().isNotEmpty) 'reason': ctl.text.trim(), 'value': ?value}) : null,
              child: Text(tr('Gửi')),
            ),
          ],
        );
      },
    ),
  );
}

Color _tone(String? t, Color fallback) => switch (t) {
      'green' => const Color(0xFF16A34A),
      'red' => const Color(0xFFDC2626),
      'orange' => const Color(0xFFEA7A0C),
      'blue' => const Color(0xFF2563EB),
      'purple' => const Color(0xFF7C3AED),
      'gray' => const Color(0xFF6B7280),
      _ => fallback,
    };

const _icons = <String, IconData>{
  'invoice': Icons.receipt_long_rounded,
  'debt': Icons.account_balance_wallet_outlined,
  'incident': Icons.build_circle_outlined,
  'sign': Icons.draw_outlined,
  'report': Icons.insights_rounded,
  'order': Icons.shopping_bag_outlined,
  'attendance': Icons.fingerprint_rounded,
  'task': Icons.assignment_turned_in_outlined,
  'event': Icons.event_rounded,
  'info': Icons.info_outline_rounded,
};

/// Biểu tượng của từ khoá thẻ (invoice, debt, task…); không phải từ khoá thì null (emoji).
IconData? cardKeywordIcon(String k) => _icons[k.trim()];

class FlygoCard extends StatelessWidget {
  final FlygoCardData data;
  final double width;
  /// Bấm nút hoặc gửi lựa chọn (`choices`: action có `id`, `label`, `values`, `reply`). Trả về Future thì phần lựa chọn
  /// chờ gửi xong mới khoá; lỗi thì mở lại.
  final FutureOr<void> Function(Map<String, dynamic> action)? onAction;
  /// Phần đính liền ở cuối thẻ (ghi chú dán lên tin).
  final Widget? footer;
  const FlygoCard({super.key, required this.data, this.width = 340, this.onAction, this.footer});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = data.m;
    final accent = _tone(m['accent'] as String?, pal.accent);
    final tint = accent.withValues(alpha: dark ? .18 : .09);
    String s(Object? v) => v == null ? '' : '$v';
    final status = m['status'] is Map ? (m['status'] as Map).cast<String, dynamic>() : null;
    final hero = m['hero'] is Map ? (m['hero'] as Map).cast<String, dynamic>() : null;
    final stats = [for (final x in (m['stats'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final fields = [for (final x in (m['fields'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final items = m['items'] is Map ? (m['items'] as Map).cast<String, dynamic>() : null;
    final rows = [for (final x in (items?['rows'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final stepsM = m['steps'] is Map ? (m['steps'] as Map).cast<String, dynamic>() : null;
    final steps = [for (final x in (stepsM?['rows'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final progress = m['progress'] is Map ? (m['progress'] as Map).cast<String, dynamic>() : null;
    final actions = [for (final x in (m['actions'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final choices = m['choices'] is Map ? (m['choices'] as Map).cast<String, dynamic>() : null;
    final processId = s(m['process_id']);
    final openProcess = processId.isNotEmpty && onAction != null && !actions.any((a) => a['open'] is Map);
    final label = TextStyle(fontSize: 11, letterSpacing: .3, color: pal.sub, fontWeight: FontWeight.w600);

    Widget section(Widget child, {EdgeInsets pad = const EdgeInsets.fromLTRB(14, 10, 14, 0)}) => Padding(padding: pad, child: child);

    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: pal.inBubble,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .5 : .12), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // Đầu thẻ: icon, tiêu đề, phụ đề, trạng thái; số lớn nổi bật (nếu có).
        Container(
          color: tint,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
                child: Icon(_icons[m['icon']] ?? Icons.article_outlined, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 10),
              // Tiêu đề đứng riêng (không bị trạng thái chen làm cụt); phụ đề + trạng thái ở dòng dưới (Sếp, 2026-11-10).
              Expanded(
                child: Text(s(m['title']), maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text, height: 1.2)),
              ),
              if (openProcess)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: tr('Mở tiến trình'),
                    onPressed: () => onAction?.call({'label': tr('Mở tiến trình'), 'open': {'process': processId}}),
                    icon: Icon(Icons.open_in_new_rounded, color: pal.sub),
                  ),
                ),
            ]),
            if (s(m['subtitle']).isNotEmpty || status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 44),
                child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (s(m['subtitle']).isNotEmpty) Text(s(m['subtitle']), style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  if (status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _tone(status['tone'] as String?, accent), borderRadius: BorderRadius.circular(20)),
                      // Một dòng, cắt bằng "…": lý do dài (lỗi) xem ở bước lỗi, không chiếm đầu thẻ (Sếp, 2026-11-10).
                      constraints: BoxConstraints(maxWidth: (width - 80).clamp(80.0, 320.0)),
                      child: Text(s(status['label']), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                ]),
              ),
            // Nhãn (props tags, tối đa 5): Flows đồng bộ theo tiến trình.
            if (m['tags'] is List && (m['tags'] as List).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: FlygoTags(m['tags'] as List)),
            if (hero != null) ...[
              const SizedBox(height: 10),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(s(hero['value']),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.5, color: _tone(hero['tone'] as String?, accent))),
                ),
              ),
              if (s(hero['label']).isNotEmpty) Center(child: Text(s(hero['label']), style: TextStyle(fontSize: 13, color: pal.sub))),
            ],
          ]),
        ),
        // Ô số liệu (báo cáo): lưới 2 cột.
        if (stats.isNotEmpty)
          section(Wrap(spacing: 8, runSpacing: 8, children: [
            for (final st in stats)
              Container(
                width: (width - 28 - 8) / 2,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(color: pal.text.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s(st['label']), style: label),
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Flexible(child: Text(s(st['value']), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: pal.text))),
                    if (s(st['delta']).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      // "up 18%" / "down 2": mũi tên vẽ bằng icon để không phụ thuộc font.
                      if (st['trend'] == 'up' || st['trend'] == 'down')
                        Icon(st['trend'] == 'up' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 13, color: _tone(st['tone'] as String?, pal.sub)),
                      Text(s(st['delta']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _tone(st['tone'] as String?, pal.sub))),
                    ],
                  ]),
                ]),
              ),
          ])),
        // Các dòng nhãn : giá trị.
        if (fields.isNotEmpty)
          section(Column(children: [
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 104, child: Padding(padding: const EdgeInsets.only(top: 1.5), child: Text(s(f['label']), style: TextStyle(fontSize: 12.5, color: pal.sub)))),
                  Expanded(
                    child: Text(s(f['value']),
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            fontWeight: f['kind'] == 'money' || f['kind'] == 'copy' ? FontWeight.w700 : FontWeight.w500,
                            color: _tone(f['tone'] as String?, pal.text))),
                  ),
                  if (f['kind'] == 'copy' || f['kind'] == 'phone')
                    SizedBox(
                      width: 28,
                      height: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        onPressed: () => Clipboard.setData(ClipboardData(text: s(f['value']))),
                        icon: Icon(f['kind'] == 'phone' ? Icons.call_outlined : Icons.copy_rounded, color: pal.sub),
                      ),
                    ),
                ]),
              ),
          ])),
        // Danh sách dòng con (mặt hàng, người ký…).
        if (rows.isNotEmpty)
          section(Container(
            decoration: BoxDecoration(color: pal.text.withValues(alpha: .04), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s(items?['title']).isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 2), child: Text(s(items?['title']).toUpperCase(), style: label)),
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, indent: 10, endIndent: 10, color: pal.text.withValues(alpha: .08)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s(r['title']), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
                        if (s(r['sub']).isNotEmpty) Text(s(r['sub']), style: TextStyle(fontSize: 12, color: pal.sub)),
                      ]),
                    ),
                    if (s(r['value']).isNotEmpty)
                      Text(s(r['value']), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _tone(r['tone'] as String?, pal.text))),
                  ]),
                ),
              ],
            ]),
          )),
        // Các bước công việc: dòng thời gian dọc, bước đang làm nổi bật.
        if (steps.isNotEmpty)
          section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s(stepsM?['title']).isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s(stepsM?['title']).toUpperCase(), style: label)),
            for (final (i, st) in steps.indexed)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    width: 26,
                    child: Column(children: [
                      _StepDot(state: s(st['state']), accent: accent, pal: pal),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: st['state'] == 'done' ? const Color(0xFF16A34A).withValues(alpha: .6) : pal.text.withValues(alpha: .14),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 12 : 0, top: 1),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s(st['title']),
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: st['state'] == 'active' ? FontWeight.w800 : FontWeight.w600,
                              color: switch (s(st['state'])) {
                                'active' => accent,
                                'failed' => const Color(0xFFDC2626),
                                'pending' || 'skipped' => pal.sub,
                                _ => pal.text,
                              },
                              decoration: st['state'] == 'skipped' ? TextDecoration.lineThrough : null,
                            )),
                        if (s(st['sub']).isNotEmpty) Text(s(st['sub']), style: TextStyle(fontSize: 12, color: pal.sub, height: 1.3)),
                        if (s(st['note']).isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                            decoration: BoxDecoration(color: pal.text.withValues(alpha: .05), borderRadius: BorderRadius.circular(8)),
                            child: Text(s(st['note']), style: TextStyle(fontSize: 12.5, color: pal.text, height: 1.3)),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
          ])),
        // Thanh tiến độ.
        if (progress != null)
          section(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((progress['value'] as num?)?.toDouble() ?? 0).clamp(0, 1),
                minHeight: 7,
                color: accent,
                backgroundColor: accent.withValues(alpha: .15),
              ),
            ),
            if (s(progress['label']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s(progress['label']), style: TextStyle(fontSize: 12, color: pal.sub))),
          ])),
        if (s(m['note']).isNotEmpty)
          section(Text(s(m['note']), style: TextStyle(fontSize: 13, height: 1.35, color: pal.text))),
        // Lựa chọn (bước "Lựa chọn" của quy trình): ô tích + nút Gửi.
        if (choices != null && choices['options'] is List)
          section(FlygoChoices(choices: choices, accent: accent, pal: pal, onAction: onAction)),
        // Nút bấm: 1–2 nút chia đều một hàng; nhiều hơn (nút của bước chờ + tệp + "Mở tiến trình") thì xếp tràn dòng.
        if (actions.isNotEmpty)
          section(
            flygoCardButtons(actions, accent: accent, pal: pal, onAction: onAction),
            pad: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: s(m['footer']).isEmpty ? const SizedBox.shrink() : Text(s(m['footer']), style: TextStyle(fontSize: 11.5, color: pal.sub)),
        ),
        if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: footer),
      ]),
    );
  }
}

/// Chấm trạng thái một bước: xong (tích xanh), đang làm (vòng màu chủ đạo), lỗi (X đỏ), bỏ qua / chưa tới (vòng xám).
class _StepDot extends StatelessWidget {
  final String state;
  final Color accent;
  final Pal pal;
  const _StepDot({required this.state, required this.accent, required this.pal});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A), red = Color(0xFFDC2626);
    return switch (state) {
      'done' => Container(width: 20, height: 20, decoration: const BoxDecoration(color: green, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 14, color: Colors.white)),
      'failed' => Container(width: 20, height: 20, decoration: const BoxDecoration(color: red, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white)),
      'active' => Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent, width: 2), color: accent.withValues(alpha: .15)),
          child: Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle))),
        ),
      'skipped' => Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: pal.text.withValues(alpha: .08)),
          child: Icon(Icons.remove_rounded, size: 14, color: pal.sub)),
      _ => Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.text.withValues(alpha: .25), width: 2))),
    };
  }
}

/// Các nút của thẻ (dùng chung với trang chi tiết tiến trình): 1–2 nút chia đều một hàng, nhiều hơn thì xếp tràn dòng.
Widget flygoCardButtons(List<Map<String, dynamic>> actions, {required Color accent, required Pal pal, FutureOr<void> Function(Map<String, dynamic> action)? onAction}) {
  String s(Object? v) => v == null ? '' : '$v';
  Widget button(Map<String, dynamic> a) {
    final link = a['url'] != null || a['open'] is Map;
    final text = Text(s(a['label']), maxLines: 1, overflow: TextOverflow.ellipsis);
    if (a['style'] == 'primary') {
      return FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent, visualDensity: VisualDensity.compact), onPressed: () => onAction?.call(a), child: text);
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: pal.text),
      onPressed: () => onAction?.call(a),
      icon: link
          ? Icon(a['sign'] is Map ? Icons.draw_outlined : (a['open'] is Map && (a['open'] as Map)['file'] != null ? Icons.description_outlined : Icons.open_in_new_rounded), size: 15)
          : null,
      label: Text(s(a['label']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
    );
  }

  if (actions.length <= 2) {
    return Row(children: [
      for (final (i, a) in actions.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: button(a)),
      ],
    ]);
  }
  return Wrap(spacing: 8, runSpacing: 6, children: [for (final a in actions) button(a)]);
}

/// Phần `choices` của thẻ: danh sách ô tích, kiểm số lượng chọn (min / max), nút Gửi. Gửi xong (hoặc máy chủ đánh dấu
/// `done`) thì khoá, hiện các lựa chọn đã gửi.
class FlygoChoices extends StatefulWidget {
  final Map<String, dynamic> choices;
  final Color accent;
  final Pal pal;
  final FutureOr<void> Function(Map<String, dynamic> action)? onAction;
  const FlygoChoices({super.key, required this.choices, required this.accent, required this.pal, this.onAction});
  @override
  State<FlygoChoices> createState() => _FlygoChoicesState();
}

class _FlygoChoicesState extends State<FlygoChoices> {
  final _picked = <String>{};
  bool _sending = false, _sent = false;

  List<Map<String, dynamic>> get _options => [for (final x in (widget.choices['options'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
  int get _min => ((widget.choices['min'] as num?)?.toInt() ?? 1).clamp(0, 1 << 20);
  int get _max {
    final n = _options.length;
    final m = (widget.choices['max'] as num?)?.toInt() ?? n;
    return m <= 0 ? n : m;
  }

  bool get _locked => _sent || _sending || widget.choices['done'] == true || widget.onAction == null;
  bool get _valid => _picked.length >= _min && _picked.length <= _max && _picked.isNotEmpty;

  String get _hint {
    final min = _min < 1 ? 1 : _min, max = _max;
    if (min == max) return max == 1 ? tr('Chọn 1 mục') : tr('Chọn {0} mục', [max]);
    return tr('Chọn từ {0} đến {1} mục', [min, max]);
  }

  Future<void> _submit() async {
    final opts = _options;
    final ids = [for (final o in opts) if (_picked.contains('${o['id']}')) '${o['id']}'];
    final labels = [for (final o in opts) if (_picked.contains('${o['id']}')) '${o['label'] ?? o['id']}'];
    final submit = '${widget.choices['submit_label'] ?? ''}'.trim().isEmpty ? tr('Gửi') : '${widget.choices['submit_label']}'.trim();
    final confirm = '${widget.choices['confirm'] ?? ''}'.trim();
    if (confirm.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          content: Text(confirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            TextButton(onPressed: () => Navigator.pop(d, true), child: Text(submit)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _sending = true);
    try {
      await widget.onAction?.call({
        'id': '${widget.choices['id'] ?? 'choice'}',
        'label': submit,
        'values': ids,
        'reply': '$submit: ${labels.join(', ')}',
      });
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      // Chưa gửi được (mạng): cho chọn lại.
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal, accent = widget.accent;
    final opts = _options;
    final max = _max;
    final locked = _locked;
    final title = '${widget.choices['title'] ?? ''}';
    final submit = '${widget.choices['submit_label'] ?? ''}'.trim().isEmpty ? tr('Gửi') : '${widget.choices['submit_label']}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: pal.text)),
        ),
      Container(
        decoration: BoxDecoration(color: pal.text.withValues(alpha: .04), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          for (final o in opts)
            InkWell(
              onTap: locked
                  ? null
                  : () => setState(() {
                        final id = '${o['id']}';
                        if (!_picked.remove(id)) {
                          // Chọn một: tích mục mới thì bỏ mục cũ.
                          if (max == 1) _picked.clear();
                          if (_picked.length < max) _picked.add(id);
                        }
                      }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                child: Row(children: [
                  Checkbox(
                    value: _picked.contains('${o['id']}'),
                    activeColor: accent,
                    visualDensity: VisualDensity.compact,
                    onChanged: locked
                        ? null
                        : (v) => setState(() {
                              final id = '${o['id']}';
                              if (v == true) {
                                if (max == 1) _picked.clear();
                                if (_picked.length < max) _picked.add(id);
                              } else {
                                _picked.remove(id);
                              }
                            }),
                  ),
                  Expanded(child: Text('${o['label'] ?? o['id']}', style: TextStyle(fontSize: 13.5, color: locked && !_picked.contains('${o['id']}') ? pal.sub : pal.text))),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Text(
            _sent || widget.choices['done'] == true ? tr('Đã gửi lựa chọn') : _hint,
            style: TextStyle(fontSize: 12, color: _sent ? const Color(0xFF16A34A) : pal.sub),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent, visualDensity: VisualDensity.compact),
          onPressed: locked || !_valid ? null : _submit,
          child: _sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(submit),
        ),
      ]),
    ]);
  }
}


/// Nhãn màu trên thẻ (`tags: [{text, color?: red|orange|green|blue|gray}]`, tối đa 5).
class FlygoTags extends StatelessWidget {
  final List raw;
  const FlygoTags(this.raw, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final tags = [for (final x in raw.take(5)) if (x is Map && '${x['text'] ?? ''}'.trim().isNotEmpty) x];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: [
      for (final t in tags)
        Builder(builder: (_) {
          final c = _tone(t['color'] as String?, pal.sub);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: .4))),
            child: Text('${t['text']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
          );
        }),
    ]);
  }
}
