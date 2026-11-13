# Thiết kế bảo mật: yêu cầu thanh toán của đối tác không thể giả mạo

Ngày 2026-11-08. Bản thiết kế để Sếp duyệt. **Chưa viết code, chưa đổi gì trên máy chủ, Google Workspace hay ngân hàng.**

Yêu cầu gốc của Sếp: *"tôi muốn kể cả hệ thống liên lạc bị chiếm thì vẫn không thể tạo yêu cầu giả mạo được"*.

## 0. Tóm tắt

| # | Quyết định thiết kế | Vì sao |
|---|---|---|
| 1 | Email, WeChat, điện thoại, chat **chỉ mang thông báo, không mang quyền**. Không một tin nhắn nào đủ để tạo hay đổi lệnh chi | Kẻ chiếm kênh liên lạc chỉ gửi được tin, không có chữ ký |
| 2 | Quyền chỉ đến từ **chữ ký của khoá phần cứng** (FIDO2/WebAuthn) đã đăng ký trực tiếp từ trước | Không lấy được khoá từ xa; mỗi lần ký cần chạm khoá và nhập PIN |
| 3 | Tài khoản nhận tiền **chỉ chọn từ danh sách đã đăng ký**; không có ô nhập số tài khoản ở đâu cả | Kịch bản "đổi sang tài khoản Hồng Kông" không có chỗ để xảy ra |
| 4 | Đổi tài khoản nhận cần **M-of-N khoá của nhà cung cấp + 2 người nội bộ ký + chờ 7 ngày**, trong lúc chờ báo mọi đầu mối và ai cũng phủ quyết được | Một khoá bị mất, một máy bị nhiễm mã độc, hay một người bị lừa đều chưa đủ |
| 5 | **Sổ đăng ký đối tác cũng là sổ có chữ ký**: mọi mục (khoá, tài khoản, thu hồi) phải mang chữ ký hợp lệ, tính ngược về bộ khoá gốc của công ty | Người có quyền vào DB hay máy chủ cũng không chèn được khoá hay tài khoản giả |
| 6 | **Bộ kiểm tra độc lập** (chạy tách khỏi máy chủ) kiểm lại toàn bộ chuỗi chữ ký trước khi chi | Máy chủ bị chiếm vẫn không làm ra được một gói lệnh chi qua được bộ kiểm tra |
| 7 | **Flows không bao giờ chuyển tiền.** Lệnh chi được 2 người duyệt và nhả trên chính internet banking của ngân hàng, bằng token của ngân hàng | Lớp chặn cuối nằm ngoài hệ thống của mình |
| 8 | Nhật ký chuỗi băm, đầu chuỗi được neo ra ngoài mỗi ngày; đối soát tiền ra hằng ngày qua MCP ngân hàng (chỉ đọc) | Sửa lịch sử bị phát hiện; tiền ra tới tài khoản lạ được báo ngay |

Kiểm tra DNS (chỉ đọc, 2026-11-08) cho `congty.example`: MX là Google Workspace, SPF `~all`, đã có DKIM `google._domainkey`,
**chưa có bản ghi DMARC**. Đây là việc nên làm ngay ở Giai đoạn 0. Nếu công ty còn tên miền email khác thì cần kiểm tra
thêm (câu hỏi Q3).

## 1. Phạm vi và giả định

- Phạm vi: yêu cầu thanh toán cho nhà cung cấp (chủ yếu Trung Quốc, chi TT/SWIFT, USD/CNY) và việc đổi tài khoản nhận.
  Nhà cung cấp trong nước dùng cùng cơ chế, có thể ở mức nhẹ hơn (Q7).
- Ngân hàng: ACB ONE BIZ, VPBank NEOBiz, OCB, Shinhan. Bốn MCP ngân hàng hiện chỉ có **tool đọc** (theo chuẩn
  `bank-std/STANDARD.md`). Thiết kế này **giữ nguyên như vậy**, và cấm thêm tool chuyển tiền vào MCP/ContextForge.
- Quy trình chạy trên Flygo Flows (repo flygo-chat-server `flows/`, Rust), bước Duyệt là `approval_request`. Nhật ký `events` hiện là
  append-only nhưng chưa có chuỗi băm và chưa có chữ ký.
- Ứng dụng Flygo đã có thẻ duyệt `kind: passkey` (mở trang xác thực passkey cho thao tác nhạy cảm qua ContextForge,
  commit c137ceb). Có thể tái dùng cách đó (xem mục 3.5).

## 2. Mô hình đe doạ

### 2.1 Tài sản cần bảo vệ

| Tài sản | Hậu quả nếu mất |
|---|---|
| Tài khoản nhận của nhà cung cấp (số TK, SWIFT, tên người hưởng, ngân hàng, nước) | Chuyển tiền cho kẻ gian. Đây là rủi ro chính |
| Số tiền và chứng từ (PI, hoá đơn) đi kèm | Chi thừa, chi trùng |
| Khoá ký của nhà cung cấp và người duyệt nội bộ | Ký được yêu cầu giả |
| Bộ khoá gốc nội bộ (người được quyền xác nhận đăng ký) | Chèn được khoá, tài khoản giả vào sổ |
| Nhật ký và sổ đăng ký | Che giấu dấu vết, tạo lịch sử giả |
| Token ngân hàng của người nhả lệnh | Chuyển tiền trực tiếp, bỏ qua mọi thứ ở trên |

### 2.2 Kẻ tấn công và lớp nào chặn

Ký hiệu: ✅ chặn được, ⚠️ chặn một phần, ❌ không chặn.

