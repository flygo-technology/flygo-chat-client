import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../bubble_picker.dart';
import '../bubble_styles.dart';
import '../theme.dart';
import 'chat_appearance.dart';
import 'chat_wallpaper.dart';
import 'season.dart';
import 'season_state.dart';

/// Mở app Giao diện (màn hình native "appearance": mặc định của mình).
Future<void> openAppearance(BuildContext context) => Navigator.of(context).push(AppPageRoute(builder: (_) => const AppearancePage()));

/// Mở trang quản trị Giao diện (màn hình native "appearance-admin", mục Quản trị).
Future<void> openAppearanceAdmin(BuildContext context) =>
    Navigator.of(context).push(AppPageRoute(builder: (_) => const AppearanceAdminPage()));

Widget _group(BuildContext context, List<Widget> c, {String? title}) {
  final pal = Pal.of(context);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (title != null)
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 6, 16, 6),
        child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: .4, fontWeight: FontWeight.w700, color: pal.sub)),
      ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Material(color: pal.surface, borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias, child: Column(children: c)),
    ),
  ]);
}

Widget _sw(BuildContext context, IconData i, String title, String? sub, bool v, ValueChanged<bool>? onChanged) {
  final pal = Pal.of(context);
  return SwitchListTile(
    value: v,
    onChanged: onChanged,
    secondary: Icon(i, color: pal.accent),
    title: Text(title, style: TextStyle(fontSize: 15, color: pal.text)),
    subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12.5, color: pal.sub)),
  );
}

Widget _div(BuildContext context, [double indent = 56]) => Divider(height: 1, color: Pal.of(context).divider, indent: indent);

String _dm(String ymd) => ymd.length >= 10 ? '${ymd.substring(8, 10)}/${ymd.substring(5, 7)}' : ymd;

