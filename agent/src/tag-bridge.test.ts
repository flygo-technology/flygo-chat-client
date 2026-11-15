import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { attachedSessions, tagBridge, tagDenied } from "./tag-bridge";

const self = { id: "self0000000000000000000000", username: "ba-claude" };
const codex = { id: "codex000000000000000000000", username: "ba-codex" };
const deep = { id: "deep0000000000000000000000", username: "ba-deepseek" };

describe("tag bridge (bot chỉ nhờ bot được tag / phiên được gắn)", () => {
  test("không tag ai: không có cầu nối, ask_agent bị từ chối", () => {
    const t = tagBridge("post1", [], {}, self);
    expect(t).toBeUndefined();
    expect(tagDenied(t, codex, "")).toContain("không có tin tag");
  });
  test("tag @ba-codex: nhờ được ba-codex, không nhờ được ba-deepseek", () => {
    const t = tagBridge("post1", [self, codex], {}, self);
    expect(t?.post).toBe("post1");
    expect(tagDenied(t, codex, "")).toBe("");
    expect(tagDenied(t, deep, "")).toContain("không được tag");
  });
  test("tag bot nhưng không gắn phiên: không nói thẳng với phiên của nó được", () => {
    const t = tagBridge("post1", [codex], {}, self);
    expect(tagDenied(t, codex, "sessXXXXXXXXXXXXXXXXXXXXXX")).toContain("không được gắn");
  });
  test("gắn phiên: chỉ đúng phiên + đúng bot", () => {
    const props = { flygo_a2a_peers: JSON.stringify([{ bot_id: codex.id, username: codex.username, session_id: "s1" }]) };
    const t = tagBridge("post2", [], props, self);
    expect(tagDenied(t, codex, "s1")).toBe("");
    expect(tagDenied(t, codex, "")).toBe(""); // gắn phiên = cũng như tag bot đó
    expect(tagDenied(t, codex, "s2")).toContain("không được gắn");
    expect(tagDenied(t, deep, "s1")).toContain("không được gắn");
  });
  test("gắn phiên khác của chính mình", () => {
    const t = tagBridge("post3", [], { flygo_a2a_peers: [{ bot_id: self.id, session_id: "own" }] }, self);
    expect(tagDenied(t, self, "own")).toBe("");
    expect(tagDenied(t, self, "other")).toContain("không được gắn");
    expect(t!.bots.has(self.id)).toBe(false);
  });
  test("props hỏng không làm vỡ", () => {
    expect(attachedSessions({ flygo_a2a_peers: "{không phải json" })).toEqual([]);
    expect(attachedSessions(null)).toEqual([]);
  });
});

describe("đã gỡ tool bot ↔ bot ngoài dự án và Remote Control (cc_*)", () => {
  const mcp = readFileSync(join(import.meta.dir, "mcp-chat.ts"), "utf8");
  const runner = readFileSync(join(import.meta.dir, "runner.ts"), "utf8");
  for (const name of ["list_agents", "agent_sessions", "agent_transcript", "cc_list", "cc_read", "cc_ask"]) {
    test(`không còn tool ${name}`, () => {
      expect(mcp).not.toContain(`name: "${name}"`);
      expect(runner).not.toMatch(new RegExp("`- [^`]*\\b" + name + "\\("));
    });
  }
  test("runner không còn đường /cc/ và không đọc ~/.claude/sessions", () => {
    expect(runner).not.toContain('"/cc/"');
    expect(runner).not.toContain('"sessions"), f)');
    expect(runner).not.toContain("--fork-session");
  });
});
