// Cấu hình runner chung (v2): MỘT runner mỗi máy (mỗi người dùng hệ điều hành), nhiều bot, nhiều máy chủ chat.
// File mặc định ~/.config/flygo-agent/runner.json (chmod 600). Xem runner.example.json.
//
// Runner thuộc MỘT người: `owners` = người đã đăng nhập thành công từng máy chủ chat trên máy này (app ghi khi đăng nhập).
// Bot chỉ chạy được khi chủ bot = chủ runner trên máy chủ của bot ("chỉ chia sẻ bot, không chia sẻ runner").
// Relay kiểm lại chủ bot bằng quyền admin (runner.ts: owner_mismatch).
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";
import { CONFIG_DIR, parseConfig, type Config } from "./config";

export const MACHINE_CONFIG = join(CONFIG_DIR, "runner.json");

export interface ExportSpec {
  enabled?: boolean;
  /** Người khác (ngoài chủ runner) được gọi MCP này: "<máy chủ chat>/<user id>". */
  share?: string[];
  /** Luôn hỏi 👍 tool write, kể cả khi bên gọi đang "Luôn cho phép" / TeamWork không cần duyệt. */
  alwaysAsk?: boolean;
  /** MCP stdio tuỳ ý: { command, args?, env? }. */
  stdio?: { command: string; args?: string[]; env?: Record<string, string> };
  /** MCP HTTP đã thêm cho bot (ext-mcp): tên trong kho của bot. */
  ext?: string;
  /** Tool không đổi gì (không cần duyệt) khi MCP không tự đánh dấu readOnlyHint. */
  readOnly?: string[];
}

export interface MachineSection {
  name?: string;
  bridge?: { enabled?: boolean };
  exports?: Record<string, ExportSpec>;
  /** Client nối vào runner qua WebSocket (extension, thiết bị…): Origin extension được phép. */
  clients?: { origins?: string[] };
}

export interface BotEntry {
  key: string;
  enabled?: boolean;
  botTokenFile?: string;
  [k: string]: any;
}

export interface MachineConfig {
  version: 2;
  machine: MachineSection;
  /** Máy chủ chat -> user id của chủ runner trên máy chủ đó (đăng nhập thành công). */
  owners: Record<string, string>;
  defaults: Record<string, any>;
  servers: Record<string, Record<string, any>>;
  bots: BotEntry[];
}

export interface ResolvedBot {
  key: string;
  enabled: boolean;
  /** Cấu hình bot đã gộp; không có khi lỗi. */
  cfg?: Config;
  error?: string;
  /** Dấu vân tay để biết cấu hình bot có đổi không (nạp nóng). */
  hash: string;
}

export const normServer = (s: string) => String(s ?? "").trim().replace(/\/+$/, "").toLowerCase();
const NESTED = ["codex", "claude", "agy", "a2a", "flygoId", "env"];
const isObj = (v: any) => !!v && typeof v === "object" && !Array.isArray(v);

/** Gộp nhiều lớp cấu hình: khoá thường thì lớp sau đè lớp trước; codex/claude/agy/a2a/flygoId/env gộp một tầng. */
export function mergeLayers(...layers: Record<string, any>[]) {
  const out: Record<string, any> = {};
  for (const l of layers) {
    if (!isObj(l)) continue;
    for (const [k, v] of Object.entries(l)) {
      if (NESTED.includes(k) && isObj(v)) out[k] = { ...(isObj(out[k]) ? out[k] : {}), ...v };
      else if (v !== undefined) out[k] = v;
    }
  }
  return out;
}

export function parseMachineConfig(raw: any): MachineConfig {
  if (!isObj(raw)) throw new Error("runner.json không phải object");
  if (raw.version !== 2) throw new Error(`runner.json: version phải là 2 (đang là ${raw.version})`);
  if (!Array.isArray(raw.bots)) throw new Error("runner.json thiếu bots[]");
  const keys = new Set<string>();
  for (const b of raw.bots) {
    if (!isObj(b) || typeof b.key !== "string" || !/^[A-Za-z0-9._-]{1,64}$/.test(b.key)) throw new Error(`bot có key không hợp lệ: ${JSON.stringify(b?.key)}`);
    if (keys.has(b.key)) throw new Error(`bot trùng key: ${b.key}`);
    keys.add(b.key);
  }
  const owners: Record<string, string> = {};
  for (const [s, u] of Object.entries(isObj(raw.owners) ? raw.owners : {})) if (typeof u === "string" && u) owners[normServer(s)] = u;
  const servers: Record<string, Record<string, any>> = {};
  for (const [s, v] of Object.entries(isObj(raw.servers) ? raw.servers : {})) servers[normServer(s)] = isObj(v) ? (v as any) : {};
  return { version: 2, machine: isObj(raw.machine) ? raw.machine : {}, owners, defaults: isObj(raw.defaults) ? raw.defaults : {}, servers, bots: raw.bots };
}

const expand = (p: string, base: string) => {
  const h = p.replace(/^~(?=\/|\\|$)/, homedir());
  return isAbsolute(h) ? h : join(base, h);
};

/** Cấu hình từng bot (gộp defaults → servers[máy chủ] → bot) và kiểm luật chủ runner. `dir`: thư mục của runner.json (botTokenFile tương đối). */
export function resolveBots(mc: MachineConfig, dir = CONFIG_DIR): ResolvedBot[] {
  return mc.bots.map((b) => {
    const { key, enabled, botTokenFile, ...own } = b;
    const server = normServer(own.serverUrl ?? mc.defaults.serverUrl ?? "");
    const raw = mergeLayers(mc.defaults, mc.servers[server] ?? {}, own);
    const hash = JSON.stringify({ raw, botTokenFile: botTokenFile ?? null, owner: mc.owners[server] ?? null });
    const on = enabled !== false;
    try {
      if (botTokenFile && !raw.botToken) {
        const f = expand(botTokenFile, dir);
        if (!existsSync(f)) throw new Error(`không thấy botTokenFile ${botTokenFile}`);
        raw.botToken = readFileSync(f, "utf8").trim();
      }
      const owner = mc.owners[server];
      if (!owner) throw new Error(`runner chưa đăng nhập máy chủ ${server || "(trống)"} (thiếu owners["${server}"]): không chạy bot của máy chủ này`);
      raw.ownerUserIds = Array.isArray(raw.ownerUserIds) && raw.ownerUserIds.length ? raw.ownerUserIds : [owner];
      if (!raw.ownerUserIds.includes(owner)) throw new Error(`bot ${key} không thuộc chủ runner trên ${server} (chủ runner ${owner}, cấu hình bot ghi ${raw.ownerUserIds.join(",")})`);
      raw.runnerOwner = owner;
      const cfg = parseConfig(raw);
      return { key, enabled: on, cfg, hash };
    } catch (e: any) {
      return { key, enabled: on, error: String(e?.message ?? e), hash };
    }
  });
}

export async function loadMachineConfig(path = MACHINE_CONFIG): Promise<{ mc: MachineConfig; bots: ResolvedBot[]; path: string }> {
  const mc = parseMachineConfig(JSON.parse(readFileSync(path, "utf8")));
  return { mc, bots: resolveBots(mc, dirname(path)), path };
}
