# Changelog

Build numbers are the `+N` part of `pubspec.yaml` (`1.0.0+N`). The runner version is in `agent/package.json`.

## 477 (2026-11-14)
- Threads: Trả lời on a message inside a thread quotes it.
- Paste: clipboard BMP/TIFF converted to real PNG; file name and MIME match the content.

## 476 (2026-11-14)
- Chat: day separators show weekday + date; calendar button sits next to the scroll-down button (bottom right).
- Chat info Hình ảnh / Tập tin / Liên kết grouped by day with a calendar jump.
- Phone Apps page: the Hồ sơ avatar tile is a true circle.

## 475 (2026-11-14)
- Chat: calendar button next to scroll-to-bottom; pick a date to jump to the first message of that day.
- Flows editor: one permission "Ai được dùng quy trình (xem + chạy)"; separate start list only behind an advanced switch.

## 474 (2026-11-14)
- Mini apps: keep_visible (page stays active when hidden), own window on macOS (features.window), TV link code panel (features.tv_code) for a TV web app.

## 473 (2026-11-14)
- Flows tabs: content capped at a readable width on wide screens (lists 920px, catalog 1200px); task buttons sit under the row text.

## 472 (2026-11-14)
- Flows editor: settings open in the right column on desktop, icon next to the name, one visible Lưu button; Flows tab list is full width until a page opens.
- Mini apps can set a custom user agent (e.g. a TV web app).
- App grid labels no longer run into each other.

## 471 (2026-11-14)
- Tổ chức permissions: collapsible app groups with granted/total, group checkbox, Chọn tất cả / Bỏ tất cả.
- Flows: progress bar on list rows; realtime process updates over WebSocket (subscribe on open, unsubscribe on close), polling only as fallback.

## 470 (2026-11-14)
- Dịch AI (translate before send) also works in the self chat.

## 469 (2026-11-13)
- Runner 0.6.90: Boards task tools removed (Boards plugin disabled); assistants use the Todo app tools via Flygo Gateway.

## 468 (2026-11-13)
- Groups: a recalled message that starts a sender run keeps the sender name.

## 467 (2026-11-13)
- Runner 0.6.89: Claude engine takes new messages into the running turn (stream-json input; older CLIs keep the old path); chat_watch MCP tool (AI watches a chat, batches new messages every 10 s, owner-only, indicator post, limits, survives restarts; batches go to the owner DM when watching a public group).

## 466 (2026-11-13)
- Apps page redesign: user card only on desktop (left column, profile-style header); phones show the company name on top, a Hồ sơ tile in Cá nhân, Đăng xuất centered at the bottom; 3-finger swipe up opens the server picker.
- Edit profile screen (avatar, display name, nickname, username, title, phone, bio); current custom status under the title.
- Bảng tin: tab always visible, background new-post check with badge and prefetch; smaller + button above the nav; editor title label no longer clipped.

## 465 (2026-11-13)
- Secret thread opened from a reply adds the replied-to author automatically.
- iOS: no more dropping to the add-server screen when the keychain is locked in the background (retry on next open, notice on the login page); servers.json written atomically with a backup.

## 464 (2026-11-13)
- Secret threads keep the AI button even when only you and a bot are in the thread.

## 463 (2026-11-13)
- Apps page user card: Đăng xuất button (tap + confirm).

## 462 (2026-11-13)
- Apps page: user card (name, email, title, presence + status, server, build number + Kiểm tra cập nhật); top on phones, left 1/3 column on wide screens.
- The app shows only the build number (Phiên bản 462) on login, update dialogs, devices and admin pages.
- Account: password sign-in follow-ups (Google sign-in switch for password accounts).

## 461 (2026-11-13)
- Account: Google users can set a sign-in password (Đặt mật khẩu đăng nhập); admins enable password sign-in per user in Users admin (default off).

## 460 (2026-11-13)
- Bảng tin: polls in posts (2-10 options, multiple choice, anonymous, deadline; results after voting or when closed; voter list per option).
- Repo split: server code moved to flygo-chat-server (no app change).

## 459 (2026-11-13)
- Dịch AI: every signed-in user gets the translate button when the server runs the shared translation service (relay /translate/info); translation goes through the server first, the personal runner is only a fallback.

## 458 (2026-11-12)
- Android (Google Play build): in-app updates through Google Play (flexible download with progress, immediate when release priority >= 4), silent check on start / resume / every 3 h, honest update dialog when Play has nothing newer, plus an Open Google Play button.

## 457 (2026-11-12)
- Bảng tin: photos in comments (image button left of the composer, up to 10, one horizontal scrollable row, tap for the fullscreen viewer with copy / save).

## 456 (2026-11-12)
- Share out: phones share the actual image / file from the viewer (chat + Bảng tin) and file messages to other apps.
- Share in: Flygo Chat appears in the share sheet of other apps (Android SEND / SEND_MULTIPLE, iOS Share Extension); a Gửi tới… chooser sends to up to 5 chats with a caption.
- Desktop: drag & drop files into any chat, agent chat or thread.

## 455 (2026-11-12)
- Phones: swiping a message (reply / note) works again on every message; text selection starts only on long-press (selects the whole text, drag the handles to narrow), tap outside to leave it.

## 454 (2026-11-12)
- Image viewer (chat and Bảng tin): Sao chép ảnh (Ctrl/Cmd+C, real image on the clipboard; Linux via wl-copy / xclip) and Tải ảnh (Ctrl/Cmd+S; phones to the photo library, desktop to Downloads without overwriting).
- Saving reports the real reason (Photos permission, disk full, format); Bảng tin Lưu ảnh uses the same path.
- File pickers report errors everywhere; notes explain timeouts and reload after a failed save.

## 453 (2026-11-12)
- macOS: the file / photo picker opens again (Bảng tin post editor, chat attachments); Bảng tin shows picker errors instead of failing silently.

## 452 (2026-11-12)
- Images: viewed images are cached on disk (400 MB LRU) and reopen instantly, also after a restart; opening an image prefetches the rest of the album; thumbnails decode at display size.
- Bảng tin: the +N tile opens the post with all photos; tapping a tagged person opens a DM; only admins can unpin or delete; the desktop side panel shows the whole post above the comments.
- Todo: Quay về app Flygo Chat in the side menu.
- Processes: back button on phones when a process opens at the root of a nested page; the report section sits above the step timeline.

## 451 (2026-11-12)
- Bảng tin: only the author can edit a post (admins keep pin / delete); long-press / right-click a post for Lưu ảnh (saves all its photos) and Xác nhận đã đọc on posts that ask for it.

## 450 (2026-11-12)
- Bảng tin: tapping a photo (feed card or post page) opens the same fullscreen overlay viewer as chat, starting at the tapped photo.