/// App "Giao diện" (Cá nhân): bong bóng + hình nền mặc định cho mọi chat, tuỳ chọn mùa lễ của mình.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = SeasonState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final pal = Pal.of(context);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final bubble = app.bubbleDefault;
        final wp = s.resolveWallpaper('_preview_', dark);
        final active = s.activeSeason();
        final win = active == null ? null : s.windowOf(active);
        final seasonName = {for (final x in seasons) x.id: x.name}[active];
        final inPal = wp == null ? pal : (wp.dark ? Pal.dark : Pal.light);
        return Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, title: Text(tr('Giao diện'))),
          body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(tr('Mặc định cho mọi chat của mình. Chat nào đổi riêng (Giao diện chat) thì giữ kiểu riêng, bấm "Dùng mặc định" ở chat đó để quay về.'),
                  style: TextStyle(fontSize: 13, color: pal.sub, height: 1.35)),
            ),
            // Xem trước.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 170,
                  child: Stack(children: [
                    Positioned.fill(child: wp == null ? DoodleBackground(child: const SizedBox.expand()) : ChatWallpaperArt(choice: wp, motion: s.motion)),
                    if (s.on('lights') && active == 'giangsinh') Positioned(left: 0, right: 0, top: 0, child: LightString(motion: s.motion)),
                    Positioned(
                      left: 12,
                      top: 48,
                      child: StyledBubble(style: null, fill: inPal.inBubble, child: Text(tr('Chiều nay liên hoan nhé'), style: TextStyle(fontSize: 15, color: inPal.text))),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 16,
                      child: StyledBubble(
                        style: bubble?.def,
                        fill: bubble?.style.isNotEmpty == true ? bubble!.fill : pal.outBubble,
                        child: Text(tr('Ok, em đặt bánh rồi'),
                            style: TextStyle(fontSize: 15, color: bubble?.style.isNotEmpty == true ? bubbleTextOn(bubble!.fill) : Colors.white)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            _group(context, title: tr('Bong bóng của mình'), [
              ListTile(
                leading: Icon(Icons.chat_bubble_outline_rounded, color: pal.accent),
                title: Text(tr('Kiểu bong bóng'), style: TextStyle(fontSize: 15, color: pal.text)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(bubble?.def?.name ?? tr('Mặc định'), style: TextStyle(fontSize: 14, color: pal.sub)),
                  Icon(Icons.chevron_right_rounded, color: pal.sub),
                ]),
                onTap: () async {
                  final c = await Navigator.of(context).push<BubbleChoice>(AppPageRoute(
                    builder: (_) => BubblePickerPage(current: app.bubbleDefault, defaultFill: Pal.of(context).outBubble),
                  ));
                  if (c != null) await app.setBubble(kBubbleDefaultKey, c);
                },
              ),
            ]),
            _group(context, title: tr('Hình nền mặc định'), [
              ListTile(
                leading: Icon(Icons.wallpaper_rounded, color: pal.accent),
                title: Text(tr('Hình nền'), style: TextStyle(fontSize: 15, color: pal.text)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_wallpaperName(s.wallpaperDefault ?? 'season'), style: TextStyle(fontSize: 14, color: pal.sub)),
                  Icon(Icons.chevron_right_rounded, color: pal.sub),
                ]),
                onTap: () => Navigator.of(context).push(AppPageRoute(
                  builder: (ctx) => Scaffold(
                    backgroundColor: Pal.of(ctx).bg,
                    appBar: AppBar(backgroundColor: Pal.of(ctx).bg, surfaceTintColor: Colors.transparent, title: Text(tr('Hình nền mặc định'))),
                    body: const WallpaperPickerBody(prefKey: SeasonState.kDefaultKey, switches: false),
                  ),
                )),
              ),
            ]),
            _group(context, title: tr('Mùa lễ hội'), [
              _sw(context, Icons.celebration_outlined, tr('Dùng giao diện mùa lễ'),
                  active == null ? tr('Hiện không có mùa lễ nào công ty bật') : tr('Đang có: {0} ({1} – {2})', [seasonName ?? active, _dm(win!.start), _dm(win.end)]),
                  s.mine['off'] != true, (v) => s.setMine('off', !v)),
              _div(context),
              _sw(context, Icons.light_rounded, tr('Dây đèn trên khung chat'), null, s.mine['lights'] != false, (v) => s.setMine('lights', v)),
              _div(context),
              _sw(context, Icons.face_retouching_natural_rounded, tr('Hiện mũ Noel của mọi người'), tr('Chỉ trên máy của mình'), s.mine['hats'] != false,
                  (v) => s.setMine('hats', v)),
              _div(context),
              _sw(context, Icons.person_outline_rounded, tr('Đội mũ cho ảnh của mình'), tr('Tắt thì mọi người thấy ảnh mình không có mũ'), s.myHat,
                  (v) => s.setMyHat(v)),
              _div(context),
              _sw(context, Icons.auto_awesome_rounded, tr('Hiệu ứng khi có lời chúc'), tr('"Giáng sinh vui vẻ", "Merry Christmas", "Noel"'),
                  s.mine['effect'] != false, (v) => s.setMine('effect', v)),
              _div(context),
              _sw(context, Icons.home_outlined, tr('Banner ở Trang chủ'), tr('Đếm ngược đến 24/12'), s.mine['banner'] != false, (v) => s.setMine('banner', v)),
            ]),
            _group(context, title: tr('Chuyển động'), [
              _sw(context, Icons.animation_rounded, tr('Hiệu ứng động'), tr('Tuyết rơi, đèn nhấp nháy. Tự tắt khi máy bật giảm chuyển động.'), s.motion,
                  (v) => s.setMine('motion', v)),
            ]),
          ]),
        );
      },
    );
  }
}

String _wallpaperName(String id) => switch (id) {
      'season' => tr('Theo mùa lễ'),
      'none' => tr('Không'),
      'photo' => tr('Ảnh của mình'),
      _ when id.startsWith('plain:') => tr('Màu trơn'),
      _ => wallpaperById(id)?.name ?? id,
    };

/// Trang quản trị Giao diện: mùa lễ của công ty, phần bật sẵn, hiệu ứng lời chúc, mặc định của công ty.
class AppearanceAdminPage extends StatefulWidget {
  const AppearanceAdminPage({super.key});
  @override
  State<AppearanceAdminPage> createState() => _AppearanceAdminPageState();
}

