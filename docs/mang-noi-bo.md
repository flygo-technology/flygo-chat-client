# Mạng nội bộ (thiết kế cũ, chưa làm)

Mạng nội bộ (trước đây gọi là "Bảng tin") là một app trong Flygo Chat, giống mạng xã hội nội bộ: mọi người trong nhóm làm việc (team) đăng bài viết, thả cảm xúc, bình luận và trả lời bình luận. Toàn bộ dữ liệu là **tin nhắn của máy chủ chat**: bài viết, bình luận, cảm xúc đều là post / reaction bình thường trong một kênh riêng.

> Trạng thái: **mới thiết kế, chưa làm**. Tài liệu này ghi lại kết quả nghiên cứu để làm sau.

- **Không cần plugin hay đổi cấu hình máy chủ.** Trên chat.flygo.vn (bản 11.11) vai trò `team_user` có sẵn `create_public_channel`, `join_public_channels`; `channel_user` có `create_post`, `add_reaction`. App tự tạo và tham gia kênh.
- **Tương thích ngược:** app cũ và các ứng dụng chat khác vẫn thấy kênh "Bảng tin" như một kênh thường: bài viết là tin có chữ và tệp đính kèm, bình luận là trả lời trong luồng.

## 1. Yêu cầu

- Đăng bài: chữ, một ảnh, một video, nhiều ảnh / video, chữ trên nền màu (nhiều màu, chuyển sắc).
- Cảm xúc nhiều loại (Thích, Yêu thích, Haha, Wow, Buồn, Phẫn nộ), mỗi người một cảm xúc trên một bài.
- Bình luận bằng chữ, ảnh, video; trả lời bình luận; thả cảm xúc cho bình luận.

## 2. Kênh Bảng tin

Mỗi team một kênh **công khai**:

| Trường | Giá trị |
|---|---|
| `name` | `bang-tin` |
| `display_name` | `Bảng tin` |
| `header` | `[flygo-feed]` (mốc kỹ thuật, ẩn khi hiển thị như các mốc `[flygo-…]` khác) |
| `type` | `O` |

`MmChannel.isFeed` = `name == 'bang-tin'` hoặc header có `[flygo-feed]`.

**Tìm / tạo kênh** (lần đầu mở app Bảng tin):

1. `GET /teams/{team_id}/channels/name/bang-tin`.
2. 404: `POST /channels` với các trường trên. Hai người cùng tạo một lúc thì người sau bị lỗi trùng tên: đọc lại bước 1.
3. Chưa là thành viên: `POST /channels/{id}/members` (cần là thành viên mới đăng bài, thả cảm xúc được).
4. Vừa tham gia: `PUT /channels/{id}/members/{me}/notify_props` với `{"desktop": "mention", "push": "mention"}` để bài mới không đổ thông báo như tin chat.

Tham gia kênh công khai sinh tin hệ thống "X đã vào kênh": Bảng tin bỏ qua mọi tin `system_*`.

**Ẩn khỏi Chat:** kênh `isFeed` không hiện trong danh sách chat (`AppState.chats`), không tải tin mới trong `syncAll` (`_fetchNewer`), không bật cửa sổ thông báo / tin khẩn / tin quan trọng trong `_onPosted` (trừ khi có @nhắc tên mình).

## 3. Mô hình dữ liệu

### 3.1 Bài viết

Tin gốc (`root_id` rỗng) trong kênh Bảng tin:

```json
{
  "channel_id": "<kênh bang-tin>",
  "message": "Chúc mừng team kinh doanh vượt chỉ tiêu tháng 11!",
  "file_ids": ["<ảnh 1>", "<ảnh 2>", "<video>"],
  "props": {
    "flygo_feed": {"v": 1, "bg": "sunset"}
  }
}
```

- `message`: nội dung chữ (markdown như chat).
- `file_ids`: tối đa **10** ảnh / video (giới hạn số tệp mỗi tin của máy chủ). Tệp lớn tải theo phần qua `/uploads` (đã có `MmApi.uploadPath`), giới hạn mỗi tệp theo `FileSettings.MaxFileSize` (homelab: 100 MB).
- `props.flygo_feed.bg`: mã màu nền, **chỉ dùng cho bài chỉ có chữ, tối đa 150 ký tự**. Không có `bg`, mã lạ, hoặc bài có tệp: hiện chữ thường.
- `props.flygo_feed.v`: phiên bản định dạng, hiện là `1`.