## 449 (2026-11-11)
- Flows: the app calls Flows through the chat domain at /__apps/flows (falls back to push.* on old servers); webhook links stay on push.*.

## 448 (2026-11-11)
- Todo: a close (X) button on the home screen; long-press (without dragging) or right-click a note for Ghim / Lưu trữ / Xoá with Hoàn tác, and Khôi phục / Xoá vĩnh viễn in the trash.

## 447 (2026-11-11)
- New native app Todo (Keep-like notes and checklists: masonry grid, pins, drag reorder, labels, archive, trash, search, rich text with inline checkboxes, colours and 28 drawn backgrounds, attachments and pasted images, repeating reminders by bot DM, sharing as editor / viewer, offline cache), tile in Chính after Bảng tin.
- Process actions (buttons, choices, approvals, one-field input) on the process page and on process cards apply at once through the new server endpoint (Flows 0.42).

## 446 (2026-11-11)
- Mini apps: the Đang mở ứng dụng overlay clears as soon as the app page loads or changes route (SPA), and after at most 8 s; apps with a hidden SSO step (LarkPanel) no longer stay stuck on it.

## 445 (2026-11-11)
- Trình chiếu: Màn hình tab adds a Link cho khách row (copy / share, 7 days); timed decks show đang tự chạy theo thời gian.

## 444 (2026-11-11)
- Trình chiếu: guest links (Link cho khách) last 7 days.

## 443 (2026-11-11)
- Trình chiếu: Copy link ghép copies a ready-to-use screen link (open it in any browser, pick a language and it becomes a controlled screen, no pairing code); desktop adds Mở trên máy này.

## 442 (2026-11-11)
- Chat images: tapping an image opens a fullscreen overlay on top of the current screen (swipe / arrow keys, zoom, Esc / X / swipe down / tap outside to close); images are always shown whole; pasted images can be edited from the composer with a Xong button.
- Message notes now show under image-only and checklist messages (they were saved but not drawn); note edits no longer drop silently.
- Emoji picker closes after a pick and puts the cursor back in the message box.
- Message text: long-press selects text on phones (Sao chép · Thao tác khác · Chọn tất cả); on desktop, holding Shift while dragging selects text instead of swiping.
- Process rows in a single-flow list drop the flow name line.

## 441 (2026-11-11)
- Process list: chips only for warnings (errors always red, Quá hạn, orange/red status), info chips and chips repeating the step are hidden; a per-step progress bar with x/y on every row; paging (50 per page, auto-load at the end, Tải thêm).
- Workflow page: Báo cáo returns to the intro/report view (no separate page); draggable column dividers for the process list and discussion columns (widths remembered); process detail drops the Tạo bởi tiến trình section.

## 440 (2026-11-11)
- Workflow page header: the reload button becomes a Báo cáo button (process report for process flows, run report otherwise).

## 439 (2026-11-11)
- Trình chiếu redesign (desktop): deck list on the left + detail on the right (search Ctrl+K, filters, live shows on top, right-click menu), preview capped at 880 px with a slide grid and inline speaker notes, a Bắt đầu trình chiếu dialog, a 3-column presenter (slides, current + next + notes, Tài liệu / Màn hình / Bình luận / Phụ đề panel, session clock) with full keyboard shortcuts; phones get big Trước / Tiếp buttons and notes under the preview; the AI tab is renamed Phụ đề.
- Process list: one filter button with a Lọc tiến trình dialog.

## 438 (2026-11-11)
- Process list: status, Quá hạn, state and label chips sit on their own line under the name, so they are no longer cut off.

## 437 (2026-11-11)
- Processes: your open tasks show inline at the current step of the process page (form fields + Gửi, buttons / choices, approvals), no need to go through Việc của tôi; process cards accept a one-field answer right on the card (server 0.40.0).
- Flows: task_card posts task cards to channels (no DM) and locks them as Đã xử lý; card_extra.fields picks which form fields a flow card shows.

## 436 (2026-11-11)
- Message notes use the bubble palette text colour, so they stay readable on dark / coloured bubbles (were black on dark green).

## 435 (2026-11-11)
- Process history: internal stats and props whose key starts with _ (e.g. _loi_lan, _cho_phut) are hidden; events that only change such stats disappear.

## 434 (2026-11-11)
- Flow cards: the text renders markdown (bold, links) instead of showing ** markers; "Người đề xuất" is hidden when the requester is a bot (Flow Bot).
- Flows server fix merged (run data size, SQL-only lists, noop retention; server 0.39).

## 433 (2026-11-11)
- Bảng tin on phones: the + (Tạo bài viết) button sits just above the bottom bar instead of floating high (the safe-area inset was counted twice).

## 432 (2026-11-11)
- Agent runner 0.6.88: shared file and command tools for every engine (flygo_chat MCP): file_read, file_write, file_copy, file_move, file_trash (always into the OS trash: ~/.Trash on macOS, gio trash / freedesktop Trash on Linux, Recycle Bin on Windows) and run_command. Changes ask the requester for approval; keys and tokens stay off limits; Claude and agy may no longer run rm / rmdir / unlink / shred, deletions go through file_trash.

## 431 (2026-11-11)
- A corrupt local chat cache no longer leaves the window stuck on a white screen: it is moved aside and reloaded from the server.
- Ứng dụng: the app list refreshes every 20 s while open and on resume, so newly granted apps appear (and revoked ones disappear) without restarting.

## 430 (2026-11-10)
- Processes: card icon keywords render as icons (no more "invo ice"); icon picker "Biểu tượng thẻ" on Tạo tiến trình; props/stats starting with _ are hidden (pickers list them under Ẩn); multi-line reasons show in full under the header, the pill stays one line; phones swipe between Tiến trình and Thảo luận.

## 429 (2026-11-10)
- Process cards: the status pill is one line with ellipsis (long error reasons no longer push the title out); server 0.37.0 sends a short "Lỗi ở bước …" label.
- Flygo ID: App Proxy (server only).

## 428 (2026-11-10)
- Bảng tin phone tab: no empty top bar (search and menu live in the composer card); Dự án AI before Bảng tin (bottom bar Chat, Trợ lý, Bảng tin, Apps; launcher Chat, Dự án AI, Bảng tin; desktop default tabs Chat, Dự án AI, Bảng tin).

## 427 (2026-11-10)
- Flows editor: data fields picked from tool output schemas (Vietnamese labels, table columns for rows[]); table_loop drawn as a visible frame (nested frames); field-vs-field conditions in the UI with natural-language branch labels; Ctrl/Cmd + wheel zooms the diagram.
- Bảng tin: pinned posts on top (newest pin first) then newest posts; right-click / long-press menu Sửa / Ghim / Bỏ ghim / Xoá; authors can pin their own posts; the desktop comment column shows only comments; Đã xem opens the right panel.