| # | Kẻ tấn công | Họ làm được gì | Lớp chặn | Kết quả | Rủi ro còn lại |
|---|---|---|---|---|---|
| A1 | Chiếm email / WeChat / QQ / điện thoại của **nhà cung cấp** | Gửi "đổi tài khoản, đang kiểm toán", PI giả có số TK mới | Tài khoản chỉ lấy từ sổ đăng ký; tin nhắn không có quyền; điều khoản hợp đồng | ✅ | Nhân viên bỏ qua quy trình và chi tay ngoài hệ thống → chặn bằng kiểm soát kép ở ngân hàng (mục 4.4) |
| A2 | Chiếm email / chat **của mình** (Workspace, Mattermost) | Giả lệnh của Sếp "chi gấp", duyệt trong Flows bằng phiên bị chiếm | Duyệt cần chữ ký passkey/khoá phần cứng; phiên đăng nhập không đủ để ký | ✅ | Lừa đảo kiểu "Sếp gọi điện bảo làm ngay" → quy định không có ngoại lệ, kể cả Sếp |
| A3 | Mã độc trên máy của nhà cung cấp | Sửa nội dung hiển thị trên cổng, lừa người ký một yêu cầu khác | Khoá phần cứng không cho mã độc lấy khoá; tài khoản chỉ chọn trong sổ nên nội dung bị tráo vẫn trả cho đúng nhà cung cấp; đổi tài khoản cần M người trên M thiết bị + 7 ngày + gọi điện đối chiếu | ⚠️ | Mã độc tráo **số tiền** hay **PI** → bị chặn bởi đối chiếu với PI/đơn hàng và người duyệt nội bộ. Nếu cả M người ký đổi tài khoản đều bị lừa trên máy nhiễm độc thì còn lớp 7 ngày + gọi điện |
| A4 | Phiên nội bộ bị chiếm (token Mattermost/Flows, máy kế toán nhiễm mã độc) | Bấm Duyệt, tạo luồng, sửa form | Duyệt có chữ ký trên nội dung; ≥ ngưỡng cần 2 người ký trên 2 thiết bị; người nhả lệnh ngân hàng kiểm bằng bộ kiểm tra độc lập | ✅ / ⚠️ | Máy của một người duyệt bị chiếm có thể tráo màn hình khi họ ký → người thứ hai và người nhả lệnh đối chiếu mã ngắn (mục 3.3) |
| A5 | Người trong (quản trị DB, máy chủ ứng dụng, Docker) | Sửa bảng đăng ký, chèn khoá/TK, sửa nhật ký, sửa code Flows | Mọi mục sổ đăng ký cần chữ ký tính về bộ khoá gốc; bộ kiểm tra độc lập ghim khoá gốc; đầu chuỗi băm neo ra ngoài; tiền chỉ ra qua ngân hàng | ✅ | Quản trị viên vẫn **làm hỏng / dừng** được hệ thống (từ chối dịch vụ), nhưng không tạo được lệnh hợp lệ |
| A6 | Mất / bị lấy **một** khoá của nhà cung cấp | Ký yêu cầu thanh toán (nếu biết PIN) | PIN + khoá tự khoá sau 8 lần sai; một khoá không đủ đổi tài khoản; tiền vẫn về đúng TK đã đăng ký; báo thu hồi | ✅ | Có thể tạo yêu cầu chi **đúng TK** nhưng sai số tiền → chặn bởi đối chiếu PI và duyệt nội bộ |
| A7 | Thông đồng: nhân viên nhà cung cấp + kẻ ngoài | Đổi TK sang TK của kẻ gian với đủ M chữ ký phía nhà cung cấp | 2 người nội bộ phải ký; 7 ngày chờ và báo **mọi** đầu mối đã đăng ký (kể cả lãnh đạo nhà cung cấp); kiểm tra cờ đỏ (TK Hồng Kông, tên không khớp pháp nhân) | ⚠️ | Nếu thông đồng gồm cả lãnh đạo nhà cung cấp thì đó là rủi ro thương mại với chính nhà cung cấp, ngoài phạm vi kỹ thuật |
| A8 | Thông đồng nội bộ (2 người duyệt + 2 người nhả lệnh ngân hàng) | Chi sai | Phân tách nhiệm vụ: người duyệt ≠ người nhả; tài khoản lạ không có trong sổ thì đối soát hằng ngày báo Sếp | ⚠️ | Thông đồng đủ 4 người là rủi ro còn lại; giảm bằng đối soát tự động gửi Sếp và kiểm toán định kỳ |
| A9 | Chiếm tài khoản Cloudflare / tên miền / máy chủ cổng | Dựng cổng giả, đổi JavaScript, đổi DNS | Khoá đã đăng ký gắn với RP ID, nhưng **quyền vẫn nằm ở bộ kiểm tra**: chữ ký trên nội dung giả vẫn chỉ trỏ tới TK trong sổ; không chèn được khoá mới khi thiếu chữ ký nội bộ | ✅ / ⚠️ | Hiển thị sai cho người ký (WYSIWYS yếu đi) → bảo vệ tài khoản Cloudflare và nhà đăng ký tên miền bằng khoá phần cứng |
| A10 | Chiếm token ngân hàng của người nhả lệnh | Tự chuyển tiền trên internet banking | Ngoài phạm vi Flows. Giai đoạn 0: bật maker/checker, danh bạ người hưởng, hạn mức trên chính ngân hàng | ⚠️ | Phụ thuộc tính năng từng ngân hàng (Q6) |
| A11 | Gọi điện / video giả (deepfake) | Giả nhà cung cấp "xác nhận đổi tài khoản" | Gọi đối chiếu luôn **gọi ra** số đã có trong sổ, không gọi lại số trong tin nhắn; video chỉ là lớp phụ, không thay chữ ký | ✅ | |

### 2.3 Điều thiết kế này KHÔNG chống được

- Người có token ngân hàng tự ý chi ngoài hệ thống (cần kiểm soát kép tại ngân hàng và kỷ luật).
- Nhà cung cấp thật lừa đảo hoặc phá sản (rủi ro thương mại).
- Tất cả M khoá nhà cung cấp + 2 người nội bộ + thời gian chờ đều bị qua mặt cùng lúc mà không ai trong danh sách
  đầu mối phản ứng trong 7 ngày.
- Từ chối dịch vụ: máy chủ hỏng thì không tạo được yêu cầu mới (khi đó quay về quy trình giấy có chữ ký và dấu, xem 5.6).

## 3. Kiến trúc

