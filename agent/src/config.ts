// Cấu hình runner. Nguồn (theo thứ tự): --config-stdin (app truyền qua stdin), --config <file>,
// ~/.config/flygo-agent/config.json. Xem config.example.json.
import { existsSync } from "node:fs";
import { homedir, userInfo } from "node:os";
import { delimiter, join } from "node:path";
import { spawnSync } from "./spawn";

export type EngineName = "codex" | "claude" | "agy";
export const ENGINE_NAMES: EngineName[] = ["codex", "claude", "agy"];
/** Tên engine để hiện cho người dùng. */
export const engineLabel = (e: string) => (e === "codex" ? "Codex" : e === "agy" ? "Antigravity" : "Claude Code");

export interface Config {
  serverUrl: string; // https://chat.example.com
  botToken: string; // token của bot cá nhân
  ownerUserIds: string[]; // chỉ những người này mới giao việc được
  engine: EngineName; // mỗi bot gắn cố định một engine: bot Claude chỉ chạy Claude, bot Codex chỉ chạy Codex
  persona?: string; // ghi đè persona mặc định
  /** Biến môi trường riêng của bot, thêm vào engine (vd. ANTHROPIC_BASE_URL cho bot chạy API tương thích). Runner chung: mỗi bot một bộ. */
  env?: Record<string, string>;
  /** Runner chung: chủ của runner trên máy chủ của bot (người đã đăng nhập máy chủ đó trên máy này). Có thì bot phải thuộc đúng người này. */
  runnerOwner?: string;
  /** Điều khiển máy thật / terminal qua MCP mã nguồn mở đã cài (desktop-mcp.ts); false = tắt hẳn. Mặc định bật khi có cài. */
  computerUse?: boolean;
  /** Ghi đè / thêm MCP điều khiển máy: { "<tên>": { command, args?, env? } | false }. */
  desktopMcp?: Record<string, { command?: string; args?: string[]; env?: Record<string, string> } | false>;
  skillsDir?: string; // thư mục skill (SKILL.md) chép vào thư mục làm việc
  workspaceRoot: string; // nơi tạo thư mục làm việc theo chat (mỗi chat một thư mục "<tên chat>-<id>")
  projectRoots: string[]; // chat được gắn thư mục code ([flygo-project path=…] / "@bot dự án <path>") chỉ khi path nằm dưới các thư mục này; rỗng = tắt
  mainIdleHours: number; // chat chính nghỉ quá N giờ thì mở phiên mới; 0 = không bao giờ (mặc định)
  approvalTimeoutSec: number;
  /** TeamWork: cho lượt từ app Làm việc nhóm chạy không cần duyệt (vẫn giữ danh sách cấm) khi token hợp lệ và người giao là chủ bot.
   *  Thiếu = false (tắt); bật bằng cấu hình của từng bot. */
  teamworkBypass?: boolean;
  codex: {
    bin?: string; // đường dẫn codex (Windows cài qua npm: …\\npm\\codex.cmd)
    skipLoginCheck?: boolean; // bỏ qua kiểm tra đăng nhập (codex xác thực theo cách runner không nhận ra)
    transport: "socket" | "stdio"; // socket: app-server dùng chung (Codex app nối cùng); stdio: runner tự chạy app-server riêng (mặc định trên Windows)
    socket: string; // app-server dùng chung (Codex app có thể nối cùng socket)
    /** Thư mục dữ liệu Codex riêng cho bot (CODEX_HOME), để không dùng chung ~/.codex với Codex Desktop / codex CLI của người dùng. */
    home?: string;
    spawnArgs: string[]; // tham số thêm khi phải tự chạy app-server, vd. ["-c", "openai_base_url=..."]
    sandbox: "read-only" | "workspace-write" | "danger-full-access";
    /** Cho lệnh trong sandbox workspace-write truy cập mạng (curl, tải tệp, API nội bộ). Mặc định bật; false để tắt. */
    network?: boolean;
    model?: string;
    models?: string[]; // model cho người dùng chọn theo tin (props.flygo_agent_config); mặc định [model ?? "gpt-5.6-terra"]
    efforts?: string[]; // mặc định low,medium,high,xhigh
    effort?: string; // mức suy nghĩ mặc định (medium)
    sections?: boolean; // xếp thread vào section "Flygo · <tên chat>" trên Codex app (mặc định bật)
  };
  claude: {
    bin: string;
    allowedTools: string[]; // chạy không cần hỏi; còn lại hỏi qua Flygo
    deny: string[]; // cấm hẳn, không hỏi
    fullAccess?: boolean; // toàn quyền (bypassPermissions): không hỏi duyệt, bỏ cả deny — chỉ bật khi chủ máy yêu cầu
    model?: string;
    models?: string[]; // mặc định opus,sonnet
    efforts?: string[]; // mặc định low,medium,high,xhigh,max
    effort?: string; // mặc định high
    /** Bật Claude in Chrome (claude --chrome): agent điều khiển Chrome thật của người dùng qua extension. */
    chrome?: boolean;
    /**
     * Tool có sẵn của Claude Code được nạp (claude --tools, vd. "Read,Glob,Grep,WebFetch,WebSearch,Skill"); thiếu = mặc định
     * (đủ bộ, ~26k token mỗi lượt). Bot chat chạy qua Cổng AI nên giới hạn để giảm token (Sếp 2026-11-17: "hi" tốn 68k).
     */
    tools?: string;
  };
  // Antigravity CLI (agy): mỗi lượt chạy `agy -p … --output-format stream-json`, nói tiếp bằng --conversation.
  agy: {
    bin: string;
    model?: string; // trống = model mặc định của agy (danh sách thật lấy từ `agy models`)
    models?: string[];
    efforts?: string[]; // mặc định low,medium,high,xhigh,max
    effort?: string; // mặc định medium
    deny: string[]; // luật cấm của agy (permissions.deny), vd. "command(rm -rf)", "read_file(~/.ssh)"
    fullAccess?: boolean; // toàn quyền (--dangerously-skip-permissions)
  };
  // A2A: các bot nhờ nhau qua relay của máy chủ (push.<tên miền>/a2a). Tin tag nhiều agent: agent tag đầu tiên chủ trì.
  a2a: {
    enabled: boolean; // mặc định bật
    relay: string; // mặc định wss://push.<tên miền của serverUrl>/a2a/connect (trạm của chính máy chủ bot)
    maxCalls: number; // số lần ask_agent tối đa mỗi lượt (5); ask_agent chỉ tới agent được tag (0.6.95)
    timeoutSec: number; // chờ một agent tối đa (900)
    /** Đồng đội trong dự án (team_list / team_ask…): mặc định bật; false = bot này rút khỏi đội (không hiện, không gọi được). */
    team?: boolean;
    /** Ghi đè hồ sơ đồng đội khi runner đoán sai, vd. { "provider": "DeepSeek", "auth": "api_key" }. Không ghi bí mật vào đây. */
    describe?: { auth?: "subscription" | "api_key"; provider?: string; endpoint?: string; model?: string };
  };
  // Chuyển tiếp TCP bằng bun (macOS chặn Local Network với binary codex/node). Chỉ codex-shared dùng.
  forwards: Array<{ listen: number; host: string; port: number }>;
  /** Flygo ID + Flygo Gateway của máy chủ chat: tool MCP theo quyền của người nhờ (xem gateway.ts). Không có = tắt. */
  flygoId?: { url: string; gatewayUrl: string };
  /**
   * Cổng AI công ty (vn.flygo.ai, 0.7.6): bot engine claude gọi model qua cổng thay vì gói Claude của máy. Mỗi lượt gửi kèm
   * email người nhờ (X-Flygo-User) để tính vào hạn mức của chính người đó. keyFile: khoá ứng dụng fgk_… có quyền gọi thay
   * người dùng (quản trị Cổng AI cấp), chỉ nằm trên máy runner. Chỉ dùng cho engine claude.
   */
  flygoAi?: { url?: string; keyFile: string; app?: string };
}

