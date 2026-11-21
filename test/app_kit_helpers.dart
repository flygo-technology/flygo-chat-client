// Dùng chung cho test các trang-app (mockup "mỗi trang là một app"): dựng PageAppShell ở các kiểu màn hình
// (điện thoại dọc, điện thoại ngang, máy tính) × tối / sáng, kiểm tra không tràn, lưu ảnh khi đặt APP_OUT=<thư mục>.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/pages/app_shell.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/pages_api.dart';
import 'package:flygo_chat/ui/pages/stage_frame.dart';

final appTestState = AppState('t');

/// Các hành động app đã gửi (ctx.act), để kiểm tra.
final appActs = <(String, Map<String, dynamic>)>[];

/// Kích thước màn hình của từng kiểu.
const appFormSizes = {'dien-thoai-doc': Size(390, 844), 'dien-thoai-ngang': Size(844, 390), 'may-tinh': Size(1280, 800)};

PageCtx appCtx(String type, Map<String, dynamic> view,
        {String role = 'owner', bool presenting = false, String title = 'Trang thử', Map<String, dynamic> content = const {}, String? meeting = 'abc-defg-hij'}) =>
    PageCtx(
      data: PageData.from({
        'page': {'id': 'p1', 'type': type, 'title': title, 'owner': 'o', 'owner_name': 'Nguyễn Văn Lợi', 'visibility': 'meeting', 'meeting': meeting, 'content': content},
        'view': view,
        'role': role,
        'rev': 3,
      }),
      api: PagesApi(appTestState.calls),
      call: appTestState.calls,
      presenting: presenting,
      onStage: false,
      act: (a, [b = const {}]) async => appActs.add((a, b)),
      reload: () async {},
    );

Future<void> loadAppTestFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f);
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  for (final fam in ['Flygo Inter', 'Noto Sans', 'Roboto']) {
    await load(fam, [for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$f.ttf']);
  }
}

final _shotKey = GlobalKey();

/// Dựng [spec] trong PageAppShell ở mọi kiểu màn hình × tối / sáng. Ảnh: `APP_OUT/<name>-<kiểu>-<toi|sang>.png`.
/// [check] chạy sau mỗi lần dựng (kiểm tra chữ, bấm nút…).
Future<void> pumpAppForms(WidgetTester t, String name, PageTypeSpec spec, PageCtx ctx,
    {bool editing = false, Future<void> Function(WidgetTester t, String form, bool light)? check, Iterable<String>? forms}) async {
  for (final form in forms ?? appFormSizes.keys) {
    for (final light in [false, true]) {
      final size = appFormSizes[form]!;
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final errs = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (d) => errs.add(d.exceptionAsString());
      final th = StageTheme(light: light);
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Flygo Inter', brightness: light ? Brightness.light : Brightness.dark),
        home: RepaintBoundary(
          key: _shotKey,
          child: Scaffold(
            backgroundColor: light ? const Color(0xFFF7F8FA) : const Color(0xFF0E1116),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: PageAppShell(ctx: ctx, spec: spec, editing: editing, theme: th),
              ),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      FlutterError.onError = old;
      expect(errs, isEmpty, reason: '$name $form ${light ? 'sáng' : 'tối'}');
      await check?.call(t, form, light);
      final dir = Platform.environment['APP_OUT'];
      if (dir != null) {
        await t.runAsync(() async {
          final ro = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await ro.toImage(pixelRatio: 1);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/$name-$form-${light ? 'sang' : 'toi'}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }
  }
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}
