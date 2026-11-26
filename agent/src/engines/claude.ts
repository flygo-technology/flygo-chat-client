// Engine Claude: mỗi lượt chạy `claude -p --output-format stream-json`, nói tiếp bằng --resume.
// Quyền: công cụ ngoài allowedTools được hỏi qua tool MCP flygo_chat.approve (--permission-prompt-tool)
// -> runner hiện yêu cầu duyệt trên Flygo.
import { claudeConfigDir } from "../config";
import { createHash } from "node:crypto";
import { liveTurn } from "./claude-live";
import { badgeOf } from "../cmd-limits";
import { claudeReadOnly, desktopMcp } from "../desktop-mcp";
import { mergeDeny, TW_CLAUDE_DENY } from "../teamwork";
import { normTodos } from "../todos";
import { chmodSync, copyFileSync, existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { base, clip, commandLabel, hostOf, mcpFromName } from "../labels";
import { homedir } from "node:os";
import claudeBase from "../../profiles/default/claude-base.md" with { type: "text" };
import { dirname, join } from "node:path";
import { resolveBin, type Config } from "../config";
import type { Engine, EngineInventory, TurnHooks, TurnInput, TurnResult } from "./types";
import { CHAT_OP_SELF_STEP, CHAT_OP_TOOLS } from "../chat-ops";
import { spawn, spawnSync } from "../spawn";
import { claudeLimits, type UsageLimits } from "../limits";
import { ADB_TOOLS } from "../adb-tools";

// Danh sách model lấy từ chính Claude Code (yêu cầu `initialize` của stream-json trả về models, như /model): Claude Code có model
// mới là app thấy, không phải sửa runner. Danh sách cố định dưới đây chỉ dùng khi hỏi không được (claude cũ / lỗi / quá hạn).
const CLAUDE_EFFORTS = ["low", "medium", "high", "xhigh", "max"];
const CLAUDE_MODELS = [
  { id: "claude-opus-5-5", name: "Opus 5.5", aliases: ["opus"] },
  { id: "claude-sonnet-5-5", name: "Sonnet 5.5", aliases: ["sonnet"] },
  { id: "claude-haiku-5-5", name: "Haiku 5.5", aliases: ["haiku"] },
  { id: "claude-fable-5-2", name: "Fable 5.2", aliases: ["fable"] },
];
/** Bí danh -> id đầy đủ theo danh sách cố định (dự phòng khi chưa hỏi được Claude Code). */
export const CLAUDE_ALIASES: Record<string, string> = Object.fromEntries(CLAUDE_MODELS.flatMap((m) => m.aliases.map((a) => [a, m.id])));

type ModelInfo = EngineInventory["models"][number];
export interface ClaudeModelList { models: ModelInfo[]; aliases: Record<string, string> }

/** Đổi `models` trong trả lời `initialize` của Claude Code thành danh sách cho app: bỏ mục "default", bí danh (opus, fable…)
 *  đổi sang id đầy đủ (resolvedModel) vì app gửi id đầy đủ, bỏ trùng; [want] = model mặc định của bot (bí danh hoặc id). */
export function parseClaudeModels(raw: unknown, want = "sonnet"): ClaudeModelList | null {
  if (!Array.isArray(raw)) return null;
  const models: ModelInfo[] = [];
  const aliases: Record<string, string> = {};
  for (const m of raw as any[]) {
    const value = String(m?.value ?? "").trim();
    if (!value || value === "default") continue;
    const id = String(m?.resolvedModel || value).trim();
    if (!/^claude-/.test(id)) continue; // bí danh chưa phân giải được thì bỏ (app cần id đầy đủ)
    if (value !== id) aliases[value] = id;
    if (models.some((x) => x.id === id)) continue;
    const efforts = Array.isArray(m?.supportedEffortLevels) && m.supportedEffortLevels.length ? m.supportedEffortLevels.map(String) : CLAUDE_EFFORTS;
    models.push({ id, ...(m?.displayName ? { name: String(m.displayName) } : {}), efforts, defaultEffort: efforts.includes("medium") ? "medium" : efforts.includes("high") ? "high" : efforts[efforts.length - 1] });
  }
  if (!models.length) return null;
  const def = aliases[want] ?? want;
  for (const m of models) m.isDefault = m.id === def;
  return { models, aliases };
}

/** Hỏi Claude Code danh sách model: chạy `claude -p` stream-json, gửi `initialize`, đọc `control_response` rồi tắt (không gửi
 *  tin nào nên không tốn token). Không MCP, không settings cá nhân. Lỗi / quá [ms] thì null. */
async function probeClaudeModels(bin: string, env: Record<string, string | undefined>, ms = 30_000): Promise<unknown[] | null> {
  const proc = spawn([bin, "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    "--setting-sources", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}'],
  { env: { ...process.env, ...env, CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" } as Record<string, string>, cwd: homedir(), stdin: "pipe", stdout: "pipe", stderr: "ignore" });
  const timer = setTimeout(() => { try { proc.kill(); } catch {} }, ms);
  try {
    proc.stdin.write(JSON.stringify({ type: "control_request", request_id: "flygo-models", request: { subtype: "initialize" } }) + "\n");
    proc.stdin.flush();
    const dec = new TextDecoder();
    let buf = "";
    for await (const chunk of proc.stdout as unknown as AsyncIterable<Uint8Array>) {
      buf += dec.decode(chunk, { stream: true });
      let i: number;
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (!line.startsWith("{")) continue;
        let ev: any;
        try { ev = JSON.parse(line); } catch { continue; }
        if (ev?.type === "control_response" && ev.response?.request_id === "flygo-models") {
          return ev.response.subtype === "success" && Array.isArray(ev.response.response?.models) ? ev.response.response.models : null;
        }
      }
    }
    return null;
  } catch { return null; }
  finally {
    clearTimeout(timer);
    try { proc.stdin.end(); } catch {}
    try { proc.kill(); } catch {}
  }
}

function describe(name: string, input: any): { kind: "command" | "file" | "tool" | "search"; title: string; label: string } {
  const file = base(input?.file_path ?? input?.notebook_path ?? "");
  switch (name) {
    case "Bash": {
      const cmd = String(input?.command ?? "");
      return { kind: "command", title: `$ ${cmd.split("\n")[0].slice(0, 160)}`, label: input?.description ? clip(input.description) : commandLabel(cmd) };
    }
    case "Edit": case "MultiEdit": case "NotebookEdit": return { kind: "file", title: `Sửa ${file}`, label: clip(`Sửa ${file}`) };
    case "Write": return { kind: "file", title: `Sửa ${file}`, label: clip(`Tạo ${file}`) };
    case "Read": return { kind: "tool", title: `Đọc ${file}`, label: clip(`Đọc ${file}`) };
    case "Grep": case "Glob": return { kind: "search", title: `${name} ${input?.pattern ?? ""}`, label: clip(`Tìm ${input?.pattern ?? ""}`) };
    case "WebSearch": return { kind: "search", title: `Tìm web: ${input?.query ?? ""}`, label: clip(`Tìm web ${input?.query ?? ""}`) };
    case "WebFetch": return { kind: "search", title: `Mở ${input?.url ?? ""}`, label: clip(`Mở ${hostOf(input?.url ?? "")}`) };
    case "Task": case "Agent": return { kind: "tool", title: name, label: clip(input?.description || "Giao việc cho agent phụ") };
    case "TodoWrite": return { kind: "tool", title: name, label: "Cập nhật danh sách việc" };
    case "Skill": return { kind: "tool", title: name, label: clip(`Dùng kỹ năng ${input?.skill ?? input?.command ?? ""}`) };
    default: return { kind: "tool", title: name.replace(/^mcp__([^_]+(?:_[^_]+)*)__/, "$1."), label: mcpFromName(name) ?? clip(name) };
  }
}

/** claude --resume tìm phiên trong ~/.claude/projects/<cwd>: thư mục làm việc đổi (đổi tên chat, gắn dự án, kênh bí mật về chat cha)
 *  thì chép file phiên sang thư mục mới để vẫn nói tiếp được. */
function adoptSession(id: string, cwd: string, root: string) {
  const want = join(root, cwd.replace(/[^a-zA-Z0-9]/g, "-"), `${id}.jsonl`);
  if (existsSync(want) || !existsSync(root)) return;
  for (const d of readdirSync(root)) {
    const f = join(root, d, `${id}.jsonl`);
    if (existsSync(f)) { mkdirSync(dirname(want), { recursive: true }); copyFileSync(f, want); return; }
  }
}

/** File phiên trên máy (thư mục dự án bất kỳ). */
function sessionFile(id: string, root: string): string | null {
  if (!existsSync(root)) return null;
  for (const d of readdirSync(root)) { const f = join(root, d, `${id}.jsonl`); if (existsSync(f)) return f; }
  return null;
}

/** Token ngữ cảnh của lần gọi model gần nhất trong file phiên (đọc phần đuôi). */
export async function tailTokens(path: string, pick: (ev: any) => number | null): Promise<number | null> {
  const size = statSync(path).size;
  const tail = await Bun.file(path).slice(Math.max(0, size - 1024 * 1024)).text();
  const lines = tail.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i].includes("tokens")) continue;
    try { const n = pick(JSON.parse(lines[i])); if (n != null) return n; } catch {}
  }
  return Math.round(size / 4); // không thấy: ước theo cỡ file
}

// Tool A2A của flygo_chat: luôn cho phép (nhờ agent khác / gửi tệp kết quả; agent kia tự xin duyệt quyền của nó).
const A2A_TOOLS = ["mcp__flygo_chat__ask_agent", "mcp__flygo_chat__return_files", "mcp__flygo_chat__chat_report_out", "mcp__flygo_chat__remote_agents", "mcp__flygo_chat__remote_agent_send", "mcp__flygo_chat__agent_send", "mcp__flygo_chat__agent_list",
  "mcp__flygo_chat__skill_list", "mcp__flygo_chat__skill_read", "mcp__flygo_chat__skill_save", "mcp__flygo_chat__skill_delete", "mcp__flygo_chat__role_set",
  "mcp__flygo_chat__schedule_create", "mcp__flygo_chat__schedule_list", "mcp__flygo_chat__schedule_update", "mcp__flygo_chat__schedule_delete",
  "mcp__flygo_chat__chat_edit_message", "mcp__flygo_chat__chat_recall_message", "mcp__flygo_chat__chat_session_title",
  // Kế hoạch / tóm tắt cuối lượt: chỉ hiện trên thẻ, không cần duyệt.
  "mcp__flygo_chat__update_plan", "mcp__flygo_chat__wrap_up",
  // Quản lý phiên / dự án: runner tự xin duyệt (fork / new / project_create) và tự ghi bước lên thẻ.
  ...["session_rename", "session_fork", "session_new", "spawn_task", "project_list", "project_create", "project_rename"].map((t) => `mcp__flygo_chat__${t}`),
  "mcp__flygo_chat__ref_read", "mcp__flygo_chat__ref_thread", "mcp__flygo_chat__ref_post",
  // Bộ công cụ chat (chat-ops.ts): runner kiểm phạm vi, tự xin duyệt khi gửi ra chat khác / quản lý chat, tự ghi bước.
  ...[...CHAT_OP_TOOLS].map((t) => `mcp__flygo_chat__${t}`),
  ...["state", "say", "show", "slides", "draw", "web", "people", "suggest", "watch", "music_list", "music_play", "music_volume", "music_fade", "music_pause", "music_stop", "deck", "deck_go", "asset", "sfx", "scene", "qa", "poll", "link", "present", "lobby"].map((t) => `mcp__flygo_chat__meeting_${t}`)]; // report_out / skill_save… runner tự xin duyệt khi cần

const HIDDEN = new Set(["mcp__flygo_chat__approve", "mcp__flygo_chat__chat_report_out", "mcp__flygo_chat__chat_edit_message", "mcp__flygo_chat__chat_recall_message", "mcp__flygo_chat__ref_post", "mcp__flygo_chat__chat_session_title", "mcp__flygo_chat__session_rename", "mcp__flygo_chat__session_fork", "mcp__flygo_chat__session_new", "mcp__flygo_chat__project_create", "mcp__flygo_chat__project_rename", "mcp__flygo_chat__meeting_suggest", "mcp__flygo_chat__ask_user", "ToolSearch", "AskUserQuestion", "ExitPlanMode", "TodoWrite", "mcp__flygo_chat__update_plan", "mcp__flygo_chat__wrap_up", "mcp__flygo_chat__spawn_task", "mcp__flygo_chat__chat_send_files", "mcp__ccd_turn__update_plan", "mcp__ccd_turn__wrap_up"]);
// Tệp kế hoạch Claude tự ghi ở chế độ Lập kế hoạch (~/.claude/plans/…): không hiện thành bước, kế hoạch đã nằm trong lời xin duyệt.
for (const t of CHAT_OP_SELF_STEP) HIDDEN.add(`mcp__flygo_chat__${t}`);
export const hidden = (name: string, input: any) => HIDDEN.has(name) || (/^(Write|Edit|MultiEdit)$/.test(name) && /[\\/]\.claude[\\/]plans[\\/]/.test(String(input?.file_path ?? "")));
const resultText = (c: any) => (typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => x.text ?? "").join("\n") : "");

