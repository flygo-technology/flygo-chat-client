import { expect, test } from "bun:test";
import { normTodos } from "./todos";

test("claude TodoWrite input", () => {
  expect(normTodos({ todos: [
    { content: "Check how claude-rc is run", status: "in_progress", activeForm: "Checking" },
    { content: "Stop old and start new", status: "pending", activeForm: "Stopping" },
    { content: "Verify it connects", status: "completed", activeForm: "Verifying" },
  ] })).toEqual([
    { text: "Check how claude-rc is run", status: "in_progress" },
    { text: "Stop old and start new", status: "pending" },
    { text: "Verify it connects", status: "completed" },
  ]);
});

test("codex turn/plan/updated params", () => {
  expect(normTodos({ threadId: "t", turnId: "u", explanation: null, plan: [{ step: "Read code", status: "completed" }, { step: "Patch", status: "inProgress" }, { step: "Test", status: "pending" }] }))
    .toEqual([{ text: "Read code", status: "completed" }, { text: "Patch", status: "in_progress" }, { text: "Test", status: "pending" }]);
});

test("agy shapes: JSON string, plain strings, unknown status", () => {
  expect(normTodos(JSON.stringify({ items: [{ title: "A", state: "DONE" }, "B", { text: "  C  ", status: "weird" }] })))
    .toEqual([{ text: "A", status: "completed" }, { text: "B", status: "pending" }, { text: "C", status: "pending" }]);
});

test("not a list", () => {
  expect(normTodos({ foo: 1 })).toBeNull();
  expect(normTodos("not json")).toBeNull();
  expect(normTodos({ todos: [] })).toEqual([]);
});
