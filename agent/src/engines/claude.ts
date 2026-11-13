// Engine Claude: mỗi lượt chạy `claude -p --output-format stream-json`, nói tiếp bằng --resume.
// Quyền: công cụ ngoài allowedTools được hỏi qua tool MCP flygo_chat.approve (--permission-prompt-tool)
// -> runner hiện yêu cầu duyệt trên Flygo.
import { claudeReadOnly, desktopMcp } from "../desktop-mcp";
import { normTodos } from "../todos";
import { copyFileSync, existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { base, clip, commandLabel, hostOf, mcpFromName } from "../labels";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { resolveBin, type Config } from "../config";
import type { Engine, EngineInventory, TurnHooks, TurnInput, TurnResult } from "./types";
import { CHAT_OP_SELF_STEP, CHAT_OP_TOOLS } from "../chat-ops";
import { spawn, spawnSync } from "../spawn";
import { claudeLimits, type UsageLimits } from "../limits";

// Claude không có API liệt kê model qua CLI: danh sách cố định (alias + id đầy đủ, app gửi id đầy đủ).
const CLAUDE_EFFORTS = ["low", "medium", "high", "xhigh", "max"];
const CLAUDE_MODELS = [
  { id: "claude-opus-5-5", name: "Opus 5.5", aliases: ["opus"] },
  { id: "claude-sonnet-5-5", name: "Sonnet 5.5", aliases: ["sonnet"] },
  { id: "claude-haiku-5-5", name: "Haiku 5.5", aliases: ["haiku"] },
  { id: "claude-fable-5-1", name: "Fable 5.1", aliases: ["fable"] },
];

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
function adoptSession(id: string, cwd: string) {
  const root = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude"), "projects");
  const want = join(root, cwd.replace(/[^a-zA-Z0-9]/g, "-"), `${id}.jsonl`);
  if (existsSync(want) || !existsSync(root)) return;
  for (const d of readdirSync(root)) {
    const f = join(root, d, `${id}.jsonl`);
    if (existsSync(f)) { mkdirSync(dirname(want), { recursive: true }); copyFileSync(f, want); return; }
  }
}

/** File phiên trên máy (thư mục dự án bất kỳ). */
function sessionFile(id: string): string | null {
  const root = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), ".claude"), "projects");
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
const A2A_TOOLS = ["mcp__flygo_chat__list_agents", "mcp__flygo_chat__ask_agent", "mcp__flygo_chat__return_files", "mcp__flygo_chat__chat_report_out",
  "mcp__flygo_chat__skill_list", "mcp__flygo_chat__skill_read", "mcp__flygo_chat__skill_save", "mcp__flygo_chat__skill_delete", "mcp__flygo_chat__role_set",
  "mcp__flygo_chat__schedule_create", "mcp__flygo_chat__schedule_list", "mcp__flygo_chat__schedule_update", "mcp__flygo_chat__schedule_delete",
  "mcp__flygo_chat__chat_edit_message", "mcp__flygo_chat__chat_recall_message", "mcp__flygo_chat__chat_session_title",
  // Kế hoạch / tóm tắt cuối lượt: chỉ hiện trên thẻ, không cần duyệt.
  "mcp__flygo_chat__update_plan", "mcp__flygo_chat__wrap_up", "mcp__flygo_chat__browser_token_set", "mcp__flygo_chat__browser_extension_setup",
  // Quản lý phiên / dự án: runner tự xin duyệt (fork / new / project_create) và tự ghi bước lên thẻ.
  ...["session_rename", "session_fork", "session_new", "spawn_task", "project_list", "project_create", "project_rename"].map((t) => `mcp__flygo_chat__${t}`),
  "mcp__flygo_chat__ref_read", "mcp__flygo_chat__ref_thread", "mcp__flygo_chat__ref_post",
  // Bộ công cụ chat (chat-ops.ts): runner kiểm phạm vi, tự xin duyệt khi gửi ra chat khác / quản lý chat, tự ghi bước.
  ...[...CHAT_OP_TOOLS].map((t) => `mcp__flygo_chat__${t}`),
  // task_create / task_update: tool tự xin duyệt qua runner (một bước duyệt chung cho Claude và Codex).
  "mcp__flygo_chat__task_create", "mcp__flygo_chat__task_update",
  ...["state", "say", "show", "slides", "draw", "web", "people", "suggest", "watch", "music_list", "music_play", "music_volume", "music_fade", "music_pause", "music_stop", "deck", "deck_go", "asset", "sfx", "scene", "qa", "poll", "link", "present", "lobby"].map((t) => `mcp__flygo_chat__meeting_${t}`)]; // report_out / skill_save… runner tự xin duyệt khi cần