/** Model "mặc định của agy": không truyền --model. */
export const AGY_DEFAULT_MODEL = "default";

export const CONFIG_DIR = join(homedir(), ".config", "flygo-agent");

const defaults: Omit<Config, "serverUrl" | "botToken" | "ownerUserIds" | "engine"> = {
  workspaceRoot: join(homedir(), "flygo-agent", "workspaces"),
  projectRoots: [],
  mainIdleHours: 0,
  approvalTimeoutSec: 600,
  codex: {
    transport: process.platform === "win32" ? "stdio" : "socket",
    socket: join(homedir(), ".codex", "flygo-shared.sock"),
    spawnArgs: [],
    sandbox: "danger-full-access", // không dùng sandbox: lệnh chạy thẳng trên máy
  },
  claude: {
    bin: "claude",
    allowedTools: ["Read", "Grep", "Glob", "LS", "TodoWrite", "WebSearch", "WebFetch", "mcp__flygo_chat__chat_thread", "mcp__flygo_chat__chat_history", "mcp__flygo_chat__chat_search", "mcp__flygo_chat__chat_info", "mcp__flygo_chat__chat_files", "mcp__flygo_chat__chat_read_file", "mcp__flygo_chat__chat_send_files", "mcp__flygo_chat__chat_send_bilingual", "mcp__flygo_chat__session_list", "mcp__flygo_chat__session_read", "mcp__flygo_chat__session_ask", "mcp__flygo_chat__project_info", "mcp__flygo_chat__team_list", "mcp__flygo_chat__team_session_read", "mcp__flygo_chat__team_ask", "mcp__flygo_chat__team_post", "mcp__flygo_chat__remote_agents", "mcp__flygo_chat__remote_agent_send", "mcp__flygo_chat__file_read"],
    // Cấm hẳn (không hiện thẻ duyệt): xoá đệ quy, đọc khoá/token. ssh/scp/sudo/git push: không cấm, hỏi duyệt từng lần như lệnh khác.
    deny: [
      // Xoá tệp luôn qua file_trash (thùng rác, khôi phục được), không rm (Sếp, 2026-11-10).
      "Bash(rm -rf:*)", "Bash(rm:*)", "Bash(rmdir:*)", "Bash(unlink:*)", "Bash(shred:*)",
      "Read(~/.ssh/**)", "Read(~/.config/flygo-agent/**)", "Read(~/.codex/auth.json)", "Read(~/.aws/**)",
    ],
  },
  agy: {
    bin: "agy",
    deny: ["command(rm -rf)", "command(rm)", "command(rmdir)", "command(unlink)", "command(shred)", "read_file(~/.ssh)", "read_file(~/.config/flygo-agent)", "read_file(~/.codex/auth.json)", "read_file(~/.aws)"],
  },
  a2a: { enabled: true, relay: "", maxCalls: 5, timeoutSec: 900 }, // relay rỗng = trạm của máy chủ (xem loadConfig)
  forwards: [],
};