## 426 (2026-11-10)
- Process cards: the title stands on its own line; subtitle and status pill move to the row below (no more truncated titles).
- Flows editor: "Nút, nhãn, tệp trên thẻ chat" section on card-sending and process-card steps (server branch feat/flows-card-extras).

## 425 (2026-11-10)
- Flows: new step "Soạn nội dung" (compose): rich-text subject + body with data chips, if/each blocks, money/date helpers and a preview.
- Flow cards: custom buttons, coloured tags and attachments inside the card (one post: card + file); process cards show tags.

## 424 (2026-11-10)
- Mini apps open their tab at once and show the app icon, a spinner and "Đang mở ứng dụng …" while the ticket / SSO / first page load (no blank screen, no wait before the tab opens); errors show Thử lại.
- Apps page: Tổ chức and Quy trình move to Quản trị; empty sections are hidden; Esc clears and leaves the app search.
- Chat: Flow cards (props.flygo_flow) stand alone without the grey bubble; message notes attach to the bottom of the card.

## 423 (2026-11-10)
- Apps page: Teable, Multica, Nebula and Codex move from Chính to Ứng dụng; section order Chính, Ứng dụng, Ký số, Quy trình…, Quản trị, Cá nhân; a search box at the top right filters apps by name (accent-insensitive) and hides empty sections.

## 422 (2026-11-10)
- Bảng tin: newest post always on top (pinned posts keep their place, "Đã ghim" label only); phones get a floating + button to create a post; the tab no longer spins forever (timeouts, error + Thử lại); Flygo ID device id read no longer hangs on a stuck Android Keystore.

## 421 (2026-11-10)
- Bảng tin: every post (pinned too) is a Facebook-style card (author, time, content, photos, tags, reactions, comments, shares, views); share to up to 5 chats; desktop composer dialog "Tạo bài viết"; Bảng tin opens as its own desktop tab and is a default tab; launcher order Chat, Bảng tin, Dự án AI…; phone bottom bar Chat, Bảng tin, Trợ lý, Apps.
- Flows: write steps without approval only warn (server 0.35.0); the allow-without-approval box shows only on steps that already have one.

## 420 (2026-11-10)
- Flows editor: flow settings get "Chế độ chạy" (requester / creator / custom, shows who enabled it, custom shows subject flow:<id>); write steps get "Cho phép chạy không cần duyệt" with a required reason (shows who allowed it); the server 403 for non-human admins opens a clear dialog; tapping a check issue opens that step.

## 419 (2026-11-10)
- Flows: new table step "Đọc hết trang" (mcp_pages) reads every page of a read-only MCP tool (cursor or offset paging) into one table, with per-page retry/timeout and no silent partial tables; editor card + config with paging guessed from the tool arguments.
- Server branches merged: Flygo ID users/devices admin, gateway p1, deploy-admin, cf_identity gateway mode for LinkQ, payment-request security design.

## 418 (2026-11-10)
- Bảng tin, new social-feed look: composer card, pinned carousel, rich post cards (avatar ring, badges, galleries, tags, reaction summary), max 680 px wide on desktop with post + comments in a right column (no new tab), phones open the full page.
- Bảng tin posting: 20 coloured backgrounds for short text posts, several photos, tag people (picker or @), tagged people are notified.
- Bảng tin reactions: hover (desktop) or long-press on Thích to pick 👍 ❤️ 😆 😮 😢 😡; one reaction per person.
- Mini apps: a bare build number in native.min_client is compared with the app build (fixes Bảng tin opening as a web page).

## 417 (2026-11-10)
- Bảng tin: its tile sits in "Chính" right after "Dự án AI" (no longer down in Công việc); on phones it also has its own tab in the bottom bar (Chat, Trợ lý, Bảng tin, Apps) that shows the news feed in place. The bot's DM gets an "Mở bài trong Bảng tin" button.

## 416 (2026-11-10)
- Merge of three preview branches into main: AI assistant tools and UI (builds 403-415 above), the Flows table nodes and loop frame, and the Bảng tin mini app.
- Flows editor: new "Bảng" group (Lọc bảng, Thêm cột, Nhóm bảng, Ghép bảng, Lặp bảng). Lặp bảng is a frame around child steps (drag and drop, "Cài đặt lặp": table, row name, row key, stop on error); old foreach loops open as Lặp bảng. Variable picker knows row columns, item and loop counters; expressions get prefix/suffix/before/after/starts_with/hash. Timed starts get "Bỏ lượt khi lượt trước chưa xong" and "Ẩn lượt chạy không làm gì". Needs a Flows server with the table nodes.
- Bảng tin (new mini app, native screen): company news with categories, pinning, expiry, audience by department / people, read receipts, required acknowledgement with optional deadline and reminders, comments and reactions, bot notifications. Opens from the Bảng tin tile.

## 415 (2026-11-10)
- Tapping a photo (single photo or album): on desktop the photo viewer opens in the right column next to the chat (close button at the top), on phones it opens as a new page. Tap a photo there to zoom, save or forward as before.
- The screenshot button next to the message box is gone in every chat (screenshot is still in the attach menu on desktop).

## 414 (2026-11-10)
- AI assistant cards: arrows follow one rule, pointing down when the content is shown and sideways when it is folded. The step list under the model name, the task list and long step groups are open by default (tap to fold); step details stay folded until tapped.

## 413 (2026-11-10)
- AI assistant: images and files the assistant sends during its answer now show at the exact spot in the answer where it sent them (between its text and steps), instead of a separate message above the answer. The separate file message is hidden in the main chat (older apps still show it); in threads, where the answer is a separate card, the file message stays as before. File steps stay visible when the step list is folded. Needs runner 0.6.87.

## 412 (2026-11-10)
- AI assistant: sets up the connection to the owner's Chrome by itself. New tool browser_extension_setup: if the Playwright MCP Bridge extension is installed it reads the token straight from the Chrome profile and saves it; if not, it registers the extension for Chrome to install (external extension) and opens its Web Store page so the owner only clicks Add once (Chrome requires that confirmation), then running it again picks up the token. The runner also reads the token from the Chrome profile automatically when no token was saved. Needs runner 0.6.86.

## 411 (2026-11-10)
- AI assistant: connects to the owner's real Chrome automatically, without the "Allow" prompt. Install the Playwright MCP Bridge extension, copy its PLAYWRIGHT_MCP_EXTENSION_TOKEN and send it to the assistant: the new tool browser_token_set saves it on the bot machine (owner-only file). From the next turn the "chrome" MCP server (Playwright --extension with the token) is used instead of the prompting Chrome DevTools autoConnect. Sending an empty token removes it. Needs runner 0.6.85.

