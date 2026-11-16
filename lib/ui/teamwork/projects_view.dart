// TeamWork: danh sách dự án (thẻ: mã, tên, phòng ban, mô tả, tiến độ theo nhóm trạng thái, hạn, thành viên, vai trò của
// mình) + lọc theo trạng thái dự án + hộp tạo dự án mới.
import 'package:flutter/material.dart';

import 'cover.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';

class TwProjectsView extends StatefulWidget {
  const TwProjectsView({super.key, required this.store, required this.onOpen});
  final TwStore store;
  final void Function(TwProject) onOpen;
  @override
  State<TwProjectsView> createState() => _TwProjectsViewState();
}

class _TwProjectsViewState extends State<TwProjectsView> {
  String _status = 'active';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final wide = twWide(context);
    final all = widget.store.projects.where((p) => !p.archived).toList();
    final counts = {for (final s in kProjectStatuses) s: all.where((p) => p.status == s).length};
    final list = all.where((p) => p.status == _status && (_q.isEmpty || p.name.toLowerCase().contains(_q) || p.key.toLowerCase().contains(_q))).toList()
      ..sort((a, b) => a.starred != b.starred ? (a.starred ? -1 : 1) : b.updatedAt.compareTo(a.updatedAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 14, vertical: 8), children: [
          for (final s in kProjectStatuses)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TwPill(
                key: ValueKey('pstatus-$s'),
                set: _status == s,
                onTap: () => setState(() => _status = s),
                child: Text('${kProjectStatusNames[s]} · ${counts[s]}'),
              ),
            ),
          if (wide) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 240,
              child: TextField(
                key: const ValueKey('project-q'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Tìm dự án…',
                  isDense: true,
                  filled: true,
                  fillColor: look.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
          ],
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text(widget.store.loaded ? 'Chưa có dự án nào ở mục này' : 'Đang tải…', style: TextStyle(color: look.sub)))
            : Builder(builder: (context) {
                // 4 cột từ ~1400px cửa sổ, 3 cột ~1050px, 2 cột máy tính bảng, 1 cột điện thoại.
                final w = MediaQuery.sizeOf(context).width;
                final cols = w >= 1400 ? 4 : (w >= 1050 ? 3 : (w >= 640 ? 2 : 1));
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 6, wide ? 24 : 14, 90),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: ProjectCard.height),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ProjectCard(project: list[i], store: widget.store, compact: cols == 1, onTap: () => widget.onOpen(list[i])),
                );
              }),
      ),
    ]);
  }
}

/// Thẻ dự án gọn: dải hình nền 56px, ô dự án đè lên mép dưới trái, sao ở góc phải; tên + phòng ban; thanh tiến độ mảnh chia
/// theo nhóm trạng thái; một dòng: trạng thái, "x/y xong", hạn, thành viên. Vai trò của mình: chú thích khi rê chuột vào ô dự án.
class ProjectCard extends StatefulWidget {
  const ProjectCard({super.key, required this.project, required this.store, required this.onTap, this.compact = false, this.preview = false});
  final TwProject project;
  final TwStore store;
  final VoidCallback onTap;
  final bool compact;
  /// Xem trước trong trình chọn hình nền (không bấm được sao).
  final bool preview;
  static const height = 158.0;
  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final p = widget.project;
    final sc = hexColor(kProjectStatusColors[p.status]);
    final meta = TextStyle(fontSize: 12, color: look.sub);
    final color = hexColor(p.color, kTwAccent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _hover ? [BoxShadow(color: Colors.black.withValues(alpha: look.dark ? .4 : .12), blurRadius: 14, offset: const Offset(0, 4))] : const [],
        ),
        child: Material(
          key: ValueKey('project-${p.key}'),
          color: look.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: look.divider)),
          child: InkWell(
            onTap: widget.onTap,
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TwCoverView(key: ValueKey('cover-of-${p.key}'), cover: p.cover, fallback: color, height: 56),
                Padding(
                  padding: const EdgeInsets.fromLTRB(60, 6, 12, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: look.text)),
                    Text(p.deptNames.isEmpty ? p.key : p.deptNames.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                  ]),
                ),
                const Spacer(),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: CategoryBar(p.counts, height: 4)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: _MetaRow(project: p, statusColor: sc, style: meta),
                ),
              ]),
              Positioned(
                left: 12,
                top: 38,
                child: Tooltip(
                  message: 'Vai trò của bạn: ${kRoleNames[p.myRole] ?? p.myRole}',
                  child: Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: look.card, width: 3)),
                    child: ProjectBadge(p, size: 36),
                  ),
                ),
              ),
              if (!widget.preview)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: .18),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => widget.store.star(p),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(p.starred ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: p.starred ? const Color(0xFFFFD43B) : Colors.white),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Dòng thông tin của thẻ dự án: trạng thái + "x/y xong" + hạn luôn hiện đủ (không cắt); avatar thành viên co lại (tối đa 3 +
/// "+N") rồi bỏ hẳn khi không còn chỗ; hết chỗ nữa thì bỏ hạn trước, không bao giờ cắt số việc.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.project, required this.statusColor, required this.style});
  final TwProject project;
  final Color statusColor;
  final TextStyle style;
  static const _av = 22.0;

  static double _avatarsWidth(int shown, int total) => shown <= 0 ? 0 : _av + (shown - 1) * _av * .7 + (total > shown ? _av * .9 + 3 : 0);

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final p = project;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double w(String t, TextStyle st) => (TextPainter(text: TextSpan(text: t, style: base.merge(st)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout()).width;
    final status = kProjectStatusNames[p.status]!;
    final counts = '${p.doneCount}/${p.total} xong';
    final due = p.due == null ? null : dShort(p.due!);
    return LayoutBuilder(builder: (context, c) {
      final chipW = w(status, const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)) + 16;
      final countW = w(counts, style) + 1;
      final dueW = due == null ? 0.0 : 8 + 13 + 2 + w(due, style) + 1;
      final members = p.memberPreview;
      var showDue = due != null;
      var text = chipW + 8 + countW + (showDue ? dueW : 0);
      if (text > c.maxWidth && showDue) {
        showDue = false;
        text = chipW + 8 + countW;
      }
      var shown = members.length.clamp(0, 3);
      while (shown > 0 && text + 6 + _avatarsWidth(shown, members.length) > c.maxWidth) {
        shown--;
      }
      return Row(children: [
        TwChip(status, color: statusColor),
        const SizedBox(width: 8),
        Text(counts, key: ValueKey('counts-${p.key}'), maxLines: 1, softWrap: false, style: style),
        if (showDue) ...[
          const SizedBox(width: 8),
          Icon(Icons.event_outlined, size: 13, color: look.sub),
          const SizedBox(width: 2),
          Text(due!, maxLines: 1, softWrap: false, style: style),
        ],
        const Spacer(),
        if (shown > 0) TwAvatars(members, size: _av, max: shown),
      ]);
    });
  }
}