export function parseConfig(raw: any, requireBot = true): Config {
  const cfg = { ...defaults, ...raw, codex: { ...defaults.codex, ...raw.codex }, claude: { ...defaults.claude, ...raw.claude }, agy: { ...defaults.agy, ...raw.agy }, a2a: { ...defaults.a2a, ...raw.a2a } } as Config;
  // Relay mặc định = trạm của chính máy chủ (chat.congty.vn → wss://push.congty.vn/a2a/connect), không mượn trạm máy chủ khác.
  if (!raw.a2a?.relay) {
    const host = (() => { try { return new URL(cfg.serverUrl).hostname.toLowerCase(); } catch { return ""; } })();
    const labels = host.split(".");
    if (labels.length >= 2) cfg.a2a.relay = `wss://push.${(labels.length > 2 ? labels.slice(1) : labels).join(".")}/a2a/connect`;
  }
  if (!cfg.a2a.relay) cfg.a2a.enabled = false; // máy chủ là IP / tên nội bộ, không cấu hình relay: tắt A2A
  cfg.engine ??= raw.defaultEngine; // cấu hình cũ
  if (requireBot) for (const k of ["serverUrl", "botToken", "ownerUserIds", "engine"] as const) if (!cfg[k]) throw new Error(`config thiếu ${k}`);
  if (requireBot && !ENGINE_NAMES.includes(cfg.engine)) throw new Error(`engine không hợp lệ: ${cfg.engine}`);
  cfg.serverUrl = (cfg.serverUrl ?? "").replace(/\/$/, "");
  cfg.workspaceRoot = cfg.workspaceRoot.replace(/^~(?=\/|$)/, homedir());
  cfg.projectRoots = (cfg.projectRoots ?? []).map((p) => p.replace(/^~(?=\/|$)/, homedir()));
  cfg.codex.socket = cfg.codex.socket.replace(/^~(?=\/|$)/, homedir());
  return cfg;
}

export async function loadConfig(args: string[], requireBot = true): Promise<Config> {
  if (args.includes("--config-stdin")) return parseConfig(JSON.parse(await Bun.stdin.text()), requireBot);
  const i = args.indexOf("--config");
  const path = i >= 0 ? args[i + 1] : process.env.FLYGO_AGENT_CONFIG ?? join(CONFIG_DIR, "config.json");
  return parseConfig(await Bun.file(path).json(), requireBot);
}

