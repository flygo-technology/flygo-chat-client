// `flygo-agent migrate`: gộp các runner một-bot cũ (mỗi bot một dịch vụ) thành runner chung (một dịch vụ, runner.json).
//   migrate [--dry-run] [--only-server <url>] [--exclude <key>]… [--owner <url>=<user id>]… [--json]
//   migrate --rollback [--from <thư mục legacy-…>]
// An toàn:
// - File cấu hình cũ GIỮ NGUYÊN chỗ cũ; bản sao + plist/unit/drop-in vào ~/.config/flygo-agent/legacy-<thời điểm>/ cùng manifest.json.
// - Dịch vụ cũ chỉ bị tắt (macOS: bootout + đổi plist thành .migrated; Linux: disable --now; Windows: /DISABLE), không xoá.
// - Chỉ gộp bot của CHỦ RUNNER (runner thuộc một người); bot của người khác bị bỏ ra, giữ dịch vụ cũ.
// - Bot không lên được trong runner chung (90 giây) thì tự bật lại dịch vụ cũ của riêng bot đó.
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir, hostname } from "node:os";
import { basename, join } from "node:path";
import { CONFIG_DIR, normHost } from "./config";
import { MACHINE_CONFIG, normServer } from "./machine-config";
import { installMachineService, machineServiceStatus, uninstallMachineService } from "./service";
import { ctl } from "./supervisor";
import { spawn, spawnSync } from "./spawn";

const home = homedir();
const sh = (cmd: string[]) => { const p = spawnSync(cmd, { stdout: "pipe", stderr: "pipe" }); return { code: p.exitCode, out: (p.stdout.toString() + p.stderr.toString()).trim() }; };

export interface LegacyService {
  platform: NodeJS.Platform;
  /** macOS label / systemd unit / Windows task. */
  name: string;
  /** plist / unit file (Windows: tên task). */
  file: string;
  dropins: string[];
  config: string;
  active: boolean;
  /** Windows: tác vụ Task Scheduler ("task") hay khoá Run của người dùng ("run", máy không có quyền quản trị); cmd = lệnh chạy. */
  win?: { kind: "task" | "run"; cmd: string; xml?: string };
}
export interface PlanBot { key: string; config: string; server: string; engine: string; owner: string; service?: LegacyService }
export interface Plan {
  bots: PlanBot[];
  skipped: { config: string; key: string; reason: string }[];
  owners: Record<string, string>;
  runnerJson: string;
}

const xmlUnescape = (s: string) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&");

/** Đối số `--config <file>` của lệnh `run` trong dịch vụ cũ; null = không phải runner một bot (vd. codex-shared, machine). */
export function runConfigOf(args: string[]): string | null {
  const i = args.indexOf("run");
  if (i < 0) return null;
  const c = args.indexOf("--config");
  return c > i && args[c + 1] ? args[c + 1] : null;
}

/** Tách ExecStart của systemd (các đối số được JSON.stringify hoặc không có ngoặc). */
export function splitExec(line: string): string[] {
  const out: string[] = [];
  const re = /"((?:[^"\\]|\\.)*)"|(\S+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(line))) out.push(m[1] !== undefined ? JSON.parse(`"${m[1]}"`) : m[2]);
  return out;
}

export function plistArgs(xml: string): string[] {
  const arr = /<key>ProgramArguments<\/key>\s*<array>([\s\S]*?)<\/array>/.exec(xml)?.[1] ?? "";
  return [...arr.matchAll(/<string>([\s\S]*?)<\/string>/g)].map((m) => xmlUnescape(m[1]));
}