/// Mã dự án gợi ý từ tên: chữ cái đầu các từ (bỏ dấu), 2–4 ký tự.
String suggestKey(String name) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final plain = name.toLowerCase().split('').map((c) {
    final i = from.indexOf(c);
    return i < 0 ? c : to[i];
  }).join();
  final words = plain.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  var k = words.length == 1 ? words.first.substring(0, words.first.length.clamp(0, 3)) : words.take(4).map((w) => w[0]).join();
  if (k.length < 2 && words.first.length >= 2) k = words.first.substring(0, 2);
  return k.toUpperCase();
}

const kTemplates = {'general': 'Dự án chung', 'recruit': 'Tuyển dụng', 'maintenance': 'Bảo trì định kỳ'};

/// Hộp tạo dự án mới; trả về dự án đã tạo.
Future<TwProjectFull?> createProjectDialog(BuildContext context, TwStore store) => twSheet<TwProjectFull>(context, width: 480, builder: (c) => _CreateProject(store: store));

class _CreateProject extends StatefulWidget {
  const _CreateProject({required this.store});
  final TwStore store;
  @override
  State<_CreateProject> createState() => _CreateProjectState();
}

class _CreateProjectState extends State<_CreateProject> {
  final _name = TextEditingController(), _key = TextEditingController(), _desc = TextEditingController();
  bool _keyTouched = false, _busy = false;
  String _color = '#5B5BD6', _template = 'general';
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim(), key = _key.text.trim().toUpperCase();
    if (name.isEmpty) return setState(() => _err = 'Nhập tên dự án');
    if (!RegExp(r'^[A-Z0-9]{2,6}$').hasMatch(key)) return setState(() => _err = 'Mã dự án gồm 2–6 chữ in hoa hoặc số');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final f = await widget.store.createProject({
        'name': name,
        'key': key,
        'color': _color,
        'template': _template,
        if (_desc.text.trim().isNotEmpty) 'description': blocksToJson(markdownToBlocks(_desc.text.trim())),
      });
      if (mounted) Navigator.pop(context, f);
    } catch (e) {
      setState(() {
        _busy = false;
        _err = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Dự án mới', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('np-name'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên dự án', border: OutlineInputBorder()),
          onChanged: (v) {
            if (!_keyTouched) _key.text = suggestKey(v);
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(
            width: 140,
            child: TextField(
              key: const ValueKey('np-key'),
              controller: _key,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Mã', helperText: 'Việc đánh số MÃ-1, MÃ-2…', border: OutlineInputBorder()),
              onChanged: (_) => _keyTouched = true,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in kSwatches.take(10))
                InkWell(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: hexColor(c), borderRadius: BorderRadius.circular(7), border: _color == c ? Border.all(color: look.text, width: 2) : null),
                  ),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Mô tả (không bắt buộc)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Text('Mẫu quy trình', style: TextStyle(fontSize: 12.5, color: look.sub, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final e in kTemplates.entries) ChoiceChip(label: Text(e.value), selected: _template == e.key, onSelected: (_) => setState(() => _template = e.key)),
        ]),
        const SizedBox(height: 6),
        Text('Trạng thái mặc định: Cần làm / Đang làm (bắt đầu) / Chờ duyệt / Tạm hoãn / Xong / Huỷ. Đổi được trong Cài đặt dự án.', style: TextStyle(fontSize: 12, color: look.sub)),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: TextStyle(color: look.red))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          const SizedBox(width: 8),
          FilledButton(key: const ValueKey('np-save'), onPressed: _busy ? null : _save, child: const Text('Tạo dự án')),
        ]),
      ]),
    );
  }
}