const HIDDEN = new Set(["mcp__flygo_chat__approve", "mcp__flygo_chat__chat_report_out", "mcp__flygo_chat__chat_edit_message", "mcp__flygo_chat__chat_recall_message", "mcp__flygo_chat__ref_post", "mcp__flygo_chat__chat_session_title", "mcp__flygo_chat__session_rename", "mcp__flygo_chat__session_fork", "mcp__flygo_chat__session_new", "mcp__flygo_chat__project_create", "mcp__flygo_chat__project_rename", "mcp__flygo_chat__meeting_suggest", "mcp__flygo_chat__ask_user", "ToolSearch", "AskUserQuestion", "ExitPlanMode", "TodoWrite", "mcp__flygo_chat__update_plan", "mcp__flygo_chat__wrap_up", "mcp__flygo_chat__spawn_task", "mcp__flygo_chat__browser_token_set", "mcp__flygo_chat__browser_extension_setup", "mcp__flygo_chat__chat_send_files", "mcp__ccd_turn__update_plan", "mcp__ccd_turn__wrap_up"]);
// Tệp kế hoạch Claude tự ghi ở chế độ Lập kế hoạch (~/.claude/plans/…): không hiện thành bước, kế hoạch đã nằm trong lời xin duyệt.
for (const t of CHAT_OP_SELF_STEP) HIDDEN.add(`mcp__flygo_chat__${t}`);
export const hidden = (name: string, input: any) => HIDDEN.has(name) || (/^(Write|Edit|MultiEdit)$/.test(name) && /[\\/]\.claude[\\/]plans[\\/]/.test(String(input?.file_path ?? "")));
const resultText = (c: any) => (typeof c === "string" ? c : Array.isArray(c) ? c.map((x) => x.text ?? "").join("\n") : "");

/** Một tin user dạng stream-json để ghi vào stdin của claude (-p --input-format stream-json). */
const streamUserMsg = (text: string) => JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "text", text }] } }) + "\n";

/** `claude` cũ (trước khi có `--input-format stream-json`) thì không chèn tin giữa lượt được: kiểm một lần theo bin rồi nhớ.
 *  Không đọc được help thì coi như không hỗ trợ (chạy đường cũ: prompt làm tham số, không steering). */
const streamInputCache = new Map<string, Promise<boolean>>();
function supportsStreamInput(bin: string): Promise<boolean> {
  let p = streamInputCache.get(bin);
  if (!p) {
    p = (async () => {
      try {
        const proc = spawn([bin, "--help"], { env: { ...process.env }, stdout: "pipe", stderr: "pipe", stdin: "ignore" });
        const timer = setTimeout(() => { try { proc.kill(); } catch {} }, 15_000);
        const out = await new Response(proc.stdout).text().catch(() => "");
        await proc.exited.catch(() => {});
        clearTimeout(timer);
        return /--input-format\b/.test(out);
      } catch { return false; }
    })();
    streamInputCache.set(bin, p);
  }
  return p;
}

export class ClaudeEngine implements Engine {
  name = "claude" as const;
  private initSkills: string[] = []; // kỹ năng claude nạp (sự kiện init của lượt gần nhất)
  private limits: UsageLimits | null = null; // hạn mức gói Claude (rate_limit_event của lượt gần nhất)
  async usageLimits() { return this.limits; }

  async inventory(): Promise<EngineInventory> {
    return {
      skills: this.initSkills.map((name) => ({ name, description: "" })),
      models: CLAUDE_MODELS.map((m) => ({ id: m.id, name: m.name, efforts: CLAUDE_EFFORTS, defaultEffort: "high", isDefault: m.aliases.includes(this.cfg.claude.model ?? "opus") || m.id === this.cfg.claude.model })),
    };
  }
  constructor(private cfg: Config, private mcpCommand: { command: string; args: string[] }, private log: (s: string) => void) {}

  async contextTokens(id: string) {
    const f = sessionFile(id);
    if (!f) return null;
    return tailTokens(f, (ev) => {
      const u = ev?.type === "assistant" ? ev.message?.usage : null;
      return u ? (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) : null;
    });
  }