```
 Nhà cung cấp (TQ)                    Công ty                                     Ngân hàng
 ┌─────────────────┐   HTTPS   ┌──────────────────────────┐   bước Flows   ┌──────────────────┐
 │ Trình duyệt +   │──────────▶│ Cổng đối tác             │───────────────▶│ Flygo Flows      │
 │ khoá FIDO2      │ WebAuthn  │ partner.<tên miền>       │  yêu cầu đã ký │ Duyệt (chế độ ký)│
 └─────────────────┘           │ (dịch vụ riêng, Rust)    │                │ passkey trên app │
                               │  ├ Sổ đăng ký (có ký)    │◀───────────────│                  │
                               │  └ Nhật ký chuỗi băm     │                └────────┬─────────┘
                               └───────────┬──────────────┘                         │ gói lệnh chi
                                           │ đầu chuỗi mỗi ngày                     ▼  (PDF + JSON)
                                           ▼                            ┌───────────────────────┐
                               Nơi neo ngoài (email Sếp,               │ Bộ kiểm tra độc lập    │
                               Drive khoá sửa, máy khác)               │ (máy kế toán trưởng)   │
                                                                       └──────────┬────────────┘
                                                                                  ▼ 2 người nhập + nhả
                                                                       ACB / VPB / OCB / SHB (token NH)
                                                                                  │
                                            MCP ngân hàng (chỉ đọc) ◀─────────────┘ đối soát tiền ra hằng ngày
```

### 3.1 Cổng đối tác (partner portal)

| Mục | Thiết kế |
|---|---|
| Chạy ở đâu | Dịch vụ riêng `flygo-partner` (Rust/axum, cùng kiểu Flows), container trên máy chủ ứng dụng, DB riêng (SQLite WAL), **không chung DB với Flows**. Flows gọi nó qua mạng nội bộ Docker |
| Truy cập từ Trung Quốc | Đề xuất `partner.congty.example` qua Cloudflare tunnel như hiện tại; cần thử từ TQ (Q8). Nếu chậm/chặn: một VPS Hồng Kông/Singapore làm reverse proxy. Đổi đường đi không ảnh hưởng khoá |
| RP ID (WebAuthn) | **Cố định mãi mãi**, đổi là mất hết khoá đã đăng ký. Đề xuất `congty.example` (cho phép mọi tên miền con dùng chung) hoặc `partner.congty.example` (chặt hơn). Sếp chọn (Q9) |
| Đăng nhập | **Chỉ WebAuthn** (khoá phần cứng). Không mật khẩu, không OTP SMS/email, không "quên khoá → gửi link" |
| Giao diện | Tiếng Trung giản thể + tiếng Anh. Không dùng JavaScript bên thứ ba, không CDN; CSP chặt, Subresource Integrity |
| Chức năng | Xem PI/đơn hàng đang mở, tạo yêu cầu thanh toán, xem trạng thái, đề nghị đổi tài khoản, phủ quyết, quản lý người đại diện (cần M-of-N), báo mất khoá |
| Người dùng nội bộ | Không đăng nhập cổng. Nội bộ ký trên app Flygo (mục 3.5) |

### 3.2 Sổ đăng ký đối tác (partner registry)

Sổ là **chuỗi mục chỉ thêm, có chữ ký** (không sửa, không xoá). Trạng thái hiện tại = tính lại từ chuỗi. DB chỉ là bộ đệm;
bộ kiểm tra độc lập tự tính lại từ chuỗi.

| Loại mục | Nội dung | Chữ ký bắt buộc | Hiệu lực |
|---|---|---|---|
| `root_init` | Bộ khoá gốc nội bộ (vd Sếp, kế toán trưởng, 1 người nữa), ngưỡng 2-of-3 | Tất cả người trong bộ gốc | Ngay; dấu vân tay in giấy, ghim vào bộ kiểm tra |
| `internal_signer_add` / `_revoke` | Người duyệt nội bộ, vai trò, hạn mức | 2 khoá gốc | Thêm: sau 24 giờ; thu hồi: ngay |
| `supplier_add` | Pháp nhân: tên pháp lý (中文 + EN), mã tín dụng xã hội thống nhất (统一社会信用代码), địa chỉ, ảnh giấy phép, hợp đồng khung | 2 người nội bộ | Ngay |
| `contact_add` / `_revoke` | Đầu mối: tên, chức vụ, điện thoại, email, WeChat ID (để **thông báo** và **gọi đối chiếu**) | Đăng ký lần đầu: 2 nội bộ sau nghi thức. Về sau: M khoá NCC + 2 nội bộ | Thêm: sau 7 ngày; thu hồi: ngay |
| `key_add` / `key_revoke` | Khoá FIDO2 của người đại diện: credential ID, khoá công khai, AAGUID, người giữ | Lần đầu: 2 nội bộ có mặt trong nghi thức. Về sau: M khoá NCC còn lại + 2 nội bộ | Thêm: 7 ngày (trừ nghi thức); thu hồi: **ngay**, một chữ ký bất kỳ (NCC hay nội bộ) |
| `account_add` | TK nhận: tên người hưởng, số TK/IBAN, ngân hàng, SWIFT, địa chỉ NH, nước, tiền tệ, tài liệu chứng minh | Lần đầu (trong nghi thức): 2 nội bộ + M khoá NCC. Về sau: như đổi tài khoản (mục 3.7) | 7 ngày, có phủ quyết |
| `account_retire` | Ngừng dùng TK | 1 khoá NCC hoặc 2 nội bộ | Ngay |
| `policy_set` | M-of-N của NCC, ngưỡng số tiền, thời gian chờ | 2 khoá gốc | Nới lỏng: sau 7 ngày; siết lại: ngay |

Quy tắc chung: **siết lại (thu hồi, ngừng, giảm hạn mức) thì dễ và ngay; nới ra (thêm khoá, thêm TK, tăng hạn mức) thì
khó và có thời gian chờ.**

Mỗi mục: `{seq, prev_hash, type, body, created_at, signatures: [{signer_key_id, webauthn...}]}`, `hash = SHA-256(...)`.

### 3.3 Định dạng chuẩn và ký ("thấy gì ký nấy")

**Định dạng chuẩn của yêu cầu** (JSON, chuẩn hoá theo RFC 8785 JCS: khoá xếp thứ tự, không khoảng trắng, số tiền là
chuỗi số nguyên đơn vị nhỏ nhất để không lệch số thực):

