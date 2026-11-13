import '../i18n/i18n.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Thay trình sửa ảnh trong kiểm thử (không dựng ProImageEditor).
@visibleForTesting
Future<String?> Function(BuildContext context, String path)? editImageOverride;

/// Mở trình sửa ảnh (vẽ có chọn màu, cắt, xoay). Trả về đường dẫn ảnh đã sửa,
/// hoặc null nếu người dùng hủy.
Future<String?> editImage(BuildContext context, String path) async {
  if (editImageOverride != null) return editImageOverride!(context, path);
  Uint8List? result;
  await Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => ProImageEditor.file(
      File(path),
      configs: ProImageEditorConfigs(
        designMode: ImageEditorDesignMode.cupertino,
        mainEditor: MainEditorConfigs(
          tools: const [SubEditorMode.paint, SubEditorMode.cropRotate],
          widgets: MainEditorWidgets(appBar: (editor, rebuild) => ReactiveAppbar(stream: rebuild, builder: (_) => EditorAppBar(editor: editor))),
        ),
        // Mặc định trình sửa thu ảnh về tối đa 2000px; giữ gần nguyên độ phân giải ảnh gốc.
        imageGeneration: const ImageGenerationConfigs(maxOutputSize: Size(8000, 8000), jpegQuality: 92),
        i18n: I18n(
          cancel: tr('Hủy'),
          undo: tr('Hoàn tác'),
          redo: tr('Làm lại'),
          done: tr('Xong'),
          remove: tr('Xóa'),
          doneLoadingMsg: tr('Đang lưu ảnh...'),
          paintEditor: I18nPaintEditor(
            bottomNavigationBarText: tr('Vẽ'),
            freestyle: tr('Vẽ tự do'),
            arrow: tr('Mũi tên'),
            line: tr('Đường thẳng'),
            rectangle: tr('Hình chữ nhật'),
            circle: tr('Hình tròn'),
            dashLine: tr('Nét đứt'),
            lineWidth: tr('Độ dày nét'),
            eraser: tr('Tẩy'),
            toggleFill: tr('Tô đặc'),
            changeOpacity: tr('Độ mờ'),
            undo: tr('Hoàn tác'),
            redo: tr('Làm lại'),
            done: tr('Xong'),
            back: tr('Quay lại'),
            smallScreenMoreTooltip: tr('Thêm'),
            moveAndZoom: tr('Phóng to'),
          ),
          cropRotateEditor: I18nCropRotateEditor(
            bottomNavigationBarText: tr('Cắt / Xoay'),
            rotate: tr('Xoay'),
            flip: tr('Lật'),
            ratio: tr('Tỉ lệ'),
            back: tr('Quay lại'),
            done: tr('Xong'),
            cancel: tr('Hủy'),
            undo: tr('Hoàn tác'),
            redo: tr('Làm lại'),
            reset: tr('Đặt lại'),
            smallScreenMoreTooltip: tr('Thêm'),
          ),
          various: I18nVarious(
            loadingDialogMsg: tr('Vui lòng chờ...'),
            closeEditorWarningTitle: tr('Bỏ các thay đổi?'),
            closeEditorWarningMessage: tr('Ảnh sẽ không được lưu.'),
            closeEditorWarningConfirmBtn: tr('Bỏ'),
            closeEditorWarningCancelBtn: tr('Tiếp tục sửa'),
          ),
        ),
      ),
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          result = bytes;
          Navigator.of(ctx).pop();
        },
      ),
    ),
  ));
  if (result == null) return null;
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/edit_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await f.writeAsBytes(result!);
  return f.path;
}

/// Thanh trên của trình sửa ảnh: Hủy (giữ ảnh gốc), Hoàn tác / Làm lại và nút chữ "Xong" nổi bật để lưu ảnh đã sửa.
class EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  final ProImageEditorState editor;
  const EditorAppBar({super.key, required this.editor});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final style = editor.configs.mainEditor.style;
    final fg = style.appBarColor;
    return AppBar(
      foregroundColor: fg,
      backgroundColor: style.appBarBackground,
      leading: IconButton(tooltip: tr('Hủy'), icon: const Icon(Icons.close_rounded), onPressed: editor.closeEditor),
      actions: [
        IconButton(
          tooltip: tr('Hoàn tác'),
          icon: Icon(Icons.undo_rounded, color: editor.canUndo ? fg : fg.withAlpha(80)),
          onPressed: editor.undoAction,
        ),
        IconButton(
          tooltip: tr('Làm lại'),
          icon: Icon(Icons.redo_rounded, color: editor.canRedo ? fg : fg.withAlpha(80)),
          onPressed: editor.redoAction,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: FilledButton(
            key: const ValueKey('editor-done'),
            onPressed: editor.doneEditing,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 18)),
            child: Text(tr('Xong'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
