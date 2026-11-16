import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mergeLayers, parseMachineConfig, resolveBots } from "./machine-config";

const base = (bots: any[], extra: any = {}) => parseMachineConfig({
  version: 2,
  owners: { "https://chat.a.example/": "uA", "https://chat.b.example": "uB" },
  defaults: { projectRoots: ["/tmp"], claude: { bin: "claude-x" } },
  servers: { "https://chat.a.example": { a2a: { relay: "wss://push.a.example/a2a/connect" } } },
  bots,
  ...extra,
});

test("gộp defaults → servers → bot, codex/claude gộp một tầng", () => {
  const [b] = resolveBots(base([{ key: "c1", serverUrl: "https://chat.a.example", botToken: "t", engine: "claude", claude: { model: "sonnet" } }]));
  expect(b.error).toBeUndefined();
  expect(b.cfg!.claude.bin).toBe("claude-x");
  expect(b.cfg!.claude.model).toBe("sonnet");
  expect(b.cfg!.a2a.relay).toBe("wss://push.a.example/a2a/connect");
  expect(b.cfg!.ownerUserIds).toEqual(["uA"]);
  expect(b.cfg!.runnerOwner).toBe("uA");
  expect(b.cfg!.projectRoots).toEqual(["/tmp"]);
});

test("runner chưa đăng nhập máy chủ của bot: không chạy", () => {
  const [b] = resolveBots(base([{ key: "x", serverUrl: "https://chat.c.example", botToken: "t", engine: "codex" }]));
  expect(b.cfg).toBeUndefined();
  expect(b.error).toContain("chưa đăng nhập máy chủ");
});

test("bot của người khác: không chạy trên runner này", () => {
  const [b] = resolveBots(base([{ key: "x", serverUrl: "https://chat.b.example", botToken: "t", engine: "codex", ownerUserIds: ["uOther"] }]));
  expect(b.cfg).toBeUndefined();
  expect(b.error).toContain("không thuộc chủ runner");
});

test("botTokenFile tương đối theo thư mục runner.json; enabled=false giữ nhưng tắt", () => {
  const d = mkdtempSync(join(tmpdir(), "mc-"));
  writeFileSync(join(d, "tok"), "secret\n");
  const [b] = resolveBots(base([{ key: "f", serverUrl: "https://chat.b.example", botTokenFile: "tok", engine: "agy", enabled: false }]), d);
  expect(b.cfg!.botToken).toBe("secret");
  expect(b.enabled).toBe(false);
});

test("hash đổi khi cấu hình bot đổi, không đổi khi bot khác đổi", () => {
  const b1 = { key: "a", serverUrl: "https://chat.a.example", botToken: "t", engine: "claude" };
  const b2 = { key: "b", serverUrl: "https://chat.a.example", botToken: "t2", engine: "codex" };
  const h1 = resolveBots(base([b1, b2]));
  const h2 = resolveBots(base([b1, { ...b2, engine: "agy" }]));
  expect(h1[0].hash).toBe(h2[0].hash);
  expect(h1[1].hash).not.toBe(h2[1].hash);
});

test("key trùng / sai / version sai bị từ chối", () => {
  expect(() => base([{ key: "a" }, { key: "a" }])).toThrow("trùng key");
  expect(() => base([{ key: "a b" }])).toThrow("key không hợp lệ");
  expect(() => parseMachineConfig({ version: 1, bots: [] })).toThrow("version");
});

test("mergeLayers: env gộp, mảng thay hẳn", () => {
  expect(mergeLayers({ env: { A: "1" }, projectRoots: ["x"] }, { env: { B: "2" }, projectRoots: ["y"] })).toEqual({ env: { A: "1", B: "2" }, projectRoots: ["y"] });
});
