import { expect, test } from "bun:test";
import { RunCard } from "./card";

const card = () => new RunCard({} as any, { channel_id: "c", root_id: "" }, "r", "claude", "t", "o", () => {});

test("update_plan: items, advance, done/start", () => {
  const c = card();
  expect(c.updatePlan({ advance: true })).toContain("Chưa có kế hoạch");
  c.updatePlan({ items: [{ content: "A", status: "in_progress" }, { content: "B", status: "pending" }, { content: "C", status: "pending" }], scope: "continuation" } as any);
  expect(c.todos.map((t) => t.status)).toEqual(["in_progress", "pending", "pending"]);
  expect(c.updatePlan({ advance: true })).toBe("Kế hoạch: bước 2/3 đang làm (1 xong).");
  c.updatePlan({ done: [2], start: 3 });
  expect(c.todos.map((t) => t.status)).toEqual(["completed", "completed", "in_progress"]);
  expect((c.props() as any).flygo_agent.todos.length).toBe(3);
});

test("wrap_up: chỉ tóm tắt (ask / actions không vào ô, nhắc hỏi bằng thẻ câu hỏi), xong các bước đang làm trừ khi blocked", () => {
  const c = card();
  c.updatePlan({ items: [{ content: "A", status: "completed" }, { content: "B", status: "in_progress" }] });
  expect(c.setWrapUp({ recap: "" })).toBe("Thiếu recap.");
  c.setWrapUp({ recap: "Waiting for a code", blocked: true });
  expect(c.todos[1].status).toBe("in_progress");
  const r = c.setWrapUp({ recap: "Done", ask: "Restart?", actions: [{ label: "Yes" }, { label: "No" }] });
  expect(r).toContain("AskUserQuestion");
  expect(r).toContain("Restart?");
  expect(c.todos[1].status).toBe("completed");
  expect((c.props() as any).flygo_agent.wrap_up).toEqual({ recap: "Done" });
  expect(c.setWrapUp({ recap: "Only recap" })).toContain("Viết câu trả lời cuối");
  expect((c.props() as any).flygo_agent.wrap_up).toEqual({ recap: "Only recap" });
});

test("bước hỏi người dùng mang step.questions trong props (app vẽ câu hỏi tại bước)", async () => {
  const { RunCard } = await import("./card");
  const card = new RunCard({} as any, { channel_id: "c", root_id: "" }, "r", "claude", "t", "u", () => {});
  const q = { post_id: "q1", id: "x", question: "Làm tới đâu?", header: "", options: [{ label: "A", description: "" }, { label: "B", description: "" }], multi: false, status: "pending" as const };
  card.step({ id: "ask-1", kind: "approval", title: "Chờ trả lời: Làm tới đâu?", status: "waiting", questions: [q] });
  card.step({ id: "ask-1", kind: "approval", title: "Đã trả lời: B", status: "done", questions: [{ ...q, status: "answered", answer: "B", choices: ["B"] }] });
  const st = (card.props() as any).flygo_agent.steps.find((s: any) => s.id === "ask-1");
  expect(st.questions).toEqual([{ ...q, status: "answered", answer: "B", choices: ["B"] }]);
  expect(st.status).toBe("done");
});

test("thẻ mang props.flygo_agent.bg khi có tác vụ nền", async () => {
  const { RunCard } = await import("./card");
  const card = new RunCard({} as any, { channel_id: "c", root_id: "" }, "r", "claude", "t", "u", () => {});
  expect((card.props() as any).flygo_agent.bg).toBeUndefined();
  card.bg = () => [{ id: "bg-1", kind: "detached", command: "nohup x &", status: "running", started_at: 1, updated_at: 2, tail: "ok" }];
  expect((card.props() as any).flygo_agent.bg[0]).toMatchObject({ id: "bg-1", status: "running", tail: "ok" });
});

test("bước lệnh bị dừng vì quá hạn hiện ⏱ trên thẻ (run_command và Bash của Claude Code)", async () => {
  const { RunCard } = await import("./card");
  const card = new RunCard({} as any, { channel_id: "c", root_id: "" }, "r", "claude", "t", "u", () => {});
  card.step({ id: "a", kind: "command", title: "grep -rln 129846 data/", status: "done", detail: "…\n⏱ đã dừng sau 120 s" });
  card.step({ id: "b", kind: "command", title: "find / -name x", status: "error", detail: "Command timed out after 2m 0.0s" });
  card.step({ id: "c", kind: "command", title: "ls", status: "done", detail: "a b" });
  const st = (card.props() as any).flygo_agent.steps;
  expect(st[0].title).toBe("⏱ grep -rln 129846 data/ · đã dừng sau 120 s");
  expect(st[0].label).toBe("⏱ đã dừng sau 120 s");
  expect(st[1].title).toContain("⏱ find / -name x");
  expect(st[2].title).toBe("ls");
});

test("bước lệnh có hạn: xong thì ghi thời gian thực tế", async () => {
  const { RunCard } = await import("./card");
  const card = new RunCard({} as any, { channel_id: "c", root_id: "" }, "r", "claude", "t", "u", () => {});
  card.step({ id: "x", kind: "command", title: "$ ls · ⏱ dự kiến 5 s · giới hạn 30 s", status: "running" });
  card.step({ id: "x", kind: "command", title: "$ ls · ⏱ dự kiến 5 s · giới hạn 30 s", status: "done", detail: "a" });
  expect((card.props() as any).flygo_agent.steps[0].title).toMatch(/^\$ ls · ⏱ dự kiến 5 s · giới hạn 30 s · xong sau \d+ s$/);
});
