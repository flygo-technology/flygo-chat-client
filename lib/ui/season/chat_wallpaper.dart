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
        // Hình nền / màu trơn tự theo chế độ máy; riêng ảnh tự chọn (có lớp tối mờ) thì vùng chat dùng bảng màu tối.
        if (w.photoKey != null && !dark) body = Theme(data: buildTheme(Brightness.dark), child: body);
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
    if (choice.color != null) return ColoredBox(color: plainWallpaperColor(choice.color!, Theme.of(context).brightness == Brightness.dark));
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

/// Dải cây thông ở mép trên vùng tin nhắn (mùa Giáng sinh, công ty bật, mình không tắt).
class SeasonLights extends StatelessWidget {
  const SeasonLights({super.key});

  /// Dải đang hiện (chat chừa thêm khoảng trên cho tin đầu).
  static bool get visible => SeasonState.instance.on('lights') && SeasonState.instance.activeSeason() == 'giangsinh';
  @override
  Widget build(BuildContext context) {
    final s = SeasonState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) =>
          visible ? Garland(backing: Color.alphaBlend(Pal.of(context).glass, Pal.of(context).bg)) : const SizedBox.shrink(),
    );
  }
}

/// Nền Trang chủ ("Màu nền"): vẽ phía sau toàn bộ trang danh sách ứng dụng (điện thoại + máy tính).
class HomeBackground extends StatelessWidget {
  final Widget child;
  /// Chỉ vẽ khi người dùng đã tự chọn trong "Màu nền" (trang Mở ứng dụng trên máy tính: mặc định để nền thường).
  final bool explicitOnly;
  const HomeBackground({super.key, required this.child, this.explicitOnly = false});

  /// Trang có đang vẽ nền không (để chữ trên trang thêm bóng mờ).
  static bool showing({bool explicitOnly = false}) {
    final s = SeasonState.instance;
    if (explicitOnly && s.mine['home_bg'] == null) return false;
    return s.homeChoice() != null;
  }
  @override
  Widget build(BuildContext context) {
    final s = SeasonState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final w = showing(explicitOnly: explicitOnly) ? s.homeChoice() : null;
        if (w == null) return child;
        return Stack(fit: StackFit.expand, children: [
          ChatWallpaperArt(choice: w, motion: false),
          child,
        ]);
      },
    );
  }
}
