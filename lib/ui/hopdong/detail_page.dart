// Hợp đồng: chi tiết trên máy tính — xem PDF (pdfrx, tải bằng vé Flygo ID) bên trái, tiến độ ký + nhật ký bên phải.
// Nhiều tài liệu: khung trái có thanh chọn "Chữ ký" (bảng chữ ký theo tài liệu) / từng tài liệu (xem PDF), tải từng tệp hoặc ZIP.
// Điện thoại: chi tiết là trang Tiến độ ký, PDF mở toàn màn hình. Hợp đồng nháp mở thẳng trang soạn.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart' show isDesktop;
import '../app_route.dart';
import 'api.dart';
import 'edit_page.dart';
import 'look.dart';
import 'model.dart';
import 'progress.dart';

/// Mở một hợp đồng: nháp → soạn; còn lại → chi tiết (máy tính) / tiến độ ký (điện thoại). Trả về bản mới nếu có đổi.
Future<Contract?> openContract(BuildContext context, HopdongApi api, Contract c, {required bool wide}) {
  final nav = Navigator.of(context);
  if (c.isDraft && c.canEdit) return nav.push<Contract>(AppPageRoute(builder: (_) => ContractEditPage(api: api, initial: c)));
  if (wide) return nav.push<Contract>(AppPageRoute(builder: (_) => ContractDetailPage(api: api, contract: c)));
  return nav.push<Contract>(AppPageRoute(builder: (_) => ContractProgressPage(api: api, contract: c)));
}

/// Xem PDF toàn màn hình. Không nói tài liệu nào mà hợp đồng có nhiều tài liệu thì hỏi chọn trước.
Future<void> openPdf(BuildContext context, HopdongApi api, Contract c, {HdDoc? doc}) async {
  final d = doc ?? (c.docs.length > 1 ? await chooseDoc(context, c) : c.doc);
  if (d == null || !context.mounted) return;
  await Navigator.of(context).push(AppPageRoute(builder: (_) => PdfFullPage(api: api, contract: c, doc: d)));
}

/// Hộp chọn một tài liệu của hợp đồng.
Future<HdDoc?> chooseDoc(BuildContext context, Contract c, {String title = 'Xem tài liệu'}) {
  final l = HdLook.of(context);
  return showModalBottomSheet<HdDoc>(
    context: context,
    showDragHandle: true,
    backgroundColor: l.card,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: TextStyle(color: l.text, fontSize: 16, fontWeight: FontWeight.w700))),
        for (final d in c.docs)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE5484D)),
            title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(docSub(d)),
            onTap: () => Navigator.pop(ctx, d),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// "Phụ lục 01 · 2 trang · bản 2".
String docSub(HdDoc d) => [if (d.label.isNotEmpty) d.label, if (d.pages != null) '${d.pages} trang', if (d.rev > 1) 'bản ${d.rev}'].join(' · ');

/// Lưu tệp tải về: máy tính hỏi chỗ lưu; điện thoại ghi tạm rồi mở bảng chia sẻ (lưu vào Tệp / gửi đi).
Future<void> hdSaveBytes(BuildContext context, String name, Uint8List bytes) async {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), ' ').trim();
  if (isDesktop) {
    final saved = await FilePicker.saveFile(fileName: safe, bytes: bytes);
    if (saved != null && context.mounted) hdToast(context, 'Đã lưu $safe');
    return;
  }
  final f = File('${(await getTemporaryDirectory()).path}/$safe');
  await f.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], title: safe));
}

/// Tải PDF của một tài liệu (bản hiện tại, gồm chữ ký đã có).
Future<void> downloadDoc(BuildContext context, HopdongApi api, Contract c, HdDoc d) async {
  try {
    final b = await api.docPdf(c.id, d, dl: true);
    if (context.mounted) await hdSaveBytes(context, d.name.isEmpty ? 'hop-dong.pdf' : d.name, b);
  } catch (e) {
    if (context.mounted) hdToast(context, 'Không tải được ${d.name}: $e');
  }
}

/// Tải tất cả tài liệu thành một ZIP (máy chủ cũ: chỉ một tệp PDF).
Future<void> downloadAll(BuildContext context, HopdongApi api, Contract c) async {
  if (!c.multi) return c.doc == null ? null : downloadDoc(context, api, c, c.doc!);
  hdToast(context, 'Đang nén ${c.docs.length} tài liệu…');
  try {
    final b = await api.zip(c.id);
    final base = (c.no.isEmpty ? 'hop-dong-${c.id}' : c.no).replaceAll('/', '-');
    if (context.mounted) await hdSaveBytes(context, '$base.zip', b);
  } catch (e) {
    if (context.mounted) hdToast(context, 'Không tải được ZIP: $e');
  }
}