/** App mở từ giao diện có PATH rất ngắn: thêm các nơi hay cài codex/claude/bun. */
export function extendPath() {
  const h = homedir();
  const extra = [join(h, ".local", "bin"), join(h, ".bun", "bin"), join(h, ".claude", "local"), join(h, ".npm-global", "bin"),
    "/opt/homebrew/bin", "/usr/local/bin", join(h, "AppData", "Roaming", "npm"),
    join(h, "AppData", "Local", "Programs", "codex"), join(h, "AppData", "Local", "Programs", "claude"), join(h, ".codex", "bin"),
    join(h, "AppData", "Local", "agy", "bin")]; // agy: bộ cài chính thức đặt ở ~/.local/bin (macOS/Linux), %LOCALAPPDATA%\agy\bin (Windows)
  const cur = (process.env.PATH ?? "").split(delimiter);
  process.env.PATH = [...cur, ...extra.filter((d) => existsSync(d) && !cur.includes(d))].join(delimiter);
  // Claude Code đọc token trong keychain theo USER; launchd/app có thể không đặt biến này.
  // (userInfo() của Bun trả "unknown" khi thiếu USER nên hỏi hệ điều hành bằng `id -un`.)
  if (process.platform !== "win32" && (!process.env.USER || process.env.USER === "unknown")) {
    const u = spawnSync(["/usr/bin/id", "-un"]).stdout.toString().trim() || userInfo().username;
    process.env.USER = u;
    process.env.LOGNAME ??= u;
  }
  process.env.HOME ??= homedir();
}

/** Tên máy để so mốc host=: chữ thường, bỏ đuôi ".local" (macOS), khoảng trắng và "]" thành "-". App dùng cùng quy tắc. */
export const normHost = (h: string) => h.trim().toLowerCase().replace(/\.local\.?$/, "").replace(/[\s\]]+/g, "-");

/** Đường dẫn đầy đủ của một lệnh theo PATH hiện tại (đã extendPath). */
export const resolveBin = (name: string) => Bun.which(name, { PATH: process.env.PATH ?? "" }) ?? name;

/** Model / mức suy nghĩ bot cho chọn, và mặc định. `marker`: thêm từ mốc "[flygo-agent … models=… efforts=… default=model:mức]" do chủ bot ghi. */
export function agentOptions(cfg: Config, marker = "") {
  const attr = (k: string) => new RegExp(`\\[flygo-agent[^\\]]*\\b${k}=([^\\s\\]]+)`, "i").exec(marker)?.[1];
  const list = (k: string) => attr(k)?.split(",").filter(Boolean) ?? [];
  const e = cfg.engine === "codex"
    ? { model: cfg.codex.model ?? "gpt-5.6-terra", models: cfg.codex.models, effort: cfg.codex.effort ?? "medium", efforts: cfg.codex.efforts ?? ["low", "medium", "high", "xhigh"] }
    : cfg.engine === "agy"
    // agy: model mặc định "default" = không truyền --model (agy tự chọn); runner thay bằng model mặc định `agy models` báo khi có.
    ? { model: cfg.agy.model ?? AGY_DEFAULT_MODEL, models: cfg.agy.models, effort: cfg.agy.effort ?? "medium", efforts: cfg.agy.efforts ?? ["low", "medium", "high", "xhigh", "max"] }
    : { model: cfg.claude.model ?? "opus", models: cfg.claude.models ?? ["opus", "sonnet"], effort: cfg.claude.effort ?? "high", efforts: cfg.claude.efforts ?? ["low", "medium", "high", "xhigh", "max"] };
  const models = [...new Set([e.model, ...(e.models ?? []), ...list("models")])];
  const efforts = [...new Set([...e.efforts, ...list("efforts")])];
  // default=model:mức trong mốc (thiếu phần nào thì giữ mặc định của cấu hình)
  const [dm, de] = (attr("default") ?? "").split(":");
  if (dm && !models.includes(dm)) models.push(dm);
  if (de && !efforts.includes(de)) efforts.push(de);
  return { models, efforts, default: { model: dm || e.model, effort: de || e.effort } };
}

/** Tham số chạy codex app-server: spawnArgs của cấu hình + bật mạng cho sandbox (trừ khi codex.network = false hoặc đã tự đặt). */
export function codexAppServerArgs(cfg: Config): string[] {
  const a = [...cfg.codex.spawnArgs];
  if (cfg.codex.network !== false && !a.some((x) => x.startsWith("sandbox_workspace_write.network_access"))) a.push("-c", "sandbox_workspace_write.network_access=true");
  return a;
}
