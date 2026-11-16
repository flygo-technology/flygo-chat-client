import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../bubble_picker.dart';
import '../chat_themes.dart';
import '../common.dart' show pickFilesOrReport;
import '../theme.dart';
import 'chat_wallpaper.dart';
import 'season.dart';
import 'season_state.dart';

/// "Giao diện chat" của một chat: tab Màu chat (mọi người trong chat), Bong bóng (tin mình gửi, ai cũng thấy),
/// Hình nền (chỉ mình thấy; chỉ có khi được dùng app Giao diện).
Future<void> openChatAppearance(BuildContext context, MmChannel ch) =>
    Navigator.of(context).push(AppPageRoute(builder: (_) => ChatAppearancePage(channelId: ch.id)));

class ChatAppearancePage extends StatelessWidget {
  final String channelId;
  const ChatAppearancePage({super.key, required this.channelId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final ch = app.channels[channelId];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wall = SeasonState.instance.available;
    Widget note(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(t, style: TextStyle(fontSize: 13, color: pal.sub)),
        );
    return DefaultTabController(
      length: wall ? 3 : 2,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          title: Text(tr('Giao diện chat'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
          bottom: TabBar(tabs: [
            Tab(text: tr('Màu chat')),
            Tab(text: tr('Bong bóng')),
            if (wall) Tab(text: tr('Hình nền')),
          ]),
        ),
        body: TabBarView(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            note(tr('Đổi cho mọi người trong cuộc trò chuyện này. Mỗi giao diện tự đổi theo chế độ ngày / đêm của máy.')),
            Expanded(
              child: ChatThemeGrid(
                current: ch?.themeId,
                onPick: (id) => app.setChatTheme(channelId, id.isEmpty ? null : id),
              ),
            ),
          ]),
          BubblePickerBody(
            current: app.bubbleFor(channelId),
            allowInherit: true,
            inherited: app.bubbleDefault,
            defaultFill: chatThemeById(ch?.themeId)?.colors(dark).outBubble ?? pal.outBubble,
            onChanged: (c) => app.setBubble(channelId, c),
          ),
          if (wall) WallpaperPickerBody(prefKey: channelId),
        ]),
      ),
    );
  }
}

/// Chọn hình nền: [prefKey] = id kênh (có "Dùng mặc định") hoặc [SeasonState.kDefaultKey] (mặc định của mình).
class WallpaperPickerBody extends StatelessWidget {
  final String prefKey;
  /// Thêm các công tắc chung (Hiệu ứng động, dây đèn) ở cuối.
  final bool switches;
  const WallpaperPickerBody({super.key, required this.prefKey, this.switches = true});

  bool get _perChat => prefKey != SeasonState.kDefaultKey;

  static const _plain = ['E8EEF4', 'F3EADB', 'DCEDC8', 'FCE4EC', 'E1F5FE', '1F2933', '0B1A33', '2E1A1A', '1B2E24', '000000'];