class ContractDetailPage extends StatefulWidget {
  const ContractDetailPage({super.key, required this.api, required this.contract});
  final HopdongApi api;
  final Contract contract;
  @override
  State<ContractDetailPage> createState() => _ContractDetailPageState();
}

class _ContractDetailPageState extends State<ContractDetailPage> {
  late Contract c = widget.contract;
  bool _changed = false;

  /// Khung trái: -1 = bảng chữ ký theo tài liệu, còn lại = vị trí tài liệu đang xem.
  late int _tab = c.docs.length > 1 ? -1 : 0;

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

  Future<void> _remindAll() async {
    final cur = c.current;
    if (cur.isEmpty) return hdToast(context, 'Không có bên nào đang chờ ký');
    try {
      Contract? n;
      for (final p in cur) {
        n = await widget.api.partyAction(c.id, p.id, 'remind');
      }
      _set(n!);
      if (mounted) hdToast(context, 'Đã ghi nhận nhắc ký ${cur.map((p) => p.name).join(', ')}');
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final now = hdNow();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.of(context).pop(_changed ? c : null);
      },
      child: Scaffold(
        backgroundColor: l.bg,
        body: SafeArea(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.border))),
              child: Row(children: [
                IconButton(visualDensity: VisualDensity.compact, onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: l.sub, size: 20)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hợp đồng${c.ownerName.isNotEmpty ? ' › ${c.ownerName}' : ''}', style: TextStyle(color: l.sub, fontSize: 12)),
                    Row(children: [
                      Flexible(
                        child: Text(c.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 15.5, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      StatusChip(c, now: now, withProgress: true, size: 11),
                    ]),
                  ]),
                ),
                if (c.docs.length > 1) ...[
                  HdAction(Icons.download_rounded, 'Tải tất cả (ZIP)', small: true, onTap: () => downloadAll(context, widget.api, c)),
                  const SizedBox(width: 8),
                ] else if (c.doc != null) ...[
                  HdAction(Icons.history_rounded, 'Bản ${c.doc!.rev}', small: true, onTap: () => openPdf(context, widget.api, c)),
                  const SizedBox(width: 8),
                ],
                if (c.status == 'sending' && c.canEdit) ...[
                  HdAction(Icons.notifications_none_rounded, 'Nhắc ký', small: true, onTap: _remindAll),
                  const SizedBox(width: 8),
                ],
                if (c.canEdit && ['sending', 'rejected'].contains(c.status))
                  HdAction(Icons.block_rounded, 'Huỷ', danger: true, small: true, onTap: () async {
                    final n = await cancelContract(context, widget.api, c);
                    if (n != null) _set(n);
                  }),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: Container(
                    color: l.dark ? const Color(0xFF070B15) : const Color(0xFFE6EAF1),
                    child: c.doc == null
                        ? Center(child: Text('Chưa có tài liệu PDF', style: TextStyle(color: l.sub)))
                        : c.docs.length == 1
                            ? HdPdfView(api: widget.api, contract: c, key: ValueKey('${c.id}:${c.doc!.rev}'))
                            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                _docTabs(l),
                                Expanded(child: _tab < 0 || _tab >= c.docs.length ? _sigsView() : _docView(c.docs[_tab])),
                              ]),
                  ),
                ),
                Container(
                  width: 400,
                  decoration: BoxDecoration(color: l.nav, border: Border(left: BorderSide(color: l.border))),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), children: [
                    Text('THỨ TỰ KÝ · ${c.mode == 'par' ? 'CÙNG LÚC' : 'LẦN LƯỢT'}', style: TextStyle(color: l.sub, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
                    const SizedBox(height: 10),
                    ProgressPane(api: widget.api, contract: c, onChanged: _set, header: false, docs: false),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Thanh chọn trên khung trái: "Chữ ký" + từng tài liệu (nhãn · tên), nút tải tệp đang xem.
  Widget _docTabs(HdLook l) {
    Widget tab(int i, String text, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: HdChip(text, selected: _tab == i, small: true, icon: icon, onTap: () => setState(() => _tab = i)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(color: l.nav, border: Border(bottom: BorderSide(color: l.border))),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              tab(-1, 'Chữ ký ${c.sigsDone}/${c.sigsTotal}', icon: Icons.grid_view_rounded),
              for (var i = 0; i < c.docs.length; i++) tab(i, c.docs[i].title, icon: Icons.picture_as_pdf_outlined),
            ]),
          ),
        ),
        if (_tab >= 0 && _tab < c.docs.length)
          IconButton(
            tooltip: 'Tải ${c.docs[_tab].name}',
            visualDensity: VisualDensity.compact,
            onPressed: () => downloadDoc(context, widget.api, c, c.docs[_tab]),
            icon: Icon(Icons.download_rounded, color: l.sub, size: 20),
          ),
      ]),
    );
  }

  Widget _docView(HdDoc d) => HdPdfView(api: widget.api, contract: c, doc: d, key: ValueKey('${c.id}:${d.id}:${d.rev}'));

  /// Bảng chữ ký theo tài liệu (bấm tên tài liệu để xem PDF).
  Widget _sigsView() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: HdCard(
              pad: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: DocSigs(api: widget.api, contract: c, onOpen: (d) => setState(() => _tab = c.docs.indexOf(d))),
            ),
          ),
        ),
      );
}

