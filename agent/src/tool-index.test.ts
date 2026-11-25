import { expect, test } from "bun:test";
import { ToolIndex, appOf, compactSchema, toolCallNeedsApproval } from "./tool-index";
import fixture from "./tool-index.fixture.json";

// Chỉ mục = 493 tool app thật (tên + tiêu đề từ manifest Flygo ID homelab, 2026-11-25) + một ít tool của bot.
const local = ["chat_history", "chat_send", "agent_send", "run_command", "file_read", "schedule_create", "session_fork", "skill_save", "integrated_browser_open", "browser_open_profiles", "adb_screenshot"]
  .map((name) => ({ name, title: name.replace(/_/g, " ") }));
const idx = new ToolIndex([...(fixture as any[]).map((t) => ({ name: t.name, title: t.title })), ...local]);

const EVAL: [string, RegExp][] = [
  ["mở trình duyệt ký số", /integrated_browser_(start|list|open)/],
  ["gửi thư nháp", /mail_(save|send)_draft/],
  ["tạo cuộc họp", /meet_(schedule|start_now|rooms)/],
  ["họp ngay", /meet_start_now/],
  ["chụp màn hình trang web", /browser_take_screenshot/],
  ["tạo ghi chú việc cần làm", /todo__(create_note|add_checklist_items)/],
  ["xem số dư ngân hàng", /tcb_(total|account)_balance/],
  ["tạo sự kiện lịch", /calendar__create_event/],
  ["điền biểu mẫu", /forms__/],
  ["bấm nút trên trang", /browser_click/],
  ["mời thêm người vào cuộc họp", /meet_invite/],
  ["đặt lời nhắc", /set_reminder/],
  ["xem sự kiện tuần này", /calendar__list_events/],
  ["tạo quy trình", /flows__/],
  ["tìm danh bạ", /contacts__/],
];

test(`tìm đúng tool cho việc thường gặp (top 5), chỉ mục ${idx.size} tool`, () => {
  const miss: string[] = [];
  for (const [q, want] of EVAL) {
    const names = idx.search(q, { limit: 5 }).map((h) => h.name);
    if (!names.some((n) => want.test(n))) miss.push(`${q} → ${names.join(", ")}`);
  }
  expect(miss).toEqual([]);
});

test("lọc theo app; nhóm app", () => {
  expect(idx.search("xem", { app: "mail", limit: 3 }).every((h) => h.app === "mail")).toBe(true);
  expect(appOf("vn_flygo_clients__browser_click")).toBe("browser");
  expect(appOf("vn_flygo_clients__integrated_browser_start")).toBe("ky-so");
  expect(appOf("vn_flygo_web_office__docx_read")).toBe("office");
  expect(appOf("vn_flygo_bank_techcombank__tcb_total_balance")).toBe("bank-techcombank");
  expect(appOf("chat_send")).toBe("chat");
  expect(idx.apps().browser).toBeGreaterThan(40);
});

test("schema rút gọn", () => {
  expect(compactSchema({ type: "object", properties: { to: { type: "string" }, n: { type: "number" } }, required: ["to"] })).toEqual({ required: ["to"], params: { to: "string", n: "number" } });
});

test("tool_call xin duyệt như gọi thẳng", () => {
  const allowed = "chat_history,chat_thread,tool_search";
  expect(toolCallNeedsApproval("chat_history", { gateway: false, selfApproving: false, allowed })).toBe(false);
  expect(toolCallNeedsApproval("skill_save", { gateway: false, selfApproving: false, allowed })).toBe(true); // Claude sẽ hỏi
  expect(toolCallNeedsApproval("vn_flygo_mail__mail_send_draft", { gateway: true, selfApproving: false, allowed })).toBe(false); // gateway tự xin duyệt tool ghi
  expect(toolCallNeedsApproval("run_command", { gateway: false, selfApproving: true, allowed })).toBe(false); // tự xin duyệt bên trong
  expect(toolCallNeedsApproval("skill_save", { gateway: false, selfApproving: false, allowed: "*" })).toBe(false); // codex / agy: cả server được phép
});