/** Một tin user dạng stream-json để ghi vào stdin của claude (-p --input-format stream-json). */
const streamUserMsg = (text: string, uuid?: string) => JSON.stringify({ type: "user", ...(uuid ? { uuid } : {}), message: { role: "user", content: [{ type: "text", text }] } }) + "\n";

/** `claude` cũ (trước khi có `--input-format stream-json`) thì không chèn tin giữa lượt được: kiểm một lần theo bin rồi nhớ.
 *  Không đọc được help thì coi như không hỗ trợ (chạy đường cũ: prompt làm tham số, không steering).
 *  replay: có `--replay-user-messages` (claude phát lại tin user lúc thật sự đọc -> biết lúc tin chèn được điều hướng). */
const streamInputCache = new Map<string, Promise<{ stream: boolean; replay: boolean }>>();
function supportsStreamInput(bin: string, env?: Record<string, string>): Promise<{ stream: boolean; replay: boolean }> {
  let p = streamInputCache.get(bin);
  if (!p) {
    p = (async () => {
      try {
        const proc = spawn([bin, "--help"], { env: { ...process.env, ...(env ?? {}) }, stdout: "pipe", stderr: "pipe", stdin: "ignore" });
        const timer = setTimeout(() => { try { proc.kill(); } catch {} }, 15_000);
        const out = await new Response(proc.stdout).text().catch(() => "");
        await proc.exited.catch(() => {});
        clearTimeout(timer);
        return { stream: /--input-format\b/.test(out), replay: /--replay-user-messages\b/.test(out) };
      } catch { return { stream: false, replay: false }; }
    })();
    streamInputCache.set(bin, p);
  }
  return p;
}

