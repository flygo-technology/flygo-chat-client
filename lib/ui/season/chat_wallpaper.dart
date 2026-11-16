import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'season.dart';
import 'season_state.dart';

/// Nền vùng chat: hình nền mình chọn (app Giao diện / Giao diện chat) nếu có, không thì nền hoạ tiết sẵn có.
/// Hình nền khác chế độ sáng / tối của máy thì vùng chat theo chế độ
/// của hình nền để chữ luôn đọc được.
class SeasonChatBackground extends StatelessWidget {
  final String channelId;
  /// Chat kiểu trợ lý (Claude / ChatGPT): giữ nền của hãng, không hình nền, không dây đèn.
  final bool off;
  final Color? color;
  final Widget child;
  const SeasonChatBackground({super.key, required this.channelId, this.off = false, this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    if (off) return DoodleBackground(color: color, child: child);
    final season = SeasonState.instance;
    return ListenableBuilder(
      listenable: season,
      builder: (context, _) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final w = season.resolveWallpaper(channelId, dark);
        Widget body = child;
        if (w == null) return DoodleBackground(color: color, child: body);
        if (w.dark != dark) body = Theme(data: buildTheme(w.dark ? Brightness.dark : Brightness.light), child: body);
        return Stack(children: [
          Positioned.fill(child: ChatWallpaperArt(choice: w, motion: season.motion)),
          Positioned.fill(child: body),
        ]);
      },
    );
  }
}

/// Vẽ một hình nền đã chọn (dùng cả ở ô xem trước).
class ChatWallpaperArt extends StatelessWidget {
  final WallpaperChoice choice;
  final bool motion;
  final double? frozenT;
  const ChatWallpaperArt({super.key, required this.choice, this.motion = true, this.frozenT});

  @override
  Widget build(BuildContext context) {
    final art = choice.art;
    if (art != null) return WallpaperView(wallpaper: art, motion: motion, frozenT: frozenT);
    if (choice.color != null) return ColoredBox(color: choice.color!);
    return FutureBuilder<File>(
      future: SeasonState.photoFile(choice.photoKey!),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null || !f.existsSync()) return ColoredBox(color: Pal.of(context).chatBg);
        return Stack(fit: StackFit.expand, children: [
          Image.file(f, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: Pal.of(context).chatBg)),
          // Lớp tối mờ cho chữ hệ thống (ngày, "đang nhập…") đọc được trên mọi ảnh.
          const ColoredBox(color: Color(0x59000000)),
        ]);
      },
    );
  }
}

/// Dây đèn ở mép trên vùng tin nhắn (mùa Giáng sinh, công ty bật, mình không tắt).
class SeasonLights extends StatelessWidget {
  const SeasonLights({super.key});
  @override
  Widget build(BuildContext context) {
    final s = SeasonState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) =>
          s.on('lights') && s.activeSeason() == 'giangsinh' ? LightString(motion: s.motion) : const SizedBox.shrink(),
    );
  }
}
