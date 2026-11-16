import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildPlan, keyOf, plistArgs, runConfigOf, splitExec, type LegacyService } from "./migrate";

test("đọc --config của lệnh run từ plist / ExecStart; bỏ qua codex-shared", () => {
  const xml = `<key>ProgramArguments</key><array><string>/Users/x/.local/share/flygo-agent/flygo-agent</string><string>run</string><string>--config</string><string>/Users/x/.config/flygo-agent/config-a&amp;b.json</string></array>`;
  expect(runConfigOf(plistArgs(xml))).toBe("/Users/x/.config/flygo-agent/config-a&b.json");
  expect(runConfigOf(splitExec(`"/home/u/bin/flygo-agent" "run" "--config" "/home/u/.config/flygo-agent/config-d.json"`))).toBe("/home/u/.config/flygo-agent/config-d.json");
  expect(runConfigOf(splitExec(`/home/u/bin/flygo-agent codex-shared --config /x.json`))).toBeNull();
  expect(keyOf("/a/config.json")).toBe("default");
  expect(keyOf("/a/config-ba.codex.json")).toBe("ba.codex");
});

test("kế hoạch gộp: chỉ bot của chủ runner, có dịch vụ đang bật, lọc theo máy chủ", () => {
  const d = mkdtempSync(join(tmpdir(), "mig-"));
  const w = (n: string, o: any) => writeFileSync(join(d, n), JSON.stringify(o));
  w("config.json", { serverUrl: "https://chat.a.example", botToken: "t1", ownerUserIds: ["uA"], engine: "codex" });
  w("config-sep.json", { serverUrl: "https://chat.a.example", botToken: "t2", ownerUserIds: ["uA"], engine: "claude" });
  w("config-dnd.json", { serverUrl: "https://chat.b.example", botToken: "t3", ownerUserIds: ["uB"], engine: "claude" });
  w("config-other.json", { serverUrl: "https://chat.a.example", botToken: "t4", ownerUserIds: ["uX"], engine: "claude" });
  w("config-off.json", { serverUrl: "https://chat.a.example", botToken: "t5", ownerUserIds: ["uA"], engine: "claude" });
  const svc = (n: string, active = true): LegacyService => ({ platform: "linux", name: `flygo-agent-${n}`, file: `/u/${n}.service`, dropins: [], config: join(d, n === "default" ? "config.json" : `config-${n}.json`), active });
  const services = [svc("default"), svc("sep"), svc("dnd"), svc("other"), svc("off", false)];
  // Hai chủ trên chat.a: phải chỉ định --owner
  let p = buildPlan({ dir: d, services });
  expect(p.bots.map((b) => b.key).sort()).toEqual(["dnd"]);
  expect(p.skipped.find((s) => s.key === "sep")!.reason).toContain("--owner");
  p = buildPlan({ dir: d, services, owners: { "https://chat.a.example": "uA" } });
  expect(p.bots.map((b) => b.key).sort()).toEqual(["default", "dnd", "sep"]);
  expect(p.skipped.find((s) => s.key === "other")!.reason).toContain("người khác");
  expect(p.skipped.find((s) => s.key === "off")!.reason).toContain("không có dịch vụ");
  expect(p.owners).toEqual({ "https://chat.a.example": "uA", "https://chat.b.example": "uB" });
  p = buildPlan({ dir: d, services, owners: { "https://chat.a.example": "uA" }, onlyServer: "https://chat.a.example/" });
  expect(p.bots.map((b) => b.key).sort()).toEqual(["default", "sep"]);
  p = buildPlan({ dir: d, services, owners: { "https://chat.a.example": "uA" }, existing: { owners: {}, bots: [{ key: "sep" }] } });
  expect(p.skipped.find((s) => s.key === "sep")!.reason).toContain("đã có");
  // Lần gộp trước trả về dịch vụ cũ (enabled:false) mà dịch vụ cũ còn chạy: lần sau bật lại
  p = buildPlan({ dir: d, services, owners: { "https://chat.a.example": "uA" }, existing: { owners: {}, bots: [{ key: "sep", enabled: false }] } });
  expect(p.bots.find((b) => b.key === "sep")!.reenable).toBe(true);
});
