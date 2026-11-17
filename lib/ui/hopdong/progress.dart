// Hợp đồng: tiến độ ký — các bước theo từng bên (MST khớp, CA, ký qua plugin / offline, giờ ký), hành động với bên đang tới
// lượt (sao chép link, gửi nhắc, gia hạn, thu hồi) và nhật ký. Dùng làm khung phải trên máy tính và trang riêng trên điện thoại.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_route.dart';
import 'api.dart';
import 'detail_page.dart';
import 'edit_page.dart';
import 'look.dart';
import 'model.dart';

/// Các bước ký + nhật ký của một hợp đồng.
class ProgressPane extends StatefulWidget {
  const ProgressPane({super.key, required this.api, required this.contract, required this.onChanged, this.compact = false, this.header = true, this.logLimit});
  final HopdongApi api;
  final Contract contract;
  final ValueChanged<Contract> onChanged;

  /// Điện thoại: chữ gọn, nút ngắn, không ký trên máy.
  final bool compact;

  /// Hiện tiêu đề (luồng ký, tên HĐ, nút Sửa / PDF).
  final bool header;
  final int? logLimit;
  @override
  State<ProgressPane> createState() => _ProgressPaneState();
}

class _ProgressPaneState extends State<ProgressPane> {
  bool _busy = false;
  bool _allLog = false;
  Contract get c => widget.contract;