/** Dịch vụ runner một-bot đang cài trên máy (theo người dùng hiện tại). */
export function scanServices(): LegacyService[] {
  const out: LegacyService[] = [];
  if (process.platform === "darwin") {
    const dir = join(home, "Library", "LaunchAgents");
    if (!existsSync(dir)) return out;
    for (const f of readdirSync(dir)) {
      if (!/^vn\.flygo\.agent\.runner.*\.plist(\.disabled)?$/.test(f)) continue;
      const file = join(dir, f);
      const config = runConfigOf(plistArgs(readFileSync(file, "utf8")));
      if (!config) continue;
      const label = f.replace(/\.plist(\.disabled)?$/, "");
      out.push({ platform: "darwin", name: label, file, dropins: [], config, active: !f.endsWith(".disabled") });
    }
  } else if (process.platform === "linux") {
    const dir = join(home, ".config", "systemd", "user");
    if (!existsSync(dir)) return out;
    for (const f of readdirSync(dir)) {
      if (!/^flygo-agent.*\.service$/.test(f) || f === "flygo-agent-machine.service") continue;
      const file = join(dir, f);
      const unit = f.replace(/\.service$/, "");
      const dDir = join(dir, `${f}.d`);
      const dropins = existsSync(dDir) ? readdirSync(dDir).filter((x) => x.endsWith(".conf")).map((x) => join(dDir, x)) : [];
      // ExecStart cuối cùng thắng (drop-in có thể đổi binary nhưng vẫn giữ --config).
      const lines = [readFileSync(file, "utf8"), ...dropins.map((d) => readFileSync(d, "utf8"))].flatMap((t) => t.split("\n")).filter((l) => /^ExecStart=\S/.test(l.trim()));
      const last = lines.at(-1);
      const config = last ? runConfigOf(splitExec(last.trim().slice("ExecStart=".length))) : null;
      if (!config) continue;
      const active = sh(["systemctl", "--user", "is-enabled", unit]).out === "enabled" || sh(["systemctl", "--user", "is-active", unit]).out === "active";
      out.push({ platform: "linux", name: unit, file, dropins, config, active });
    }
  } else {
    const q = sh(["schtasks", "/Query", "/FO", "CSV", "/V", "/NH"]);
    const seen = new Set<string>();
    for (const line of q.out.split(/\r?\n/)) {
      const cols = [...line.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
      const name = cols.find((c) => /^\\?FlygoAgent(-|$)/.test(c));
      if (!name || /FlygoAgentMachine$/.test(name)) continue;
      const tn = name.replace(/^\\/, "");
      if (seen.has(tn)) continue; // CSV /V: mỗi trigger một dòng
      const tr = cols.find((c) => /flygo-agent/i.test(c) && / run /.test(c)) ?? "";
      const config = runConfigOf(splitExec(tr));
      if (!config) continue;
      seen.add(tn);
      out.push({ platform: "win32", name: tn, file: tn, dropins: [], config, active: !cols.some((c) => c === "Disabled"), win: { kind: "task", cmd: tr } });
    }
    // Máy không có quyền quản trị: chạy khi đăng nhập bằng khoá Run (service.ts).
    const r = sh(["reg", "query", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"]);
    for (const line of r.out.split(/\r?\n/)) {
      const m = /^\s*(FlygoAgent-[^\s]+|FlygoAgent)\s+REG_SZ\s+(.+)$/.exec(line);
      if (!m || m[1] === "FlygoAgentMachine" || seen.has(m[1])) continue;
      const config = runConfigOf(splitExec(m[2]));
      if (!config) continue;
      out.push({ platform: "win32", name: m[1], file: m[1], dropins: [], config, active: true, win: { kind: "run", cmd: m[2].trim() } });
    }
  }
  return out;
}

const keyOf = (configPath: string) => basename(configPath).replace(/\.json$/, "").replace(/^config-?/, "").replace(/[^A-Za-z0-9._-]/g, "_") || "default";

export function buildPlan(o: { onlyServer?: string; exclude?: string[]; owners?: Record<string, string>; services?: LegacyService[]; existing?: any; dir?: string } = {}): Plan {
  const dirC = o.dir ?? CONFIG_DIR;
  const services = o.services ?? scanServices();
  const byConfig = new Map(services.map((s) => [s.config, s]));
  const configs = existsSync(dirC) ? readdirSync(dirC).filter((f) => /^config(-.+)?\.json$/.test(f)).map((f) => join(dirC, f)) : [];
  for (const s of services) if (!configs.includes(s.config) && existsSync(s.config)) configs.push(s.config);
  const plan: Plan = { bots: [], skipped: [], owners: { ...(o.existing?.owners ?? {}) }, runnerJson: MACHINE_CONFIG };
  for (const [k, v] of Object.entries(o.owners ?? {})) plan.owners[normServer(k)] = v;
  const have = new Set<string>((o.existing?.bots ?? []).map((b: any) => b.key));
  const cand: PlanBot[] = [];
  for (const config of configs) {
    const key = keyOf(config);
    const svc = byConfig.get(config);
    let raw: any;
    try { raw = JSON.parse(readFileSync(config, "utf8")); } catch (e: any) { plan.skipped.push({ config, key, reason: `không đọc được: ${e?.message ?? e}` }); continue; }
    const server = normServer(raw.serverUrl ?? "");
    if (!svc || !svc.active) { plan.skipped.push({ config, key, reason: "không có dịch vụ đang bật (bot không chạy nền trên máy này)" }); continue; }
    if (!raw.botToken || !server || !raw.engine) { plan.skipped.push({ config, key, reason: "cấu hình thiếu serverUrl / botToken / engine" }); continue; }
    if (o.onlyServer && server !== normServer(o.onlyServer)) { plan.skipped.push({ config, key, reason: `khác máy chủ (${server})` }); continue; }
    if (o.exclude?.includes(key)) { plan.skipped.push({ config, key, reason: "bị loại (--exclude)" }); continue; }
    if (have.has(key)) { plan.skipped.push({ config, key, reason: "đã có trong runner.json" }); continue; }
    cand.push({ key, config, server, engine: raw.engine, owner: String(raw.ownerUserIds?.[0] ?? ""), service: svc });
  }
  // Chủ runner theo từng máy chủ: lấy từ --owner / runner.json sẵn có; không có thì người chủ của các bot cũ, nếu tất cả cùng một người.
  for (const server of new Set(cand.map((c) => c.server))) {
    if (plan.owners[server]) continue;
    const ids = [...new Set(cand.filter((c) => c.server === server).map((c) => c.owner).filter(Boolean))];
    if (ids.length === 1) plan.owners[server] = ids[0];
  }
  for (const c of cand) {
    const owner = plan.owners[c.server];
    if (!owner) { plan.skipped.push({ config: c.config, key: c.key, reason: `nhiều chủ khác nhau trên ${c.server}: chỉ định --owner ${c.server}=<user id của chủ runner>` }); continue; }
    if (c.owner !== owner) { plan.skipped.push({ config: c.config, key: c.key, reason: `bot của người khác (${c.owner}), runner thuộc ${owner}: giữ dịch vụ cũ` }); continue; }
    plan.bots.push(c);
  }
  return plan;
}

function disableService(s: LegacyService) {
  if (s.platform === "darwin") {
    sh(["launchctl", "bootout", `gui/${process.getuid!()}/${s.name}`]);
    if (existsSync(s.file) && s.file.endsWith(".plist")) renameSync(s.file, `${s.file}.migrated`);
  } else if (s.platform === "linux") {
    sh(["systemctl", "--user", "disable", "--now", s.name]);
    // Đổi tên unit để app cũ (syncBundledRunner) không thấy "đã cài" rồi cài lại dịch vụ một-bot.
    if (existsSync(s.file)) renameSync(s.file, `${s.file}.migrated`);
    sh(["systemctl", "--user", "daemon-reload"]);
  } else if (s.win?.kind === "run") {
    sh(["reg", "delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", s.name, "/f"]);
    stopWin(s.config);
  } else {
    // Xoá hẳn tác vụ (đã lưu XML trong bản sao lưu): app cũ thấy tác vụ còn (dù tắt) sẽ cài lại runner một-bot.
    sh(["schtasks", "/End", "/TN", s.name]);
    sh(["schtasks", "/Delete", "/F", "/TN", s.name]);
    stopWin(s.config);
  }
}

function stopWin(config: string) {
  const esc = config.replace(/'/g, "''");
  sh(["powershell", "-NoProfile", "-Command", `Get-CimInstance Win32_Process -Filter "Name='flygo-agent.exe'" | Where-Object { $_.CommandLine -like '*${esc}*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`]);
}

function enableService(s: LegacyService) {
  if (s.platform === "darwin") {
    const migrated = `${s.file}.migrated`;
    if (existsSync(migrated)) renameSync(migrated, s.file);
    sh(["launchctl", "bootstrap", `gui/${process.getuid!()}`, s.file]);
    sh(["launchctl", "kickstart", `gui/${process.getuid!()}/${s.name}`]);
  } else if (s.platform === "linux") {
    if (existsSync(`${s.file}.migrated`)) renameSync(`${s.file}.migrated`, s.file);
    sh(["systemctl", "--user", "daemon-reload"]);
    sh(["systemctl", "--user", "enable", "--now", s.name]);
  } else if (s.win?.kind === "run") {
    sh(["reg", "add", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", s.name, "/t", "REG_SZ", "/d", s.win.cmd, "/f"]);
    const args = splitExec(s.win.cmd);
    if (args.length) spawn(args, { stdin: "ignore", stdout: "ignore", stderr: "ignore" }).unref();
  } else {
    if (s.win?.xml && existsSync(s.win.xml)) sh(["schtasks", "/Create", "/F", "/TN", s.name, "/XML", s.win.xml]);
    sh(["schtasks", "/Run", "/TN", s.name]);
  }
}

const stamp = () => new Date().toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 13);

export async function migrate(o: { selfCommand: string[]; dryRun?: boolean; onlyServer?: string; exclude?: string[]; owners?: Record<string, string>; verifyMs?: number; log: (s: string) => void }) {
  const existing = existsSync(MACHINE_CONFIG) ? JSON.parse(readFileSync(MACHINE_CONFIG, "utf8")) : null;
  const plan = buildPlan({ onlyServer: o.onlyServer, exclude: o.exclude, owners: o.owners, existing });
  if (o.dryRun || !plan.bots.length) return { ok: true, dryRun: !!o.dryRun, plan: redactPlan(plan) };

  // 1. sao lưu
  const dir = join(CONFIG_DIR, `legacy-${stamp()}`);
  mkdirSync(dir, { recursive: true });
  for (const b of plan.bots) {
    copyFileSync(b.config, join(dir, basename(b.config)));
    const s = b.service!;
    if (s.platform !== "win32" && existsSync(s.file)) copyFileSync(s.file, join(dir, basename(s.file)));
    if (s.platform === "win32" && s.win?.kind === "task") {
      const x = sh(["schtasks", "/Query", "/TN", s.name, "/XML"]);
      if (x.code === 0) { s.win.xml = join(dir, `${s.name}.xml`); writeFileSync(s.win.xml, x.out, "utf16le"); }
    }
    for (const d of s.dropins) { mkdirSync(join(dir, `${basename(s.file)}.d`), { recursive: true }); copyFileSync(d, join(dir, `${basename(s.file)}.d`, basename(d))); }
  }
  if (existing) copyFileSync(MACHINE_CONFIG, join(dir, "runner.json.before"));
  const manifest = { created: new Date().toISOString(), runnerJsonExisted: !!existing, machineServiceExisted: machineServiceStatus().installed, bots: plan.bots.map((b) => ({ key: b.key, config: b.config, service: b.service })) };
  writeFileSync(join(dir, "manifest.json"), JSON.stringify(manifest, null, 2), { mode: 0o600 });
  o.log(`đã sao lưu vào ${dir}`);

  // 2. runner.json (gộp vào bản có sẵn)
  const mc = existing ?? { version: 2, machine: { name: normHost(hostname()) }, owners: {}, defaults: {}, servers: {}, bots: [] };
  mc.owners = { ...(mc.owners ?? {}), ...plan.owners };
  for (const b of plan.bots) {
    const raw = JSON.parse(readFileSync(b.config, "utf8"));
    mc.bots.push({ key: b.key, ...raw, migratedFrom: b.config });
  }
  writeJson(MACHINE_CONFIG, mc);

  // 3. tắt dịch vụ cũ rồi cài / khởi động lại runner chung
  for (const b of plan.bots) disableService(b.service!);
  await Bun.sleep(3000); // runner cũ tắt êm (chốt thẻ, xoá khoá)
  installMachineService(o.selfCommand, MACHINE_CONFIG);
  o.log("đã cài dịch vụ runner chung");

  // 4. kiểm: bot nào không lên thì trả về dịch vụ cũ
  const failed = await verify(plan.bots.map((b) => b.key), o.verifyMs ?? 90_000);
  if (failed.length) {
    const cur = JSON.parse(readFileSync(MACHINE_CONFIG, "utf8"));
    for (const b of cur.bots) if (failed.some((f) => f.key === b.key)) b.enabled = false;
    writeJson(MACHINE_CONFIG, cur);
    await Bun.sleep(2000);
    for (const f of failed) { const b = plan.bots.find((x) => x.key === f.key)!; enableService(b.service!); o.log(`bot ${f.key} không lên trong runner chung (${f.why}): bật lại dịch vụ cũ`); }
  }
  return { ok: failed.length === 0, backup: dir, plan: redactPlan(plan), failed };
}

async function verify(keys: string[], ms: number): Promise<{ key: string; why: string }[]> {
  const t0 = Date.now();
  let last: any = null;
  while (Date.now() - t0 < ms) {
    await Bun.sleep(3000);
    last = await ctl("status").catch(() => null);
    if (!last?.bots) continue;
    const bad = keys.filter((k) => last.bots.find((b: any) => b.key === k)?.phase !== "running");
    if (!bad.length) return [];
    // lỗi vĩnh viễn thì khỏi chờ
    if (bad.every((k) => last.bots.find((b: any) => b.key === k)?.phase === "error")) break;
  }
  return keys.filter((k) => last?.bots?.find((b: any) => b.key === k)?.phase !== "running")
    .map((k) => { const b = last?.bots?.find((x: any) => x.key === k); return { key: k, why: b?.error?.message ?? b?.phase ?? "runner chung không trả lời" }; });
}

export async function rollback(o: { from?: string; log: (s: string) => void }) {
  const dirs = existsSync(CONFIG_DIR) ? readdirSync(CONFIG_DIR).filter((d) => d.startsWith("legacy-")).sort() : [];
  const dir = o.from ?? (dirs.length ? join(CONFIG_DIR, dirs.at(-1)!) : "");
  if (!dir || !existsSync(join(dir, "manifest.json"))) throw new Error("không thấy bản sao lưu legacy-…/manifest.json");
  const m = JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  if (m.machineServiceExisted && m.runnerJsonExisted && existsSync(join(dir, "runner.json.before"))) {
    // Runner chung đã có từ trước lần gộp này: chỉ bỏ các bot của lần gộp này.
    writeJson(MACHINE_CONFIG, JSON.parse(readFileSync(join(dir, "runner.json.before"), "utf8")));
    await Bun.sleep(3000);
  } else {
    uninstallMachineService();
    if (existsSync(MACHINE_CONFIG)) renameSync(MACHINE_CONFIG, `${MACHINE_CONFIG}.rolledback-${stamp()}`);
    await Bun.sleep(2000);
  }
  for (const b of m.bots) { enableService(b.service); o.log(`bật lại dịch vụ cũ ${b.service.name}`); }
  return { ok: true, from: dir, restored: m.bots.map((b: any) => b.key) };
}

function writeJson(path: string, v: any) {
  const tmp = `${path}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify(v, null, 2) + "\n", { mode: 0o600 });
  renameSync(tmp, path);
}

const redactPlan = (p: Plan) => ({
  runnerJson: p.runnerJson, owners: p.owners,
  bots: p.bots.map((b) => ({ key: b.key, server: b.server, engine: b.engine, config: b.config, service: b.service?.name })),
  skipped: p.skipped,
});

export { keyOf };
