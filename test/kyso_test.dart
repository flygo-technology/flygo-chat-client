import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/kyso/kyso_api.dart';
import 'package:flygo_chat/browser/browser_page.dart';
import 'package:flygo_chat/browser/chrome_ui.dart';
import 'package:flygo_chat/browser/flygo_id.dart';

void main() {
  final tokens = <Map<String, dynamic>>[
    {'tokenId': 'fpt:40d4f0', 'companyName': 'CÔNG TY TRÁCH NHIỆM HỮU HẠN ABC VINA'},
    {'tokenId': 'fpt:7e3f04', 'companyName': 'CÔNG TY TNHH ABC CAPITAL'},
  ];

  test('tên ô là "Ký số" + tên công ty đầy đủ theo chứng thư', () {
    expect(kysoTileName(tokens[1]), 'Ký số CÔNG TY TNHH ABC CAPITAL');
  });

  test('tìm token theo mã, rồi tên ô, rồi tên công ty', () {
    expect(KysoApi.match(tokens, 'fpt:7e3f04')?['tokenId'], 'fpt:7e3f04');
    expect(KysoApi.match(tokens, 'FPT:40D4F0')?['tokenId'], 'fpt:40d4f0');
    expect(KysoApi.match(tokens, 'ký số công ty tnhh abc capital')?['tokenId'], 'fpt:7e3f04');
    expect(KysoApi.match(tokens, 'Công ty TNHH ABC Capital')?['tokenId'], 'fpt:7e3f04');
    expect(KysoApi.match(tokens, 'ABC'), isNull);
    expect(KysoApi.match(tokens, ''), isNull);
  });

  test('space Ký số từ Flygo ID: tìm theo mã token, mã space, tên', () {
    final spaces = [
      BrowserSpace.fromJson({
        'id': 'vn.flygo.kyso/fpt-7e3f04',
        'name': 'Ký số CÔNG TY TNHH ABC CAPITAL',
        'whitelist': {'o0': {'pattern': 'https://*.gdt.gov.vn/*'}},
        'extensions': {
          'vn.flygo.kyso': {'env': {'TOKEN': 'fpt:7e3f04', 'SERVER': 'https://kyso.example.com', 'MST': '0100000000'}},
        },
        'vault': {'can_manage': false},
      }),
    ];
    expect(spaces.first.space.env['TOKEN'], 'fpt:7e3f04');
    expect(spaces.first.space.allows('https://dichvucong.gdt.gov.vn/tthc/home'), isTrue);
    expect(spaces.first.space.allows('https://mail.google.com/'), isFalse);
    expect(KysoApi.matchSpace(spaces, 'fpt:7e3f04'), isNotNull);
    expect(KysoApi.matchSpace(spaces, 'fpt-7e3f04'), isNotNull);
    expect(KysoApi.matchSpace(spaces, 'Công ty TNHH ABC Capital'), isNotNull);
    expect(KysoApi.matchSpace(spaces, 'ABC VINA'), isNull);
  });

  test('màu công ty giống trình duyệt Magic Sign (company-color.js)', () {
    expect(companyHue('CÔNG TY TNHH ABC CAPITAL'), 343);
    expect(companyHue('CÔNG TY TRÁCH NHIỆM HỮU HẠN ABC VINA'), 157);
    expect(companyHue('CÔNG TY TNHH THANG MÁY XYZ VIỆT NAM'), 159);
    expect(companyHue('Ký số CÔNG TY TNHH MINH ANH VINA'), 88);
  });

  test('ô địa chỉ: địa chỉ thì mở, chữ thường thì tìm Google', () {
    expect(kysoAddressToUrl('thuedientu.gdt.gov.vn'), 'https://thuedientu.gdt.gov.vn');
    expect(kysoAddressToUrl('https://a.vn/x?y=1'), 'https://a.vn/x?y=1');
    expect(kysoAddressToUrl('hoadondientu.gdt.gov.vn/tra-cuu'), 'https://hoadondientu.gdt.gov.vn/tra-cuu');
    expect(kysoAddressToUrl('tra cứu mã số thuế'), 'https://www.google.com/search?q=tra+c%E1%BB%A9u+m%C3%A3+s%E1%BB%91+thu%E1%BA%BF');
    expect(kysoAddressToUrl('minvoice'), 'https://www.google.com/search?q=minvoice');
    expect(kysoAddressToUrl('1.2'), 'https://www.google.com/search?q=1.2');
  });
}
