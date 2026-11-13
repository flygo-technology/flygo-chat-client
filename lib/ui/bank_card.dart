import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'theme.dart';

/// Một bên của giao dịch (người gửi / người nhận).
class BankParty {
  final String name;
  final String account;
  final String bank;
  const BankParty({this.name = '', this.account = '', this.bank = ''});
  bool get isEmpty => name.isEmpty && account.isEmpty && bank.isEmpty;
}

/// Dữ liệu một tin báo nợ / báo có.
class BankTxn {
  final bool incoming;
  final int amount;
  final String currency;
  final DateTime at;
  final String accountLabel; // vd "OCB · ABC Vina" (tài khoản của công ty)
  final BankParty from;
  final BankParty to;
  final String content;
  final String ref; // số tham chiếu
  final String txnNo; // số giao dịch
  /// Số dư sau giao dịch (chỉ có ở nhóm được xem số dư); trống thì không hiện.
  final String balance;
  final String balanceLabel;
  const BankTxn({
    required this.incoming,
    required this.amount,
    this.currency = 'VND',
    required this.at,
    this.accountLabel = '',
    this.from = const BankParty(),
    this.to = const BankParty(),
    this.content = '',
    this.ref = '',
    this.txnNo = '',
    this.balance = '',
    this.balanceLabel = 'Số dư sau giao dịch',
  });
}

String _money(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Thẻ giao dịch ngân hàng: số tiền lớn, thời gian, người gửi → người nhận, nội dung, số tham chiếu.
class BankTxnCard extends StatelessWidget {
  final BankTxn t;
  final double width;
  /// Phần đính ở cuối thẻ (ghi chú của tin), nằm trong thẻ.
  final Widget? footer;
  const BankTxnCard({super.key, required this.t, this.width = 340, this.footer});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = t.incoming ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final toneSoft = tone.withValues(alpha: dark ? .18 : .10);
    final time = '${_two(t.at.hour)}:${_two(t.at.minute)} · ${_two(t.at.day)}/${_two(t.at.month)}/${t.at.year}';

    // Icon căn giữa theo chiều dọc với khối chữ của từng bên; mũi tên nằm giữa hai icon (cùng cột 30px).
    Widget party(String label, BankParty p, IconData icon) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: pal.text.withValues(alpha: .06), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: pal.sub),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11, letterSpacing: .3, color: pal.sub, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text(p.isEmpty ? 'Ngân hàng không cho biết' : (p.name.isEmpty ? p.bank : p.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.25, color: p.isEmpty ? pal.sub : pal.text, fontWeight: FontWeight.w600, fontStyle: p.isEmpty ? FontStyle.italic : null)),
              if (!p.isEmpty && (p.account.isNotEmpty || (p.name.isNotEmpty && p.bank.isNotEmpty)))
                Text([if (p.account.isNotEmpty) p.account, if (p.name.isNotEmpty && p.bank.isNotEmpty) p.bank].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
            ]),
          ),
        ]);

    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: pal.inBubble,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .5 : .12), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // Đầu thẻ: loại giao dịch + tài khoản công ty, số tiền lớn, thời gian.
        Container(
          color: toneSoft,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(t.incoming ? Icons.south_west_rounded : Icons.north_east_rounded, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(t.incoming ? 'TIỀN VỀ' : 'TIỀN ĐI',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: Colors.white)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Tài khoản công ty căn phải; nhãn TIỀN VỀ / TIỀN ĐI ở bên trái.
                child: Text(t.accountLabel, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.text.withValues(alpha: .75))),
              ),
            ]),
            const SizedBox(height: 10),
            // Số tiền và thời gian căn giữa thẻ.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${t.incoming ? '+' : '−'}${_money(t.amount)}',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: tone, letterSpacing: -.5)),
                TextSpan(text: ' ${t.currency == 'VND' ? '₫' : t.currency}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tone)),
              ])),
            ),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.schedule_rounded, size: 13, color: pal.sub),
              const SizedBox(width: 4),
              Text(time, style: TextStyle(fontSize: 12.5, color: pal.sub, fontWeight: FontWeight.w500)),
            ]),
            if (t.balance.isNotEmpty) ...[
              const SizedBox(height: 6),
              // Số dư: chữ thường trên nền đầu thẻ, to hơn dòng giờ một chút.
              Center(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${t.balanceLabel}: ', style: TextStyle(fontSize: 14, color: pal.sub)),
                  TextSpan(text: '${_money(int.tryParse(t.balance.split('.').first.replaceAll(',', '')) ?? 0)} ₫',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: pal.text)),
                ])),
              ),
            ],
          ]),
        ),
        // Người gửi → người nhận.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(children: [
            party('NGƯỜI GỬI', t.from, Icons.person_outline_rounded),
            SizedBox(
              width: double.infinity,
              child: Row(children: [
                SizedBox(width: 30, child: Center(child: Icon(Icons.arrow_downward_rounded, size: 16, color: pal.sub.withValues(alpha: .7)))),
              ]),
            ),
            party('NGƯỜI NHẬN', t.to, Icons.account_balance_outlined),
          ]),
        ),
        // Nội dung chuyển khoản.
        if (t.content.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
            decoration: BoxDecoration(color: pal.text.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)),
            // Nội dung chuyển khoản + nút sao chép (góc trên bên phải).
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NỘI DUNG', style: TextStyle(fontSize: 11, letterSpacing: .3, color: pal.sub, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(t.content, style: TextStyle(fontSize: 13.5, height: 1.3, color: pal.text)),
                ]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Sao chép nội dung',
                onPressed: () => Clipboard.setData(ClipboardData(text: t.content)),
                icon: Icon(Icons.copy_rounded, color: pal.sub),
              ),
            ]),
          ),
        // Số giao dịch / số tham chiếu (bấm để sao chép).
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Column(children: [
            for (final (label, v) in [('Số giao dịch', t.txnNo), ('Số tham chiếu', t.ref)])
              if (v.isNotEmpty)
                Row(children: [
                  SizedBox(width: 96, child: Text(label, style: TextStyle(fontSize: 12, color: pal.sub))),
                  Expanded(
                    child: Text(v,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Sao chép',
                    onPressed: () => Clipboard.setData(ClipboardData(text: v)),
                    icon: Icon(Icons.copy_rounded, color: pal.sub),
                  ),
                ]),
          ]),
        ),
        // Ghi chú của tin: đính liền ở cuối thẻ.
        if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: DefaultTextStyle.merge(style: TextStyle(color: pal.text), child: footer!)),
      ]),
    );
  }
}

