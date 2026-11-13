import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'theme.dart';

/// Máy tính: kéo tệp / ảnh (từ Finder, Explorer, trình duyệt) thả vào khung chat là đính kèm vào ô soạn tin, như nút
/// đính kèm. Đang kéo thì hiện khung "Thả để đính kèm". Điện thoại: chỉ trả lại [child].
class FileDropZone extends StatefulWidget {
  final Widget child;

  /// Tệp vừa thả: (đường dẫn, tên).
  final void Function(List<(String, String)> files) onFiles;

  /// Kiểm thử: bật trên mọi nền tảng.
  final bool? enabled;
  const FileDropZone({super.key, required this.child, required this.onFiles, this.enabled});

  @override
  State<FileDropZone> createState() => FileDropZoneState();
}

class FileDropZoneState extends State<FileDropZone> {
  bool _dragging = false;

  bool get dragging => _dragging;

  /// Nhận tệp thả (dùng chung cho DropTarget và kiểm thử).
  void drop(List<(String, String)> files) {
    setState(() => _dragging = false);
    final ok = [for (final f in files) if (f.$1.isNotEmpty) f];
    if (ok.isNotEmpty) widget.onFiles(ok);
  }

  void hover(bool on) {
    if (on != _dragging) setState(() => _dragging = on);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled ?? (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    if (!on) return widget.child;
    final pal = Pal.of(context);
    return DropTarget(
      onDragEntered: (_) => hover(true),
      onDragExited: (_) => hover(false),
      onDragDone: (d) => drop([for (final f in d.files) (f.path, f.name)]),
      child: Stack(children: [
        widget.child,
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pal.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: pal.accent, width: 2.5),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.attach_file_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(tr('Thả để đính kèm'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