/** Tool flygo_chat luôn chạy không cần duyệt (kể cả khi cấu hình tự đặt allowedTools): đăng artifact vào chính phiên;
 *  mcp_add tự mở hộp duyệt riêng trên app nên không xin duyệt hai lần; browser_open_profiles chỉ mở Chrome của chủ máy. */
/** Env "gọn" cho Claude Code của bot chat (Sếp 2026-11-25: nhanh, tiết kiệm như Claude desktop). Env tiến trình / env của bot ghi đè được.
 *  - CLAUDE_CODE_AUTO_COMPACT_WINDOW: tự nén khi ngữ cảnh vượt ~180k (mặc định Claude Code chỉ nén gần cửa sổ 1M token).
 *  - ENABLE_CLAUDEAI_MCP_SERVERS=false: không kéo connector của tài khoản claude.ai (Google Drive, Claude Docs…) vào bot.
 *  - BASH_MAX_OUTPUT_LENGTH / MAX_MCP_OUTPUT_TOKENS: trần kết quả lệnh / tool MCP (giữ đầu + cuối). */
export function leanEnv(compactAt?: number): Record<string, string> {
  const e: Record<string, string> = {};
  const set = (k: string, v: string) => { if (process.env[k] === undefined) e[k] = v; };
  const w = compactAt === undefined ? 180_000 : compactAt;
  if (w > 0) set("CLAUDE_CODE_AUTO_COMPACT_WINDOW", String(w));
  set("ENABLE_CLAUDEAI_MCP_SERVERS", "false");
  set("BASH_MAX_OUTPUT_LENGTH", "12000");
  set("MAX_MCP_OUTPUT_TOKENS", "10000");
  return e;
}