/// props.flygo_bank_txn (worker báo nợ báo có, bản 1): dữ liệu để vẽ thẻ; tin vẫn có nội dung chữ cho app cũ.
/// Không có / sai khuôn thì null (hiện tin chữ như cũ).
BankTxn? bankTxnOf(MmPost p) {
  final m = p.props['flygo_bank_txn'];
  if (m is! Map || m['v'] != 1) return null;
  String str(Object? v) => v == null ? '' : '$v'.trim();
  final amount = double.tryParse(str(m['amount']).replaceAll(',', ''));
  final at = DateTime.tryParse(str(m['at']))?.toLocal();
  if (amount == null || at == null) return null;
  final incoming = m['dir'] != 'out';
  BankParty side(Object? v, String fallbackName) {
    if (v is Map) return BankParty(name: str(v['name']), account: str(v['account']), bank: str(v['bank']));
    return BankParty(name: fallbackName);
  }

  // Bản 1: ours / other là chuỗi; bổ sung (cùng v1): ours_party / other_party {name, account, bank}.
  final ours = side(m['ours_party'], str(m['ours']));
  final other = side(m['other_party'], str(m['other']));
  final ref = str(m['ref']);
  final label = str(m['ref_label']).toLowerCase();
  // Ngân hàng gọi mã là "Số GD" (ACB) thì là số giao dịch; còn lại là số tham chiếu.
  final isTxnNo = label.contains('gd') || label.contains('giao dịch');
  return BankTxn(
    incoming: incoming,
    amount: amount.round(),
    currency: str(m['currency']).isEmpty ? 'VND' : str(m['currency']),
    at: at,
    accountLabel: str(m['bank']),
    from: incoming ? other : ours,
    to: incoming ? ours : other,
    content: str(m['content']),
    ref: isTxnNo ? '' : ref,
    txnNo: isTxnNo ? ref : str(m['txn_no']),
    balance: str(m['balance']),
    balanceLabel: str(m['balance_label']).isEmpty ? 'Số dư sau giao dịch' : str(m['balance_label']),
  );
}
