import { test, expect } from "bun:test";
import { ClaudeEngine, modelName, newTurnState } from "./engines/claude";

test("modelName", () => {
  expect(modelName("claude-opus-4-8")).toBe("Opus 4.8");
  expect(modelName("claude-fable-5-2")).toBe("Fable 5.2");
  expect(modelName("claude-sonnet-5")).toBe("Sonnet 5");
});

test("model_refusal_fallback báo bước + usage.model là model thật", () => {
  const steps: any[] = [];
  const hooks: any = { step: (s: any) => steps.push(s), text() {}, session() {} };
  const st = newTurnState();
  const on = (ClaudeEngine.prototype as any).onEvent.bind({});
  on({ type: "system", subtype: "model_refusal_fallback", originalModel: "claude-fable-5-2", fallbackModel: "claude-opus-4-8", apiRefusalCategory: "cyber", scope: "session" }, st, hooks);
  on({ type: "assistant", message: { model: "claude-opus-4-8", content: [] } }, st, hooks);
  on({ type: "result", result: "ok" }, st, hooks);
  expect(steps[0].title).toContain("Fable 5.2");
  expect(steps[0].title).toContain("Opus 4.8");
  expect(st.usage.model).toBe("claude-opus-4-8");
});