export const ALWAYS_OK = ["mcp__flygo_chat__tool_search", "mcp__flygo_chat__tool_describe", "mcp__flygo_chat__tool_call", "mcp__flygo_chat__artifact_publish", "mcp__flygo_chat__mcp_add", "mcp__flygo_chat__browser_open_profiles", "mcp__flygo_chat__integrated_browser_open",
  // adb_*: runner tự kiểm chủ bot + xin duyệt cài / gỡ / xoá dữ liệu / shell ghi / nút gửi, thanh toán (adb-tools.ts).
  ...ADB_TOOLS.map((t) => `mcp__flygo_chat__${t.name}`)];

/** Quyền của lượt Claude. fullAccess / "luôn cho phép" / bypassPermissions: không hỏi, không deny (như trước).
 *  Lượt TeamWork không cần duyệt (twBypass): --permission-mode bypassPermissions NHƯNG vẫn giữ deny (cấu hình + TW_CLAUDE_DENY);
 *  Claude Code vẫn chặn theo deny trong chế độ bypass (đã kiểm với 2.1.x: Read / Bash bị cấm trả về permission_denials). */
export function claudePerms(cfg: Config, input: Pick<TurnInput, "bypass" | "mode" | "twBypass">) {
  const full = !!cfg.claude.fullAccess || !!input.bypass || input.mode === "bypassPermissions";
  if (!full && input.twBypass) return { full: false, permMode: "bypassPermissions", permissions: { defaultMode: "bypassPermissions", deny: mergeDeny(cfg.claude.deny, TW_CLAUDE_DENY) } };
  // Chế độ quyền: thủ công = default (hỏi trước mọi thay đổi), acceptEdits, plan (lập kế hoạch, ExitPlanMode xin duyệt), auto (Claude tự xét).
  const permMode = ({ manual: "default", acceptEdits: "acceptEdits", plan: "plan", auto: "auto", bypassPermissions: "bypassPermissions" } as const)[input.mode ?? "manual"];
  return { full, permMode: full ? "bypassPermissions" : permMode, permissions: full ? { defaultMode: "bypassPermissions" } : { defaultMode: permMode, deny: cfg.claude.deny } };
}

/**
 * Biến môi trường cho Claude Code khi bot chạy qua Cổng AI: địa chỉ cổng, khoá ứng dụng (Bearer) và header người nhờ.
 * Không có email người nhờ thì ném lỗi: không gọi model khi không biết tính vào hạn mức của ai.
 */
export async function flygoAiEnv(cfg: Pick<Config, "flygoAi" | "serverUrl">, email: string, botName = ""): Promise<Record<string, string>> {
  const g = cfg.flygoAi!;
  const key = (await Bun.file(g.keyFile).text().catch(() => "")).trim();
  if (!key.startsWith("fgk_")) throw new Error(`Cổng AI: không đọc được khoá ứng dụng ở ${g.keyFile}`);
  if (!/^[^\s@]+@[^\s@]+$/.test(email)) throw new Error("Cổng AI: không biết email người nhờ, không tính được hạn mức");
  return {
    // Mặc định: đường công khai của Cổng AI trên chính máy chủ chat (https://chat.congty.vn/__apps/ai).
    ANTHROPIC_BASE_URL: (g.url || `${cfg.serverUrl.replace(/\/+$/, "")}/__apps/ai`).replace(/\/+$/, ""),
    ANTHROPIC_AUTH_TOKEN: key,
    ANTHROPIC_API_KEY: "",
    // App = "bot:<username>" để Cổng AI tách chi phí theo từng trợ lý (app hiện ở chi tiết trợ lý); cfg.flygoAi.app ghi đè.
    ANTHROPIC_CUSTOM_HEADERS: `X-Flygo-User: ${email}\nX-Flygo-App: ${g.app && g.app !== "vn.flygo.agent" ? g.app : botName ? `bot:${botName.toLowerCase()}` : "vn.flygo.agent"}`,
    // Model Claude Code chưa biết (vd. bản mới hơn CLI): không tự chặn ngữ cảnh 200k.
    CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT: "1",
    // Claude Code tắt tool search khi ANTHROPIC_BASE_URL không phải của Anthropic: bật lại để tool MCP (~90 tool flygo_chat,
    // ~33k token) chỉ nạp khi cần, không nạp hết vào mỗi lượt.
    ENABLE_TOOL_SEARCH: "true",
  };
}

export class ClaudeEngine implements Engine {
  name = "claude" as const;
  private initSkills: string[] = []; // kỹ năng claude nạp (sự kiện init của lượt gần nhất)
  private limits: UsageLimits | null = null; // hạn mức gói Claude (rate_limit_event của lượt gần nhất)
  async usageLimits() { return this.limits; }
  /** <CLAUDE_CONFIG_DIR của bot>/projects: nơi Claude Code của bot này lưu phiên. */
  projectsDir() { return join(claudeConfigDir(this.cfg), "projects"); }

  // Danh sách model hỏi được từ Claude Code: inventory chạy sau mỗi lượt nên nhớ 1 giờ; lỗi thì giữ bản tốt gần nhất
  // và 10 phút sau mới hỏi lại.
  private probed: { at: number; list: ClaudeModelList } | null = null;
  private probeFailedAt = 0;
  private probing: Promise<ClaudeModelList | null> | null = null;
  private async claudeModels(): Promise<ClaudeModelList | null> {
    if (this.probed && Date.now() - this.probed.at < 3600_000) return this.probed.list;
    if (Date.now() - this.probeFailedAt < 600_000) return this.probed?.list ?? null;
    this.probing ??= (async () => {
      const raw = await probeClaudeModels(resolveBin(this.cfg.claude.bin ?? "claude"), this.cfg.env ?? {}).catch(() => null);
      const list = parseClaudeModels(raw, this.cfg.claude.model ?? "sonnet");
      if (list) this.probed = { at: Date.now(), list };
      else this.probeFailedAt = Date.now(), this.log(`claude: không hỏi được danh sách model${this.probed ? ", dùng bản trước" : ", dùng danh sách cố định"}`);
      return list ?? this.probed?.list ?? null;
    })().finally(() => { this.probing = null; });
    return this.probing;
  }