```json
{
  "v": 1,
  "type": "payment_request",
  "request_id": "PR-2026-000123",
  "supplier_id": "SUP-0007",
  "registry_head": "<hash mục sổ mới nhất lúc tạo>",
  "documents": [{"kind": "PI", "no": "HL-PI-2026-118", "sha256": "<hash tệp PI>"}],
  "amount_minor": "1250000",
  "currency": "USD",
  "payee": {
    "account_entry": "<hash mục account_add>",
    "beneficiary": "NINGBO XYZ ELEVATOR PARTS CO., LTD.",
    "account_no": "3901 2345 6789 0123 456",
    "bank": "BANK OF CHINA NINGBO BRANCH",
    "swift": "BKCHCNBJ92A",
    "country": "CN"
  },
  "purpose": "Payment for PI HL-PI-2026-118",
  "created_at": "2026-11-08T10:12:00+07:00",
  "expires_at": "2026-11-22T23:59:59+07:00",
  "nonce": "<16 byte ngẫu nhiên do máy chủ cấp>"
}
```

- `payee` vừa trỏ tới mục sổ (`account_entry`) vừa chép nguyên văn thông tin TK, để người ký thấy đúng cái họ ký và bộ
  kiểm tra so khớp hai phần.
- **Challenge WebAuthn** = `SHA-256("FLYGO-PAYREQ-v1\0" || JCS(request))`. Mỗi loại tài liệu có tiền tố riêng
  (`FLYGO-REGISTRY-v1`, `FLYGO-APPROVAL-v1`, `FLYGO-VETO-v1`) để chữ ký của loại này không dùng được cho loại khác.
- Luôn yêu cầu **user verification** (PIN hoặc vân tay trên khoá) và **user presence** (chạm khoá).
- Lưu nguyên văn `authenticatorData`, `clientDataJSON`, `signature`, `credentialId` để ai cũng kiểm lại được.
- Kiểm tra: chữ ký đúng khoá công khai trong sổ; `clientDataJSON.challenge` khớp hash tự tính; `origin` thuộc danh sách
  cho phép; `rpIdHash` khớp; cờ UP+UV bật; `request_id` chưa dùng (chống phát lại); chưa hết hạn; khoá còn hiệu lực
  tại `registry_head`.
- Bộ đếm chữ ký (sign counter) chỉ để cảnh báo (nhiều khoá FIDO2 mới luôn trả 0), không dùng làm điều kiện.

**Hiển thị trước khi ký** (cổng và app giống nhau):
- Số tiền bằng số và bằng chữ (tiếng Trung viết hoa kiểu 壹万贰仟伍佰美元 / tiếng Anh / tiếng Việt), tiền tệ to, rõ.
- TK nhận đầy đủ, chia nhóm 4 số, tên người hưởng, ngân hàng, SWIFT, nước, cờ "đã đăng ký từ ngày …".
- **Mã đối chiếu 8 ký tự** (từ hash, chữ dễ đọc, vd `K7Q2-XA9M`). Mã này hiện ở cổng, ở app người duyệt, trên gói lệnh
  chi và trong bộ kiểm tra. Ai thấy mã khác nhau là dừng.

Giới hạn cần nói thật: khoá FIDO2 **không có màn hình**, nên "thấy gì ký nấy" chỉ đúng khi máy và trang hiển thị trung
thực. Thiết kế bù lại bằng: (1) TK chỉ từ sổ nên tráo nội dung ít giá trị; (2) nhiều người ký trên nhiều thiết bị cùng
đối chiếu mã ngắn; (3) bộ kiểm tra độc lập hiển thị lại nội dung từ dữ liệu đã ký.

### 3.4 Kiểm tra trong Flows

Đề xuất **bước Duyệt có chế độ ký** thay vì bước mới hoàn toàn, để giữ một bước Duyệt duy nhất trong trình sửa:

```json
{ "id": "kt", "type": "approval_request", "name": "Kế toán trưởng ký duyệt",
  "approver": {"role": "ke_toan_truong"}, "mode": "all",
  "signed": { "doc": "{{steps.nhan.output.request}}", "min_signers": 2, "roles": ["ke_toan_truong", "giam_doc"] },
  "approve_to": "xuat_lenh" }
```

Thêm hai bước tự động (không có quyền ký, chỉ kiểm và xuất):

| Bước | Việc làm | Kết quả |
|---|---|---|
| `payreq_receive` (trigger từ cổng) | Nhận yêu cầu đã ký từ `flygo-partner`; Flows **kiểm lại** chữ ký và sổ (không tin cổng); đối chiếu PI với ERPNext (số tiền ≤ còn phải trả, chưa chi trùng) | `request`, `hash`, `code` (mã đối chiếu), `red_flags` |
| `payreq_export` | Gom yêu cầu + mọi chữ ký duyệt + đoạn sổ liên quan thành **gói lệnh chi** (JSON + PDF có mã QR); ghi nhật ký | `bundle_id`, `download_url`, `code` |

Quy tắc trong bước Duyệt có ký:
- Không có `editable` (sửa nội dung = phải tạo yêu cầu mới và nhà cung cấp ký lại).
- "Trả lại" vẫn được, nhưng lần nộp lại là yêu cầu mới, hash mới.
- Ủy quyền chỉ cho người cũng có khoá đã đăng ký và đúng vai trò (`delegation.role`).
- Ngưỡng: dưới ngưỡng 1 người ký; từ ngưỡng trở lên 2 người khác nhau ký trên 2 thiết bị khác nhau (credential khác
  nhau); quá ngưỡng cao thêm Sếp (Q5).
- Lint của Flows cấm `auto mcp` gọi tool ghi của ngân hàng trong quy trình có `payreq_*`.

### 3.5 Passkey người ký nội bộ trên app Flygo

| Mục | Thiết kế |
|---|---|
| Loại khoá | Ưu tiên **khoá phần cứng** (YubiKey NFC chạm vào điện thoại, hoặc cắm USB máy tính). Passkey trong điện thoại chỉ dùng dưới ngưỡng, nếu Sếp đồng ý (Q10) |
| Khoá đồng bộ đám mây | Passkey đồng bộ iCloud/Google có cờ `BE/BS` = 1; ai chiếm được tài khoản Apple/Google là có passkey. Chỉ chấp nhận khoá `BE = 0` cho mức ≥ ngưỡng |
| Cách làm trên app | Giai đoạn 1 dùng lại cách thẻ `kind: passkey` đã có: app mở trang ký trên `partner.<tên miền>/sign/<id>` trong trình duyệt hệ thống (WebAuthn chạy ổn trên Android/iOS/Windows/macOS). Về sau có thể gọi API passkey gốc (Android Credential Manager, iOS ASAuthorization) với cùng RP ID, cần file `assetlinks.json` / `apple-app-site-association` |
| Nội dung ký | `FLYGO-APPROVAL-v1` trên `{request_hash, decision, signer, role, at, comment_hash}` |
| Đăng ký khoá nội bộ | Trực tiếp với 2 người trong bộ gốc, mục `internal_signer_add` |

