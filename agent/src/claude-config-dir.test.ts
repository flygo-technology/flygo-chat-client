import { expect, test } from "bun:test";
import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { claudeConfigDir, claudeEnv } from "./config";
import { doctor } from "./doctor";
import { ClaudeEngine } from "./engines/claude";

test("CLAUDE_CONFIG_DIR của bot thắng env tiến trình; ~ được mở rộng", () => {
  const old = process.env.CLAUDE_CONFIG_DIR;
  delete process.env.CLAUDE_CONFIG_DIR;
  expect(claudeConfigDir({})).toBe(join(homedir(), ".claude"));
  expect(claudeConfigDir({ env: { CLAUDE_CONFIG_DIR: "~/.config/flygo-agent/claude-ba-claude2" } })).toBe(join(homedir(), ".config/flygo-agent/claude-ba-claude2"));
  process.env.CLAUDE_CONFIG_DIR = "/proc-wide";
  expect(claudeConfigDir({})).toBe("/proc-wide");
  expect(claudeConfigDir({ env: { CLAUDE_CONFIG_DIR: "/bot2" } })).toBe("/bot2");
  expect(claudeEnv({ env: { CLAUDE_CONFIG_DIR: "/bot2" } }, { X: "1" })).toMatchObject({ CLAUDE_CONFIG_DIR: "/bot2", X: "1" });
  if (old === undefined) delete process.env.CLAUDE_CONFIG_DIR; else process.env.CLAUDE_CONFIG_DIR = old;
});

test("kiểm tra đăng nhập (auth status) chạy với env của bot: tài khoản thứ hai đăng xuất thì báo chưa đăng nhập", async () => {
  const d = mkdtempSync(join(tmpdir(), "cc-"));
  const bin = join(d, "claude");
  // CLI giả: chỉ "đăng nhập" khi CLAUDE_CONFIG_DIR là thư mục mặc định của người dùng
  writeFileSync(bin, `#!/bin/sh\nif [ "$1" = "--version" ]; then echo "9.9.9 (Claude Code)"; exit 0; fi\nif [ "$CLAUDE_CONFIG_DIR" = "/bot2" ]; then echo '{"loggedIn":false}'; exit 1; fi\necho '{"loggedIn":true,"email":"ba@flygo.vn"}'\n`);
  chmodSync(bin, 0o755);
  expect((await doctor({ claude: bin })).claude.loggedIn).toBe(true);
  const r = await doctor({ claude: bin, claudeEnv: { CLAUDE_CONFIG_DIR: "/bot2" } });
  expect(r.claude.loggedIn).toBe(false);
});

test("engine claude tìm phiên trong <CLAUDE_CONFIG_DIR của bot>/projects", () => {
  const e = new ClaudeEngine({ env: { CLAUDE_CONFIG_DIR: "/bot2" }, claude: {} } as any);
  expect(e.projectsDir()).toBe("/bot2/projects");
});