  async inventory(): Promise<EngineInventory> {
    const skills = this.initSkills.map((name) => ({ name, description: "" }));
    // Claude Code trỏ sang endpoint tương thích (ANTHROPIC_BASE_URL, vd. DeepSeek) với claude.models trong cấu hình: báo đúng
    // các model đó, không báo model Anthropic (app sẽ cho chọn model mà endpoint không có).
    if (this.cfg.claude.models?.length && (this.cfg.flygoAi || (process.env.ANTHROPIC_BASE_URL && !/(^|\.)anthropic\.com(:|\/|$)/.test(new URL(process.env.ANTHROPIC_BASE_URL, "http://x").host))))
      return { skills, models: this.cfg.claude.models.map((id) => ({ id, efforts: this.cfg.claude.efforts?.length ? this.cfg.claude.efforts : CLAUDE_EFFORTS, defaultEffort: this.cfg.claude.effort ?? "medium", isDefault: id === this.cfg.claude.model })) };
    const live = await this.claudeModels();
    if (live) return { skills, models: live.models, aliases: { ...CLAUDE_ALIASES, ...live.aliases } };
    return {
      skills, aliases: CLAUDE_ALIASES,
      models: CLAUDE_MODELS.map((m) => ({ id: m.id, name: m.name, efforts: CLAUDE_EFFORTS, defaultEffort: "medium", isDefault: m.aliases.includes(this.cfg.claude.model ?? "sonnet") || m.id === this.cfg.claude.model })),
    };
  }
  constructor(private cfg: Config, private mcpCommand: { command: string; args: string[] }, private log: (s: string) => void,
    /** Email theo id Mattermost (Cổng AI): runner tra qua API chat, có bộ nhớ đệm. */
    private emailOf: (mmId: string) => Promise<string> = async () => "",
    private botName: () => string = () => "") {}

  async contextTokens(id: string) {
    const f = sessionFile(id, this.projectsDir());
    if (!f) return null;
    return tailTokens(f, (ev) => {
      const u = ev?.type === "assistant" ? ev.message?.usage : null;
      return u ? (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) : null;
    });
  }

