// Thư: dữ liệu mẫu trong bộ nhớ (xem thử, chụp ảnh, test). Tên người và công ty đều là giả.
import 'dart:io';

import 'admin_api.dart';
import 'api.dart';
import 'model.dart';

class DemoMailApi extends MailApi {
  DemoMailApi({DateTime? now, this.latency = Duration.zero}) : _now = now ?? DateTime.now() {
    _seed();
    _seedShared();
  }

  final DateTime _now;
  final Duration latency;
  @override
  bool get demo => true;

  static const user = MailPerson('khoa@example.com', 'Trần Minh Khoa', true);
  final _labels = <MailLabel>[
    const MailLabel('l1', 'Khách hàng', 0xFF1F6FEB),
    const MailLabel('l2', 'Kế toán', 0xFF0F9D58),
    const MailLabel('l3', 'Dự án', 0xFF7C3AED),
    const MailLabel('l4', 'Cá nhân', 0xFFE8710A),
    const MailLabel('l5', 'Nhà cung cấp', 0xFFD93025),
  ];
  /// Thư theo từng hộp (hộp mẫu: cá nhân, hộp chung, hộp được uỷ quyền).
  final _store = <String, List<_T>>{};
  List<_T> get _threads => _store.putIfAbsent(_cur, () => []);
  String get _cur => mailbox ?? user.email;
  var _seq = 1;

  /// Các hộp thư người dùng mẫu mở được: của mình, hộp chung (gửi được / chỉ xem), hộp được uỷ quyền, và hộp chỉ thấy vì là quản trị.
  static const boxes = [
    MailboxInfo('khoa@example.com', name: 'Trần Minh Khoa', access: 'admin', via: 'owner'),
    MailboxInfo('hotro@example.com', name: 'Hỗ trợ khách hàng', access: 'send', kind: 'shared'),
    MailboxInfo('ketoan@example.com', name: 'Phòng Kế toán', access: 'read', kind: 'shared'),
    MailboxInfo('trang.phan@example.com', name: 'Phan Thu Trang', access: 'send'),
    MailboxInfo('tuyendung@example.com', name: 'Tuyển dụng', access: 'admin', kind: 'shared', via: 'admin'),
  ];
  MailboxInfo get _box => boxes.firstWhere((b) => b.id == _cur, orElse: () => boxes.first);
  /// Hộp đang xem, dưới dạng người gửi ("tôi" trong danh sách).
  MailPerson get _meP => _cur == user.email ? user : MailPerson(_box.id, _box.name, true);

