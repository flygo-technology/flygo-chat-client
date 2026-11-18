// Hợp đồng: tiến độ ký — các bước theo từng bên (MST khớp, CA, ký qua plugin / offline, giờ ký), hành động với bên đang tới
// lượt (sao chép link, gửi nhắc, gia hạn, thu hồi) và nhật ký. Dùng làm khung phải trên máy tính và trang riêng trên điện thoại.
// Nhiều tài liệu: thêm "Chữ ký theo tài liệu" — bảng tài liệu × bên (rộng) hoặc danh sách từng tài liệu (hẹp), tải từng tệp.
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
  const ProgressPane({
    super.key, required this.api, required this.contract, required this.onChanged, this.compact = false, this.header = true, this.logLimit, this.docs = true,
  });
  final HopdongApi api;
  final Contract contract;
  final ValueChanged<Contract> onChanged;

  /// Điện thoại: chữ gọn, nút ngắn, không ký trên máy.
  final bool compact;

  /// Hiện tiêu đề (luồng ký, tên HĐ, nút Sửa / PDF).
  final bool header;
  final int? logLimit;

  /// Hiện "Chữ ký theo tài liệu" khi có nhiều tài liệu (chi tiết máy tính đã có bảng riêng bên trái).
  final bool docs;
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
              Text('Luồng ký · ${c.mode == 'par' ? 'cùng lúc' : 'lần lượt'}', style: TextStyle(color: l.sub, fontSize: 12)),
              const SizedBox(height: 1),
              Text(c.heading.isEmpty ? 'Hợp đồng chưa đặt tên' : c.heading, style: TextStyle(color: l.text, fontSize: 15.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 12),
          if (c.docs.length > 1) ...[
            HdAction(Icons.download_rounded, 'Tải ZIP', small: true, onTap: () => downloadAll(context, widget.api, c)),
            const SizedBox(width: 6),
          ],
          if (c.doc != null) ...[
            HdAction(Icons.picture_as_pdf_outlined, c.docs.length > 1 ? 'Xem tài liệu' : 'Xem PDF', small: true, onTap: () => openPdf(context, widget.api, c)),
            const SizedBox(width: 6),
          ],
          if (c.canEdit) HdAction(Icons.edit_outlined, c.isDraft ? 'Sửa hợp đồng' : 'Ghi chú', small: true, onTap: _edit),
        ]),
        const SizedBox(height: 14),
      ],
      if (widget.docs && c.docs.length > 1) ...[
        cp ? HdCard(pad: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: DocSigs(api: widget.api, contract: c, compact: true)) : DocSigs(api: widget.api, contract: c),
        SizedBox(height: cp ? 18 : 14),
      ],
      for (var i = 0; i < c.parties.length; i++) _step(context, l, c.parties[i], i, now, cp),
      _finalStep(l, total, cp),
      SizedBox(height: cp ? 22 : 14),
      Text(cp ? 'NHẬT KÝ GẦN ĐÂY' : 'NHẬT KÝ', style: TextStyle(color: l.sub, fontSize: cp ? 13 : 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
      SizedBox(height: cp ? 10 : 6),
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
          SizedBox(width: size < 36 ? 10 : 14),
          Expanded(child: Padding(padding: EdgeInsets.only(bottom: size < 36 ? 12 : 18), child: child)),
        ]),
      );

  Widget _step(BuildContext context, HdLook l, HdParty p, int i, DateTime now, bool cp) {
    final st = _state(p);
    final expired = st == HdStep.current && p.linkExpired(now);
    final over = st == HdStep.current && (c.overdue(now) || expired);
    final dotSize = cp ? 40.0 : 26.0;
    final fT = cp ? 16.0 : 13.5, fS = cp ? 14.0 : 12.0;
    // Phần phải: trạng thái của bên.
    final (String right, Color rc) = switch (st) {
      HdStep.done => ('Đã ký ${dmHm(p.signedAt)}', l.ok),
      HdStep.rejected => ('Từ chối ký', l.warn),
      HdStep.current => (expired ? 'Link hết hạn' : 'Đang chờ ký', expired ? l.red : l.accentText),
      HdStep.todo => (c.status == 'draft' ? 'Chưa gửi' : c.status == 'cancelled' ? 'Đã huỷ' : 'Chưa tới lượt', l.sub),
    };
    final idOk = p.signed ? '${p.idLabel} ✓ khớp' : p.idLabel;
    // Nhiều tài liệu: "đã ký a/b tài liệu" (bên đã ký đủ thì đã ký hết, khỏi nói).
    final docs = c.docs.length > 1 && !p.signed && c.status != 'draft' ? 'đã ký ${c.docsSignedOf(p)}/${c.docsTotalOf(p)} tài liệu' : '';
    final sub = <String>[
      idOk,
      docs,
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
          ]), style: TextStyle(color: l.text, fontSize: fT, fontWeight: FontWeight.w600));

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
          Text(right, style: TextStyle(color: rc, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(color: l.sub, fontSize: fS, height: 1.35)),
        if (cp) ...[
          const SizedBox(height: 2),
          Text(st == HdStep.current && p.linkExpires != null ? '$right · hạn link ${dmHm(p.linkExpires)}' : right,
              style: TextStyle(color: rc, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
        if (st == HdStep.rejected && (p.rejectReason ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('"${p.rejectReason}"', style: TextStyle(color: l.warn, fontSize: fS, fontStyle: FontStyle.italic)),
        ],
        if (canAct && p.internal) ...[
          SizedBox(height: cp ? 10 : 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: cp ? 12 : 10, vertical: cp ? 10 : 6),
            decoration: BoxDecoration(color: l.accentSoft.withValues(alpha: .6), borderRadius: BorderRadius.circular(cp ? 12 : 8)),
            child: Row(children: [
              Icon(Icons.usb_rounded, size: cp ? 18 : 15, color: l.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cp ? 'Mở trang ký trên máy tính có cắm USB token' : 'Bên mình ký trên trình duyệt có plugin ký số và USB token',
                    style: TextStyle(color: l.accentText, fontSize: cp ? 13.5 : 12)),
              ),
            ]),
          ),
        ],
        if (canAct) ...[
          SizedBox(height: cp ? 10 : 8),
          Wrap(spacing: cp ? 8 : 6, runSpacing: cp ? 8 : 6, children: [
            if (p.internal && !cp && p.link != null)
              HdAction(Icons.open_in_new_rounded, 'Mở trang ký', small: !cp, onTap: _busy ? null : () => launchUrl(Uri.parse(p.link!), mode: LaunchMode.externalApplication)),
            HdAction(Icons.link_rounded, cp ? 'Link' : 'Sao chép link ký', small: !cp, onTap: _busy ? null : () => _copy(p)),
            HdAction(Icons.notifications_none_rounded, cp ? 'Nhắc' : 'Gửi nhắc', small: !cp, onTap: _busy ? null : () => _act(p, 'remind')),
            HdAction(Icons.schedule_rounded, cp ? 'Gia hạn' : 'Gia hạn link', small: !cp, onTap: _busy ? null : () => _act(p, 'extend')),
            HdAction(Icons.link_off_rounded, 'Thu hồi', danger: true, small: !cp, onTap: _busy ? null : () => _act(p, 'revoke')),
          ]),
        ],
      ]),
    );
  }

  Widget _finalStep(HdLook l, int total, bool cp) {
    final done = c.status == 'signed';
    final cancelled = c.status == 'cancelled';
    final ds = cp ? 40.0 : 26.0;
    final dot = done
        ? StepDot(HdStep.done, size: ds)
        : Container(
            width: ds, height: ds,
            decoration: BoxDecoration(shape: BoxShape.circle, color: l.card2, border: Border.all(color: l.border, width: 1.5)),
            child: Icon(cancelled ? Icons.block_rounded : Icons.check_rounded, size: cp ? 18 : 14, color: cancelled ? l.red : l.sub),
          );
    final sub = done
        ? (c.docs.length > 1 ? 'Đủ chữ ký ${dmHm(c.doneAt)} · ${c.docs.length} tài liệu, ${c.sigsTotal} chữ ký' : 'Đủ chữ ký ${dmHm(c.doneAt)} · PDF đã ký gồm $total chữ ký')
        : cancelled
            ? 'Hợp đồng đã huỷ · link ký của các bên đã bị thu hồi'
            : cp
                ? 'Gửi PDF đã ký cho $total bên'
                : 'Đủ chữ ký thì khoá bản cuối · gửi PDF đã ký cho $total bên';
    return _rail(
      l,
      line: false,
      size: ds,
      dot: dot,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(cancelled ? 'Đã huỷ' : 'Hoàn tất', style: TextStyle(color: cancelled ? l.red : l.text, fontSize: cp ? 15.5 : 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(color: l.sub, fontSize: cp ? 13.5 : 12)),
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
            padding: EdgeInsets.symmetric(vertical: cp ? 7 : 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: cp ? 98 : 84, child: Text(dmHm(e.at), style: TextStyle(color: l.sub, fontSize: cp ? 14 : 12, fontFeatures: const [FontFeature.tabularFigures()]))),
              Expanded(child: Text(t, style: TextStyle(color: warn ? l.warn : l.text, fontSize: cp ? 14 : 12.5, height: 1.35))),
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
      case 'zip':
        return downloadAll(context, widget.api, c);
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
            if (c.doc != null)
              IconButton(tooltip: c.docs.length > 1 ? 'Xem tài liệu' : 'Xem PDF', onPressed: () => openPdf(context, widget.api, c), icon: const Icon(Icons.picture_as_pdf_outlined)),
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (c.doc != null) PopupMenuItem(value: 'pdf', child: Text(c.docs.length > 1 ? 'Xem tài liệu' : 'Xem PDF toàn màn hình')),
                if (c.docs.length > 1) const PopupMenuItem(value: 'zip', child: Text('Tải tất cả (ZIP)')),
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
                  Expanded(
                    child: Text('${c.signedCount}/${c.parties.length} bên đã ký${c.docs.length > 1 ? ' · ${c.docsDone}/${c.docsTotal} tài liệu xong' : ''}',
                        style: TextStyle(color: l.sub, fontSize: 14)),
                  ),
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
                label: Text(c.docs.length > 1
                    ? 'Xem tài liệu · ${c.docs.length} file'
                    : 'Xem PDF${c.doc!.pages != null ? ' · ${c.doc!.pages} trang' : ''}'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Chữ ký theo tài liệu: tiêu đề "x/y chữ ký · a/b tài liệu hoàn tất"; rộng ≥ 560px (không [compact]) là bảng tài liệu × bên,
/// hẹp là danh sách từng tài liệu với một dòng trạng thái cho mỗi bên. Mỗi tài liệu có nút tải PDF; bấm tên tài liệu là xem.
class DocSigs extends StatelessWidget {
  const DocSigs({super.key, required this.api, required this.contract, this.compact = false, this.onOpen});
  final HopdongApi api;
  final Contract contract;
  final bool compact;

  /// Bấm tên tài liệu (mặc định: mở PDF toàn màn hình).
  final ValueChanged<HdDoc>? onOpen;

  Contract get c => contract;

  /// Ô của [p] trên [d]: (icon, chữ chính, màu, dòng phụ); icon null = không cần ký.
  (IconData?, String, Color, String) _cell(HdLook l, HdDoc d, HdParty p, int i) {
    if (!d.signs(p.id)) return (null, 'không cần ký', l.sub, '');
    final s = c.sigOf(d, p);
    if (s != null) {
      final now = hdNow();
      final t = s.signedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(s.signedAt!);
      final today = t != null && t.year == now.year && t.month == now.month && t.day == now.day;
      final hm = t == null ? '' : (today ? dmHm(s.signedAt).split(' ').last : dmHm(s.signedAt));
      final sub = [
        if (p.internal) 'token công ty',
        if ((s.certIssuer ?? '').isNotEmpty) s.certIssuer!,
        if (!p.internal) '${p.idKind == 'cccd' ? 'CCCD' : 'MST'} khớp',
        viaText(s.via).replaceFirst('qua plugin ', ''),
      ].where((x) => x.isNotEmpty).join(' · ');
      return (Icons.check_circle_rounded, 'Đã ký $hm'.trim(), l.ok, sub);
    }
    if (c.status == 'draft') return (Icons.radio_button_unchecked_rounded, 'Chưa gửi', l.sub, '');
    if (c.status == 'cancelled') return (Icons.block_rounded, 'Đã huỷ', l.sub, '');
    if (p.status == 'rejected') return (Icons.cancel_rounded, 'Từ chối ký', l.warn, '');
    if (p.waitingTurn && c.status == 'sending') {
      if (p.internal) return (Icons.pending_outlined, 'Đến lượt mình', l.accentText, 'chờ ký bằng token công ty');
      final expired = p.linkExpired(hdNow());
      return (Icons.pending_outlined, expired ? 'Link hết hạn' : 'Chờ ký', expired ? l.red : l.accentText, p.openCount > 0 ? 'đã mở link ${p.openCount} lần' : 'chưa mở link');
    }
    final prev = c.mode == 'seq' && i > 0 ? c.parties[i - 1] : null;
    return (Icons.schedule_rounded, 'Đang chờ', l.sub, prev == null ? '' : 'sau ${prev.label.isEmpty ? prev.name : prev.label}');
  }

  void _open(BuildContext context, HdDoc d) => onOpen != null ? onOpen!(d) : openPdf(context, api, c, doc: d);

  /// Tên ngắn của bên cho tiêu đề cột: "1 · Đông Nam Á (Bên A)".
  static String _col(HdParty p, int i) {
    final n = p.name.replaceFirst(RegExp(r'^(CÔNG TY|CTY)\s+(CỔ PHẦN|CP|TNHH)?\s*', caseSensitive: false), '').trim();
    final short = n.isEmpty ? p.name : n.split(' ').map((w) => w.length <= 1 ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
    return '${i + 1} · ${short.isEmpty ? p.label : short}${p.label.isNotEmpty && short.isNotEmpty ? ' (${p.label})' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final head = Row(children: [
      Icon(Icons.grid_view_rounded, size: compact ? 20 : 18, color: l.accentText),
      SizedBox(width: compact ? 10 : 8),
      Expanded(child: Text('Chữ ký theo tài liệu', style: TextStyle(color: l.text, fontSize: compact ? 16 : 14, fontWeight: FontWeight.w700))),
      Text('${c.sigsDone}/${c.sigsTotal} chữ ký · ${c.docsDone}/${c.docsTotal} tài liệu${compact ? '' : ' hoàn tất'}', style: TextStyle(color: l.sub, fontSize: compact ? 13 : 12)),
    ]);
    return LayoutBuilder(builder: (context, box) {
      final table = !compact && box.maxWidth >= 560;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        SizedBox(height: table ? 8 : 6),
        if (table) _table(context, l) else for (var k = 0; k < c.docs.length; k++) _docBlock(context, l, c.docs[k], k),
      ]);
    });
  }

  Widget _docTitle(BuildContext context, HdLook l, HdDoc d, {double size = 13}) => InkWell(
        onTap: () => _open(context, d),
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Icon(Icons.picture_as_pdf_rounded, color: const Color(0xFFE5484D), size: size + 5),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: size, fontWeight: FontWeight.w600)),
              Text([if (d.label.isNotEmpty) d.label, if (d.pages != null) '${d.pages} trang'].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: size - 2)),
            ]),
          ),
        ]),
      );

  Widget _dl(BuildContext context, HdLook l, HdDoc d, {double size = 18}) => IconButton(
        tooltip: 'Tải ${d.name}',
        visualDensity: VisualDensity.compact,
        onPressed: () => downloadDoc(context, api, c, d),
        icon: Icon(Icons.download_rounded, color: l.sub, size: size),
      );

  Widget _status(HdLook l, (IconData?, String, Color, String) v, {double size = 12.5}) {
    final (icon, text, color, sub) = v;
    if (icon == null) return Text(text, style: TextStyle(color: l.sub, fontSize: size - .5));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: size + 4, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600))),
      ]),
      if (sub.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(left: size + 10),
          child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: size - 1.5)),
        ),
    ]);
  }

  /// Bảng: cột Tài liệu co giãn, mỗi bên một cột bằng nhau, cột tải 44px.
  Widget _table(BuildContext context, HdLook l) {
    final ps = c.parties;
    final th = TextStyle(color: l.sub, fontSize: 12, fontWeight: FontWeight.w600);
    return Table(
      columnWidths: {0: const FlexColumnWidth(1.4), for (var i = 0; i < ps.length; i++) i + 1: const FlexColumnWidth(1), ps.length + 1: const FixedColumnWidth(44)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: l.border), top: BorderSide(color: l.border), bottom: BorderSide(color: l.border)),
      children: [
        TableRow(children: [
          Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 8), child: Text('Tài liệu', style: th)),
          for (var i = 0; i < ps.length; i++)
            Padding(padding: const EdgeInsets.fromLTRB(0, 8, 8, 8), child: Text(_col(ps[i], i), maxLines: 1, overflow: TextOverflow.ellipsis, style: th)),
          const SizedBox(),
        ]),
        for (final d in c.docs)
          TableRow(children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 9, 12, 9), child: _docTitle(context, l, d)),
            for (var i = 0; i < ps.length; i++) Padding(padding: const EdgeInsets.only(right: 8), child: _status(l, _cell(l, d, ps[i], i))),
            _dl(context, l, d),
          ]),
      ],
    );
  }

  /// Hẹp / điện thoại: mỗi tài liệu một khối, dưới là từng bên: nhãn bên + trạng thái.
  Widget _docBlock(BuildContext context, HdLook l, HdDoc d, int k) {
    final fs = compact ? 14.0 : 12.5;
    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 8),
      decoration: BoxDecoration(border: k == 0 ? null : Border(top: BorderSide(color: l.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _docTitle(context, l, d, size: compact ? 14.5 : 13)),
          _dl(context, l, d, size: compact ? 22 : 18),
        ]),
        for (var i = 0; i < c.parties.length; i++)
          Padding(
            padding: EdgeInsets.only(left: compact ? 26 : 24, top: compact ? 6 : 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: compact ? 70 : 60,
                child: Text(c.parties[i].label.isEmpty ? '${i + 1}' : c.parties[i].label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: fs - .5, fontWeight: FontWeight.w600)),
              ),
              Expanded(child: _status(l, _cell(l, d, c.parties[i], i), size: fs)),
            ]),
          ),
      ]),
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