  /** Lệnh, env, tệp MCP của một lần chạy claude; sig = mọi thứ mà đổi thì phải mở lại tiến trình (phiên sống). */
  private async prepare(input: TurnInput) {
    const mcpConfig = JSON.stringify({
      mcpServers: {
        flygo_chat: { command: this.mcpCommand.command, args: this.mcpCommand.args, env: input.mcpEnv }, ...desktopMcp(this.cfg).servers,
        // MCP bên ngoài của chủ bot: tool của chúng không nằm trong allowedTools nên mỗi lần gọi vẫn xin duyệt.
        ...Object.fromEntries(Object.entries(input.extMcp ?? {}).map(([k, v]) => [k, { type: "http", url: v.url, headers: v.headers }])),
      },
    });
    // Không nạp settings cá nhân (~/.claude/settings.json có thể allow Bash/Write hoặc bypass);
    // quyền của phiên chỉ gồm allowedTools + deny của runner, còn lại hỏi Sếp qua Flygo.
    // claude.fullAccess: toàn quyền, không hỏi, không deny.
    const { full, permMode, permissions } = claudePerms(this.cfg, input);
    // AskUserQuestion: hook PreToolUse (chạy ở mọi chế độ quyền, kể cả bypass) gọi `flygo-agent ask-hook` -> runner hỏi trên Flygo,
    // trả câu trả lời về trong cùng lượt (updatedInput.answers).
    const hookCmd = [this.mcpCommand.command, ...this.mcpCommand.args.slice(0, -1), "ask-hook"].map((x) => `"${x}"`).join(" ");
    const settings = JSON.stringify({
      permissions,
      hooks: { PreToolUse: [{ matcher: "AskUserQuestion", hooks: [{ type: "command", command: hookCmd, timeout: 86400 }] }] },
      // Không nạp connector claude.ai của tài khoản (Google Drive, Claude Docs…): bot không dùng, mỗi lượt tốn token mô tả tool
      // và có thể chạm dữ liệu cá nhân của chủ tài khoản Claude (Sếp 25/11: tối ưu token).
      disableClaudeAiConnectors: true,
      // Tắt auto-memory của Claude Code: nó ghi theo thư mục làm việc, mà nhiều phiên dùng chung thư mục (luồng bí mật dùng thư mục
      // chat cha, chat AI riêng dùng thư mục nhóm) -> ghi nhớ của phiên này lộ sang phiên khác. Ghi nhớ lâu dài của bot: memory.md riêng.
      autoMemoryEnabled: false,
    });
    // --mcp-config qua TỆP quyền 600, không để JSON trên dòng lệnh: trong đó có MM_TOKEN của bot, tiến trình khác đọc được bằng ps.
    const mcpDir = join(tmpdir(), `flygo-mcp-${process.getuid?.() ?? "u"}`);
    mkdirSync(mcpDir, { recursive: true, mode: 0o700 });
    const mcpFile = join(mcpDir, `${crypto.randomUUID()}.json`);
    writeFileSync(mcpFile, mcpConfig, { mode: 0o600 });
    chmodSync(mcpFile, 0o600);
    const bin = resolveBin(this.cfg.claude.bin);
    // stream-json ở chiều vào: prompt (và tin chèn giữa lượt) đưa qua stdin, không truyền prompt làm tham số.
    // claude cũ không có --input-format thì chạy đường cũ (prompt làm tham số, không chèn được tin giữa lượt).
    const { stream: streamIn, replay } = await supportsStreamInput(bin, this.cfg.env);
    const args = [
      bin, "-p",
      ...(streamIn ? ["--input-format", "stream-json", ...(replay ? ["--replay-user-messages"] : [])] : [input.prompt]),
      "--output-format", "stream-json", "--verbose", "--include-partial-messages",
      // Chỉ theo Flygo (Sếp 25/11): không nạp CLAUDE.md / .claude/settings của thư mục chat hay thư mục cha;
      // quyền, hook, MCP, kỹ năng đều do runner đưa vào (kỹ năng của bot qua --plugin-dir).
      "--setting-sources", "",
      "--settings", settings,
      "--permission-mode", permMode,
      "--mcp-config", mcpFile,
      // --permission-prompt-tool luôn có (cả toàn quyền): claude -p chỉ bật AskUserQuestion khi có nơi trả lời câu hỏi.
      "--permission-prompt-tool", "mcp__flygo_chat__approve",
      ...(full || input.twBypass ? [] : ["--allowedTools", [...this.cfg.claude.allowedTools, ...A2A_TOOLS, ...ALWAYS_OK, ...claudeReadOnly(desktopMcp(this.cfg))].join(",")]),
      // Lời dặn hệ thống: mặc định THAY HẲN lời dặn gốc của Claude Code bằng bản gọn của Flygo (claude-base.md) + persona,
      // bỏ phần an toàn / Chrome / game / WebSearch… (an toàn đã nằm ở model và phía Anthropic). basePrompt "claude": giữ gốc, nối persona.
      ...(this.cfg.claude.basePrompt === "claude" ? ["--append-system-prompt", input.persona] : ["--system-prompt", `${claudeBase.trim()}\n\n${input.persona}`]),
      ...(input.addDirs ?? []).flatMap((d) => ["--add-dir", d]),
      ...(input.pluginDirs ?? []).flatMap((d) => ["--plugin-dir", d]),
    ];
    const model = input.model ?? this.cfg.claude.model;
    if (model) args.push("--model", model);
    if (this.cfg.claude.tools !== undefined) {
      // Bot qua Cổng AI: luôn kèm ToolSearch, thiếu nó thì Claude Code tắt tool search và nạp hết tool MCP (~26k token).
      const t = this.cfg.claude.tools.split(",").map((x) => x.trim()).filter(Boolean);
      if (this.cfg.flygoAi && !t.includes("ToolSearch")) t.push("ToolSearch");
      args.push("--tools", t.join(","));
    }
    if (input.effort) args.push("--effort", input.effort);
    const pdir = this.projectsDir();
    if (input.sessionId) { adoptSession(input.sessionId, input.cwd, pdir); args.push("--resume", input.sessionId); }
    else if (input.forkFrom && sessionFile(input.forkFrom, pdir)) { adoptSession(input.forkFrom, input.cwd, pdir); args.push("--resume", input.forkFrom, "--fork-session"); } // phiên mới mang ngữ cảnh phiên cha
    args.push("--name", input.title);
    if (this.cfg.claude.chrome) args.push("--chrome");

    const gate = this.cfg.flygoAi ? await flygoAiEnv(this.cfg, await this.emailOf(input.requester || this.cfg.ownerUserIds[0] || "").catch(() => ""), this.botName()) : {};
    // Bash của Claude Code: hạn mặc định theo commandTimeoutSec của bot (120 s), tối đa 10 phút; chạy nền (run_in_background) không tính.
    const maxSec = Math.max(30, Number(input.mcpEnv.FLYGO_CMD_TIMEOUT_MAX_SEC) || 1800);
    const cmdMs = String(Math.min(maxSec, Math.max(5, Number(input.mcpEnv.FLYGO_CMD_TIMEOUT_SEC) || 120)) * 1000);
    // Agent tự đặt timeout cho từng lệnh Bash (persona); đây chỉ là mặc định khi không đặt và trần commandTimeoutMaxSec.
    const bashTimeouts = { BASH_DEFAULT_TIMEOUT_MS: process.env.BASH_DEFAULT_TIMEOUT_MS ?? cmdMs, BASH_MAX_TIMEOUT_MS: process.env.BASH_MAX_TIMEOUT_MS ?? String(maxSec * 1000) };
    // Một cơ chế nén duy nhất (gộp 2 dòng 0.7.27 / 0.7.33): leanEnv đặt CLAUDE_CODE_AUTO_COMPACT_WINDOW (mặc định 180k);
    // nhận cả claude.compactAt lẫn claude.compactWindow (tên cũ của dòng Mac mini). Env của bot đặt sẵn thì giữ (spread sau).
    const lean = leanEnv(this.cfg.claude.compactAt ?? this.cfg.claude.compactWindow);
    const env = { ...process.env, ...bashTimeouts, ...lean, ...this.cfg.env, ...gate, MCP_TOOL_TIMEOUT: "1800000", FLYGO_RUNNER_URL: input.mcpEnv.RUNNER_URL ?? "", FLYGO_RUN_KEY: input.mcpEnv.RUN_KEY ?? "", CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" } as Record<string, string>;
    // Phiên sống: model / chế độ quyền đổi tại chỗ (control request); còn lại (persona, quyền đầy đủ, tool, thư mục, người gọi qua
    // Cổng AI, MCP ngoài, effort) đổi thì mở lại tiến trình (--resume).
    const sigArgs = args.filter((x, i) => !["--model", "--permission-mode", "--resume", "--name", "--mcp-config"].includes(args[i - 1] ?? "") && !["--model", "--permission-mode", "--resume", "--fork-session", "--name", "--mcp-config"].includes(x));
    const h = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex").slice(0, 8);
    const flag = (f: string) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : ""; };
    // Từng phần của chữ ký (để log rõ phần nào đổi khi phiên sống phải mở lại).
    const sigParts: Record<string, string> = { persona: h(flag("--append-system-prompt")), settings: h(flag("--settings")), tools: h([flag("--allowedTools"), flag("--tools")]), effort: flag("--effort"), dirs: h(args.filter((_, i) => args[i - 1] === "--add-dir")), cwd: h(input.cwd), gate: h(gate), ext: h(Object.keys(input.extMcp ?? {}).sort()), rest: h(sigArgs) };
    const sig = createHash("sha256").update(JSON.stringify([sigArgs, input.cwd, gate, Object.keys(input.extMcp ?? {}).sort(), input.mcpEnv.SCOPE ?? ""])).digest("hex").slice(0, 16);
    env.FLYGO_SCOPE = input.mcpEnv.SCOPE ?? ""; // ask-hook của phiên sống hỏi runner RUN_KEY hiện tại theo SCOPE
    return { args, env, mcpFile, streamIn, replay, sig, sigParts, model: model ?? "", permMode, bin, cwd: input.cwd };
  }

