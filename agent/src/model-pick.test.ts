import { expect, test } from "bun:test";
import { pickEffort, pickModel } from "./model-pick";

const MODELS = ["sonnet", "opus", "claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2"];
const INFO = [{ id: "claude-opus-5-5", name: "Opus 5.5" }, { id: "claude-sonnet-5-5", name: "Sonnet 5.5" }, { id: "claude-fable-5-2", name: "Fable 5.2" }];

test("session_new model: id, bí danh, tên hiển thị, gõ thiếu", () => {
  expect(pickModel("sonnet", MODELS, INFO)).toBe("sonnet");
  expect(pickModel("claude-opus-5-5", MODELS, INFO)).toBe("claude-opus-5-5");
  expect(pickModel("Sonnet 5.5", MODELS, INFO)).toBe("claude-sonnet-5-5");
  expect(pickModel("sonnet-5.5", MODELS, INFO)).toBe("claude-sonnet-5-5");
  expect(pickModel("Fable", MODELS, INFO)).toBe("claude-fable-5-2");
  expect(pickModel("gpt-5", MODELS, INFO)).toBeNull();
  expect(pickModel("", MODELS, INFO)).toBeNull();
  expect(pickModel("Haiku 4", MODELS, [{ id: "claude-haiku-4", name: "Haiku 4" }])).toBeNull(); // có tên nhưng bot không dùng được
});

test("session_new effort: không phân biệt hoa thường, chỉ mức có", () => {
  expect(pickEffort("High", ["low", "medium", "high"])).toBe("high");
  expect(pickEffort("max", ["low", "medium", "high"])).toBeNull();
});
