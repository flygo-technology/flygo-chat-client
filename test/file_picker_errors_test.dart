import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/common.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Hộp chọn tệp lỗi (vd máy Mac thiếu quyền): báo lỗi, trả về danh sách rỗng, không im lặng.
void main() {
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

  testWidgets('hộp chọn tệp lỗi: hiện "Không mở được hộp chọn tệp", trả về rỗng', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'ENTITLEMENT_NOT_FOUND', message: 'thiếu quyền'));
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    List<PlatformFile>? got;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (c) => FilledButton(onPressed: () async => got = await pickFilesOrReport(c, type: FileType.image), child: const Text('chọn')),
        ),
      ),
    ));
    await t.tap(find.text('chọn'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(got, isEmpty);
    expect(find.textContaining('Không mở được hộp chọn tệp'), findsOneWidget);
  });
}