### 3.6 Nhật ký chuỗi băm

- Mọi sự kiện (yêu cầu, chữ ký, quyết định, xuất lệnh, mục sổ, phủ quyết, thu hồi) nối thành chuỗi:
  `hash_n = SHA-256(hash_{n-1} || JCS(event_n))`.
- **Neo ra ngoài mỗi ngày**: đầu chuỗi (seq + hash) gửi tới (a) email Sếp và kế toán trưởng, (b) một tệp trên Google
  Drive có khoá lưu giữ (Vault retention) hoặc máy chủ nội bộ, (c) tuỳ chọn OpenTimestamps. Ai sửa lịch sử thì đầu chuỗi
  không khớp với bản đã neo.
- Bộ kiểm tra tải chuỗi và kiểm từ đầu tới đầu chuỗi đã neo gần nhất.
- Bảng `events` hiện có của Flows giữ nguyên; thêm cột `prev_hash`, `hash` cho luồng có `payreq_*` (hoặc cho mọi luồng,
  chi phí nhỏ).

### 3.7 Đổi tài khoản nhận

| Bước | Ai | Ghi chú |
|---|---|---|
| 1. Đề nghị | Một người đại diện NCC trên cổng, ký bằng khoá | Nhập TK mới **chỉ ở đây**, kèm thư có dấu 公章 (scan) và giấy xác nhận TK của ngân hàng (开户证明) |
| 2. Ký đủ M-of-N phía NCC | Các người đại diện còn lại, mỗi người trên khoá của mình | Đề nghị hết hạn sau 14 ngày nếu chưa đủ |
| 3. Kiểm tra cờ đỏ | Hệ thống + kế toán | Bảng mục 4.6. Có cờ đỏ thì bắt buộc nghi thức lại |
| 4. Gọi đối chiếu | Nhân viên mua hàng **gọi ra** số trong sổ (không phải số trong đề nghị), ghi âm, ghi biên bản | Ghi kết quả vào sổ, có chữ ký của người gọi |
| 5. 2 người nội bộ ký | Hai khoá nội bộ khác nhau, ít nhất một người thuộc bộ gốc | |
| 6. Thời gian chờ 7 ngày | Tự động | Báo **mọi** đầu mối và mọi khoá đã đăng ký qua email + WeChat (nếu có) + thông báo trên cổng; báo cả nội bộ. Ai có khoá (NCC hay nội bộ) bấm **Phủ quyết** là huỷ |
| 7. Hiệu lực | Tự động | TK cũ vẫn dùng được trong lúc chờ (nhà cung cấp không bị kẹt thanh toán) |
| 8. Lần chi đầu tới TK mới | Kế toán | Tuỳ chọn: hạn mức lần đầu (vd ≤ 10.000 USD) hoặc chờ NCC xác nhận đã nhận tiền |

### 3.8 Xuất lệnh chi và tích hợp ngân hàng (Flows không chuyển tiền)

- Gói lệnh chi = JSON (yêu cầu + chữ ký + đoạn sổ + đường dẫn chuỗi) + PDF in được: số tiền bằng số và chữ, TK, mã đối
  chiếu, QR chứa hash gói.
- Người lập lệnh (maker) nhập vào internet banking từ gói (hoặc tải file lô nếu ngân hàng hỗ trợ), người duyệt lệnh
  (checker) mở **bộ kiểm tra độc lập**, quét QR / mở gói, so từng trường với màn hình ngân hàng, rồi mới nhả bằng token.
- Người duyệt trong Flows **không được** là người nhả lệnh ở ngân hàng (phân tách nhiệm vụ).
- **Đối soát hằng ngày**: bank-notify / MCP ngân hàng (đọc) lấy giao dịch Nợ; mỗi khoản chi ra nước ngoài hoặc trên
  ngưỡng phải khớp một gói lệnh chi (số tiền, TK nhận). Không khớp → báo ngay Sếp và kế toán trưởng.
- MCP ngân hàng giữ **chỉ đọc**; Flows config giữ "không cho tool ghi"; ContextForge không đăng ký tool chuyển tiền.

### 3.9 Bộ kiểm tra độc lập (verifier)

- Một trang HTML tĩnh chạy offline (hoặc CLI) được build lại và **ký phát hành**; cài trên máy kế toán trưởng và người
  nhả lệnh, không tải code từ máy chủ lúc chạy.
- Ghim sẵn dấu vân tay bộ khoá gốc (đối chiếu với bản in giấy cất két).
- Đầu vào: gói lệnh chi + chuỗi sổ + đầu chuỗi đã neo. Đầu ra: ✅/❌, hiển thị lại số tiền, TK, mã đối chiếu, danh sách
  người ký, ngày TK được đăng ký, cờ đỏ.
- Mã nguồn nhỏ, tách repo con hoặc thư mục riêng, để kiểm toán dễ.

## 4. Vòng đời khoá

### 4.1 Nghi thức đăng ký nhà cung cấp (một lần)

