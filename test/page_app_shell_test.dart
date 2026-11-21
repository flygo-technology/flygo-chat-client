// Vỏ chung của trang-app (pages/app_shell.dart) và bộ ô điều khiển (pages/app_kit.dart): ba kiểu màn hình × tối / sáng không tràn,
// sửa tại chỗ (Xong gọi hàm lưu của app), nút hỏi lại hai lần, menu nổi dùng chung. APP_OUT=<thư mục>: lưu ảnh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/pages/app_kit.dart';
import 'package:flygo_chat/ui/pages/app_shell.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/stage_frame.dart';

import 'app_kit_helpers.dart';

var _saved = <String>[];

class _DemoStage extends StatefulWidget {
  final PageCtx ctx;
  const _DemoStage(this.ctx);
  @override
  State<_DemoStage> createState() => _DemoStageState();
}

class _DemoStageState extends State<_DemoStage> {
  late String _title = '${widget.ctx.view['title'] ?? ''}';
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    s.registerEdit(() async {
      if (_title.trim().isEmpty) return false;
      _saved.add(_title);
      return true;
    });
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppInlineField(key: const ValueKey('demo-title'), value: _title, onChanged: (v) => _title = v, style: TextStyle(color: s.theme.text, fontSize: 44, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        Text('Kiểu: ${s.form.name}', style: TextStyle(color: s.theme.sub, fontSize: 22)),
      ]),
    );
  }
}

final _spec = PageTypeSpec(
  type: 'demo',
  label: 'Thử',
  icon: Icons.widgets_outlined,
  color: const Color(0xFF3D7BFF),
  stageThemed: true,
  inlineEdit: true,
  view: (context, ctx) => _DemoStage(ctx),
  panel: (context, ctx) => AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const AppSectionLabel('Phần của người xem'),
      Row(children: [
        Expanded(child: AppButton('Cần thêm thời gian', onPressed: () => ctx.act('more'))),
        const SizedBox(width: 8),
        Expanded(child: AppButton('Đã rõ', kind: AppButtonKind.success, onPressed: () => ctx.act('clear'))),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: const [AppChip('Đồng ý'), AppChip('Phản đối', color: Color(0xFFF28B3F)), AppChip('Ý kiến khác', color: Color(0xFF8E99A8))]),
    ]),
  ),
  controls: (context, ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const AppSectionLabel('Điều khiển'),
    AppSegmented<int>(items: const [(0, 'Tự động'), (1, 'Lưới'), (2, 'Một người')], value: 1, onChanged: (_) {}),
    AppToggleRow('Ẩn danh', value: true, onChanged: (_) {}),
    AppSelectRow('Người xem thấy kết quả', value: 'Sau khi chọn', onTap: () {}),
    Row(children: [
      Expanded(child: Text('Giờ mỗi lượt', style: TextStyle(color: AppScope.of(context).theme.text))),
      AppNumberStepper(value: 2, min: 1, format: (v) => '$v′', onChanged: (_) {}),
    ]),
    const SizedBox(height: 8),
    Row(children: [
      const AppProgressRing(value: .62, size: 56, stroke: 6, child: Text('13')),
      const SizedBox(width: 12),
      Expanded(child: AppButton('Xoá hết', kind: AppButtonKind.danger, confirm: true, onPressed: () => ctx.act('reset'))),
    ]),
  ]),
);

void main() {
  setUpAll(loadAppTestFonts);

  testWidgets('vỏ app: ba kiểu màn hình × tối / sáng, chủ trang thấy điều khiển', (t) async {
    await pumpAppForms(t, 'vo-app', _spec, appCtx('demo', {'title': 'Giao ban tháng 12'}), check: (t, form, light) async {
      expect(find.text('PHẦN CỦA NGƯỜI XEM'), findsOneWidget);
      expect(find.text('ĐIỀU KHIỂN'), findsOneWidget);
      expect(find.text('Kiểu: ${form == 'dien-thoai-doc' ? 'phonePortrait' : form == 'dien-thoai-ngang' ? 'phoneLandscape' : 'wide'}'), findsOneWidget);
    });
  });

  testWidgets('người xem không thấy điều khiển', (t) async {
    await pumpAppForms(t, 'vo-app-nguoi-xem', _spec, appCtx('demo', {'title': 'Giao ban'}, role: 'member'), forms: ['dien-thoai-doc'], check: (t, _, _) async {
      expect(find.text('ĐIỀU KHIỂN'), findsNothing);
      expect(find.text('PHẦN CỦA NGƯỜI XEM'), findsOneWidget);
    });
  });

  testWidgets('sửa tại chỗ: Xong gọi hàm lưu của app, trống thì ở lại', (t) async {
    _saved = [];
    var ended = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PageAppShell(ctx: appCtx('demo', {'title': 'Cũ'}), spec: _spec, editing: true, theme: const StageTheme(), onEditEnd: () => ended++),
        ),
      ),
    ));
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('demo-title')), matching: find.byType(TextField)), '');
    await t.tap(find.text('Xong'));
    await t.pumpAndSettle();
    expect(ended, 0);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('demo-title')), matching: find.byType(TextField)), 'Mới');
    await t.tap(find.text('Xong'));
    await t.pumpAndSettle();
    expect(_saved, ['Mới']);
    expect(ended, 1);
  });

  testWidgets('nút hỏi lại: bấm hai lần mới chạy', (t) async {
    appActs.clear();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PageAppShell(ctx: appCtx('demo', {'title': 'A'}), spec: _spec, theme: const StageTheme())))));
    await t.ensureVisible(find.text('Xoá hết'));
    await t.tap(find.text('Xoá hết'));
    await t.pump();
    expect(appActs, isEmpty);
    expect(find.textContaining('Bấm lần nữa'), findsOneWidget);
    await t.tap(find.textContaining('Bấm lần nữa'));
    await t.pump();
    expect(appActs.single.$1, 'reset');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('menu nổi dùng chung: chạy mục đã chọn', (t) async {
    var hit = '';
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showAppMenu(c, items: [
              PageMenuItem(label: 'Ghim lên TV', icon: Icons.push_pin_outlined, onTap: () async => hit = 'pin'),
              PageMenuItem(label: 'Ẩn', icon: Icons.visibility_off_outlined, danger: true, onTap: () async => hit = 'hide'),
              const PageMenuItem(label: 'Tắt', icon: Icons.block, enabled: false),
            ]),
            child: const Text('mở'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Tắt'), findsOneWidget);
    await t.tap(find.text('Ẩn'));
    await t.pumpAndSettle();
    expect(hit, 'hide');
  });
}
