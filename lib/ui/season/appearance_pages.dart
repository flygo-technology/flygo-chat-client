import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../bubble_picker.dart';
import '../bubble_styles.dart';
import '../theme.dart';
import 'appearance_widgets.dart';
import 'season.dart';
import 'season_state.dart';
import '../app_shell.dart';

/// Mở app Giao diện (màn hình native "appearance": mặc định của mình).
Future<void> openAppearance(BuildContext context) =>
    AppHost.of(context).open(key: 'appearance', title: tr('Giao diện'), builder: (_) => const AppearancePage());

/// Mở trang quản trị Giao diện (màn hình native "appearance-admin", mục Quản trị).
Future<void> openAppearanceAdmin(BuildContext context) =>
    AppHost.of(context).open(key: 'admin:appearance', title: tr('Quản trị Giao diện'), builder: (_) => const AppearanceAdminPage());

Widget _div(BuildContext context, [double indent = 56]) => Divider(height: 1, color: Pal.of(context).divider, indent: indent);

String _dm(String ymd) => ymd.length >= 10 ? '${ymd.substring(8, 10)}/${ymd.substring(5, 7)}' : ymd;

/// "Giao diện" của mình (Cá nhân › Giao diện, Cài đặt › Giao diện): luôn hiện lựa chọn của mình; chưa đổi gì thì theo công ty (mọi thứ theo
/// Quản trị › Giao diện, đồng bộ mọi máy) hoặc "Cài riêng" (nền Trang chủ, mùa lễ, chat của riêng mình).
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
        final custom = s.custom;
        Widget sw(String title, String? sub, bool v, ValueChanged<bool> on) => SwitchListTile(
              value: v,
              onChanged: on,
              dense: true,
              title: Text(title, style: TextStyle(fontSize: 14.5, color: pal.text)),
              subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: pal.sub)),
            );
        // Đổi bất kỳ mục nào là chuyển sang cài riêng (Sếp, 2026-11-17: trang này chỉ là của riêng mình).
        Future<void> mine(String k, Object? v) async {
          if (!custom) await s.setMine('mode', 'custom');
          await s.setMine(k, v);
        }
        final def = app.bubbleDefault;
        final seasonPick = s.seasonBubble(app.me?.id ?? '');
        final sections = <Widget>[
          SectionCard(title: tr('Nền Trang chủ'), icon: Icons.space_dashboard_outlined, children: [
            // Một lựa chọn chung cho điện thoại và máy tính (Sếp, 2026-11-17).
            BackgroundPicker(
                value: s.homeBgId(desktop: false),
                arts: homeBackgroundIds,
                onChanged: (v) async {
                  await mine('home_bg_phone', v);
                  await mine('home_bg_desktop', v);
                }),
          ]),
          SectionCard(title: tr('Chat của tôi'), icon: Icons.chat_bubble_outline_rounded, children: [
            subHead(context, tr('Hình nền chat')),
            BackgroundPicker(
              value: s.wallpaperDefault ?? 'season',
              arts: [for (final w in wallpapers) w.id],
              onChanged: (v) async {
                if (!custom) await s.setMine('mode', 'custom');
                await s.setWallpaper(SeasonState.kDefaultKey, v == 'season' ? null : v);
              },
            ),
            subHead(context, tr('Bong bóng tin của tôi')),
            ListTile(
              dense: true,
              title: Text(def == null ? tr('Theo công ty / mùa lễ') : def.def?.name ?? tr('Bong bóng thường'),
                  style: TextStyle(fontSize: 14.5, color: pal.text)),
              trailing: Icon(Icons.chevron_right_rounded, color: pal.sub),
              onTap: () async {
                final c = await Navigator.of(context).push<BubbleChoice>(AppPageRoute(
                  builder: (_) => BubblePickerPage(current: def, allowInherit: true, inherited: seasonPick, defaultFill: Pal.of(context).outBubble),
                ));
                if (c == null) return;
                if (!custom) await s.setMine('mode', 'custom');
                await app.setBubble(kBubbleDefaultKey, c);
              },
            ),
          ]),
          SectionCard(title: tr('Của tôi'), icon: Icons.person_outline_rounded, children: [
            sw(tr('Đội mũ cho ảnh của mình'), tr('Tắt thì mọi người thấy ảnh mình không mũ'), s.myHat, (v) => s.setMyHat(v)),
            sw(tr('Hiệu ứng động'), tr('Tự tắt khi máy bật giảm chuyển động'), s.motion, (v) => mine('motion', v)),
          ]),
        ];
        return Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, title: Text(tr('Giao diện của tôi'))),
          body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Row(children: [
                    Icon(custom ? Icons.person_outline_rounded : Icons.business_rounded, size: 18, color: pal.sub),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          custom
                              ? tr('Đang dùng giao diện riêng của bạn, áp dụng trên mọi máy của bạn.')
                              : tr('Đang theo giao diện chung của công ty. Đổi bất kỳ mục nào bên dưới để cài riêng cho bạn.'),
                          style: TextStyle(fontSize: 13, color: pal.sub, height: 1.35)),
                    ),
                    if (custom)
                      TextButton.icon(
                        onPressed: () => s.setMine('mode', null),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: Text(tr('Về giao diện công ty')),
                      ),
                  ]),
                ),
              ),
            ),
            SectionGrid(children: sections),
          ]),
        );
      },
    );
  }
}


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

  /// Bong bóng + hình nền mùa lễ tự áp cho mọi người (người chưa tự chọn riêng).
  List<Widget> _autoApply(BuildContext context, String id, Map<String, dynamic> se, bool admin) {
    final pal = Pal.of(context);
    final group = [for (final st in bubbleStyles) if (st.group == id) st];
    final art = wallpaperById(id);
    if (group.isEmpty && art == null) return const [];
    final b = ((se['bubble'] as Map?) ?? {'mode': 'random'}).cast<String, dynamic>();
    final mode = '${b['mode'] ?? 'random'}';
    final wp = '${se['wallpaper'] ?? 'auto'}' == 'off' ? 'off' : id;
    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.sub))),
        );
    Widget mini(BubbleStyle st, {bool sel = false, VoidCallback? onTap}) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 70,
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            decoration: sel ? BoxDecoration(border: Border.all(color: pal.accent, width: 2), borderRadius: BorderRadius.circular(10)) : null,
            child: Column(children: [
              SizedBox(
                height: 44,
                child: Center(
                  child: StyledBubble(
                    style: st,
                    fill: st.color,
                    scale: .62,
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    child: Text('Aa', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: bubbleTextOn(st.color))),
                  ),
                ),
              ),
              Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: pal.sub)),
            ]),
          ),
        );
    return [
      if (group.isNotEmpty) ...[
        Divider(height: 1, color: pal.divider),
        head(tr('Bong bóng mùa lễ · tự áp cho mọi người')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'random', label: Text(tr('Ngẫu nhiên'))),
              ButtonSegment(value: 'one', label: Text(tr('Một kiểu'))),
              ButtonSegment(value: 'off', label: Text(tr('Không'))),
            ],
            selected: {mode},
            onSelectionChanged: !admin
                ? null
                : (v) => _edit(() => se['bubble'] = v.first == 'one' ? {'mode': 'one', 'style': b['style'] ?? group.first.id} : {'mode': v.first}),
          ),
        ),
        if (mode != 'off')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text(
                mode == 'random' ? tr('Mỗi người một kiểu cố định trong nhóm (theo tài khoản), giống nhau trên mọi máy.') : tr('Chọn kiểu dùng cho mọi người.'),
                style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ),
        if (mode != 'off')
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Wrap(spacing: 2, runSpacing: 2, children: [
              for (final st in group)
                mini(st,
                    sel: mode == 'one' && b['style'] == st.id,
                    onTap: !admin ? null : () => _edit(() => se['bubble'] = {'mode': 'one', 'style': st.id})),
            ]),
          ),
      ],
      if (art != null) ...[
        Divider(height: 1, color: pal.divider),
        head(tr('Hình nền mùa lễ · tự áp cho mọi người')),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(children: [
            for (final (v, name) in [(id, art.name), ('off', tr('Không'))])
              Expanded(
                child: InkWell(
                  onTap: !admin ? null : () => _edit(() => se['wallpaper'] = v),
                  child: Column(children: [
                    Container(
                      height: 86,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: EdgeInsets.all(wp == v ? 2.5 : 1),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: wp == v ? pal.accent : pal.divider, width: wp == v ? 2.5 : 1)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: v == 'off' ? Container(color: pal.chatBg) : WallpaperView(wallpaper: art, frozenT: 2),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(name, style: TextStyle(fontSize: 12.5, fontWeight: wp == v ? FontWeight.w700 : FontWeight.w500, color: pal.text)),
                  ]),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(tr('Hình nền tự đổi theo chế độ sáng / tối của máy.'), style: TextStyle(fontSize: 12, color: pal.sub)),
        ),
      ],
    ];
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
      'lights': tr('Dải cây thông trên khung chat'),
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
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: pal.surface2.withValues(alpha: .5),
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
                ..._autoApply(context, def.id, se, admin),
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
    final sections = <Widget>[
      SectionCard(
        title: tr('Nền Trang chủ'),
        icon: Icons.space_dashboard_outlined,
        subtitle: tr('Điện thoại và máy tính. Áp dụng cho mọi người chưa cài riêng.'),
        children: [
          // Một lựa chọn chung cho điện thoại và máy tính (Sếp, 2026-11-17).
          BackgroundPicker(
            value: (defaults['home_bg_phone'] as String?) ?? (defaults['home_bg'] as String?) ?? 'season',
            arts: homeBackgroundIds,
            onChanged: admin
                ? (v) => _edit(() {
                      defaults['home_bg_phone'] = v;
                      defaults['home_bg_desktop'] = v;
                    })
                : null,
          ),
        ],
      ),
      SectionCard(
        title: tr('Mùa lễ'),
        icon: Icons.celebration_outlined,
        subtitle: tr('Bật một lần: đến ngày tự bật, hết ngày tự tắt, năm sau lặp lại.'),
        children: [
          if (admin)
            SwitchListTile(
              value: s.preview != null,
              onChanged: (v) => s.setMine('preview', v ? 'giangsinh' : null),
              dense: true,
              secondary: Icon(Icons.visibility_outlined, color: pal.accent),
              title: Text(tr('Xem thử Giáng sinh'), style: TextStyle(fontSize: 14.5, color: pal.text)),
              subtitle: Text(tr('Chỉ mình thấy, bất kể ngày'), style: TextStyle(fontSize: 12, color: pal.sub)),
            ),
          const SizedBox(height: 6),
          for (final def in seasons) seasonCard(def),
        ],
      ),
      SectionCard(
        title: tr('Chat'),
        icon: Icons.chat_bubble_outline_rounded,
        children: [
          subHead(context, tr('Hình nền chat mặc định')),
          BackgroundPicker(
            value: (defaults['wallpaper'] as String?) ?? 'season',
            arts: [for (final w in wallpapers) w.id],
            onChanged: admin ? (v) => _edit(() => defaults['wallpaper'] = v == 'season' ? null : v) : null,
          ),
          subHead(context, tr('Bong bóng mặc định')),
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
          SwitchListTile(
            value: defaults['allow_chat_custom'] != false,
            onChanged: admin ? (v) => _edit(() => defaults['allow_chat_custom'] = v) : null,
            dense: true,
            title: Text(tr('Cho phép nhân viên tự đổi giao diện chat'), style: TextStyle(fontSize: 14.5, color: pal.text)),
            subtitle: Text(tr('Bong bóng, hình nền riêng từng chat'), style: TextStyle(fontSize: 12, color: pal.sub)),
          ),
        ],
      ),
      SectionCard(
        title: tr('Hiệu ứng lời chúc'),
        icon: Icons.auto_awesome_rounded,
        children: [
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
              ],
      ),
    ];
    return ListView(padding: const EdgeInsets.only(bottom: 30, top: 4), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(tr('Admin chỉnh ở đây là mọi máy của nhân viên tự cập nhật (trừ người chọn "Cài riêng" trong Giao diện của họ).'),
            style: TextStyle(fontSize: 13, color: pal.sub, height: 1.35)),
      ),
      SectionGrid(children: sections),
    ]);
  }
}