  Future<void> _pickPlain(BuildContext context, SeasonState s) async {
    final pal = Pal.of(context);
    final hex = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final h in _plain)
            GestureDetector(
              onTap: () => Navigator.pop(ctx, h),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: Color(0xFF000000 | int.parse(h, radix: 16)), borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
              ),
            ),
        ]),
      ),
    );
    if (hex != null) await s.setWallpaper(prefKey, 'plain:$hex');
  }

  Future<void> _pickPhoto(BuildContext context, SeasonState s) async {
    final r = await pickFilesOrReport(context, type: FileType.image);
    final src = r.firstOrNull?.path;
    if (src == null) return;
    final f = await SeasonState.photoFile(prefKey);
    await File(src).copy(f.path);
    imageCache.evict(FileImage(f));
    await s.setWallpaper(prefKey, 'photo');
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final pal = Pal.of(context);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final cur = _perChat ? s.wallpaperOf(prefKey) : (s.wallpaperDefault ?? 'season');
        Widget tile(String? id, Widget art, String name, {bool soon = false, VoidCallback? onTap}) {
          final on = !soon && id != null && (cur == id || (id == 'plain' && (cur?.startsWith('plain:') ?? false)));
          return SizedBox(
            width: 88,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: soon ? null : onTap ?? () => s.setWallpaper(prefKey, id),
              child: Column(children: [
                Container(
                  width: 80,
                  height: 112,
                  padding: EdgeInsets.all(on ? 3 : 1),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? pal.accent : pal.divider, width: on ? 3 : 1)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(fit: StackFit.expand, children: [
                      art,
                      if (soon)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black.withValues(alpha: .5),
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            alignment: Alignment.center,
                            child: Text(tr('Sắp có'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                      if (on) const Positioned(right: 6, bottom: 6, child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 22)),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(name, maxLines: 2, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.2, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: pal.text)),
              ]),
            ),
          );
        }

        Widget section(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: pal.text)),
            );
        Widget wrap(List<Widget> c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Wrap(spacing: 4, runSpacing: 12, children: c));
        final plainCur = cur != null && cur.startsWith('plain:') ? Color(0xFF000000 | (int.tryParse(cur.substring(6), radix: 16) ?? 0xE8EEF4)) : null;
        return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
                _perChat
                    ? tr('Chỉ mình thấy, riêng chat này. Màu bong bóng và chữ giữ nguyên.')
                    : tr('Mặc định cho mọi chat của mình. Chat nào chọn riêng thì giữ hình nền riêng.'),
                style: TextStyle(fontSize: 13, color: pal.sub)),
          ),
          if (_perChat && cur != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                Icon(Icons.push_pin_outlined, size: 18, color: pal.sub),
                const SizedBox(width: 6),
                Expanded(child: Text(tr('Chat này đang dùng hình nền riêng'), style: TextStyle(fontSize: 13.5, color: pal.text))),
                OutlinedButton(onPressed: () => s.setWallpaper(prefKey, null), child: Text(tr('Dùng mặc định'))),
              ]),
            ),
          section(tr('Giáng sinh')),
          wrap([
            for (final w in wallpapers) tile(w.id, WallpaperView(wallpaper: w, frozenT: 2.4), w.name),
            tile(null, Container(color: const Color(0xFFB71C1C), child: const Center(child: Icon(Icons.local_florist_rounded, color: Color(0xFFFFD54F), size: 30))), tr('Tết'), soon: true),
            tile(null, Container(color: const Color(0xFF283593), child: const Center(child: Icon(Icons.nightlight_round, color: Color(0xFFFFE082), size: 30))), tr('Trung thu'), soon: true),
          ]),
          section(tr('Cơ bản')),
          wrap([
            tile('season', Row(children: [
              Expanded(child: WallpaperView(wallpaper: wallpaperById('demnoel')!, frozenT: 2)),
              Expanded(child: WallpaperView(wallpaper: wallpaperById('tuyettrang')!, frozenT: 2)),
            ]), tr('Theo mùa lễ')),
            tile('none', Container(color: pal.chatBg, child: Center(child: Icon(Icons.chat_bubble_outline_rounded, color: pal.sub))), tr('Không')),
            tile('plain', Container(color: plainCur ?? (dark ? const Color(0xFF1F2933) : const Color(0xFFE8EEF4))), tr('Màu trơn'), onTap: () => _pickPlain(context, s)),
            tile('photo', cur == 'photo' ? ChatWallpaperArt(choice: WallpaperChoice.photo(prefKey)) : Container(color: pal.surface2, child: Icon(Icons.add_photo_alternate_outlined, color: pal.sub, size: 30)),
                tr('Ảnh của mình'), onTap: () => _pickPhoto(context, s)),
          ]),
          if (!_perChat || cur == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(tr('"Theo mùa lễ": Đêm Noel khi máy tối, Tuyết trắng khi máy sáng, trong mùa công ty bật; ngoài mùa thì không có hình nền.'),
                  style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ),
          if (switches) ...[
            Divider(color: pal.divider, height: 32),
            SwitchListTile(
              value: s.motion,
              onChanged: (v) => s.setMine('motion', v),
              title: Text(tr('Hiệu ứng động'), style: TextStyle(fontSize: 15, color: pal.text)),
              subtitle: Text(tr('Tuyết rơi, đèn nhấp nháy. Tự tắt khi máy bật giảm chuyển động.'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ),
            SwitchListTile(
              value: s.mine['lights'] != false,
              onChanged: (v) => s.setMine('lights', v),
              title: Text(tr('Dây đèn trên khung chat'), style: TextStyle(fontSize: 15, color: pal.text)),
              subtitle: Text(tr('Mọi chat, trong mùa Giáng sinh'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ),
          ],
        ]);
      },
    );
  }
}