  Future<void> _act(HdParty p, String action) async {
    if (_busy) return;
    int? until;
    if (action == 'revoke') {
      final ok = await hdConfirm(context, 'Thu hồi link ký?', 'Link đã gửi cho ${p.name} sẽ không dùng được nữa. Muốn bên này ký tiếp thì gia hạn để có link mới.',
          ok: 'Thu hồi', danger: true);
      if (!ok) return;
    }
    if (action == 'extend') {
      if (!mounted) return;
      final days = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Gia hạn link ký · ${p.name}'),
          children: [
            for (final d in [3, 7, 14, 30])
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('Thêm $d ngày'))),
          ],
        ),
      );
      if (days == null) return;
      final base = [hdNow().millisecondsSinceEpoch, p.linkExpires ?? 0].reduce((a, b) => a > b ? a : b);
      until = base + days * 86400000;
    }
    setState(() => _busy = true);
    try {
      final n = await widget.api.partyAction(c.id, p.id, action, until: until);
      widget.onChanged(n);
      if (mounted) {
        hdToast(context, switch (action) {
          'remind' => 'Đã ghi nhận nhắc ký ${p.name}',
          'extend' => 'Đã gia hạn link tới ${dmHm(until)}',
          _ => 'Đã thu hồi link ký của ${p.name}',
        });
      }
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(HdParty p) {
    if (p.link == null) return hdToast(context, 'Chưa có link ký');
    Clipboard.setData(ClipboardData(text: p.link!));
    hdToast(context, 'Đã sao chép link ký của ${p.name}');
  }

  Future<void> _edit() async {
    final n = await Navigator.of(context).push<Contract>(AppPageRoute(builder: (_) => ContractEditPage(api: widget.api, initial: c)));
    if (n != null) widget.onChanged(n);
  }

  HdStep _state(HdParty p) {
    if (p.signed) return HdStep.done;
    if (p.status == 'rejected') return HdStep.rejected;
    if (p.waitingTurn && c.status == 'sending') return HdStep.current;
    return HdStep.todo;
  }

  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final now = hdNow();
    final cp = widget.compact;
    final total = c.parties.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.header) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Luồng ký · ${c.mode == 'par' ? 'cùng lúc' : 'lần lượt'}', style: TextStyle(color: l.sub, fontSize: 13)),
              const SizedBox(height: 2),
              Text(c.heading.isEmpty ? 'Hợp đồng chưa đặt tên' : c.heading, style: TextStyle(color: l.text, fontSize: 19, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 12),
          if (c.doc != null) ...[
            HdAction(Icons.picture_as_pdf_outlined, 'Xem PDF', onTap: () => openPdf(context, widget.api, c)),
            const SizedBox(width: 8),
          ],
          if (c.canEdit) HdAction(Icons.edit_outlined, c.isDraft ? 'Sửa hợp đồng' : 'Ghi chú', onTap: _edit),
        ]),
        const SizedBox(height: 18),
      ],
      for (var i = 0; i < c.parties.length; i++) _step(context, l, c.parties[i], i, now, cp),
      _finalStep(l, total, cp),
      const SizedBox(height: 22),
      Text(cp ? 'NHẬT KÝ GẦN ĐÂY' : 'NHẬT KÝ', style: TextStyle(color: l.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6)),
      const SizedBox(height: 10),
      ..._log(l, cp),
    ]);
  }

  Widget _rail(HdLook l, {required Widget dot, required bool line, required Widget child, double size = 40}) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: size,
            child: Column(children: [
              dot,
              if (line) Expanded(child: Center(child: Container(width: 2, color: l.border))),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 18), child: child)),
        ]),
      );

  Widget _step(BuildContext context, HdLook l, HdParty p, int i, DateTime now, bool cp) {
    final st = _state(p);
    final expired = st == HdStep.current && p.linkExpired(now);
    final over = st == HdStep.current && (c.overdue(now) || expired);
    final dotSize = cp ? 40.0 : 40.0;
    // Phần phải: trạng thái của bên.
    final (String right, Color rc) = switch (st) {
      HdStep.done => ('Đã ký ${dmHm(p.signedAt)}', l.ok),
      HdStep.rejected => ('Từ chối ký', l.warn),
      HdStep.current => (expired ? 'Link hết hạn' : 'Đang chờ ký', expired ? l.red : l.accentText),
      HdStep.todo => (c.status == 'draft' ? 'Chưa gửi' : c.status == 'cancelled' ? 'Đã huỷ' : 'Chưa tới lượt', l.sub),
    };
    final idOk = p.signed ? '${p.idLabel} ✓ khớp' : p.idLabel;
    final sub = <String>[
      idOk,
      if (p.signed) ...[
        if ((p.certIssuer ?? '').isNotEmpty) p.certIssuer!,
        if (!cp && (p.certSerial ?? '').isNotEmpty) 'serial ${_short(p.certSerial!)}',
        viaText(p.signedVia),
      ] else if (st == HdStep.current) ...[
        if (p.internal) 'token công ty',
        if (!cp && p.linkExpires != null) 'link hạn ${dmHm(p.linkExpires)}',
        p.openCount > 0 ? 'đã mở ${p.openCount} lần' : 'chưa mở link',
      ] else if (st == HdStep.todo) ...[
        if (p.email.isNotEmpty && !cp) p.email,
        if (c.mode == 'seq' && i > 0) 'sau ${c.parties[i - 1].label.isEmpty ? c.parties[i - 1].name : c.parties[i - 1].label}',
      ],
    ].where((x) => x.isNotEmpty).join(' · ');

    final title = cp
        ? Text.rich(TextSpan(children: [
            TextSpan(text: p.internal ? '${p.name} (mình)' : p.name),
            if (p.label.isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Pill(p.label.replaceFirst('Bên ', ''), fg: p.internal ? l.accentText : l.warn, bg: p.internal ? l.accentSoft : l.warnSoft, size: 12),
                ),
              ),
          ]), style: TextStyle(color: l.text, fontSize: 16, fontWeight: FontWeight.w700))
        : Text.rich(TextSpan(children: [
            if (p.label.isNotEmpty) TextSpan(text: '${p.label} · '),
            TextSpan(text: p.name.isEmpty ? 'Chưa đặt tên' : p.name),
            if (p.internal) TextSpan(text: ' (mình)', style: TextStyle(color: l.sub, fontWeight: FontWeight.w500)),
          ]), style: TextStyle(color: l.text, fontSize: 15.5, fontWeight: FontWeight.w700));

    final canAct = st == HdStep.current && c.canEdit && c.status == 'sending';
    return _rail(
      l,
      size: dotSize,
      line: true,
      dot: StepDot(st, label: '${i + 1}', size: dotSize, warn: over),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cp) title else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: title),
          const SizedBox(width: 10),
          Text(right, style: TextStyle(color: rc, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 3),
        Text(sub, style: TextStyle(color: l.sub, fontSize: cp ? 14 : 13.5, height: 1.35)),
        if (cp) ...[
          const SizedBox(height: 2),
          Text(st == HdStep.current && p.linkExpires != null ? '$right · hạn link ${dmHm(p.linkExpires)}' : right,
              style: TextStyle(color: rc, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
        if (st == HdStep.rejected && (p.rejectReason ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('"${p.rejectReason}"', style: TextStyle(color: l.warn, fontSize: 14, fontStyle: FontStyle.italic)),
        ],
        if (canAct && p.internal) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: l.accentSoft.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.usb_rounded, size: 18, color: l.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cp ? 'Mở trang ký trên máy tính có cắm USB token' : 'Bên mình ký trên trình duyệt có plugin ký số và USB token',
                    style: TextStyle(color: l.accentText, fontSize: 13.5)),
              ),
            ]),
          ),
        ],
        if (canAct) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (p.internal && !cp && p.link != null)
              HdAction(Icons.open_in_new_rounded, 'Mở trang ký', onTap: _busy ? null : () => launchUrl(Uri.parse(p.link!), mode: LaunchMode.externalApplication)),
            HdAction(Icons.link_rounded, cp ? 'Link' : 'Sao chép link ký', onTap: _busy ? null : () => _copy(p)),
            HdAction(Icons.notifications_none_rounded, cp ? 'Nhắc' : 'Gửi nhắc', onTap: _busy ? null : () => _act(p, 'remind')),
            HdAction(Icons.schedule_rounded, cp ? 'Gia hạn' : 'Gia hạn link', onTap: _busy ? null : () => _act(p, 'extend')),
            HdAction(Icons.link_off_rounded, 'Thu hồi', danger: true, onTap: _busy ? null : () => _act(p, 'revoke')),
          ]),
        ],
      ]),
    );
  }

  Widget _finalStep(HdLook l, int total, bool cp) {
    final done = c.status == 'signed';
    final cancelled = c.status == 'cancelled';
    final dot = done
        ? const StepDot(HdStep.done, size: 40)
        : Container(
            width: 40, height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: l.card2, border: Border.all(color: l.border, width: 1.5)),
            child: Icon(cancelled ? Icons.block_rounded : Icons.check_rounded, size: 18, color: cancelled ? l.red : l.sub),
          );
    final sub = done
        ? 'Đủ chữ ký ${dmHm(c.doneAt)} · PDF đã ký gồm $total chữ ký'
        : cancelled
            ? 'Hợp đồng đã huỷ · link ký của các bên đã bị thu hồi'
            : cp
                ? 'Gửi PDF đã ký cho $total bên'
                : 'Đủ chữ ký thì khoá bản cuối · gửi PDF đã ký cho $total bên';
    return _rail(
      l,
      line: false,
      dot: dot,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(cancelled ? 'Đã huỷ' : 'Hoàn tất', style: TextStyle(color: cancelled ? l.red : l.text, fontSize: 15.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(sub, style: TextStyle(color: l.sub, fontSize: 13.5)),
      ]),
    );
  }

  List<Widget> _log(HdLook l, bool cp) {
    final ev = c.events;
    if (ev.isEmpty) return [Text('Chưa có nhật ký', style: TextStyle(color: l.sub))];
    final lim = _allLog ? ev.length : (widget.logLimit ?? (cp ? 6 : 30));
    return [
      for (final e in ev.take(lim))
        Builder(builder: (_) {
          final (t, warn) = eventText(e, c);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: cp ? 98 : 120, child: Text(dmHm(e.at), style: TextStyle(color: l.sub, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()]))),
              Expanded(child: Text(t, style: TextStyle(color: warn ? l.warn : l.text, fontSize: 14, height: 1.35))),
            ]),
          );
        }),
      if (ev.length > lim)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(() => _allLog = true), child: Text('Xem tất cả ${ev.length} dòng')),
        ),
    ];
  }
}

