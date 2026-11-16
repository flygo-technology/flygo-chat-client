// TeamWork: danh sách dự án (thẻ: mã, tên, phòng ban, mô tả, tiến độ theo nhóm trạng thái, hạn, thành viên, vai trò của
// mình) + lọc theo trạng thái dự án + hộp tạo dự án mới.
import 'package:flutter/material.dart';

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
            : LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 6, wide ? 24 : 14, 90),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 14, mainAxisExtent: cols == 1 ? 150 : 196),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ProjectCard(project: list[i], store: widget.store, compact: cols == 1, onTap: () => widget.onOpen(list[i])),
                );
              }),
      ),
    ]);
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, required this.store, required this.onTap, this.compact = false});
  final TwProject project;
  final TwStore store;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final p = project;
    final sc = hexColor(kProjectStatusColors[p.status]);
    final meta = TextStyle(fontSize: 12, color: look.sub);
    return Material(
      key: ValueKey('project-${p.key}'),
      color: look.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: look.divider)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ProjectBadge(p, size: compact ? 30 : 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  if (p.deptNames.isNotEmpty) Text(p.deptNames.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                ]),
              ),
              if (compact) TwAvatars(p.memberPreview, size: 22, max: 3),
              IconButton(
                tooltip: p.starred ? 'Bỏ ghim sao' : 'Ghim sao',
                visualDensity: VisualDensity.compact,
                icon: Icon(p.starred ? Icons.star_rounded : Icons.star_outline_rounded, color: p.starred ? const Color(0xFFE8B10C) : look.sub),
                onPressed: () => store.star(p),
              ),
            ]),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text(blocksText(p.description).replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: look.sub, height: 1.45)),
            ],
            const Spacer(),
            CategoryBar(p.counts),
            const SizedBox(height: 8),
            Row(children: [
              TwChip(kProjectStatusNames[p.status]!, color: sc),
              const SizedBox(width: 8),
              Text('${p.doneCount}/${p.total} xong', style: meta),
              const Spacer(),
              if (p.due != null) ...[Icon(Icons.event_outlined, size: 15, color: look.sub), const SizedBox(width: 3), Text(dLong(p.due!), style: meta)],
            ]),
            if (!compact) ...[
              const SizedBox(height: 8),
              Row(children: [TwAvatars(p.memberPreview, size: 26), const Spacer(), Text(kRoleNames[p.myRole] ?? '', style: meta)]),
            ],
          ]),
        ),
      ),
    );
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