| # | Việc | Người làm | Bằng chứng lưu |
|---|---|---|---|
| 1 | Xác minh pháp nhân trên Qichacha / 国家企业信用信息公示系统: tên pháp lý, mã tín dụng, người đại diện pháp luật, tình trạng | Mua hàng | Ảnh chụp kết quả, ngày tra |
| 2 | Hẹn lịch video (hoặc gặp trực tiếp khi đi công tác) qua kênh **đã biết từ trước** (số trong hợp đồng cũ), không qua liên lạc mới | Mua hàng + 1 người bộ gốc | Biên bản |
| 3 | Gửi trước khoá FIDO2 (công ty mua, chuyển phát) hoặc NCC tự mua mẫu trong danh sách | Mua hàng | Số seri khoá |
| 4 | Trong buổi video: mỗi người đại diện (≥ 2 người, nên có lãnh đạo/kế toán NCC) mở link đăng ký **dùng một lần, hết hạn 30 phút**, cắm khoá, đặt PIN, đăng ký 2 khoá (chính + dự phòng) | NCC, nội bộ chứng kiến | Credential ID, AAGUID, ảnh màn hình mã đối chiếu đọc to |
| 5 | Kiểm tra AAGUID trong danh sách cho phép, `BE = 0` | Hệ thống | |
| 6 | Đăng ký TK nhận: đối chiếu với hợp đồng, PI cũ, lịch sử chi đã thành công, 开户证明 | Kế toán | Tệp đính kèm, hash |
| 7 | NCC gửi **mẫu đăng ký có dấu 公章** (song ngữ, liệt kê người đại diện, khoá theo seri, TK) qua chuyển phát | NCC | Bản gốc cất hồ sơ, scan lưu hash vào sổ |
| 8 | 2 người nội bộ ký mục `supplier_add`, `contact_add`, `key_add`, `account_add` | Nội bộ | Chữ ký trong sổ |
| 9 | Chạy thử: NCC tạo một yêu cầu thử (số tiền 0, loại `test`) | NCC | |

### 4.2 Mất hoặc bị lấy khoá

- Người giữ báo (trên cổng bằng khoá dự phòng, hoặc báo qua bất kỳ kênh nào) → **thu hồi ngay**. Thu hồi là thao tác
  siết lại, nên một chữ ký nội bộ là đủ, và cũng chấp nhận báo không có chữ ký (tệ nhất là thu hồi nhầm, chỉ phiền chứ
  không mất tiền).
- Thêm khoá thay thế: M khoá NCC còn lại + 2 nội bộ + 7 ngày; hoặc làm lại nghi thức.
- Nếu NCC chỉ còn dưới M khoá: tạm dừng yêu cầu mới của NCC đó, làm lại nghi thức video + mẫu có dấu.

### 4.3 Nhân sự nghỉ việc

| Phía | Việc |
|---|---|
| Nhà cung cấp | NCC báo bằng khoá người khác; nội bộ thu hồi khoá và đầu mối ngay; nếu dưới M người thì bổ sung như 4.2. Hợp đồng ghi nghĩa vụ báo trong 3 ngày làm việc |
| Nội bộ | Thu hồi trong ngày nghỉ (checklist nghỉ việc), thu lại khoá vật lý, đổi người nhả lệnh ở ngân hàng, rà các luồng đang chờ người đó ký |
| Người trong bộ gốc | Thay bằng 2 khoá gốc còn lại + 7 ngày; in lại dấu vân tay bộ gốc, cập nhật bộ kiểm tra |

### 4.4 Thay khoá định kỳ, khôi phục

- Khoá FIDO2 không cần thay theo lịch; rà soát mỗi năm: khoá nào 12 tháng không dùng thì hỏi lại, mẫu khoá có lỗ hổng
  công bố thì thay.
- Mỗi người có **2 khoá** (chính + dự phòng, cất riêng). Không có "khôi phục" bằng email, SMS hay câu hỏi bí mật. Khôi
  phục = khoá dự phòng, hoặc M-of-N + thời gian chờ, hoặc làm lại nghi thức. Đây là chủ ý, vì mọi đường khôi phục dễ
  dàng đều là đường cho kẻ gian.
- Bộ gốc: 3 người, 2-of-3; mỗi người 2 khoá; một bộ khoá dự phòng niêm phong trong két ngân hàng (tuỳ chọn).

### 4.5 Kiểm soát kép tại ngân hàng (Giai đoạn 0)

- Bật maker/checker trên ACB ONE BIZ, VPBank NEOBiz, OCB, Shinhan cho mọi lệnh chi; checker ≠ người duyệt trong Flows.
- Dùng danh bạ người hưởng của ngân hàng (nếu có), thêm người hưởng mới cũng cần 2 người.
- Đặt hạn mức theo giao dịch/ngày; token ngân hàng của checker giữ riêng, không dùng chung máy.
- Việc này Sếp/kế toán làm với ngân hàng, em không đụng (Q6).

### 4.6 Cờ đỏ (tự động gắn, buộc xem xét thêm)

| Cờ | Ví dụ |
|---|---|
| Nước của ngân hàng nhận khác nước pháp nhân | NCC Trung Quốc, TK Hồng Kông / Singapore / nước thứ ba |
| Tên người hưởng không khớp tên pháp lý | Thiếu "CO., LTD.", tên cá nhân, tên công ty thương mại khác |
| TK cá nhân | Không có 公司 / LIMITED |
| Từ khoá áp lực trong nội dung kèm theo | urgent, audit, 账户变更, 审计, 新账户, "account under review" |
| TK mới < 30 ngày, hoặc yêu cầu đầu tiên tới TK mới | |
| Số tiền khác PI, PI đã chi đủ, PI mới chưa có trong ERP | |
| Thời điểm bất thường | Ngay trước Tết, cuối tuần, ngoài giờ làm việc của NCC |

## 5. Vận hành

### 5.1 Khoá phần cứng nên mua (giá tham khảo, cần kiểm lại khi mua)

| Mẫu | Cho ai | Ghi chú | Giá tham khảo |
|---|---|---|---|
| Feitian ePass FIDO2 (K9/A4B, USB-A/C + NFC) | Nhà cung cấp TQ | Hãng Trung Quốc (飞天诚信), mua dễ trên JD/Taobao, FIDO2 certified, có PIN | ¥150–250 (~0,6–0,9 tr đ) |
| Feitian BioPass K27 (vân tay) | NCC nếu muốn tiện | Vân tay thay PIN | ¥400–550 |
| Yubico Security Key NFC (FIDO2) | Nội bộ, đa số | Chạm NFC vào điện thoại Android/iPhone, cắm USB-C/A | ~29 USD (~0,8 tr đ) |
| YubiKey 5C NFC | Bộ gốc, quản trị Workspace/Cloudflare | Thêm OTP, PIV; dùng cho Google Advanced Protection | ~55 USD (~1,5 tr đ) |

Ước tính: 10 NCC × 3 người × 2 khoá ≈ 60 khoá Feitian ≈ 45 tr đ; nội bộ 8 người × 2 khoá ≈ 16 khoá ≈ 15–20 tr đ. Sếp
chọn công ty mua và gửi (kiểm soát được mẫu, AAGUID) hay để NCC tự mua theo danh sách (Q11).