  async runTurn(input: TurnInput, hooks: TurnHooks, signal: AbortSignal): Promise<TurnResult> {
    const mcpConfig = JSON.stringify({
      mcpServers: { flygo_chat: { command: this.mcpCommand.command, args: this.mcpCommand.args, env: input.mcpEnv }, ...desktopMcp(this.cfg).servers },
    });
    // Không nạp settings cá nhân (~/.claude/settings.json có thể allow Bash/Write hoặc bypass);
    // quyền của phiên chỉ gồm allowedTools + deny của runner, còn lại hỏi Sếp qua Flygo.
    // claude.fullAccess: toàn quyền, không hỏi, không deny.
    const full = !!this.cfg.claude.fullAccess || !!input.bypass || input.mode === "bypassPermissions";
    // Chế độ quyền: thủ công = default (hỏi trước mọi thay đổi), acceptEdits, plan (lập kế hoạch, ExitPlanMode xin duyệt), auto (Claude tự xét).
    const permMode = ({ manual: "default", acceptEdits: "acceptEdits", plan: "plan", auto: "auto", bypassPermissions: "bypassPermissions" } as const)[input.mode ?? "manual"];
    // AskUserQuestion: hook PreToolUse (chạy ở mọi chế độ quyền, kể cả bypass) gọi `flygo-agent ask-hook` -> runner hỏi trên Flygo,
    // trả câu trả lời về trong cùng lượt (updatedInput.answers).
    const hookCmd = [this.mcpCommand.command, ...this.mcpCommand.args.slice(0, -1), "ask-hook"].map((x) => `"${x}"`).join(" ");
    const settings = JSON.stringify({
      permissions: full ? { defaultMode: "bypassPermissions" } : { defaultMode: permMode, deny: this.cfg.claude.deny },
      hooks: { PreToolUse: [{ matcher: "AskUserQuestion", hooks: [{ type: "command", command: hookCmd, timeout: 86400 }] }] },
      // Tắt auto-memory của Claude Code: nó ghi theo thư mục làm việc, mà nhiều phiên dùng chung thư mục (luồng bí mật dùng thư mục
      // chat cha, chat AI riêng dùng thư mục nhóm) -> ghi nhớ của phiên này lộ sang phiên khác. Ghi nhớ lâu dài của bot: memory.md riêng.
      autoMemoryEnabled: false,
    });
    const bin = resolveBin(this.cfg.claude.bin);
    // stream-json ở chiều vào: prompt (và tin chèn giữa lượt) đưa qua stdin, không truyền prompt làm tham số.
    // claude cũ không có --input-format thì chạy đường cũ (prompt làm tham số, không chèn được tin giữa lượt).
    const streamIn = await supportsStreamInput(bin);
    const args = [
      bin, "-p",
      ...(streamIn ? ["--input-format", "stream-json"] : [input.prompt]),
      "--output-format", "stream-json", "--verbose", "--include-partial-messages",
      "--setting-sources", "project,local",
      "--settings", settings,
      "--permission-mode", full ? "bypassPermissions" : permMode,
      "--mcp-config", mcpConfig,
      // --permission-prompt-tool luôn có (cả toàn quyền): claude -p chỉ bật AskUserQuestion khi có nơi trả lời câu hỏi.
      "--permission-prompt-tool", "mcp__flygo_chat__approve",
      ...(full ? [] : ["--allowedTools", [...this.cfg.claude.allowedTools, ...A2A_TOOLS, ...claudeReadOnly(desktopMcp(this.cfg))].join(",")]),
      "--append-system-prompt", input.persona,
      ...(input.addDirs ?? []).flatMap((d) => ["--add-dir", d]),
    ];
    const model = input.model ?? this.cfg.claude.model;
    if (model) args.push("--model", model);
    if (input.effort) args.push("--effort", input.effort);
    if (input.sessionId) { adoptSession(input.sessionId, input.cwd); args.push("--resume", input.sessionId); }
    else if (input.forkFrom && sessionFile(input.forkFrom)) { adoptSession(input.forkFrom, input.cwd); args.push("--resume", input.forkFrom, "--fork-session"); } // phiên mới mang ngữ cảnh phiên cha
    args.push("--name", input.title);
    if (this.cfg.claude.chrome) args.push("--chrome");

    const proc = spawn(args, { env: { ...process.env, MCP_TOOL_TIMEOUT: "1800000", FLYGO_RUNNER_URL: input.mcpEnv.RUNNER_URL ?? "", FLYGO_RUN_KEY: input.mcpEnv.RUN_KEY ?? "", CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1" }, cwd: input.cwd, stdout: "pipe", stderr: "pipe", stdin: streamIn ? "pipe" : "ignore" });
    const kill = () => proc.kill();
    signal.addEventListener("abort", kill);

    let sessionId = input.sessionId ?? "";
    let final = "";
    let usage: any;
    let isError = false;
    let curMsg = "";
    let ctxTokens = 0; // token ngữ cảnh của lần gọi model gần nhất
    let gotResult = false;
    let lingering = false;
    const tools = new Map<string, { name: string; input: any }>();
    const stderr = new Response(proc.stderr).text();

    // Chế độ stream-json vào: ghi prompt đầu vào stdin; đóng stdin khi xong lượt để claude thoát sạch (không treo chờ tin mới).
    const stdin = proc.stdin; // FileSink khi stdin:"pipe" (streamIn), undefined khi "ignore"
    let turnEnded = false;
    let stdinOpen = streamIn;
    const endStdin = () => { if (stdinOpen) { stdinOpen = false; try { stdin?.end(); } catch {} } };
    if (streamIn && stdin) {
      try { stdin.write(streamUserMsg(input.prompt)); stdin.flush(); } catch {}
      // Tin mới của người dùng trong lúc lượt đang chạy: chèn thẳng vào lượt (đưa thêm một tin user vào stdin) thay vì xếp hàng.
      hooks.steerable?.(async (text) => {
        if (turnEnded || !stdinOpen) return false;
        try { stdin.write(streamUserMsg(text)); stdin.flush(); return true; }
        catch { return false; }
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
          if (ev.type === "system" && ev.subtype === "init" && ev.session_id) {
            sessionId = ev.session_id; hooks.session(sessionId);
            if (Array.isArray(ev.skills)) this.initSkills = ev.skills.map(String);
          }
          else if (ev.type === "rate_limit_event") this.limits = claudeLimits(ev.rate_limit_info, this.limits);
          else if (ev.type === "stream_event") {
            const e = ev.event;
            if (e?.type === "message_start") curMsg = e.message?.id ?? curMsg;
            else if (e?.type === "content_block_delta" && e.delta?.type === "text_delta" && curMsg) hooks.text({ id: curMsg, delta: e.delta.text });
          }
          else if (ev.type === "assistant") {
            const u = ev.message?.usage;
            if (u) ctxTokens = (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
            for (const c of ev.message?.content ?? []) {
              if (c.type === "tool_use") {
                tools.set(c.id, { name: c.name, input: c.input });
                if (c.name === "TodoWrite") { const t = normTodos(c.input); if (t) hooks.todos?.(t); }
                if (hidden(c.name, c.input)) continue; // report_out / câu hỏi: runner tự ghi bước
                const d = describe(c.name, c.input);
                hooks.step({ id: c.id, kind: d.kind, title: d.title, label: d.label, status: "running" });
              } else if (c.type === "text" && c.text?.trim()) {
                hooks.text({ id: ev.message?.id ?? String(ev.uuid), full: c.text, done: true });
              }
            }
          } else if (ev.type === "user") {
            for (const c of ev.message?.content ?? []) {
              if (c.type !== "tool_result") continue;
              const t = tools.get(c.tool_use_id);
              if (!t || hidden(t.name, t.input)) continue;
              const d = describe(t.name, t.input);
              hooks.step({ id: c.tool_use_id, kind: d.kind, title: d.title, label: d.label, status: c.is_error ? "error" : "done", detail: resultText(c.content).slice(-600) });
            }
          } else if (ev.type === "result") {
            final = ev.result ?? "";
            isError = !!ev.is_error;
            const win = Math.max(0, ...Object.values<any>(ev.modelUsage ?? {}).map((m) => Number(m?.contextWindow) || 0));
            usage = { cost_usd: ev.total_cost_usd, duration_ms: ev.duration_ms, ...ev.usage, ...(ctxTokens ? { contextTokens: ctxTokens } : {}), ...(win ? { contextWindow: win } : {}) };
            if (ev.session_id) sessionId = ev.session_id;
            gotResult = true;
            turnEnded = true; // hết lượt: không nhận chèn tin nữa, đóng stdin để claude thoát (thay vì chờ tin mới -> treo)
            endStdin();
          }
        }
      }
      if (lingering) { reader.cancel().catch(() => {}); killTree(proc.pid); }
      const code = lingering ? 0 : await proc.exited;
      if (signal.aborted) throw new Error("đã dừng");
      if (code !== 0 && !final) throw new Error(`claude thoát mã ${code}: ${(await stderr).slice(-400)}`);
      if (isError) throw new Error(final || "claude báo lỗi");
    } finally {
      signal.removeEventListener("abort", kill);
      hooks.steerable?.(null);
      endStdin();
    }
    return { sessionId, text: final, usage };
  }
}

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