Bảng màu nền định nghĩa trong app (thêm mã mới không làm hỏng app cũ: app cũ hiện chữ thường):

| Mã | Kiểu | Màu |
|---|---|---|
| `blue` | đơn sắc | `#1877F2` |
| `red` | đơn sắc | `#E53935` |
| `green` | đơn sắc | `#2E7D32` |
| `purple` | đơn sắc | `#7B1FA2` |
| `black` | đơn sắc | `#212121` |
| `sunset` | chuyển sắc | `#FF5F6D` → `#FFC371` |
| `ocean` | chuyển sắc | `#2193B0` → `#6DD5ED` |
| `forest` | chuyển sắc | `#11998E` → `#38EF7D` |
| `violet` | chuyển sắc | `#8E2DE2` → `#4A00E0` |
| `peach` | chuyển sắc | `#ED4264` → `#FFEDBC` |
| `night` | chuyển sắc | `#0F2027` → `#2C5364` |
| `candy` | chuyển sắc | `#FC466B` → `#3F5EFB` |

Chữ trên nền màu: trắng, đậm, cỡ lớn, căn giữa, khung vuông (tỉ lệ ~ 1:1 trên điện thoại).

### 3.2 Cảm xúc

Reaction của máy chủ chat với bộ emoji cố định:

| Loại | `emoji_name` | Hiện |
|---|---|---|
| Thích | `+1` | 👍 |
| Yêu thích | `heart` | ❤️ |
| Haha | `laughing` | 😆 |
| Wow | `open_mouth` | 😮 |
| Buồn | `cry` | 😢 |
| Phẫn nộ | `rage` | 😡 |

- Mỗi người **một** cảm xúc trên một bài / bình luận: chọn loại khác thì gỡ loại cũ (như `AppState.toggleReaction`), bấm lại đúng loại đang chọn thì gỡ.
- Thả: `POST /reactions`; gỡ: `DELETE /users/{me}/posts/{post}/reactions/{emoji}`.
- Cảm xúc khác do ứng dụng khác thả vẫn được đếm và hiện (dùng ảnh emoji chung của app).
- Dòng tổng: tối đa 3 emoji nhiều nhất + tổng số người; bấm vào mở danh sách ai thả gì (dùng lại `showReactionDetails`).

### 3.3 Bình luận

Trả lời trong luồng của bài: `root_id` = id bài viết, có `message` và / hoặc `file_ids` (ảnh, video).

### 3.4 Trả lời bình luận

Luồng của máy chủ chat là phẳng (một tầng), nên trả lời bình luận vẫn là trả lời trong luồng của bài, thêm mốc:

```json
{
  "root_id": "<id bài viết>",
  "message": "@lan đồng ý!",
  "props": {"flygo_reply_to": "<id bình luận>"}
}
```

- App hiện **một tầng lồng**: trả lời nằm dưới bình luận được trả lời.
- Trả lời một câu trả lời: `flygo_reply_to` trỏ về **bình luận gốc** (tầng 1), nội dung bắt đầu bằng `@tên` người được trả lời.
- `flygo_reply_to` trỏ tới bình luận đã xoá / không tìm thấy: hiện như bình luận thường.
- Ứng dụng khác thấy mọi bình luận và trả lời trong cùng một luồng, theo thứ tự thời gian.

### 3.5 Sửa, xoá

- Sửa nội dung bài / bình luận của mình: `PUT /posts/{id}/patch` (giữ nguyên `props.flygo_feed`, cho đổi màu nền).
- Xoá: `DELETE /posts/{id}`. Xoá bài thì máy chủ xoá cả luồng bình luận. Quản trị viên kênh / hệ thống xoá được bài của người khác (máy chủ tự kiểm tra quyền; app hiện nút khi `AppState.canManage`).

## 4. API dùng

