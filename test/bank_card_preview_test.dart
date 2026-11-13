// Ảnh xem trước thẻ giao dịch ngân hàng (chạy tay): BANK_OUT=<thư mục> flutter test test/bank_card_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/bank_card.dart';
import 'package:flygo_chat/ui/notes.dart';
import 'package:provider/provider.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['BANK_OUT'];
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['u2'] = MmUser({'id': 'u2', 'username': 'lan', 'first_name': 'Lan Kế toán'});
  final noted = MmPost({
    'id': 'p' * 26, 'channel_id': 'c1', 'user_id': 'bot', 'create_at': 1793840400000, 'message': '',
    'props': {
      'flygo_notes': [
        {'id': 'n1', 'by': 'u2', 'color': 'yellow', 'text': 'Đã đối chiếu với hợp đồng 0123, đúng số tiền.', 'at': 1793841000000},
      ],
    },
  });
  final txns = [
    BankTxn(
      incoming: true,
      amount: 400000000,
      at: DateTime(2026, 11, 7, 11, 4),
      accountLabel: 'OCB · ABC Vina',
      to: const BankParty(name: 'ABC Vina', account: '••••8888', bank: 'OCB'),
      content: 'NGUYEN THI DUYEN CMND 001189005922 NGAYCAP 21/11/2022 NOICAP CUC CANH SAT QLHC VE TTXH NOP TIEN',
      ref: 'TT26311TGGKK',
      txnNo: '5208114',
      balance: '1258400000',
    ),
    BankTxn(
      incoming: true,
      amount: 102000000,
      at: DateTime(2026, 11, 7, 14, 9),
      accountLabel: 'ACB · ABC Capital',
      from: const BankParty(name: 'CTY TNHH THANG MAY KY THUAT THIEN HUNG', account: '••••5979', bank: 'ACB'),
      to: const BankParty(name: 'ABC Capital', account: '•••552628', bank: 'ACB'),
      content: 'CTY TNHH THANG MAY KY THUAT THIEN HUNG TT TIEN HANG CHO CTY DD CAPITAL',
      txnNo: '3119',
      balance: '486250000',
    ),
    BankTxn(
      incoming: false,
      amount: 35500000,
      at: DateTime(2026, 11, 7, 15, 20),
      accountLabel: 'VPBank · ABC Vina',
      from: const BankParty(name: 'ABC Vina', account: '••••2468', bank: 'VPBank'),
      to: const BankParty(name: 'CONG TY TNHH CAP THEP HA NOI', account: '••••7713', bank: 'Vietcombank'),
      content: 'DD VINA THANH TOAN HD 0123 CAP THEP LO 12',
      ref: 'FT26311A9QX',
      txnNo: '880127',
      balance: '92300000',
    ),
  ];

  Future<void> shot(WidgetTester tester, String name, Brightness b) async {
    tester.view.physicalSize = const Size(400, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: app, child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(b),
      home: Builder(builder: (c) {
        final pal = Pal.of(c);
        return RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: pal.chatBg,
            body: ListView(padding: const EdgeInsets.fromLTRB(14, 20, 14, 20), children: [
              for (final (i, t) in txns.indexed) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: BankTxnCard(t: t, width: 340, footer: i == 1 ? MessageNotes(app: app, post: noted, width: 320) : null),
                ),
                const SizedBox(height: 14),
              ],
            ]),
          ),
        );
      }),
    )));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('ảnh xem trước thẻ ngân hàng', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    for (final b in Brightness.values) {
      await shot(tester, 'bank-${b.name}', b);
    }
  });
}
