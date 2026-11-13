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

test("wrap_up: recap, ask needs actions, completes in-progress unless blocked", () => {
  const c = card();
  c.updatePlan({ items: [{ content: "A", status: "completed" }, { content: "B", status: "in_progress" }] });
  expect(c.setWrapUp({ recap: "" })).toBe("Thiếu recap.");
  c.setWrapUp({ recap: "Waiting for a code", blocked: true });
  expect(c.todos[1].status).toBe("in_progress");
  expect(c.setWrapUp({ recap: "Done", ask: "Restart?", actions: [{ label: "Yes" }, { label: "No" }] })).toContain("đừng hỏi lại");
  expect(c.todos[1].status).toBe("completed");
  expect((c.props() as any).flygo_agent.wrap_up).toEqual({ recap: "Done", ask: "Restart?", actions: ["Yes", "No"] });
  c.setWrapUp({ recap: "Only recap", ask: "Q?" });
  expect((c.props() as any).flygo_agent.wrap_up).toEqual({ recap: "Only recap" });
});
