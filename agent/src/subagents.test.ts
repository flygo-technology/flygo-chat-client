import { expect, test } from "bun:test";
import { SubagentTracker, actionOf } from "./subagents";

const ev = {
  start: (id: string, o: any = {}) => ({ type: "assistant", message: { content: [{ type: "tool_use", id, name: "Agent", input: { subagent_type: "Explore", description: "Tìm chỗ gọi API", prompt: "Tìm mọi chỗ gọi /v1/messages token=abcdef123456", ...o } }] } }),
  child: (parent: string, name: string, input: any) => ({ type: "assistant", parent_tool_use_id: parent, message: { content: [{ type: "tool_use", id: "c" + Math.random(), name, input }] } }),
  result: (id: string, text: string, is_error = false) => ({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, content: [{ type: "text", text }], is_error }] } }),
};

test("sub-agent tiền cảnh: mở khi gọi Agent, tiến độ qua tin con, xong khi có tool_result", () => {
  let n = 0;
  const t = new SubagentTracker(() => n++, () => 1000);
  t.onEvent(ev.start("tu1"));
  expect(t.list[0]).toMatchObject({ id: "tu1", type: "Explore", title: "Tìm chỗ gọi API", status: "running", background: false, tool_uses: 0 });
  expect(t.list[0].prompt).not.toContain("abcdef123456"); // che bí mật
  t.onEvent({ type: "system", subtype: "task_started", task_id: "T1", tool_use_id: "tu1" });
  t.onEvent(ev.child("tu1", "Bash", { command: "grep -rn v1/messages src" }));
  t.onEvent(ev.child("tu1", "Read", { file_path: "/a/b/lib/ui/x.dart" }));
  expect(t.list[0]).toMatchObject({ tool_uses: 2, last_action: "Đọc lib/ui/x.dart", task_id: "T1" });
  t.onEvent({ type: "system", subtype: "task_progress", task_id: "T1", usage: { total_tokens: 1234, tool_uses: 3 } });
  expect(t.list[0].tokens?.total).toBe(1234);
  t.onEvent(ev.result("tu1", "Có 3 chỗ: a.ts, b.ts, c.ts"));
  expect(t.list[0]).toMatchObject({ status: "done", result: "Có 3 chỗ: a.ts, b.ts, c.ts" });
  expect(t.active).toBe(false);
  expect(n).toBeGreaterThan(3);
});

test("sub-agent chạy nền: tool_result chưa kết thúc; task_notification mới chốt; lượt kết thúc không giữ phiên thì dừng theo", () => {
  const t = new SubagentTracker(() => {}, () => 2000);
  t.onEvent(ev.start("tu2", { run_in_background: true }));
  t.onEvent(ev.result("tu2", "Đã chạy nền, id T2"));
  expect(t.list[0].status).toBe("running");
  t.onEvent({ type: "system", subtype: "task_started", task_id: "T2", tool_use_id: "tu2", is_backgrounded: true });
  t.onEvent({ type: "system", subtype: "task_notification", task_id: "T2", status: "completed", summary: "Xong, đã sửa 2 tệp", usage: { input_tokens: 10, output_tokens: 20 } });
  expect(t.list[0]).toMatchObject({ status: "done", result: "Xong, đã sửa 2 tệp", tokens: { input: 10, output: 20 } });
  t.onEvent(ev.start("tu3", { run_in_background: true }));
  t.endTurn(true);
  expect(t.get("tu3")!.status).toBe("running"); // phiên sống: còn chạy
  t.endTurn(false);
  expect(t.get("tu3")!.status).toBe("stopped");
});

test("lỗi và dừng", () => {
  const t = new SubagentTracker(() => {});
  t.onEvent(ev.start("tu4"));
  t.onEvent(ev.result("tu4", "Lỗi: không đọc được", true));
  expect(t.get("tu4")).toMatchObject({ status: "failed", error: "Lỗi: không đọc được" });
  t.onEvent(ev.start("tu5"));
  t.markStopped("tu5");
  expect(t.get("tu5")!.status).toBe("stopped");
  expect(actionOf("Bash", { command: "curl -H 'Authorization: Bearer sk-ant-api03-AAAAAAAAAAAA' x" })).not.toContain("sk-ant-api03-AAAA");
});