### 5.2 Đào tạo

- Nội bộ (1 buổi 1 giờ + bài kiểm tra ngắn): "kênh liên lạc không mang quyền", không có ngoại lệ, kể cả lệnh từ Sếp
  qua chat; cách đối chiếu mã 8 ký tự; cách phủ quyết; cách báo mất khoá; gọi đối chiếu luôn gọi số trong sổ.
- NCC (tài liệu 1 trang tiếng Trung + video ngắn): cách tạo yêu cầu, cách ký, "Công ty sẽ không bao giờ yêu cầu bạn gửi số
  tài khoản qua email/WeChat", cách đề nghị đổi TK.
- Diễn tập mỗi 6 tháng: gửi một email giả "đổi TK" có kiểm soát cho phòng mua hàng/kế toán.

### 5.3 Điều khoản hợp đồng

**Tiếng Việt**
> Điều X. Tài khoản thanh toán. Bên Mua chỉ thanh toán vào tài khoản đã được hai Bên đăng ký trên Cổng đối tác của
> Bên Mua theo thủ tục đăng ký đã thống nhất. Mọi thay đổi tài khoản chỉ có hiệu lực khi (i) được đề nghị và ký điện tử
> trên Cổng đối tác bằng khoá bảo mật đã đăng ký của số người đại diện theo quy định, (ii) kèm văn bản sửa đổi có đóng
> dấu pháp nhân của Bên Bán, (iii) được Bên Mua xác nhận bằng cuộc gọi thoại hoặc video tới đầu mối đã đăng ký, và
> (iv) sau thời gian chờ bảy (07) ngày. Thông báo thay đổi tài khoản qua email, tin nhắn, điện thoại hoặc trên hoá đơn,
> PI không có giá trị. Khoản thanh toán Bên Mua đã chuyển vào tài khoản đã đăng ký được coi là đã thanh toán hợp lệ.

**English**
> Article X. Payment account. The Buyer shall pay only into an account registered by both Parties on the Buyer's
> Partner Portal under the agreed registration procedure. A change of account takes effect only if (i) it is requested
> and electronically signed on the Partner Portal with the registered security keys of the required number of
> representatives, (ii) it is accompanied by a written amendment bearing the Seller's company seal, (iii) the Buyer
> confirms it by a voice or video call to a registered contact, and (iv) a waiting period of seven (7) days has
> elapsed. Notices of account changes by email, messaging, telephone, or on invoices or proforma invoices have no
> effect. Any payment made by the Buyer into a registered account constitutes valid payment.

**中文**
> 第X条 收款账户。买方仅向双方按约定登记程序在买方合作伙伴门户上登记的账户付款。收款账户的变更仅在同时满足以下条件时
> 生效：（一）由规定人数的代表在合作伙伴门户上使用已登记的安全密钥提出并电子签署；（二）附有加盖卖方公章的书面变更函；
> （三）买方通过语音或视频电话向已登记的联系人确认；（四）经过七（7）天的等待期。通过电子邮件、即时通讯、电话或在发票、
> 形式发票（PI）上发出的账户变更通知均属无效。买方向已登记账户支付的款项视为有效付款。

(Nên nhờ luật sư rà lại trước khi dùng, nhất là luật áp dụng và trọng tài trong hợp đồng hiện có.)

### 5.4 Gia cố Google Workspace

| Việc | Cách làm trong Admin console | Ghi chú |
|---|---|---|
| Bắt buộc khoá bảo mật cho tài chính, mua hàng, quản trị | Security → 2-Step Verification → Enforcement, "Only security key" cho OU Tài chính/Quản trị | Đăng ký khoá trước rồi mới bật |
| Advanced Protection cho Sếp, kế toán trưởng, admin | Security → Advanced Protection Program | Chặn ứng dụng OAuth lạ |
| Chặn tự chuyển tiếp ra ngoài | Apps → Gmail → End User Access → Automatic forwarding: tắt | Kẻ BEC hay đặt rule chuyển tiếp |
| Rà rule/bộ lọc và uỷ quyền hộp thư hiện có | Gmail log search, Alert center | Kiểm tra dấu vết vụ cũ còn sót |
| Cảnh báo email từ ngoài | Gmail → End User Access → Warn for external recipients; Safety → banner thư bên ngoài | |
| Chống giả mạo tên miền giống | Gmail → Safety → Spoofing and authentication: bật tất cả (similar domain names, employee names, unauthenticated) → đưa vào spam/cách ly | |
| Chặn ứng dụng OAuth bên thứ ba | Security → API controls → chỉ cho app trong danh sách | Lừa cấp quyền OAuth là đường BEC phổ biến |
| Tắt mật khẩu ứng dụng, IMAP/POP nếu không dùng | Security, Gmail End User Access | |
| Thời hạn phiên | Google session control: 12–24 giờ cho OU Tài chính | |
| Mua tên miền giống | congty.example.vn, congtyexample.com, c0ngty.example … ; theo dõi đăng ký mới (dnstwist, cảnh báo cert transparency) | |

**Lộ trình DMARC cho `congty.example`** (hiện: SPF `~all`, DKIM có, chưa có DMARC):

| Tuần | Bản ghi | Việc |
|---|---|---|
| 0 | Kiểm DKIM đang ký thư (Admin → Gmail → Authenticate email: trạng thái "Authenticating") | Liệt kê mọi hệ thống gửi thư thay tên miền (ERPNext, mInvoice, phần mềm kế toán, website, Mattermost) |
| 1 | `_dmarc` TXT `v=DMARC1; p=none; rua=mailto:dmarc@congty.example; fo=1` | Thu báo cáo (dùng dịch vụ đọc báo cáo miễn phí hoặc hộp thư riêng) |
| 2–3 | Sửa SPF/DKIM cho các nguồn hợp lệ còn thiếu; SPF đổi `~all` → `-all` khi đủ | |
| 4 | `p=quarantine; pct=25` → `pct=100` | |
| 6 | `p=reject; sp=reject; adkim=s; aspf=s` | Kèm tên miền con. Thêm BIMI tuỳ chọn |

### 5.5 Theo dõi hằng ngày

- Báo cáo tự động mỗi sáng (Flow Bot DM Sếp + kế toán trưởng): yêu cầu mới, đổi TK đang chờ, cờ đỏ, khoản chi không khớp
  gói lệnh, đầu chuỗi nhật ký.
