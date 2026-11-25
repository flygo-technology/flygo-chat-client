import { expect, test } from "bun:test";
import { leanEnv } from "./engines/claude";
import { desktopMcp } from "./desktop-mcp";

test("env gọn cho Claude Code: nén ở 180k, không connector claude.ai, trần output; env có sẵn thắng", () => {
  const keep = { ...process.env };
  for (const k of ["CLAUDE_CODE_AUTO_COMPACT_WINDOW", "ENABLE_CLAUDEAI_MCP_SERVERS", "BASH_MAX_OUTPUT_LENGTH", "MAX_MCP_OUTPUT_TOKENS"]) delete process.env[k];
  expect(leanEnv()).toEqual({ CLAUDE_CODE_AUTO_COMPACT_WINDOW: "180000", ENABLE_CLAUDEAI_MCP_SERVERS: "false", BASH_MAX_OUTPUT_LENGTH: "12000", MAX_MCP_OUTPUT_TOKENS: "10000" });
  expect(leanEnv(250_000).CLAUDE_CODE_AUTO_COMPACT_WINDOW).toBe("250000");
  expect(leanEnv(0).CLAUDE_CODE_AUTO_COMPACT_WINDOW).toBeUndefined();
  process.env.BASH_MAX_OUTPUT_LENGTH = "50000";
  expect(leanEnv().BASH_MAX_OUTPUT_LENGTH).toBeUndefined();
  process.env = keep;
});

test("desktop MCP chỉ bật khi bot được cấu hình điều khiển máy", () => {
  expect(Object.keys(desktopMcp({ botToken: "a" }).servers)).toEqual([]);
  expect(Object.keys(desktopMcp({ botToken: "b", computerUse: false }).servers)).toEqual([]);
  // bật: có thể vẫn rỗng nếu máy test không cài server nào; quan trọng là không bị chặn bởi điều kiện
  expect(desktopMcp({ botToken: "c", computerUse: true, desktopMcp: { mine: { command: "/bin/true", args: [] } } }).servers.mine).toBeDefined();
  expect(desktopMcp({ botToken: "d", desktopMcp: { mine: { command: "/bin/true", args: [] } } }).servers.mine).toBeDefined();
});