## 410 (2026-11-10)
- Photo albums in a message (2+ images): the horizontal photo row now uses the full width of the message area instead of stopping at about 560-720 px, so wide desktop windows show more photos before scrolling.

## 409 (2026-11-10)
- AI assistant: browser control without picking a browser. The runner also detects Playwright MCP (the bot gets its own Chrome window with a persistent profile per bot, logins kept between turns, the default for web work) and Chrome DevTools MCP (--autoConnect to the owner's open Chrome, using its logins, Chrome asks to allow). Opening and reading pages runs directly; clicking, typing and submitting forms ask for approval. Desktop MCP servers now get a full PATH so Node-based servers start when the runner is launched by the app. Needs runner 0.6.84.

## 408 (2026-11-10)
- Approval card (agent asks for permission): on desktop it is centered and at most 560 px wide instead of stretching across the chat; phones unchanged.

## 407 (2026-11-10)
- AI assistant: controls the real computer it runs on. The runner detects open-source desktop-control MCP servers installed on the machine and gives them to every engine, so the assistant picks the right tool: Cua Driver (macOS / Windows / Linux, works in the background without taking the mouse), Peekaboo (macOS), Windows-MCP (Windows), computer-use-linux (Linux) and tmux-mcp (terminal). Read-only tools (list apps / windows, accessibility tree, permissions) run directly; clicks, typing, launching apps ask for approval. Config: computerUse=false turns it off, desktopMcp overrides or adds servers. Needs runner 0.6.83.

## 406 (2026-11-10)
- AI assistant: new tool spawn_task(title, prompt). The assistant hands an independent, long job to a child AI session that runs in the background (same group / project) while the conversation goes on; when it finishes, the child posts its report back to the parent session. At most 5 at once per session.
- Chat header: AI sessions with running background tasks show "N background tasks" (with a spinner) under the chat name; tapping it opens the list, each task opens its child session.
- Needs runner 0.6.82.

## 405 (2026-11-10)
- AI assistant: two new tools modelled on the Claude desktop app. update_plan shows the plan for the turn as a checklist on the progress card (advance / done / start move through the steps). wrap_up shows a short recap under the answer; when the assistant needs a decision it adds a question with 2-4 buttons, and tapping a button sends that text back to the assistant (with @mention in group chats). Blocked recaps (waiting for the user) are highlighted. Codex native plans still map to the same checklist. Needs runner 0.6.81.

## 404 (2026-11-10)
- AI assistant: new tools agent_sessions(bot) and agent_transcript(bot, session) let an assistant list and read the sessions the owner has with ANOTHER assistant of the same owner (e.g. a Dự án chat with @ba-codex): user messages, answers, tool calls and results, paged and with secrets masked. The other assistant reads its own engine transcript on its machine and answers over A2A; owner only, both bots must be online. Needs runner 0.6.80 on both bots.

## 403 (2026-11-10)
- AI assistant: the task list the assistant keeps while working (Claude TodoWrite, Codex plan, Antigravity todo/plan) now shows on its progress card as a checklist: not started / in progress (spinner) / done (ticked, struck through), updated live. Open while the turn runs, folded to "Task list · 2/3" when it ends. Needs runner 0.6.79.
- Runner 0.6.79: forwards the assistant task list as props.flygo_agent.todos (replaces the plain "Cập nhật danh sách việc" step).

## 402 (2026-11-09)
- 

## 401 (2026-11-09)
- 

## 399 (2026-11-09)
- 

## 398 (2026-11-09)
- 

## 396 (2026-11-09)
- 

## 395 (2026-11-09)
- 

## 393 (2026-11-09)
- 

## 392 (2026-11-09)
- 

## 391 (2026-11-09)
- 

## 390 (2026-11-09)
- 

## 389 (2026-11-09)
- 

## 388 (2026-11-09)
- 

## 386 (2026-11-09)
- 

## 384 (2026-11-09)
- Hình nền (Cá nhân, desktop): 30 Vietnam landscapes or a custom image, Blur slider; shown on Trang chủ; stored only on this computer.
- Important messages: a centred dialog as soon as they arrive (even outside the chat), no sound, with Đã đọc (acknowledge) and Mở chat.
- Trang chủ: Công việc apps merged into Chính; workflow list reloads when workflows change; Tổ chức: Quản trị per app.

## 383 (2026-11-09)
- Ký số: diagnostics log of the company list refresh.

## 382 (2026-11-09)
- Trang chủ: real Zalo and WeChat icons; "Trợ lý" renamed "Dự án AI" in Chính; experimental workflows keep the badge but are no longer dimmed.
- App tabs (Danh bạ, Lịch sử cuộc gọi, Cài đặt, Zalo, WeChat…) at most 920 px wide.
- Ký số: if the company list cannot load, Trang chủ shows why with a retry button; transient Flygo ID / registry errors are no longer remembered until restart.

## 381 (2026-11-09)
- Flows: experimental workflows ("Thử nghiệm" badge, cannot be started); Trang chủ workflow tiles shown to the people allowed to see them.
- Includes 380: Zalo and WeChat in Chính, Quy trình tile for admins only, Assistants tab after Chat at launch, closing the last Ký số tab closes its window. 380 was never installed.

## 380 (2026-11-09)
- Trang chủ: Zalo and WeChat in Chính (open a tab: "Chức năng đang phát triển"); Quy trình tile and the workflow list only for Flows admins.
- Desktop: the Assistants tab opens right after the Chat tab at launch (users with assistants).
- Ký số: closing the last tab closes the company window.

## 379 (2026-11-09)
- Ký số: the company window no longer closes after a few seconds; Chrome-style browser (tab strip with + after the last tab, address bar, back/forward/reload/home), company bookmarks saved on the sign server, company colours.
- Separate windows (popouts) no longer close by themselves either.
- New-tab chats / assistant sessions keep the left list.
- Notes: only the author can edit or delete a note.

## 378 (2026-11-09)
- Trang chủ: Ký số row right after Chính; a distinct colour per company; full names (wrapped, no ellipsis).
- Desktop: the app always opens on a Chat tab (it can still be closed).

## 377 (2026-11-09)
- Trang chủ: Trình chiếu moved to the Chính row; wider app grid with more columns, less scrolling.

## 376 (2026-11-09)
- unused

## 375 (2026-11-09)
- unused

## 374 (2026-11-09)
- Ký số: each company opens in its own window with tabs (desktop); clicking again brings that window to the front.

## 373 (2026-11-09)
- Trang chủ / Bạn: colourful gradient app tiles (white icons, soft shadow); Ký số companies in their own row.

## 372 (2026-11-09)
- Fix: Ký số tiles missing on macOS (device id read from the keychain failed); desktop keeps the browser device id and Ký số secrets in app files.
- Tổ chức: per-company Ký số permissions.

## 371 (2026-11-09)
- Ký số: one tile per company granted in Flygo ID, opening that company's signing browser with the Flygo ID ticket (no login).
- Tổ chức: company-wide node; Flows: 2-column workflow intro and stats.

## 370 (2026-11-09)
- Tổ chức: department tree and per-department / per-user tool permissions from Flygo ID (2 columns on PC); error when the server has no Flygo ID. 369 was never installed.

## 369 (2026-11-09)
- Desktop tabs: the new-tab page is called "Trang chủ".
- Flows: tools through Flygo Gateway (editor binds gateway apps; old servers unchanged).

## 368 (2026-11-09)
- Flows client uses Flygo ID tickets when the server has Flygo ID (falls back to the chat token otherwise). 367 was never installed.

## 367 (2026-11-09)
- Ký số tile shown from Flygo ID (server has Flygo ID and at least one Ký số space) instead of a build flag.

## 366 (2026-11-09)
- Ký số in-app browser (Magic Sign extension) and Flygo ID client: hidden in normal builds (KYSO_POC flag; Flygo ID only when the server advertises it); iOS 17+ only, hidden on Linux.
- Server code added (not deployed): Flygo ID (drop-in for the mini-app registry), Flows Flygo ID auth (off by default), bots cannot approve.

## 365 (2026-11-09)
- Flows round 2c: cancel path (on_cancel, cascade cancel, "Huỷ tiến trình" dialog), "Tạo tài liệu" step (document render).

## 364 (2026-11-08)
- Flows round 2b: "Bảng theo dõi" tab, process reminders, wait offsets, event matching, step SLA with "Quá hạn" chips, "Thời gian theo bước" report; editor panels for the new steps. (363 was never installed: the Mac mini ran out of disk.)

## 363 (2026-11-08)
- Flows round 2a: process props, parent / child processes, "Liên quan" section, fan-out create, "Đang chờ x/y" and process_wait; magic-sign link button.

## 362 (2026-11-08)
- Flows: discussion column in the process detail (private hidden channel per process), unread badges; these channels stay out of the chat list, search, forward picker and new-tab; pushes open the process detail.

## 361 (2026-11-08)
- Flows (desktop): 2-column workflow page (list | detail; intro, who can start, steps and stats when nothing is selected), tab title is the workflow name.
- Flows: run detail with one step timeline, "Bước tiếp theo", rounds for returned items; create form as a modal on desktop; "việc" renamed "tiến trình" (old Tiến trình tab is now "Theo dõi"); ids hidden behind "Sao chép mã".
- Desktop tabs: chat tabs take the open chat's name.

## 360 (2026-11-08)
- Flows: one Duyệt step with Phê duyệt / Từ chối / Quá hạn / Leo thang / Luôn chạy branches (old Duyệt steps upgrade when opened).
- Flows: expressions with + - * / %, date (workdays), list, text and number functions; "Viết biểu thức" mode in the editor.
- Flows: Lỗi branch and per-call timeout for automatic / AI / wait-event / start-flow steps.
- Flows: Đặt biến step and auto-numbered documents (PC-{yyyy}-{0000}).
- Flows: one Gửi step and one Chờ bấm nút step (old steps upgrade when opened); Watch start gets "Lấy mốc khi bật" and "Mỗi khoá chỉ một lần".

## 359 (2026-11-08)
- Desktop tabs: Chat tab full size, + right after the last tab, server switch at the right edge, apps from the new-tab menu open in a new tab.
- Desktop: pages opened from buttons show as a centred modal.
- Flows: "bước" instead of "nốt"; Tiến trình is the last tab instead of a separate switch.

## 358 (2026-11-08), version 1.0.4
- Desktop: browser-style tabs. Each app is a tab (several tabs per app), new tab opens the app menu (main apps, You-page apps, every workflow as its own app, mini apps), open chats / assistant sessions / message threads in a new tab, no bottom bar on PC, shortcuts Ctrl+T/W/Tab/1-9 and Ctrl+Shift+T, Alt+1-4 for panes, tabs restored on restart.

## 357 (2026-11-08)
- Flows: Tiến trình (process list, detail, report); new editor nodes (process, wait for button/choice, create approval, card); flygo_card choices and open/input/select buttons; action/request/returned items in My tasks.

## 356 (2026-11-07)
- Data card: multi-step job status (steps) with done / active / pending / failed / skipped states and per-step notes.

## 355 (2026-11-07)
- Generic data card (props.flygo_card): invoices, debts, incidents, e-sign documents, reports, orders. Buttons open a link, copy text or reply in the card thread (props.flygo_card_action) for bots. Notes attach to the card. Docs: docs/flygo-card.md.

## 354 (2026-11-07)
- Bank transaction card: copy button next to the transfer content.

## 353 (2026-11-07)
- Bank transaction card: cards from the bank bot (and anyone else) sit on the left like other incoming messages; only your own cards sit on the right. The send time stays under the right edge of the card.

## 352 (2026-11-07)
- Bank transaction card: balance after the transaction (only for groups allowed to see it; the worker sends it per group), sender / receiver icons centred on their text with the arrow between them, notes attached inside the card at the bottom. Reads the split sender / receiver fields (name, account, bank) from the worker.

## 351 (2026-11-07)
- Bank transaction card: credit / debit messages from the bank bot that carry props.flygo_bank_txn show as a card (TIỀN VỀ green / TIỀN ĐI red, company account on the right, big centred amount and time, sender and receiver, content, transaction number and reference with copy buttons) instead of the text block. Notes added to the message show right under the card. Older apps keep showing the text message (backward compatible).

## 350 (2026-11-07)
- Note dialog: Enter saves on every device (on phones the keyboard key becomes Done); Shift+Enter still adds a new line on desktop.

## 349 (2026-11-07)
- Message notes: author avatar, name and time on top, note text below.

## 348 (2026-11-07)
- Add / edit note dialog: the notification choice (silent / notify author / notify group) moves to the top, above the colours and the text box.

## 347 (2026-11-07)
- Message notes: lighter look (soft tint, thin colour bar, note text first, author and time small underneath), filling the bubble width.
- Add / edit note dialog: Thêm ghi chú im lặng (default), Báo người gửi tin (a small reply in the message thread tagging the author), or Báo cả nhóm (a message in the main chat quoting the original).

## 346 (2026-11-07)
- Composer: tapping the silent-send button turns silent sending on right away (tap again to turn it off, with a short toast); long press still opens the explanation with both choices.

## 345 (2026-11-07)
- Swipe a message from left to right to open the add-note sheet (swipe right to left still replies). Same rules as the Thêm ghi chú menu item.

## 344 (2026-11-07)
- Sending a message with an @name that matches no username asks first: it lists people with a similar username or name to pick from (the tag is replaced with the exact @username), or lets you send as typed, or cancel. Nothing is changed automatically.

## 343 (2026-11-07)
- Secret threads: @tags match the exact username only (the fuzzy matching from 342 is removed). @names that match no account are reported in a toast, as are people the server refused to add.

## 342 (2026-11-07)
- Secret thread from a message with @tags: a hand-typed @name that is not an exact username (e.g. @an for nguyenvana) is matched against the group members (end or start of the username, or a word of the display name, accents ignored); a unique person is added. Anyone who could not be found or added is now reported in a toast instead of being skipped silently.

## 341 (2026-11-07)
- One-tap attendance (auto-captured location and Wi-Fi are submitted without manual input, retry on error); FlowLocationView with mini map, pin, accuracy circle and capture time; GPS distance node (geo_distance) with a fixed company location and radius. Needs Flows server 0.21.0.

## 340 (2026-11-07)
- iOS: Access WiFi Information entitlement (com.apple.developer.networking.wifi-info) so attendance fields can read the office Wi-Fi name; the location permission text now mentions attendance check-in (vi + en).

## 339 (2026-11-07)
- Tag picker: tagging a session (Dự án tab) opens a bridge: the assistant talks to that session directly over A2A, and the request and answer show in both chats. Works for another session of the same assistant and for sessions of another assistant, Claude or Codex. Needs runner 0.6.77.
- Every tag is shown as a chip on the sent message: tagged chats and threads, connected sessions, and people picked in the Danh bạ tab.
- Tags in the composer are cleared after the message is sent.
- The + menu tag picker now also inserts people picked in the Danh bạ tab.
- Runner 0.6.77: ask_agent with the assistant's own name and a session runs the turn in that session locally (the relay does not let a bot call itself); bridged turns cannot open another bridge (depth 1); the request shows which session asked.

## 338 (2026-11-07)
- Flow forms get attendance fields (GPS location, Wi-Fi, on-site photo); editor adds per-person tasks, wait timeouts, wait-until-time and new calculations; Quy trình tabs always fit their labels.

## 337 (2026-11-06)
- Tag picker in an assistant chat: the Dự án tab lists every project (the current one first and opened), not only the current project.

## 336 (2026-11-06)
- Tag picker: the Agent tab becomes Dự án. Pick a project, then pick one session in it (radio, one session per project); project rows no longer tag the project chat itself.

## 335 (2026-11-06)
- Quy trình page tabs no longer truncate their labels; narrow columns scroll the tabs horizontally.

## 334 (2026-11-06)
- Quy trình page with five tabs (Quy trình, Cần xử lý, Đang chạy, Lỗi, Đã xong), image field in forms, copy and company-wide pin for admins; flow editor settings in the ⋮ menu, icon picker, read-only flow code, name asked on create, variables shown by name. Needs Flows server 0.18.0.

## 333 (2026-11-06)
- Quy trình page with four tabs: Quy trình (grid with pins and search; admins can edit, enable, disable, hide and add flows), Phê duyệt, Đang chạy, Đã xong. Delegation moved to the Apps grid (Work group). Needs Flows server 0.17.1.

## 332 (2026-11-06)
- Build with the flow form lookup fix (picked value is kept on submit) and live flow detail: auto refresh while running, step-by-step trace with upcoming steps, debug panel for the requester.

## 331 (2026-11-06)
- The launch gradient ring around the tab bar runs slower: one lap in about 5 seconds instead of 1.8.

## 330 (2026-11-06)
- Fixed being logged out when a call or notification wakes the app: on iPhone the saved session is now readable while the phone is locked (existing sessions are moved over the next time the app is opened), and a session that cannot be read for a moment keeps the app on its loading screen and retries instead of showing the login screen.
- A single 401 during sync no longer logs out: the app asks the server again a few seconds later and only logs out if the session is really gone; it no longer sends a logout request for a session the server has already ended.

## 329 (2026-11-06)
- Group calls: voice and video calls in a group are now real group calls (everyone in one grid, participant list showing who has joined and who is still being called), not meetings; mic is on, video calls start with the camera on. No screen share, raise hand, AI or polls. The call ends by itself when everyone has left.
- Meetings: a meeting stays open until its creator presses "End meeting" (in the call or on the meeting card); others, including the creator, can leave and rejoin. Starting a meeting without a schedule posts a meeting card. Meetings keep the full feature set and gain a "Polls" panel.
- Meetings: background music removed completely (no lobby music, presentation music is ignored; the relay rejects music).
- Video calls: your own picture floats and can be dragged anywhere; drag it to the bottom of the screen and drop it on the X to turn your camera off.
- Call history and call cards tell group voice, group video and meetings apart.
- 1-1 call history: answered calls no longer show as "No answer" / missed (the calls server does not record participants; the answering phone now leaves a hidden "answered" note), and missed calls are counted again.
- Meetings on phones: tapping the screen while a scene or slides are shown (e.g. the waiting room) brings the call buttons back again.

## 328 (2026-11-06)
- Bottom tab bar floats higher above the screen edge (content, the + button and snack bars move up with it).
- On app start a gradient light runs once around the tab bar.

## 327 (2026-11-06)
- Workflows: new "Progress" step (percent + label, normal / success / warning / error) shown as a progress bar on the task page, in task lists and on the chat card.
- Workflows: "Send message with files" step (to the requester and / or a group, files attached from download links such as bank documents).
- Workflows calculation: first / last day of a month, month / year of a date.

## 326 (2026-11-06)
- Message notes: the note text follows the note colour (dark text on light notes), so notes on your own deep-blue messages are readable again.

## 325 (2026-11-06)
- Chat settings: "Notifications" moved from the button row into the settings list (above "Group type"), showing its state (on / off / off until a time); the button row keeps Call, Video and Search.

## 324 (2026-11-06)
- Assistant messages: the @tag of the person the assistant is replying to is shown again at the start of the message (highlighted like in people messages) instead of being hidden.

## 323 (2026-11-06)
- In-chat search: the search box keeps the cursor while you type (it no longer loses focus after the first letter when a match is found).

## 322 (2026-11-06)
- Chat settings: a "Search" button next to "Notifications" goes back to the chat with the in-chat search box open (finds loaded and older messages on the server, accents optional).

## 321 (2026-11-06)
- Version 1.0.3 for the App Store (1.0.2 went out with build 285); same app as 320.

## 320 (2026-11-06)
- Workflows: starting a workflow is now called creating a new "task" (Tạo việc mới); runs are called tasks throughout the workflow screens, the message menu item is "Create task".

## 319 (2026-11-06)
- Work threads: a ⋮ menu at the top right (next to the AI button) with Rename, Close thread (asks for confirmation) and Reopen thread (continue work on a closed thread); the close link under the thread name is gone.
- Secret threads: a red frame around the whole chat so they are easy to recognise.

## 318 (2026-11-06)
- Urgent messages: confirming on one device ("Got it") closes the full-screen alert and stops the ringing on all your other devices, including the phone notification.
- Urgent messages: the full-screen alert shows the message in the largest font that fits the screen.
- Urgent / read-confirmation messages: a note under the message lists who has confirmed reading ("Nobody has confirmed reading yet" on your own message until someone does).
- Chat: a message with only a file shows the file card on a solid background with a soft shadow instead of a see-through one.

## 317 (2026-11-06)
- Chat: call cards, the reaction preview and show-mode chat lines you sent use white text and icons on the deep bubble (missed / declined in light red, answered in light green) instead of black.

## 316 (2026-11-06)
- Chat themes: your own message bubble in every theme (light and dark) is a deep shade of the theme colour tuned per colour, so white text is equally readable everywhere (7:1) and the bubble stands out from the background; default blue bubble slightly deeper.

## 315 (2026-11-06)
- Chat: your own messages are now a deep blue bubble with white text (links, times and ticks in white too), clearly standing out from the chat background; chat themes use a deep bubble in their own colour with white text. Contrast checked on every theme (text at least 4.5:1 on the bubble, bubble at least 3:1 on the background).

## 314 (2026-11-06)
- Threads list: "Public" / "Secret" tags are solid green / red with white text.
- Secret threads: "Close thread" moved from under the thread name into the thread settings, below "Leave channel", as a hold-to-confirm button; secret threads no longer offer "Delete channel".
- Closed threads say who closed them: "X closed this thread" at the bottom of the thread, "Closed by X" in the threads list.

## 313 (2026-11-06)
- Threads list: public and secret threads in one list, newest first, each with a green "Public" or red "Secret" tag before its name (no more separate sections).

## 312 (2026-11-06)
- Chat: links, copy buttons and read ticks inside message bubbles are readable again (dark navy in light mode, near-white in dark mode, at least 4.5:1 contrast on every bubble and chat theme); dark-mode bubbles for your own messages slightly deeper so text stands out.

## 311 (2026-11-06)
- Chat: much deeper chat background (light mode and chat themes), stronger bubble shadow, black text, darker secondary text; dark mode on pure black with lighter bubbles.
- Voice recording: "Send transcript" is now the main button on the far right, "Send recording" next to it.

## 310 (2026-11-06)
- Chat: stronger contrast. Deeper chat background in light mode, bubbles stand out with a soft shadow, darker secondary text and message times, richer blue for your own messages; in dark mode lighter bubbles and secondary text on a deeper background. Chat themes get the same treatment.

## 309 (2026-11-06)
- Chat: the chat background (pattern and theme colour) now runs down behind the message box instead of stopping above it.
- Chat 1-1: the other person's status always shows under their name (in red when they are on Do not disturb).
- Do not disturb warning: above the message box, "X has turned on Do not disturb" in a 1-1 chat with that person, or in a group as soon as the message being typed tags them.
- Workflow forms: catalogue fields (lookup from an app) suggest as you type right under the field; arrow keys + Enter on desktop; recent picks when the field is empty; an exact code (typed, pasted or scanned) is accepted at once; a second line per suggestion (e.g. stock, price) chosen in the field settings.
- Assistant: the quota ring shows the share used (like the context ring), not what is left.

## 308 (2026-11-06)
- Workflows: every step has a fixed code <workflow code>-<number> shown on the diagram, the run page and chat cards; "Find step by code" in the editor menu.
- Adding a workflow creates it on the server at once with a fixed 6-character code (AI assistants can edit it right away); the code can no longer be edited.
- Workflow settings: on/off switch, validity period (from / until), "Who sees this workflow" (departments, people, or the whole company).
- "Ask the AI assistant" in the editor menu opens a new assistant session about this workflow (right column on desktop, new page on phones).
- "Start another workflow" can open one run per table row, in parallel, and wait for all of them.

## 307 (2026-11-06)
- Workflows: due times in working days (company calendar with work days and holidays in the Organization app); repeat reminders until a task is done; checks on submit (e.g. end date after start date); "Wait for event" step (polls an app until a condition holds, with a time limit); loops over lists returned by a previous step; operations report (runs per workflow, slowest steps, people holding most tasks, oldest waiting tasks) from the all-runs page.

## 306 (2026-11-06)
- Workflows: "Calculate" step in flow control: variables from picked operations (add, subtract, multiply, divide, percent, round; sum / max / min / average / count over a table column with an optional row filter or over picked values; days between dates, date plus N days, today; join text, upper / lower case; if-then-else; running total inside a loop). Results are offered in Insert info, conditions and parameters of later steps.

## 305 (2026-11-06)
- Workflow editor: Save, Undo, Check and Test run moved into the three-dot menu (a dot shows unsaved changes).

## 304 (2026-11-06)
- Workflows: new form field "Delegation": filled when creating the request (e.g. leave), one card per person with the workflows below, prefilled with every workflow that involves the person (by name, role, department or as a manager); long-press a workflow to drag it to another card, or tap to choose where it goes; "Add another workflow".
- "Apply delegation" step (automatic, after the manager approval) replaces the request and approval steps; the leave template uses it.
- The all-runs button in Workflows uses a filter icon.

## 303 (2026-11-05)
- Workflows: the three delegation steps are separate items in the step picker and can be placed and removed one by one (saving still requires all three in order).

## 302 (2026-11-05)
- Workflows: delegation is three linked steps without admin settings: the employee fills "Request delegation" (dates and a table of workflows to one person), the direct manager approves ("Approve delegation", the request is shown on the approval), "Revoke delegation" ends it. Removing one removes all three.
- "Set status" step renamed "Change status".

## 301 (2026-11-05)
- Workflows: the "Set delegation" step edits its rows as a table: several workflows per row, one person to hand over to.

## 300 (2026-11-05)
- Workflows: third tab "Delegation" lists my delegations and the ones I take over, with time left and expiry; the round + sends a delegation request (no self-service delegation; it is created by the "Set delegation" step after the manager approves).
- Delegation per workflow (one person for payments, another for the rest), optional transfer of tasks already waiting; tasks show "approving for X"; steps can refuse delegation or allow it only to a role.
- New steps "Set delegation" and "Set status" (custom chat status such as "On leave until..." with expiry and optional do-not-disturb); the leave template uses both.

## 299 (2026-11-05)
- Workflows: Start nodes on the diagram (manual, specific date, recurring date, interval, webhook, group message, from a message, public form with QR, data date due, condition watch, called by another flow, incoming email). A flow only accepts start_flow calls when it has a "called by another flow" node.
- Message long-press "Create flow" opens the workflow form prefilled from the message.
- Organization app (You > Work): departments with a head, several deputies and members; a person can be in several departments; admins edit.
- Desktop: workflow pages open beside the sidebar, step settings in the right column; grouped step picker with one group per MCP app; round + button for a new run; workflow home shows the last list at once.
- Assistant: the Agents tab no longer opens a project by itself (remembers the last one); messages and commands in produced order; context and quota rings with a detail sheet.

## Runner 0.6.76 (2026-11-05)
- Codex: a new message from the user while a turn is running is steered into that turn (`turn/steer`) instead of waiting for the next turn. The message gets an :eyes: reaction and a step on the run card. Messages with files, and any message when the turn has already ended, still queue as before.

## 290 (2026-11-05)
- To-do messages stand on their own (no colored bubble around the card), like image-only messages.
- Several images: a "N photos" label above the image row (tap it to open the vertical viewer).

## 289 (2026-11-05)
- Forwarding (and report-out / share from threads and the AI column / new secret thread with files) copies attachments on the server through the push station (`relay/files.mjs`, with the user's own token) instead of downloading them to the device and uploading again. Falls back to the old way if the station does not have it.
- Several images in one message: always one horizontally scrolling row (phone and desktop). Tapping an image opens a full-screen page that scrolls vertically through all images, starting at the tapped one; tap an image there to zoom / save / forward.
- New message type "To-do" in the + menu: title, description, "allow editing after sending", items (one row each with a checkbox) and who can tick (only me / everyone in the chat / some people, with Select all). Others tick through the push station (`relay/checklist.mjs`), which enforces the rule; the card shows who ticked.
- Notes on desktop: Enter saves, Shift+Enter adds a new line.

## 288 (2026-11-05)
- Chat filter tabs swipe like the Agents tab: each filter is a page that follows the finger (the search box and tabs stay on top).
- "N unread" chips are readable in the dark Claude style (text color follows the accent brightness).
- Tasks module removed from the UI: no Tasks button in the bottom bar, no "Create task" in the message menu. Old task cards still render.

## 287 (2026-11-05)
- Unsent text is kept per chat and per thread (also across app restarts): switching to another chat and back no longer loses what you were typing. Finishing an edit brings the draft back; sending clears it.
- Tap the quoted message in a reply to scroll to the original message (loads older messages if needed) and highlight it.

## 286 (2026-11-05)
- Message notes: long-press a message, "Add note" (6 colors + text); notes sit under the message with the author, time and "edited". Long-press a note to copy, edit or delete (author, channel admin or system admin). Stored in `props.flygo_notes`, edited by the push station (`relay/notes.mjs`).
- Chat filter tabs: "Threads" is the second tab (public and secret threads that are still open, with a count); the bottom-bar "Threads" button became "Workflows", which shows "Coming soon" for now.
- Workflows (Flows) groundwork: approval cards from Flow Bot (`props.flygo_flow`) with Approve / Reject / Return, Workflows screen and forms (opened through a mini app with `native.screen = "flows"`).

## 272 (2026-10-31)
- Tasks: the Boards button opens a bottom sheet listing boards with task counts; picking one filters the Tasks list (chip "Board: ...", All / Mine toggle).
- Boards on phones stack vertically (kanban columns as sections, table rows as cards, two-column gallery); no horizontal scrolling.
- Tapping a task opens its detail full screen on phones.
- `android/app/google-services.json` is no longer tracked in git; build machines copy it in.

## 271 (2026-10-31)
- Tasks tab redesign: "My tasks" summary, filters (Today, This week, Overdue, Assigned by me, All), grouping by due date, tap the circle to complete with undo, swipe to complete or reschedule, long-press menu, quick-add sheet, skeleton loading.
- Task detail: large title, tappable status, fact chips, checklist progress, chat-style comments, bottom bar (Mark done, Message assignee, Edit).
- Create a task from a chat message (long press); optional card posted to the chat; "Open original message".
- Relay `relay/tasks.mjs`: reminders when assigned, the day before the due date, when overdue and when done, plus an 08:00 digest (opt-out in You).

## 270 (2026-10-30), runner 0.6.62
- Desktop split panes (up to 2x2) with drag and drop, pane headers, shortcuts and saved layout.
- Pop-out windows (drag outside or pop-out button); main window keeps tray, notifications, updater and runner.
- Antigravity CLI (`agy`) as a third assistant engine.

## 269 (2026-10-30), runner 0.6.61
- Runner chat toolset for agents: list, read, search, send, reply, forward, schedule, polls, cards, reactions, pins, reminders, create chats, members, private threads, bot status.
- Edit a bot's skills remotely through the A2A relay; the Skills tab groups skills per bot (collapsible).

## 268 (2026-10-30)
- Tapping a task opens a read-only detail view with an Edit toggle.

## 267 (2026-10-30)
- You page: activity and custom status on one line.

## 266 (2026-10-30), runner 0.6.60
- Fixed the first message of a new AI session not being sent.
- Runner tools to rename, fork and hand off AI sessions and to manage projects; cards for forked and handed-off sessions.

## 265 (2026-10-30)
- Agents tab: four sub-tabs (Projects, Chat, Schedules, Skills) and AI sessions of ordinary conversations.
- You page: QR login after Settings; Delete account and Sign out are small long-press buttons.
- Relay: `ref_post` can post into direct and group messages.

## 264 (2026-10-29)
- macOS image paste fixed (temp directory created at startup); paste diagnostics log.

## 263 (2026-10-28)
- Password page and forced password change on first login.
- Desktop screenshot button above the composer; paste images on all platforms.
- macOS minimum raised to 12.3.

## 262 (2026-10-27)
- iOS permission texts explain each use with an example (App Store 5.1.1(ii)).

## 261 (2026-10-26)
- Windows: system tray setup no longer blocks the first frame (white window on some PCs).

## 260 (2026-10-26)
- Desktop startup log (`%TEMP%\flygo-init.log`), time limit on startup steps, `FLYGO_SHOW=1`.

## 259 (2026-10-26)
- Windows renders with Skia instead of Impeller by default (white window on weak GPUs); `FLYGO_IMPELLER=1` opts back in.

## 258 (2026-10-26)
- Direct messages with bots are listed like other chats.

## 257 (2026-10-26)
- Tasks tab header becomes a board picker.

## 256 (2026-10-26)
- Boards: native screens (kanban, table, calendar, gallery, card detail) replace the web view.

## 255 (2026-10-26), runner 0.6.59
- Channel names encode sub/AI channel relations; `task_*` MCP tools for agents.