  async runTurn(input: TurnInput, hooks: TurnHooks, signal: AbortSignal): Promise<TurnResult> {
    const prep = await this.prepare(input);
    if (this.cfg.claude.keepAlive && prep.streamIn) {
      const botKey = createHash("sha256").update(String(this.cfg.botToken ?? "")).digest("hex").slice(0, 8);
      return liveTurn(this, prep, input, hooks, signal, { botKey, idleMin: this.cfg.claude.keepAliveIdleMin, log: this.log });
    }
    const { args, env, mcpFile, streamIn, replay } = prep;
    const proc = spawn(args, { env, cwd: input.cwd, stdout: "pipe", stderr: "pipe", stdin: streamIn ? "pipe" : "ignore" });
    const kill = () => proc.kill();
    signal.addEventListener("abort", kill);

    const st = newTurnState(input.sessionId);
    let gotResult = false;
    let lingering = false;
    const stderr = new Response(proc.stderr).text();

    // Chế độ stream-json vào: ghi prompt đầu vào stdin; đóng stdin khi xong lượt để claude thoát sạch (không treo chờ tin mới).
    const stdin = proc.stdin; // FileSink khi stdin:"pipe" (streamIn), undefined khi "ignore"
    let turnEnded = false;
    let stdinOpen = streamIn;
    const readAcks = st.readAcks; // uuid tin chèn -> báo runner khi claude đọc tin
    const endStdin = () => { if (stdinOpen) { stdinOpen = false; try { stdin?.end(); } catch {} } };
    if (streamIn && stdin) {
      try { stdin.write(streamUserMsg(input.prompt)); stdin.flush(); } catch {}
      // Tin mới của người dùng trong lúc lượt đang chạy: chèn thẳng vào lượt (đưa thêm một tin user vào stdin) thay vì xếp hàng.
      hooks.steerable?.(async (text, onRead) => {
        if (turnEnded || !stdinOpen) return false;
        const uuid = crypto.randomUUID();
        try { stdin.write(streamUserMsg(text, uuid)); stdin.flush(); }
        catch { return false; }
        // claude phát lại tin (isReplay, cùng uuid) đúng lúc đọc nó (sau bước đang chạy); claude cũ không phát lại thì coi như đọc ngay.
        if (onRead) { if (replay) readAcks.set(uuid, onRead); else onRead(); }
        return true;
      });
      // Control request trong lượt (stop_task dừng sub-agent…): ghi thẳng vào stdin, không chờ trả lời.
      hooks.controllable?.(async (request) => {
        if (turnEnded || !stdinOpen) return false;
        try { stdin.write(JSON.stringify({ type: "control_request", request_id: crypto.randomUUID(), request }) + "\n"); stdin.flush(); return true; } catch { return false; }
      });
    }

    const reader = proc.stdout.getReader();
    const dec = new TextDecoder();
    let buf = "";
    try {
      for (;;) {
        // Sau "result": claude -p có thể (a) chạy tiếp lượt khác (thông báo lệnh nền còn tồn khi resume được xử lý thành lượt riêng),
        // hoặc (b) đứng chờ lệnh nền (vd. find chạy lâu). Im lặng quá LINGER_MS sau result -> coi là (b), dừng hẳn.
        const rd = reader.read();
        const r = gotResult ? await Promise.race([rd, Bun.sleep(LINGER_MS).then(() => null)]) : await rd;
        if (r === null) { lingering = true; break; }
        const { value, done } = r;
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf("\n")) >= 0) {
          const line = buf.slice(0, i).trim();
          buf = buf.slice(i + 1);
          if (!line) continue;
          let ev: any;
          try { ev = JSON.parse(line); } catch { continue; }
          if (ev.type !== "result") gotResult = false; // còn lượt tiếp theo
          this.onEvent(ev, st, hooks);
          if (ev.type === "result") {
            gotResult = true;
            turnEnded = true; // hết lượt: không nhận chèn tin nữa, đóng stdin để claude thoát (thay vì chờ tin mới -> treo)
            endStdin();
          }
        }
      }
      if (lingering) { reader.cancel().catch(() => {}); killTree(proc.pid); }
      const code = lingering ? 0 : await proc.exited;
      if (signal.aborted) throw new Error("đã dừng");
      if (code !== 0 && !st.final) throw new Error(`claude thoát mã ${code}: ${(await stderr).slice(-400)}`);
      if (st.isError) throw new Error(st.final || "claude báo lỗi");
    } finally {
      signal.removeEventListener("abort", kill);
      hooks.steerable?.(null);
      hooks.controllable?.(null);
      endStdin();
      try { rmSync(mcpFile, { force: true }); } catch {}
    }
    return { sessionId: st.sessionId, text: st.final, usage: st.usage };
  }

  /** Một sự kiện stream-json của claude → bước / chữ / phiên / kết quả của lượt (dùng chung cho lượt thường và phiên sống). */
  onEvent(ev: any, st: TurnState, hooks: TurnHooks) {
    try { hooks.rawEvent?.(ev); } catch {}
    // Claude Code tự nén ngữ cảnh (CLAUDE_CODE_AUTO_COMPACT_WINDOW): ghi một bước để Sếp thấy phiên vẫn liền mạch.
    if (ev.type === "system" && ev.subtype === "compact_boundary") {
      const pre = Number(ev.compact_metadata?.pre_tokens ?? ev.compactMetadata?.preTokens ?? 0);
      hooks.step({ id: `compact-${Date.now()}`, kind: "thinking", title: `🗜 Đã tự nén ngữ cảnh phiên${pre ? ` (${Math.round(pre / 1000)}k token)` : ""} để chạy nhanh, tiết kiệm; nội dung cũ được tóm tắt, vẫn nhớ việc đang làm`, status: "done" });
    }
    if (ev.type === "system" && ev.subtype === "init" && ev.session_id) {
      st.sessionId = ev.session_id; hooks.session(st.sessionId);
      if (Array.isArray(ev.skills)) this.initSkills = ev.skills.map(String);
    }
    else if (ev.type === "rate_limit_event") this.limits = claudeLimits(ev.rate_limit_info, this.limits);
    else if (ev.type === "stream_event") {
      const e = ev.event;
      if (e?.type === "message_start") st.curMsg = e.message?.id ?? st.curMsg;
      else if (e?.type === "content_block_delta" && e.delta?.type === "text_delta" && st.curMsg) hooks.text({ id: st.curMsg, delta: e.delta.text });
    }
    else if (ev.type === "assistant") {
      const u = ev.message?.usage;
      if (u) st.ctxTokens = (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
      for (const c of ev.message?.content ?? []) {
        if (c.type === "tool_use") {
          st.tools.set(c.id, { name: c.name, input: c.input });
          if (c.name === "TodoWrite") { const t = normTodos(c.input); if (t) hooks.todos?.(t); }
          if (hidden(c.name, c.input)) continue; // report_out / câu hỏi: runner tự ghi bước
          const d = describe(c.name, c.input);
          const badge = badgeOf(c.name, c.input); // "⏱ dự kiến N s · giới hạn M s" trên bước lệnh
          hooks.step({ id: c.id, kind: d.kind, title: badge ? `${d.title} · ${badge}` : d.title, label: d.label, status: "running" });
        } else if (c.type === "text" && c.text?.trim()) {
          hooks.text({ id: ev.message?.id ?? String(ev.uuid), full: c.text, done: true });
        }
      }
    } else if (ev.type === "user") {
      const ack = ev.isReplay && ev.uuid ? st.readAcks.get(ev.uuid) : undefined;
      if (ack) { st.readAcks.delete(ev.uuid); try { ack(); } catch {} }
      for (const c of ev.message?.content ?? []) {
        if (c.type !== "tool_result") continue;
        const t = st.tools.get(c.tool_use_id);
        if (t) try { hooks.toolDone?.({ id: c.tool_use_id, name: t.name, input: t.input, result: resultText(c.content), isError: !!c.is_error }); } catch {}
        if (!t || hidden(t.name, t.input)) continue;
        const d = describe(t.name, t.input);
        const badge = badgeOf(t.name, t.input);
        hooks.step({ id: c.tool_use_id, kind: d.kind, title: badge ? `${d.title} · ${badge}` : d.title, label: d.label, status: c.is_error ? "error" : "done", detail: resultText(c.content).slice(-600) });
      }
    } else if (ev.type === "result") {
      st.final = ev.result ?? "";
      st.isError = !!ev.is_error;
      const win = Math.max(0, ...Object.values<any>(ev.modelUsage ?? {}).map((m) => Number(m?.contextWindow) || 0));
      st.usage = { cost_usd: ev.total_cost_usd, duration_ms: ev.duration_ms, ...ev.usage, ...(st.ctxTokens ? { contextTokens: st.ctxTokens } : {}), ...(win ? { contextWindow: win } : {}) };
      if (ev.session_id) st.sessionId = ev.session_id;
    }
  }
}


/** Trạng thái của một lượt (một "result"). */
export interface TurnState { sessionId: string; final: string; usage: any; isError: boolean; curMsg: string; ctxTokens: number; tools: Map<string, { name: string; input: any }>; readAcks: Map<string, () => void> }
export const newTurnState = (sessionId?: string): TurnState => ({ sessionId: sessionId ?? "", final: "", usage: undefined, isError: false, curMsg: "", ctxTokens: 0, tools: new Map(), readAcks: new Map() });

const LINGER_MS = 15_000;

/** Dừng tiến trình và mọi tiến trình con (lệnh nền của agent). */
export function killTree(pid: number) {
  if (process.platform === "win32") { spawnSync(["taskkill", "/T", "/F", "/PID", String(pid)], { stdout: "ignore", stderr: "ignore" }); return; }
  const all: number[] = [];
  const walk = (p: number) => {
    all.push(p);
    const out = spawnSync(["pgrep", "-P", String(p)], { stdout: "pipe", stderr: "ignore" }).stdout.toString();
    for (const c of out.split("\n").map(Number).filter(Boolean)) walk(c);
  };
  walk(pid);
  for (const p of all.reverse()) try { process.kill(p, "SIGTERM"); } catch {}
}
