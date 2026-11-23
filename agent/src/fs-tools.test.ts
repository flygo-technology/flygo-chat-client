import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync, existsSync, readFileSync, mkdirSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";
import { absPath, forbidden, fsTool } from "./fs-tools";

const yes = async () => true;
const no = async () => false;

test("fs-tools: read, write, copy, move; writes need approval", async () => {
  const d = mkdtempSync(join(tmpdir(), "fst-"));
  expect(await fsTool("file_write", { path: "a.txt", content: "x" }, no, d)).toContain("không duyệt");
  expect(existsSync(join(d, "a.txt"))).toBe(false);
  await fsTool("file_write", { path: "a.txt", content: "dòng 1\ndòng 2" }, yes, d);
  expect(await fsTool("file_read", { path: "a.txt" }, no, d)).toContain("2\tdòng 2");
  await fsTool("file_copy", { from: "a.txt", to: "sub/b.txt" }, yes, d);
  expect(readFileSync(join(d, "sub/b.txt"), "utf8")).toBe("dòng 1\ndòng 2");
  await expect(fsTool("file_copy", { from: "a.txt", to: "sub/b.txt" }, yes, d)).rejects.toThrow("đích đã có");
  await fsTool("file_move", { from: "a.txt", to: "c.txt" }, yes, d);
  expect(existsSync(join(d, "a.txt"))).toBe(false);
  expect(existsSync(join(d, "c.txt"))).toBe(true);
  expect(await fsTool("file_read", { path: "." }, no, d)).toContain("sub/");
});

test("fs-tools: keys and tokens are off limits", async () => {
  expect(forbidden(join(homedir(), ".ssh/id_ed25519"))).toBe(true);
  expect(forbidden(join(homedir(), ".config/flygo-agent/x"))).toBe(true);
  expect(forbidden(join(homedir(), "work/a.txt"))).toBe(false);
  await expect(fsTool("file_read", { path: "~/.ssh/config" }, yes)).rejects.toThrow("khoá / token");
  expect(absPath("~/x")).toBe(join(homedir(), "x"));
});

test("fs-tools: trash refuses home and root, run_command reports exit code", async () => {
  await expect(fsTool("file_trash", { path: "~" }, yes)).rejects.toThrow("thư mục nhà");
  const d = mkdtempSync(join(tmpdir(), "fst-"));
  expect(await fsTool("run_command", { command: "echo hi; exit 3" }, yes, d)).toContain("Mã thoát 3\nhi");
  expect(await fsTool("run_command", { command: "echo hi" }, no, d)).toContain("không duyệt");
});

test("run_command quá hạn: dừng cả tiến trình con, trả output đã có + gợi ý", async () => {
  const { fsTool } = await import("./fs-tools");
  const dir = (await import("node:os")).tmpdir();
  const t0 = Date.now();
  // bash -lc → sh → sleep: phải dừng cả cây, không chờ sleep 30
  const r = await fsTool("run_command", { command: "echo bat-dau; sh -c 'sleep 30'; echo khong-toi", timeout_sec: 1 }, async () => true, dir);
  expect(Date.now() - t0).toBeLessThan(8000);
  expect(r).toContain("⏱ Lệnh chạy quá 1 s nên đã bị dừng");
  expect(r).toContain("rg -l");
  expect(r).toContain("bat-dau");
  expect(r.split("--- output tới lúc dừng ---")[1]).not.toContain("khong-toi");
  expect(r.trim().endsWith("⏱ đã dừng sau 1 s")).toBe(true);
  // tiến trình sleep 30 không còn sót
  const left = Bun.spawnSync(["pgrep", "-f", "sleep 30"]).stdout.toString().trim();
  expect(left).toBe("");
});

test("run_command thường: mã thoát + output như cũ; hạn mặc định theo FLYGO_CMD_TIMEOUT_SEC", async () => {
  const { fsTool, defaultCmdTimeoutSec } = await import("./fs-tools");
  expect(await fsTool("run_command", { command: "echo ok" }, async () => true, (await import("node:os")).tmpdir())).toBe("Mã thoát 0\nok\n");
  const old = process.env.FLYGO_CMD_TIMEOUT_SEC;
  process.env.FLYGO_CMD_TIMEOUT_SEC = "45"; expect(defaultCmdTimeoutSec()).toBe(45);
  delete process.env.FLYGO_CMD_TIMEOUT_SEC; expect(defaultCmdTimeoutSec()).toBe(120);
  if (old !== undefined) process.env.FLYGO_CMD_TIMEOUT_SEC = old;
});