/// Xem PDF của hợp đồng (bản hiện tại, gồm các chữ ký đã có). [doc] null = tài liệu đầu.
class HdPdfView extends StatefulWidget {
  const HdPdfView({super.key, required this.api, required this.contract, this.doc});
  final HopdongApi api;
  final Contract contract;
  final HdDoc? doc;

  /// Kiểm thử: không nạp pdfium, vẽ trang giấy giả.
  static bool enabled = true;
  @override
  State<HdPdfView> createState() => _HdPdfViewState();
}

class _HdPdfViewState extends State<HdPdfView> {
  Future<Uint8List>? _data;

  @override
  void initState() {
    super.initState();
    final d = widget.doc ?? widget.contract.doc;
    if (HdPdfView.enabled) _data = d == null ? widget.api.pdf(widget.contract.id) : widget.api.docPdf(widget.contract.id, d);
  }

  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    if (!HdPdfView.enabled) return _FakePaper(c: widget.contract);
    return FutureBuilder<Uint8List>(
      future: _data,
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('Không mở được PDF: ${s.error}', style: TextStyle(color: l.sub)));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return PdfViewer.data(
          s.data!,
          sourceName: 'hopdong-${widget.contract.id}-${(widget.doc ?? widget.contract.doc)?.id ?? ''}-r${(widget.doc ?? widget.contract.doc)?.rev ?? 0}.pdf',
          params: PdfViewerParams(backgroundColor: l.dark ? const Color(0xFF070B15) : const Color(0xFFE6EAF1), margin: 24),
        );
      },
    );
  }
}

/// Trang giấy minh hoạ (chỉ khi kiểm thử, không có pdfium).
class _FakePaper extends StatelessWidget {
  const _FakePaper({required this.c});
  final Contract c;
  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF222222);
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / 1.414,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(48, 44, 48, 40),
          color: Colors.white,
          child: Column(children: [
            const Text('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM', style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12)),
            const Text('Độc lập – Tự do – Hạnh phúc', style: TextStyle(color: ink, fontSize: 11)),
            const SizedBox(height: 16),
            Text(c.title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Số: ${c.no}', style: const TextStyle(color: ink, fontSize: 11)),
            const SizedBox(height: 14),
            for (var i = 0; i < 9; i++)
              Container(margin: const EdgeInsets.symmetric(vertical: 5), height: 7, width: double.infinity, color: const Color(0xFFE4E4E4)),
            const Spacer(),
            Row(children: [
              for (final p in c.parties.take(2))
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: p.signed ? const Color(0xFF16A34A) : const Color(0xFF2F80FF), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(p.signed ? 'Đã ký số · ${p.label}' : 'Ô ký · ${p.label}',
                        style: TextStyle(color: p.signed ? const Color(0xFF16A34A) : const Color(0xFF2F80FF), fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// PDF toàn màn hình.
class PdfFullPage extends StatelessWidget {
  const PdfFullPage({super.key, required this.api, required this.contract, this.doc});
  final HopdongApi api;
  final Contract contract;
  final HdDoc? doc;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final d = doc ?? contract.doc;
    return Scaffold(
      backgroundColor: l.dark ? const Color(0xFF070B15) : const Color(0xFFE6EAF1),
      appBar: AppBar(
        backgroundColor: l.bg,
        surfaceTintColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(contract.no.isEmpty ? 'Hợp đồng' : contract.no, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (d != null)
            Text('${d.name} · bản ${d.rev}${d.pages != null ? ' · ${d.pages} trang' : ''}', style: TextStyle(fontSize: 12, color: l.sub)),
        ]),
        actions: [
          if (d != null) IconButton(tooltip: 'Tải PDF', onPressed: () => downloadDoc(context, api, contract, d), icon: const Icon(Icons.download_rounded)),
        ],
      ),
      body: d == null ? Center(child: Text('Chưa có tài liệu PDF', style: TextStyle(color: l.sub))) : HdPdfView(api: api, contract: contract, doc: d),
    );
  }
}