String _short(String s) => s.length <= 10 ? s : '${s.substring(0, 4)}…${s.substring(s.length - 2)}';

/// Trang tiến độ ký trên điện thoại (= chi tiết hợp đồng): tóm tắt + các bước + nhật ký; nút xem PDF toàn màn hình.
class ContractProgressPage extends StatefulWidget {
  const ContractProgressPage({super.key, required this.api, required this.contract});
  final HopdongApi api;
  final Contract contract;
  @override
  State<ContractProgressPage> createState() => _ContractProgressPageState();
}

class _ContractProgressPageState extends State<ContractProgressPage> {
  late Contract c = widget.contract;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final n = await widget.api.contract(c.id);
      if (mounted) setState(() => c = n);
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    }
  }

  void _set(Contract n) => setState(() {
        c = n;
        _changed = true;
      });

  Future<void> _menu(String a) async {
    switch (a) {
      case 'pdf':
        return openPdf(context, widget.api, c);
      case 'edit':
        final n = await Navigator.of(context).push<Contract>(AppPageRoute(builder: (_) => ContractEditPage(api: widget.api, initial: c)));
        if (n != null) _set(n);
      case 'cancel':
        final n = await cancelContract(context, widget.api, c);
        if (n != null) _set(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final now = hdNow();
    final left = c.signDeadline == null ? null : DateTime.fromMillisecondsSinceEpoch(c.signDeadline!).difference(now).inDays;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.of(context).pop(_changed ? c : null);
      },
      child: Scaffold(
        backgroundColor: l.bg,
        appBar: AppBar(
          backgroundColor: l.bg,
          surfaceTintColor: Colors.transparent,
          title: const Text('Tiến độ ký', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (c.doc != null) IconButton(tooltip: 'Xem PDF', onPressed: () => openPdf(context, widget.api, c), icon: const Icon(Icons.picture_as_pdf_outlined)),
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (c.doc != null) const PopupMenuItem(value: 'pdf', child: Text('Xem PDF toàn màn hình')),
                if (c.canEdit) PopupMenuItem(value: 'edit', child: Text(c.isDraft ? 'Sửa hợp đồng' : 'Sửa ghi chú')),
                if (c.canEdit && ['draft', 'sending', 'rejected'].contains(c.status)) const PopupMenuItem(value: 'cancel', child: Text('Huỷ hợp đồng')),
              ],
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            HdCard(
              pad: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.no.isEmpty ? 'Chưa có số' : c.no, style: TextStyle(color: l.sub, fontSize: 14))),
                  StatusChip(c, now: now),
                ]),
                const SizedBox(height: 2),
                Text(c.title.isEmpty ? 'Hợp đồng chưa đặt tên' : c.title, style: TextStyle(color: l.text, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                SegProgress(c, now: now, height: 6),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text('${c.signedCount}/${c.parties.length} bên đã ký', style: TextStyle(color: l.sub, fontSize: 14))),
                  if (c.signDeadline != null && c.status == 'sending')
                    Text('hạn ${dm(c.signDeadline)} · ${left! >= 0 ? 'còn $left ngày' : 'quá ${-left} ngày'}',
                        style: TextStyle(color: left >= 0 ? l.sub : l.red, fontSize: 14)),
                ]),
              ]),
            ),
            const SizedBox(height: 18),
            ProgressPane(api: widget.api, contract: c, onChanged: _set, compact: true, header: false),
            if (c.doc != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => openPdf(context, widget.api, c),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text('Xem PDF${c.doc!.pages != null ? ' · ${c.doc!.pages} trang' : ''}'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Huỷ hợp đồng (hỏi lý do); trả về hợp đồng mới hoặc null.
Future<Contract?> cancelContract(BuildContext context, HopdongApi api, Contract c) async {
  final reason = await hdAsk(context, 'Huỷ hợp đồng ${c.no}?', hint: 'Lý do huỷ (ghi vào nhật ký)', ok: 'Huỷ hợp đồng');
  if (reason == null) return null;
  try {
    return await api.cancel(c.id, reason);
  } catch (e) {
    if (context.mounted) hdToast(context, '$e');
    return null;
  }
}