| Việc | Gọi |
|---|---|
| Danh sách bài (chỉ tin gốc, mới nhất trước) | `GET /channels/{id}/posts?collapsedThreads=true&collapsedThreadsExtended=false&per_page=20[&before=<id bài cuối>]` |
| Một bài | `GET /posts/{id}` |
| Bình luận của bài | `GET /posts/{id}/thread` (theo trang với `perPage`, `fromCreateAt` khi luồng dài) |
| Đăng bài / bình luận | `POST /posts` |
| Tải tệp | `POST /files`, `POST /uploads` + `/uploads/{id}` (tệp lớn) |
| Ảnh xem trước / gốc | `/files/{id}/preview`, `/files/{id}/thumbnail`, `/files/{id}` |
| Cảm xúc | `POST /reactions`, `DELETE /users/{me}/posts/{post}/reactions/{emoji}` |
| Sửa / xoá | `PUT /posts/{id}/patch`, `DELETE /posts/{id}` |

Đã thử trên chat.flygo.vn: `collapsedThreads=true` chỉ trả tin gốc, mỗi tin có `reply_count` (số bình luận) và `metadata.reactions`, `metadata.files` (không cần gọi thêm).

**Thời gian thực** qua WebSocket sẵn có. Thêm vào `AppState` một luồng sự kiện phát lại (`Stream<WsEvent>`), Bảng tin nghe các sự kiện của kênh mình:

| Sự kiện | Xử lý |
|---|---|
| `posted` | tin gốc: chèn đầu danh sách (hoặc hiện nút "N bài mới" khi đang cuộn); trả lời: tăng `reply_count`, thêm vào luồng nếu đang mở |
| `post_edited` | thay nội dung |
| `post_deleted` | bỏ bài / bình luận |
| `reaction_added`, `reaction_removed` | cập nhật cảm xúc của bài hoặc bình luận |

Ghi chú: `AppState._applyReaction` hiện chỉ cập nhật kho tin chat (`_posts`), không cập nhật luồng (`_threads`), nên Bảng tin giữ kho riêng thay vì dùng lại kho chat.

## 5. Giao diện

### 5.1 Mở app

- **Máy tính:** ô "Bảng tin" ở mục Chính của Trang chủ; mở thành tab (`kDeskTabApps` thêm `'feed'`, `_appItems`, `_appPageBody`). Nội dung rộng tối đa ~ 680 px ở giữa như Facebook.
- **Điện thoại:** ô "Bảng tin" trong lưới ứng dụng (tab Bạn), mở trang mới.
- Số trên ô: số bài mới từ lần xem cuối (`total_msg_count_root` của kênh trừ `msg_count_root` của mình); mở Bảng tin là đánh dấu đã xem (`POST /channels/members/me/view`).

### 5.2 Trang Bảng tin

- Đầu trang: ảnh đại diện + ô "Bạn đang nghĩ gì?", nút Ảnh / Video. Bấm mở trang soạn bài.
- Danh sách thẻ bài, cuộn vô hạn (20 bài mỗi lần), kéo xuống để tải lại.
- Thẻ bài:
  - Đầu thẻ: ảnh đại diện, tên, thời gian ("5 phút", "Hôm qua lúc 14:20"), menu ⋯ (Sửa, Xoá, Sao chép chữ, Báo cáo).
  - Nội dung: chữ (dài thì "Xem thêm"), hoặc khung chữ nền màu.
  - Lưới ảnh / video kiểu Facebook: 1 tệp hiện theo tỉ lệ thật (giới hạn 0.6 – 1.9); 2 tệp hai ô cạnh nhau; 3 tệp một lớn + hai nhỏ; 4 tệp lưới 2×2; 5 tệp trở lên hiện 4 ô, ô cuối phủ "+N". Video có biểu tượng ▶ và thời lượng.
  - Dòng tổng: emoji cảm xúc + số người ở trái, "N bình luận" ở phải.
  - Hai nút: **Thích** (hiện cảm xúc mình đã chọn với màu tương ứng) và **Bình luận**.
- Chọn cảm xúc: nhấn giữ nút Thích (điện thoại) hoặc rê chuột lên nút (máy tính) hiện thanh 6 emoji nổi, có hiệu ứng phóng to khi rê qua. Bấm nhanh = Thích / bỏ cảm xúc.
- Bấm ảnh: mở `GalleryViewer` (xem ảnh toàn màn hình, vuốt qua lại). Bấm video: mở `VideoPlayerPage`. Xem trước video trong thẻ dùng lại `ChatVideo`.