  Future<T> _d<T>(T v) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return v;
  }

  static const _ha = MailPerson('ha.nguyen@anduong.example', 'Nguyễn Thu Hà');
  static const _long = MailPerson('long@example.com', 'Lê Hoàng Long');
  static const _mai = MailPerson('mai.ketoan@example.com', 'Phạm Thị Mai');
  static const _son = MailPerson('son@example.com', 'Đỗ Văn Sơn');
  static const _quan = MailPerson('quan@example.com', 'Vũ Minh Quân');
  static const _linh = MailPerson('linh.vu@saosang.example', 'Vũ Khánh Linh');
  static const _tuan = MailPerson('tuan.hoang@vantai.example', 'Hoàng Anh Tuấn');
  static const _bank = MailPerson('no-reply@bank.example', 'Thông báo tài khoản');
  static const _vat = MailPerson('hoadon@einvoice.example', 'Hệ thống hoá đơn điện tử');
  static const _news = MailPerson('newsletter@techweekly.example', 'Bản tin Công nghệ');
  static const _shop = MailPerson('sale@linhkien.example', 'Cửa hàng Linh kiện');
  static const _social = MailPerson('notify@network.example', 'Mạng nghề nghiệp');
  static const _cloud = MailPerson('billing@cloud.example', 'Dịch vụ Đám mây');
  static const _thao = MailPerson('thao@salon.example', 'Ngô Phương Thảo');
  static const _spam = MailPerson('win@lucky-prize.example', 'Trúng thưởng 2026');
  static const _minh = MailPerson('minh.bui@daiphat.example', 'Bùi Quang Minh');

  String _p(List<String> ps) => ps.map((x) => x.startsWith('<') ? x : '<p>$x</p>').join();
  String _sig(String n) => '<p>Trân trọng,<br>$n</p>';
  MailAttachment _att(String name, int size, String type) => MailAttachment(id: 'a${_seq++}', name: name, size: size, type: type, url: 'demo://$name');
  MailMessage _m(MailPerson from, List<MailPerson>? to, Duration ago, String html, {List<MailAttachment> att = const [], List<MailPerson> cc = const []}) =>
      MailMessage(id: 'm${_seq++}', from: from, to: to ?? [_meP], cc: cc, date: _now.subtract(ago), html: html, attachments: att);
  void _t(String subject, List<MailMessage> ms, {String box = 'inbox', String cat = 'primary', List<String> labels = const [], bool starred = false, bool unread = false, bool important = false, bool draft = false}) =>
      _threads.add(_T('t${_seq++}', subject, ms, box: box, category: cat, labels: [...labels], starred: starred, unread: unread, important: important, draft: draft));

  void _seed() {
    const h = Duration(hours: 1), d = Duration(days: 1);
    _t('Báo giá triển khai hệ thống email nội bộ', [
      _m(_ha, null, h * .4, _p(['Chào anh Khoa,', 'Bên em gửi lại báo giá triển khai hệ thống email nội bộ cho 45 người dùng như đã trao đổi hôm thứ Sáu. Báo giá đã gồm phần chuyển dữ liệu từ hệ thống cũ và đào tạo 2 buổi.', 'Anh xem giúp em mục 3 (lưu trữ 10 năm) có cần tách thành gói riêng không ạ.', _sig('Thu Hà<br>Phòng Kinh doanh – Công ty Ánh Dương')]),
          att: [_att('Bao-gia-email-noi-bo-v2.pdf', 482113, 'application/pdf'), _att('Danh-sach-nguoi-dung.xlsx', 18220, 'application/vnd.ms-excel')]),
    ], unread: true, important: true, labels: ['l1']);
    _t('Re: Lịch họp review quy trình phê duyệt chi', [
      _m(user, [_long, _mai], h * 26, _p(['Mọi người cho anh lịch rảnh tuần này để review quy trình phê duyệt chi nhé.', _sig('Khoa')])),
      _m(_long, [user, _mai], h * 20, _p(['Em rảnh chiều thứ Ba và sáng thứ Năm anh ạ.', 'Em sẽ chuẩn bị bản demo luồng mới.'])),
      _m(_mai, [user, _long], h * 1.2, _p(['Chị chốt <b>9h sáng thứ Năm</b> nhé, phòng họp tầng 3. Chị gửi kèm file quy trình hiện tại để mọi người đọc trước.', _sig('Mai – Kế toán')]),
          att: [_att('Quy-trinh-phe-duyet-chi.docx', 96000, 'application/msword')]),
    ], unread: true, labels: ['l3']);
    _t('Biến động số dư tài khoản …8868', [
      _m(_bank, null, h * 2.5, _p(['Quý khách vừa nhận <b>+25.300.000 VND</b> vào tài khoản …8868 lúc 08:41.', 'Nội dung: CTY ANH DUONG TT HD 0001245.', 'Số dư khả dụng: 412.880.500 VND.'])),
    ], unread: true, labels: ['l2']);
    _t('Hoá đơn điện tử số 0001245 – Công ty Ánh Dương', [
      _m(_vat, null, h * 4, _p(['Kính gửi Quý khách,', 'Hệ thống gửi Quý khách hoá đơn điện tử số <b>0001245</b>, ký hiệu 1C26TAD, tổng tiền thanh toán 25.300.000 VND.', 'Mã tra cứu: <b>AD-7Q2K-9XPL</b>.']),
          att: [_att('HD-0001245.pdf', 210400, 'application/pdf'), _att('HD-0001245.xml', 8100, 'text/xml')]),
    ], labels: ['l2'], important: true);
    _t('Hợp đồng vận chuyển quý I/2027', [
      _m(_tuan, null, h * 6, _p(['Anh Khoa thân mến,', 'Bên em gửi anh dự thảo hợp đồng vận chuyển quý I/2027. Đơn giá tuyến Hà Nội – Ninh Bình giữ nguyên, tuyến Hà Nội – Hải Phòng giảm 4%.', 'Anh phản hồi trước ngày 25/11 giúp em để kịp ký.', _sig('Hoàng Anh Tuấn')]),
          att: [_att('Du-thao-HD-van-chuyen-Q1-2027.docx', 143000, 'application/msword')]),
    ], starred: true, labels: ['l5']);
    _t('Ảnh nghiệm thu WiFi chi nhánh 2', [
      _m(_thao, null, h * 9, _p(['Anh ơi em gửi ảnh nghiệm thu 4 điểm phát WiFi ở chi nhánh 2. Khách vào mạng thấy trang chào rồi tự kết nối, chạy ổn anh nhé.', 'Cảm ơn anh và đội kỹ thuật!']),
          att: [_att('nghiem-thu-1.jpg', 1320000, 'image/jpeg'), _att('nghiem-thu-2.jpg', 1188000, 'image/jpeg'), _att('nghiem-thu-3.jpg', 1406000, 'image/jpeg')]),
    ], unread: true, labels: ['l1']);
    _t('Đề nghị tạm ứng công tác Ninh Bình', [
      _m(_son, [user], h * 22, _p(['Anh Khoa,', 'Em đề nghị tạm ứng 6.500.000 VND cho chuyến lắp đặt thiết bị ở Ninh Bình (3 ngày, 2 người). Bảng dự trù em để trong file đính kèm.', _sig('Sơn')]),
          att: [_att('Du-tru-cong-tac.xlsx', 22000, 'application/vnd.ms-excel')]),
      _m(user, [_son], h * 21, _p(['Ok em, anh duyệt. Em gửi chị Mai làm phiếu chi nhé.'])),
    ], labels: ['l2']);
    _t('Thông báo gia hạn dịch vụ máy chủ', [_m(_cloud, null, d * 1.1, _p(['Gói máy chủ <b>4C8G</b> của bạn sẽ hết hạn vào 01/12/2026. Gia hạn trước 25/11 để được giảm 10%.']))], cat: 'promo');
    _t('Bản tin tuần: 10 xu hướng tự động hoá doanh nghiệp', [_m(_news, null, d * 1.3, _p(['Từ AI agent cho kế toán tới quy trình phê duyệt không giấy tờ: tổng hợp 10 xu hướng nổi bật.']))], cat: 'promo');
    _t('Khuyến mãi cuối năm: giảm 20% bộ phát WiFi 6', [_m(_shop, null, d * 1.6, _p(['Chỉ đến 30/11: bộ phát WiFi 6 chuẩn AX3000 giảm 20%, miễn phí giao hàng nội thành.']))], cat: 'promo');
    _t('Linh và 3 người khác đã xem hồ sơ của bạn', [_m(_social, null, d * 1.2, _p(['Hồ sơ của bạn đang được chú ý! Xem ai đã ghé thăm trong tuần này.']))], cat: 'social');
    _t('Lời mời kết nối từ Bùi Quang Minh', [_m(_social, null, h * 3, _p(['Bùi Quang Minh (Đại Phát) muốn kết nối với bạn.']))], cat: 'social', unread: true);
    _t('Góp ý giao diện ứng dụng ghi chú', [
      _m(_quan, [user], d * 2, _p(['Anh Khoa, em gom góp ý của mọi người về app ghi chú:', '<ul><li>Nút thêm việc nên nổi bật hơn</li><li>Cho kéo thả sắp xếp</li><li>Nhắc việc qua chat</li></ul>', 'Em làm trong tuần sau được ạ.'])),
    ], labels: ['l3']);
    _t('Xác nhận đơn hàng #DP-20261102', [
      _m(_minh, null, d * 2.4, _p(['Chào anh,', 'Đại Phát xác nhận đơn hàng 12 bộ cảm biến cửa, giao trong 7 ngày làm việc.', _sig('Bùi Quang Minh')]), att: [_att('Don-hang-DP-20261102.pdf', 88000, 'application/pdf')]),
    ], starred: true, labels: ['l1']);
    _t('Hồ sơ năng lực Sao Sáng', [
      _m(_linh, null, d * 3, _p(['Kính gửi anh Khoa,', 'Sao Sáng xin gửi hồ sơ năng lực và một số dự án tiêu biểu về tích hợp hệ thống. Mong có dịp hợp tác.', _sig('Vũ Khánh Linh')]), att: [_att('Ho-so-nang-luc.pdf', 3400000, 'application/pdf')]),
    ], labels: ['l5']);
    _t('Ăn trưa thứ Sáu?', [
      _m(_long, [user], d * 4, _p(['Thứ Sáu team đi ăn bún chả nhé anh, em đặt bàn 12h.'])),
      _m(user, [_long], d * 4 - h * 2, _p(['Ok, tính anh một suất.'])),
    ], labels: ['l4']);
    _t('Báo cáo doanh thu tháng 10', [
      _m(_mai, [user], d * 9, _p(['Anh Khoa, chị gửi báo cáo doanh thu tháng 10. Doanh thu tăng 12% so với tháng 9, chủ yếu từ mảng triển khai mạng.']), att: [_att('Bao-cao-DT-T10-2026.xlsx', 56000, 'application/vnd.ms-excel')]),
    ], labels: ['l2']);
    _t('Bàn giao tài liệu hệ thống camera', [_m(_quan, [user], d * 16, _p(['Em đã cập nhật tài liệu hệ thống camera vào Drive, anh xem khi rảnh nhé.']))]);
    _t('Gửi lại hợp đồng bảo trì 2027', [
      _m(user, [_minh], h * 5, _p(['Anh Minh,', 'Em gửi lại hợp đồng bảo trì 2027 đã ký, anh kiểm tra giúp em.', _sig('Khoa')]), att: [_att('HD-bao-tri-2027-da-ky.pdf', 512000, 'application/pdf')]),
    ], box: 'all');
    _t('Phản hồi báo giá email nội bộ', [_m(user, [_ha], h * .2, _p(['Chị Hà, mục 3 bên em muốn tách thành gói riêng để...']))], box: 'drafts', draft: true);
    _t('Chúc mừng! Bạn đã trúng điện thoại', [_m(_spam, null, h * 7, _p(['Bấm vào đây để nhận quà ngay!!!']))], box: 'spam', unread: true);
    _t('Mã giảm giá đã hết hạn', [_m(_shop, null, d * 6, _p(['Mã giảm giá của bạn đã hết hạn.']))], box: 'trash', cat: 'promo');
  }

  bool _fromMe(_T t) => t.messages.any((m) => m.from.email == _meP.email);
  void _seedShared() {
    const h = Duration(hours: 1), d = Duration(days: 1);
    const lan = MailPerson('lan.tran@khachhang.example', 'Trần Ngọc Lan'), dung = MailPerson('dung@cafe.example', 'Lý Văn Dũng');
    const kho = MailPerson('kho@example.com', 'Kho vận'), ung = MailPerson('cv.nguyenha@ungvien.example', 'Nguyễn Hà My');
    mailbox = 'hotro@example.com';
    final hotro = _meP;
    _t('WiFi khách ở quán không vào được', [
      _m(dung, [hotro], h * .7, _p(['Chào bên hỗ trợ,', 'Từ sáng nay khách ở quán không vào được WiFi khách, bấm kết nối xong không hiện trang chào. WiFi nhân viên vẫn dùng bình thường.', 'Nhờ bên mình kiểm tra giúp sớm, chiều nay quán đông khách.', _sig('Lý Văn Dũng – Cà phê Phố Núi')])),
    ], unread: true, important: true);
    _t('Đổi địa chỉ xuất hoá đơn', [
      _m(lan, [hotro], h * 3, _p(['Bên chị đổi địa chỉ trụ sở từ tháng 12, nhờ em cập nhật thông tin xuất hoá đơn giúp chị nhé.', _sig('Ngọc Lan')]), att: [_att('Giay-phep-DKKD-moi.pdf', 640000, 'application/pdf')]),
    ], unread: true);
    _t('Hẹn lịch bảo trì định kỳ tháng 12', [
      _m(hotro, [lan], d * 1, _p(['Chào chị Lan, bên em xin hẹn lịch bảo trì định kỳ vào sáng thứ Bảy 05/12. Chị xác nhận giúp em nhé.'])),
      _m(lan, [hotro], h * 20, _p(['Ok em, thứ Bảy bên chị có người trực.'])),
    ]);
    mailbox = 'ketoan@example.com';
    _t('Đối chiếu công nợ tháng 10', [_m(kho, null, h * 5, _p(['Gửi phòng Kế toán bảng đối chiếu công nợ nhà cung cấp tháng 10.']), att: [_att('Doi-chieu-cong-no-T10.xlsx', 41000, 'application/vnd.ms-excel')])], unread: true);
    _t('Hoá đơn điện tử số 0001302', [_m(_vat, null, h * 8, _p(['Hệ thống gửi Quý khách hoá đơn điện tử số <b>0001302</b>, tổng tiền 8.250.000 VND.']))], unread: true);
    mailbox = 'trang.phan@example.com';
    _t('Lịch gặp đối tác thứ Tư', [_m(_minh, null, h * 2, _p(['Chị Trang, bên em xin hẹn gặp chị 14h thứ Tư tại văn phòng bên chị ạ.']))], unread: true);
    mailbox = 'tuyendung@example.com';
    _t('Ứng tuyển vị trí Kỹ sư mạng', [_m(ung, null, h * 10, _p(['Kính gửi phòng Nhân sự, em xin gửi CV ứng tuyển vị trí Kỹ sư mạng.']), att: [_att('CV-Nguyen-Ha-My.pdf', 230000, 'application/pdf')])], unread: true);
    mailbox = null;
  }

  late final _admin = DemoMailAdminApi(now: _now);
  @override
  MailAdminApi adminApi() => _admin;

  @override
  Future<MailAiResult> aiRevise({String? threadId, required String draft, String instruction = ''}) async =>
      MailAiResult(draft: '${draft.trim()}\n\n(Đã sửa theo yêu cầu: ${instruction.isEmpty ? 'trình bày lại' : instruction})');

  @override
  Future<MailDigest> aiDigest() async {
    final ts = _threads.where((t) => t.box == 'inbox' && t.category == 'primary' && t.unread && !t.draft).toList();
    return MailDigest(
      summary: ts.isEmpty ? 'Không có thư chưa đọc nào trong hộp Chính.' : 'Có ${ts.length} cuộc hội thoại chưa đọc cần xem.',
      threads: ts.length,
      tasks: [for (final t in ts) MailDigestTask(text: 'Đọc và trả lời "${t.subject}"', from: t.messages.last.from.short, urgent: t.important, threadId: t.id, subject: t.subject)],
    );
  }

  @override
  Future<MailAiResult> ai(String threadId, {String task = 'draft', String instruction = '', String tone = ''}) async {
    final t = _find(threadId);
    final last = t.messages.last, who = last.from.short;
    final body = _strip(last.html);
    // Câu nội dung đầu tiên (bỏ lời chào / chữ ký).
    final paras = RegExp(r'<p>(.*?)</p>', dotAll: true).allMatches(last.html).map((m) => _strip(m.group(1)!)).where((x) => x.isNotEmpty).toList();
    final first = paras.firstWhere((x) => !RegExp(r'^(Chào|Kính gửi|Anh |Chị |Gửi )|,$|^Trân trọng').hasMatch(x) || x.length > 60,
        orElse: () => paras.isEmpty ? body : paras.first);
    if (latency > Duration.zero) await Future<void>.delayed(latency * 4);
    final formal = tone != 'casual';
    final hi = formal ? 'Chào ${last.from.email == _meP.email ? 'anh/chị' : 'anh/chị $who'},' : 'Chào $who,';
    final draft = task == 'summary'
        ? ''
        : [
            hi,
            '',
            if (instruction.isNotEmpty) 'Về nội dung "${t.subject}": $instruction.' else 'Cảm ơn ${formal ? 'anh/chị' : 'bạn'} đã gửi thư về "${t.subject}". Bên em đã nhận được và sẽ phản hồi chi tiết trong hôm nay.',
            if (last.attachments.isNotEmpty) 'Em đã nhận đủ ${last.attachments.length} tệp đính kèm.',
            '',
            formal ? 'Trân trọng,' : 'Thân,',
            _meP.name.isEmpty ? _meP.email : _meP.name,
          ].join('\n');
    return MailAiResult(
      summary: '${last.from.display}${t.messages.length > 1 ? ' (cuộc trao đổi ${t.messages.length} thư)' : ''}: $first',
      actions: [
        if (body.contains(RegExp(r'trước ngày|hạn|sớm'))) 'Phản hồi đúng hạn được nêu trong thư',
        if (last.attachments.isNotEmpty) 'Xem ${last.attachments.length} tệp đính kèm',
        if (body.contains('?') || body.contains('nhờ') || body.contains('giúp')) 'Trả lời câu hỏi / đề nghị của $who',
      ],
      draft: draft,
      model: 'demo',
    );
  }

  bool _bad(_T t) => t.box == 'spam' || t.box == 'trash';
  bool _in(_T t, String box) => switch (box) {
        'inbox' => t.box == 'inbox',
        'starred' => t.starred && !_bad(t),
        'important' => t.important && !_bad(t),
        'sent' => _fromMe(t) && !t.draft && !_bad(t),
        'drafts' => t.draft,
        'all' => !_bad(t),
        'spam' => t.box == 'spam',
        'trash' => t.box == 'trash',
        _ => false,
      };

  static String _strip(String h) => h.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _match(_T t, String q) {
    final mq = MailQuery.parse(q);
    bool has(String hay, String needle) => hay.toLowerCase().contains(needle.toLowerCase());
    if (mq.from.isNotEmpty && !t.messages.any((m) => has('${m.from.name} ${m.from.email}', mq.from))) return false;
    if (mq.to.isNotEmpty && !t.messages.any((m) => [...m.to, ...m.cc].any((p) => has('${p.name} ${p.email}', mq.to)))) return false;
    if (mq.subject.isNotEmpty && !has(t.subject, mq.subject)) return false;
    if (mq.attachment && !t.messages.any((m) => m.attachments.isNotEmpty)) return false;
    if (mq.unread && !t.unread) return false;
    if (mq.inBox.startsWith('label:')) {
      final n = mq.inBox.substring(6);
      if (!t.labels.any((id) => has(_labels.where((l) => l.id == id).firstOrNull?.name ?? '', n))) return false;
    } else if (mq.inBox.isNotEmpty && !_in(t, mq.inBox)) {
      return false;
    }
    if (mq.within.isNotEmpty) {
      final n = int.tryParse(mq.within.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final days = n * (mq.within.endsWith('y') ? 365 : mq.within.endsWith('m') ? 30 : 1);
      if (_now.difference(t.messages.last.date).inDays > days) return false;
    }
    final all = '${t.subject} ${t.messages.map((m) => '${m.from.name} ${m.from.email} ${m.to.map((p) => '${p.name} ${p.email}').join(' ')} ${_strip(m.html)} ${m.attachments.map((a) => a.name).join(' ')}').join(' ')}';
    return mq.words.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every((w) => has(all, w.replaceAll('"', '')));
  }

  MailThreadSummary _sum(_T t) {
    final seen = <String, MailPerson>{};
    for (final m in t.messages) {
      seen.putIfAbsent(m.from.email, () => m.from.email == _meP.email ? _meP : m.from);
    }
    final last = t.messages.last;
    return MailThreadSummary(
      id: t.id,
      subject: t.subject,
      snippet: _strip(last.html),
      date: last.date,
      count: t.messages.length,
      participants: seen.values.toList(),
      to: last.to,
      unread: t.unread,
      starred: t.starred,
      important: t.important,
      labels: [...t.labels],
      box: t.box,
      draft: t.draft,
      category: t.category,
      attachments: t.messages.expand((m) => m.attachments).take(3).toList(),
    );
  }

  MailCounts _counts() => MailCounts(
        inbox: _threads.where((t) => t.box == 'inbox' && t.unread && t.category == 'primary').length,
        drafts: _threads.where((t) => t.draft).length,
        spam: _threads.where((t) => t.box == 'spam' && t.unread).length,
        categories: {for (final c in ['promo', 'social']) c: _threads.where((t) => t.box == 'inbox' && t.unread && t.category == c).length},
        labels: {for (final l in _labels) l.id: _threads.where((t) => t.labels.contains(l.id) && t.unread && !_bad(t)).length},
      );

  @override
  Future<MailMe> me() => _d(MailMe(_meP,
      mailboxes: [for (final b in boxes) b.id],
      boxes: [for (final b in boxes) MailboxInfo(b.id, name: b.name, access: b.access, kind: b.kind, via: b.via, unread: _unread(b.id))],
      access: _box.access,
      user: user,
      admin: true));

  int _unread(String box) => (_store[box] ?? const <_T>[]).where((t) => t.box == 'inbox' && t.unread && t.category == 'primary').length;
  @override
  Future<List<MailLabel>> labels() => _d([..._labels]);
  @override
  Future<MailLabel> createLabel(String name, int color) {
    final l = MailLabel('l${_seq++}', name, color);
    _labels.add(l);
    return _d(l);
  }

  @override
  Future<MailCounts> counts() => _d(_counts());

  @override
  Future<MailPage> list({String box = 'inbox', String? label, String? category, String? q, int page = 1, int size = 50}) {
    var r = _threads.where((t) {
      if (label != null) return t.labels.contains(label) && !_bad(t);
      if (q != null && q.isNotEmpty) return !_bad(t) || MailQuery.parse(q).inBox.isNotEmpty;
      return _in(t, box);
    }).toList();
    if (box == 'inbox' && label == null && (q == null || q.isEmpty) && category != null) r = r.where((t) => t.category == category).toList();
    if (q != null && q.isNotEmpty) r = r.where((t) => _match(t, q)).toList();
    r.sort((a, b) => b.messages.last.date.compareTo(a.messages.last.date));
    final items = r.skip((page - 1) * size).take(size).map(_sum).toList();
    return _d(MailPage(items, r.length, page: page, size: size, counts: _counts()));
  }

  _T _find(String id) => _threads.firstWhere((t) => t.id == id, orElse: () => throw MailException(404, 'Không tìm thấy thư'));

  @override
  Future<MailThread> thread(String id) {
    final t = _find(id);
    return _d(MailThread(_sum(t), [...t.messages]));
  }

  @override
  Future<MailCounts?> modify(List<String> ids, MailChange change) {
    for (final id in ids) {
      final t = _threads.where((x) => x.id == id).firstOrNull;
      if (t == null) continue;
      if (change.unread != null) t.unread = change.unread!;
      if (change.starred != null) t.starred = change.starred!;
      if (change.important != null) t.important = change.important!;
      if (change.box != null) t.box = change.box!;
      t.labels = {...t.labels, ...change.addLabels}.where((l) => !change.removeLabels.contains(l)).toList();
    }
    return _d(_counts());
  }

  @override
  Future<void> remove(List<String> ids) {
    _threads.removeWhere((t) => ids.contains(t.id));
    return _d(null);
  }

  @override
  Future<List<MailPerson>> contacts(String q) {
    final all = <String, MailPerson>{};
    for (final t in _threads) {
      for (final m in t.messages) {
        for (final p in [m.from, ...m.to, ...m.cc]) {
          if (p.email != user.email && !RegExp(r'no-reply|newsletter|notify|win@|sale@|billing@').hasMatch(p.email)) all[p.email] = p;
        }
      }
    }
    final l = q.toLowerCase();
    return _d(all.values.where((p) => '${p.name} ${p.email}'.toLowerCase().contains(l)).take(6).toList());
  }

  @override
  Future<MailAttachment> upload(File file, {String? name, String? type}) async {
    final n = name ?? file.uri.pathSegments.last;
    int size = 0;
    try {
      size = await file.length();
    } catch (_) {}
    return _d(MailAttachment(id: 'a${_seq++}', name: n, size: size, type: type ?? '', url: 'demo://$n', localPath: file.path));
  }

  @override
  Future<String> saveDraft(MailDraft d) {
    final msg = _m(_meP, d.to, Duration.zero, d.html, att: d.attachments, cc: d.cc);
    final t = d.id == null ? null : _threads.where((x) => x.draft && x.id == d.id).firstOrNull;
    if (t == null) {
      final nt = _T('t${_seq++}', d.subject.isEmpty ? '(không có tiêu đề)' : d.subject, [msg], box: 'drafts', draft: true);
      _threads.add(nt);
      return _d(nt.id);
    }
    t.subject = d.subject.isEmpty ? '(không có tiêu đề)' : d.subject;
    t.messages = [msg];
    return _d(t.id);
  }

  @override
  Future<void> deleteDraft(String id) {
    _threads.removeWhere((t) => t.draft && t.id == id);
    return _d(null);
  }

  @override
  Future<void> send(MailDraft d, {String? draftId}) {
    if (draftId != null) _threads.removeWhere((t) => t.id == draftId && t.draft);
    final msg = _m(_meP, d.to, Duration.zero, d.html, att: d.attachments, cc: d.cc);
    final t = d.threadId == null ? null : _threads.where((x) => x.id == d.threadId).firstOrNull;
    if (t != null) {
      t.messages = [...t.messages, msg];
    } else {
      _threads.add(_T('t${_seq++}', d.subject.isEmpty ? '(không có tiêu đề)' : d.subject, [msg], box: 'all'));
    }
    return _d(null);
  }

  @override
  Future<File> download(MailAttachment a) async {
    if (a.localPath != null) return File(a.localPath!);
    final f = File('${Directory.systemTemp.path}/flygo-mail-demo-${a.name}');
    if (!f.existsSync()) await f.writeAsString('Tệp mẫu (demo): ${a.name}');
    return f;
  }
}

class _T {
  _T(this.id, this.subject, this.messages, {this.box = 'inbox', this.category = 'primary', this.labels = const [], this.starred = false, this.unread = false, this.important = false, this.draft = false});
  final String id;
  String subject, box, category;
  List<MailMessage> messages;
  List<String> labels;
  bool starred, unread, important, draft;
}