class _AppearanceAdminPageState extends State<AppearanceAdminPage> {
  final s = SeasonState.instance;
  Map<String, dynamic>? _cfg;
  bool _dirty = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await s.refresh();
      if (!mounted) return;
      setState(() {
        _cfg = jsonDecode(jsonEncode(s.cfg)) as Map<String, dynamic>;
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await s.saveOrg(_cfg!);
      if (!mounted) return;
      setState(() => _dirty = false);
      messenger.showSnackBar(toast(Text(tr('Đã lưu'))));
    } on SeasonException catch (e) {
      messenger.showSnackBar(toast(Text(e.message)));
      if (e.status == 409) await _load();
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _edit(VoidCallback fn) => setState(() {
        fn();
        _dirty = true;
      });

  Map<String, dynamic> _season(String id) => ((_cfg!['seasons'] as Map)[id] as Map).cast<String, dynamic>();

  Future<void> _editFixed(String id) async {
    final se = _season(id);
    final y = DateTime.now().year;
    DateTime parse(String md) => DateTime(y, int.parse(md.substring(0, 2)), int.parse(md.substring(3, 5)));
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(y, 1, 1),
      lastDate: DateTime(y + 1, 12, 31),
      initialDateRange: DateTimeRange(start: parse(se['from']), end: parse(se['to']).isBefore(parse(se['from'])) ? DateTime(y + 1, parse(se['to']).month, parse(se['to']).day) : parse(se['to'])),
    );
    if (r == null) return;
    String md(DateTime d) => '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    _edit(() {
      se['from'] = md(r.start);
      se['to'] = md(r.end);
    });
  }

  Future<void> _editLunar(String id) async {
    final se = _season(id);
    var before = (se['before'] as num?)?.toInt() ?? 7, after = (se['after'] as num?)?.toInt() ?? 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Widget stepper(String label, int v, ValueChanged<int> on) => Row(children: [
              Expanded(child: Text(label)),
              IconButton(onPressed: v > 0 ? () => set(() => on(v - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(width: 28, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(onPressed: v < 45 ? () => set(() => on(v + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
            ]);
        return AlertDialog(
          title: Text(tr('Khung ngày')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            stepper(tr('Số ngày trước'), before, (x) => before = x),
            stepper(tr('Số ngày sau'), after, (x) => after = x),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xong'))),
          ],
        );
      }),
    );
    if (ok == true) {
      _edit(() {
        se['before'] = before;
        se['after'] = after;
      });
    }
  }

  Future<void> _addKeyword() async {
    final ctl = TextEditingController();
    final k = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thêm từ khoá')),
        content: TextField(controller: ctl, autofocus: true, maxLength: 60, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('Thêm'))),
        ],
      ),
    );
    if (k == null || k.trim().isEmpty) return;
    _edit(() => ((_cfg!['effect'] as Map)['keywords'] as List).add({'k': k.trim(), 'fx': 'mix'}));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cfg = _cfg;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Giao diện')),
        actions: [
          if (cfg != null && s.canAdmin)
            TextButton(
              onPressed: _dirty && !_saving ? _save : null,
              child: Text(tr('Lưu'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: cfg == null
          ? Center(
              child: _error != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: TextStyle(color: pal.sub)),
                      TextButton(onPressed: _load, child: Text(tr('Thử lại'))),
                    ])
                  : CircularProgressIndicator(color: pal.accent),
            )
          : _body(context, cfg),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> cfg) {
    final pal = Pal.of(context);
    final admin = s.canAdmin;
    const look = {
      'giangsinh': (Color(0xFFC62828), Icons.park_rounded),
      'tet': (Color(0xFFD84315), Icons.local_florist_rounded),
      'trungthu': (Color(0xFF3949AB), Icons.nightlight_round),
    };
    final featureNames = {
      'wallpaper': tr('Hình nền theo mùa'),
      'lights': tr('Dây đèn trên khung chat'),
      'hats': tr('Mũ Noel trên ảnh đại diện (chỉ tháng 12)'),
      'effect': tr('Hiệu ứng khi có lời chúc'),
      'banner': tr('Banner + đếm ngược ở Trang chủ'),
    };
    Widget seasonCard(Season def) {
      final se = _season(def.id);
      final on = se['enabled'] == true;
      final w = s.windowOf(def.id);
      final fixed = se['from'] != null;
      final range = fixed
          ? '${(se['from'] as String).substring(3)}/${(se['from'] as String).substring(0, 2)} – ${(se['to'] as String).substring(3)}/${(se['to'] as String).substring(0, 2)}'
          : w == null
              ? tr('{0} ngày trước – {1} ngày sau', [se['before'], se['after']])
              : '${_dm(w.start)} – ${_dm(w.end)} (${tr('âm lịch')})';
      final (color, icon) = look[def.id] ?? (pal.accent, Icons.celebration_rounded);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Material(
          color: pal.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? color.withValues(alpha: .6) : pal.divider)),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(def.name, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: pal.text)),
                      InkWell(
                        onTap: admin ? () => fixed ? _editFixed(def.id) : _editLunar(def.id) : null,
                        child: Row(children: [
                          Flexible(child: Text(range, style: TextStyle(fontSize: 13, color: pal.sub))),
                          if (admin) ...[const SizedBox(width: 4), Icon(Icons.edit_calendar_outlined, size: 15, color: pal.accent)],
                        ]),
                      ),
                      if (def.id != 'giangsinh') Text(tr('Sắp có'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.sub)),
                    ]),
                  ),
                  // Tết / Trung thu chưa có hình nền, banner riêng: chưa cho bật (tắt được nếu lỡ bật).
                  Switch(value: on, onChanged: admin && (def.id == 'giangsinh' || on) ? (v) => _edit(() => se['enabled'] = v) : null),
                ]),
              ),
              if (on) ...[
                Divider(height: 1, color: pal.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr('Bật sẵn cho mọi người'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.sub))),
                ),
                for (final f in kSeasonFeatures)
                  if (def.id == 'giangsinh' || f == 'effect' || f == 'banner')
                    CheckboxListTile(
                      dense: true,
                      value: (se['features'] as Map?)?[f] != false,
                      onChanged: admin ? (v) => _edit(() => (se['features'] as Map)[f] = v == true) : null,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(featureNames[f]!, style: TextStyle(fontSize: 14.5, color: pal.text)),
                    ),
                const SizedBox(height: 4),
              ],
            ]),
          ),
        ),
      );
    }

    final eff = (cfg['effect'] as Map).cast<String, dynamic>();
    final kws = (eff['keywords'] as List);
    final defaults = (cfg['defaults'] as Map).cast<String, dynamic>();
    const fxNames = {'snow': 'Tuyết', 'gifts': 'Quà', 'mix': 'Trộn'};
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
            tr('Bật một lần, áp dụng cho cả công ty: đến ngày tự bật, hết ngày tự tắt, năm sau lặp lại. Mỗi người vẫn tự tắt được trong app Giao diện của mình.'),
            style: TextStyle(fontSize: 13, color: pal.sub, height: 1.35)),
      ),
      for (final def in seasons) seasonCard(def),
      _group(context, title: tr('Hiệu ứng lời chúc'), [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'mix', label: Text(tr('Trộn tuyết + quà'))),
              ButtonSegment(value: 'keyword', label: Text(tr('Theo từ khoá'))),
            ],
            selected: {eff['mode'] == 'keyword' ? 'keyword' : 'mix'},
            onSelectionChanged: admin ? (v) => _edit(() => eff['mode'] = v.first) : null,
          ),
        ),
        for (final (i, k) in kws.indexed) ...[
          ListTile(
            dense: true,
            title: Text('"${(k as Map)['k']}"', style: TextStyle(fontSize: 14.5, color: pal.text)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (eff['mode'] == 'keyword')
                DropdownButton<String>(
                  value: fxNames.containsKey(k['fx']) ? k['fx'] as String : 'mix',
                  underline: const SizedBox.shrink(),
                  items: [for (final e in fxNames.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
                  onChanged: admin ? (v) => _edit(() => k['fx'] = v) : null,
                ),
              if (admin) IconButton(icon: Icon(Icons.close_rounded, size: 18, color: pal.sub), onPressed: () => _edit(() => kws.removeAt(i))),
            ]),
          ),
          _div(context, 16),
        ],
        if (admin)
          ListTile(
            dense: true,
            leading: Icon(Icons.add_rounded, color: pal.accent),
            title: Text(tr('Thêm từ khoá'), style: TextStyle(fontSize: 14.5, color: pal.accent, fontWeight: FontWeight.w600)),
            onTap: _addKeyword,
          ),
      ]),
      _group(context, title: tr('Mặc định của công ty (không bắt buộc)'), [
        ListTile(
          title: Text(tr('Bong bóng'), style: TextStyle(fontSize: 15, color: pal.text)),
          subtitle: Text(tr('Người chưa tự chọn sẽ dùng kiểu này'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(bubbleStyleById('${(defaults['bubble'] as Map?)?['s'] ?? ''}')?.name ?? tr('Của app'), style: TextStyle(color: pal.sub)),
            Icon(Icons.chevron_right_rounded, color: pal.sub),
          ]),
          onTap: !admin
              ? null
              : () async {
                  final b = defaults['bubble'] as Map?;
                  final cur = b == null ? null : BubbleChoice.fromJson(b);
                  final c = await Navigator.of(context).push<BubbleChoice>(AppPageRoute(
                    builder: (_) => BubblePickerPage(current: cur, defaultFill: Pal.of(context).outBubble),
                  ));
                  if (c != null) _edit(() => defaults['bubble'] = c.style.isEmpty ? null : c.toJson());
                },
        ),
        _div(context, 16),
        ListTile(
          title: Text(tr('Hình nền'), style: TextStyle(fontSize: 15, color: pal.text)),
          trailing: DropdownButton<String>(
            value: (defaults['wallpaper'] as String?) ?? 'season',
            underline: const SizedBox.shrink(),
            items: [
              for (final id in ['season', 'none', for (final w in wallpapers) w.id]) DropdownMenuItem(value: id, child: Text(_wallpaperName(id))),
            ],
            onChanged: admin ? (v) => _edit(() => defaults['wallpaper'] = v == 'season' ? null : v) : null,
          ),
        ),
      ]),
    ]);
  }
}