### 5.3 Soạn bài

- Ô chữ nhiều dòng, nút chọn ảnh / video, hàng chọn màu nền (chỉ bật khi chưa có tệp và chữ ≤ 150 ký tự).
- Chọn tệp: điện thoại dùng `showMediaPicker` (máy ảnh + thư viện); máy tính dùng `FilePicker` (`FileType.media`). Tối đa 10 tệp, xem trước dạng lưới, bỏ từng tệp.
- Bấm Đăng: bài hiện ngay đầu danh sách với ảnh trên máy, tải lên chạy nền (như `AppState.sendMedia`); lỗi thì hiện "Gửi lại" / "Bỏ".

### 5.4 Bình luận

- Điện thoại: trang / bảng kéo lên toàn màn hình; máy tính: mở trong tab (thay trang danh sách, có nút quay lại) hoặc khung bên phải khi tab đủ rộng.
- Trên cùng là bài viết, dưới là bình luận cũ trước mới sau. Mỗi bình luận: ảnh đại diện, bong bóng tên + chữ, ảnh / video, dòng "5 phút · Thích · Trả lời" và số cảm xúc.
- Trả lời hiện thụt vào dưới bình luận gốc; nhiều hơn 2 trả lời thì gom "Xem N câu trả lời".
- Ô nhập ở đáy: chữ, nút ảnh / video; đang trả lời ai thì có dải "Đang trả lời <tên> ✕".

## 6. Cấu trúc mã dự kiến

| Tệp | Nội dung |
|---|---|
| `lib/feed/feed_models.dart` | đọc `flygo_feed`, bảng màu nền, bộ cảm xúc, nhóm cảm xúc, dựng cây bình luận từ `flygo_reply_to` |
| `lib/feed/feed_store.dart` | `ChangeNotifier`: tìm / tạo / tham gia kênh, tải bài theo trang, bình luận theo bài, cảm xúc lạc quan, đăng bài có hàng chờ, nghe WebSocket |
| `lib/feed/feed_page.dart` | trang danh sách, thẻ bài, lưới ảnh / video, thanh chọn cảm xúc |
| `lib/feed/feed_composer.dart` | trang soạn bài |
| `lib/feed/feed_comments.dart` | trang bình luận |
| `lib/data/models.dart` | `MmChannel.isFeed` |
| `lib/state/app_state.dart` | luồng sự kiện WebSocket, lọc kênh Bảng tin khỏi chat / thông báo |
| `lib/ui/home_page.dart` | ô `feed` (Trang chủ, lưới ứng dụng, tab) |
| `test/feed_models_test.dart` | đọc màu nền, nhóm cảm xúc, cây bình luận, lọc kênh khỏi danh sách chat |

## 7. Giới hạn đã biết

- Video phát trong thẻ chỉ có trên Android, iOS, macOS (như chat hiện nay); Windows / Linux hiện ô xem trước, bấm mở trình phát.
- Tối đa 10 tệp mỗi bài / bình luận (giới hạn máy chủ).
- Mọi thành viên team đọc được Bảng tin (kênh công khai); không có bài riêng tư / bạn bè.
- Tìm kiếm của chat sẽ trả cả bài Bảng tin (cùng là tin nhắn).

## 8. Câu hỏi còn mở

1. **Tạo kênh trên máy chủ khác:** để app tự tạo `bang-tin` khi người đầu tiên mở, hay chỉ quản trị viên bấm "Bật Bảng tin", người khác thấy "Bảng tin chưa được bật"?
2. **Thông báo:** bản đầu chỉ báo khi bị @nhắc tên. Có báo cho người đăng khi có bình luận / cảm xúc mới không (theo dõi luồng của máy chủ chat, cần bật thông báo đẩy cho luồng)?
3. **Ai được đăng bài:** mọi người, hay chỉ quản trị viên (dùng khoá đăng tin sẵn có trong `moderation.dart`, người khác vẫn bình luận được)?
4. **Ghim bài** lên đầu Bảng tin (dùng ghim tin của máy chủ chat) có cần ở bản đầu không?
