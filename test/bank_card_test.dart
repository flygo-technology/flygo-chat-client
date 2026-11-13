import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/bank_card.dart';

MmPost post(Map<String, dynamic> props) => MmPost({'id': 'p', 'channel_id': 'c', 'user_id': 'b', 'message': 'BÁO CÓ…', 'create_at': 0, 'props': props});

void main() {
  test('đọc props.flygo_bank_txn của worker (tiền về, Số GD)', () {
    final t = bankTxnOf(post({
      'flygo_bank_txn': {
        'v': 1, 'dir': 'in', 'amount': '102000000', 'currency': 'VND', 'at': '2026-11-07T14:09:00+07:00', 'bank': 'ACB · ABC Capital',
        'ours': '•••552628 (VND) · TGTT KHTN', 'other': 'CTY THIEN HUNG · ••••5979 · ACB', 'content': 'TT TIEN HANG', 'ref': '3119', 'ref_label': 'Số GD', 'status': null,
      },
    }))!;
    expect(t.incoming, isTrue);
    expect(t.amount, 102000000);
    expect(t.accountLabel, 'ACB · ABC Capital');
    expect(t.from.name, 'CTY THIEN HUNG · ••••5979 · ACB');
    expect(t.to.name, '•••552628 (VND) · TGTT KHTN');
    expect(t.txnNo, '3119');
    expect(t.ref, '');
  });

  test('tiền đi: người gửi là tài khoản công ty, số tham chiếu', () {
    final t = bankTxnOf(post({
      'flygo_bank_txn': {'v': 1, 'dir': 'out', 'amount': '35500000.00', 'at': '2026-11-07T08:20:00Z', 'bank': 'VPB', 'ours': 'ABC Vina', 'other': null, 'ref': 'FT1', 'ref_label': 'Số tham chiếu'},
    }))!;
    expect(t.incoming, isFalse);
    expect(t.amount, 35500000);
    expect(t.from.name, 'ABC Vina');
    expect(t.to.isEmpty, isTrue);
    expect(t.ref, 'FT1');
    expect(t.txnNo, '');
  });

  test('không có hoặc sai khuôn: null (hiện tin chữ như cũ)', () {
    expect(bankTxnOf(post({})), isNull);
    expect(bankTxnOf(post({'flygo_bank_txn': {'v': 2}})), isNull);
    expect(bankTxnOf(post({'flygo_bank_txn': {'v': 1, 'amount': 'x', 'at': 'y'}})), isNull);
  });

  test('bản tách trường: ours_party / other_party, số dư', () {
    final t = bankTxnOf(post({
      'flygo_bank_txn': {
        'v': 1, 'dir': 'in', 'amount': '102000000', 'at': '2026-11-07T14:09:00+07:00', 'bank': 'ACB · ABC Capital',
        'ours': 'x', 'other': 'y',
        'ours_party': {'name': 'ABC Capital', 'account': '•••552628 (VND)', 'bank': 'ACB'},
        'other_party': {'name': 'CTY THIEN HUNG', 'account': '••••5979', 'bank': 'ACB - NH TMCP A CHAU'},
        'ref': '3119', 'ref_label': 'Số GD', 'balance': '486250000', 'balance_label': 'Số dư sau giao dịch',
      },
    }))!;
    expect(t.from.name, 'CTY THIEN HUNG');
    expect(t.from.account, '••••5979');
    expect(t.to.bank, 'ACB');
    expect(t.balance, '486250000');
  });
}