- Cảnh báo ngay: phủ quyết, thu hồi khoá, đăng nhập cổng thất bại nhiều lần, kiểm tra chữ ký sai, đối soát lệch.

### 5.6 Khi hệ thống không chạy

- Không có "chế độ khẩn cấp bỏ qua chữ ký". Nếu cổng/Flows hỏng: chi theo quy trình giấy, **chỉ tới TK đã có trong sổ**
  (bản in danh sách TK có chữ ký 2 người bộ gốc, in lại mỗi khi sổ đổi), 2 người ký giấy + kiểm soát kép ở ngân hàng.

## 6. Kế hoạch theo giai đoạn

Ước tính công em làm (code + test + tài liệu); thời gian thực tế còn tuỳ lịch NCC và ngân hàng.

| Giai đoạn | Nội dung | Ai làm | Ước tính | Kết quả |
|---|---|---|---|---|
| **0. Không code** | Gia cố Workspace (5.4), DMARC p=none ngay rồi tăng dần; bật maker/checker + danh bạ người hưởng + hạn mức ở 4 ngân hàng; điều khoản hợp đồng (luật sư rà); lập **danh sách TK nhận** hiện tại từ lịch sử chi đã thành công (có thể dùng MCP ngân hàng đọc giao dịch Nợ 12–24 tháng); quy định nội bộ "không đổi TK qua email/chat"; mua khoá | Admin Workspace, kế toán, Sếp; em soạn checklist và danh sách | 1–2 tuần lịch, ~3 ngày công em | Chặn ngay phần lớn rủi ro BEC |
| **1. Sổ đăng ký + duyệt có ký nội bộ** | Dịch vụ `flygo-partner` (sổ có ký, chuỗi băm, neo hằng ngày); đăng ký khoá nội bộ + bộ gốc; Duyệt chế độ `signed` trong Flows; trang ký WebAuthn (mở từ app); `payreq_export` + gói lệnh chi PDF/JSON; bộ kiểm tra độc lập; đối soát tiền ra hằng ngày; nhập danh sách TK từ Giai đoạn 0 (ký bởi 2 người bộ gốc) | Em | 3–4 tuần | Lệnh chi nội bộ có chữ ký, chỉ tới TK trong sổ |
| **2. Cổng đối tác, yêu cầu có ký** | Cổng ZH/EN, đăng nhập WebAuthn; nghi thức đăng ký (link dùng một lần); tạo yêu cầu từ PI (đọc ERPNext), chọn TK trong sổ; `payreq_receive` trong Flows; cờ đỏ; thử truy cập từ TQ; làm nghi thức với 1–2 NCC thí điểm | Em + mua hàng | 3–4 tuần + lịch NCC | NCC thí điểm gửi yêu cầu có ký |
| **3. Đổi TK đa chữ ký + thời gian chờ** | Đề nghị đổi TK, M-of-N, gọi đối chiếu có biên bản, 7 ngày chờ, thông báo mọi đầu mối, phủ quyết; thêm/bớt người đại diện; hạn mức lần chi đầu | Em | 2 tuần | Đủ mô hình |
| **4. (Sau)** | API passkey gốc trong app; mở rộng NCC trong nước; kiểm thử xâm nhập bên ngoài; kiểm toán mã bộ kiểm tra | Em + bên ngoài | 1–2 tuần + chi phí pentest | |

Tổng phần code: khoảng **8–10 tuần công** của em cho Giai đoạn 1–3.

Phụ thuộc: Giai đoạn 1 cần chọn RP ID và tên miền cổng (Q9); Giai đoạn 2 cần khoá đã mua và NCC thí điểm.

## 7. Câu hỏi cần Sếp trả lời

| # | Câu hỏi | Ảnh hưởng |
|---|---|---|
| Q1 | Có khoảng bao nhiêu NCC Trung Quốc đang chi thường xuyên? Bao nhiêu NCC chiếm 80% số tiền? | Số khoá, thứ tự làm nghi thức |
| Q2 | Danh sách TK nhận hiện nằm ở đâu (ERPNext, Excel, danh bạ ngân hàng, email)? | Nguồn để lập sổ ban đầu |
| Q3 | Ai là admin Google Workspace? Công ty có tên miền email nào khác ngoài `congty.example`? | Gia cố Giai đoạn 0 |
| Q4 | Bộ khoá gốc gồm những ai (đề xuất: Sếp, kế toán trưởng, 1 người nữa; 2-of-3)? | Gốc tin cậy của cả hệ thống |
| Q5 | Ngưỡng: dưới bao nhiêu 1 người ký, từ bao nhiêu 2 người, từ bao nhiêu cần Sếp? (gợi ý 5.000 / 50.000 USD) | Cấu hình Duyệt |
| Q6 | Mỗi ngân hàng hiện có bật maker/checker, danh bạ người hưởng, hạn mức chưa? Ai giữ token nhả lệnh? | Lớp chặn cuối |
| Q7 | NCC trong nước có áp dụng không, hay chỉ NCC nước ngoài? | Phạm vi |
| Q8 | Có NCC/nhân viên nào ở TQ thử giúp truy cập `*.congty.example` không? | Cần VPS HK hay không |
| Q9 | RP ID: `congty.example` hay `partner.congty.example`? (đổi về sau = đăng ký lại toàn bộ khoá) | Không đổi được về sau |
| Q10 | Người duyệt nội bộ dưới ngưỡng có được dùng passkey trong điện thoại, hay bắt buộc khoá phần cứng cho mọi mức? | Mua bao nhiêu khoá nội bộ |
| Q11 | Công ty mua và gửi khoá cho NCC, hay NCC tự mua theo danh sách mẫu? | Chi phí, kiểm soát AAGUID |
| Q12 | M-of-N cho NCC: 2-of-2 hay 2-of-3? Thời gian chờ đổi TK 7 ngày có ổn không? | Chính sách |
| Q13 | Có đồng ý quy tắc "không ngoại lệ, kể cả lệnh trực tiếp của Sếp" không? | Kẻ gian hay giả danh lãnh đạo |
| Q14 | Đăng nhập cổng có cần bản tiếng Việt cho NCC Việt Nam không? | Giao diện |
