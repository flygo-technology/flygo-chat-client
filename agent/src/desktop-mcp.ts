// Điều khiển máy thật (computer-use) và terminal: MCP server mã nguồn mở đã cài trên máy chạy runner được tự phát hiện
// và gắn vào mọi engine (Claude / Codex / Antigravity), agent tự chọn tool hợp với việc.
// Tool chỉ đọc (liệt kê app / cửa sổ, đọc cây giao diện…) chạy luôn; click, gõ phím, mở app… phải xin duyệt
// (Claude: ngoài allowedTools; Codex: default_tools_approval_mode = "prompt"; agy: hook hỏi như tool lạ).
// Tắt hẳn: "computerUse": false trong config bot. Ghi đè / thêm server: "desktopMcp": { "<tên>": { command, args } | false }.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

export interface McpSpec { command: string; args: string[]; env?: Record<string, string> }
interface Known {
  name: string; // tên server (tool hiện là mcp__<name>__<tool>); trùng tên cấu hình chung của Codex để ghi đè được
  bins: string[];
  args: string[] | ((c: DesktopCfg) => string[]);
  os: NodeJS.Platform[];
  needs?: string[]; // chương trình phải có kèm
  env?: () => Record<string, string> | null; // null = thiếu điều kiện (vd. chưa có token): bỏ server
  skipIf?: string; // bỏ server này khi đã có server tên này
  readOnly: string[]; // tool không đổi gì trên máy: không cần duyệt
  hint: string;
}

const KNOWN: Known[] = [
  {
    name: "cua-driver", bins: ["cua-driver"], args: ["mcp"], os: ["darwin", "win32", "linux"],
    readOnly: ["list_apps", "list_windows", "get_window_state", "verify_state", "get_screen_size", "get_desktop_state", "get_cursor_position",
      "get_agent_cursor_state", "check_permissions", "health_report", "get_accessibility_tree", "get_guide", "get_recording_state",
      "list_sessions", "get_session", "get_session_state"],
    hint: "điều khiển app desktop CHẠY NGẦM, không giành chuột / bàn phím của người đang dùng máy (Mac / Windows / Linux): đọc cây giao diện, click, gõ, menu, kéo thả; ưu tiên cho app desktop (việc trên web dùng trình duyệt Flygo)",
  },
  {
    name: "peekaboo", bins: ["peekaboo"], args: ["mcp"], os: ["darwin"], readOnly: [],
    hint: "macOS: chụp màn hình / cửa sổ, điều khiển cửa sổ, menu, Dock; dùng khi cua-driver không làm được",
  },
  {
    name: "windows-mcp", bins: ["windows-mcp"], args: [], os: ["win32"], readOnly: [],
    hint: "Windows: điều khiển giao diện qua UI Automation (mở app, click, gõ, đọc cửa sổ), PowerShell",
  },
  {
    name: "computer-use-linux", bins: ["computer-use-linux"], args: ["mcp"], os: ["linux"],
    readOnly: ["doctor", "list_apps", "list_windows", "focused_window", "get_app_state", "get_tree_page"],
    hint: "Linux: đọc cây giao diện AT-SPI, click / gõ trên GNOME, KDE, Wayland, X11",
  },
  {
    name: "playwright", bins: ["playwright-mcp", "mcp-server-playwright"], os: ["darwin", "win32", "linux"],
    // Hồ sơ Chrome riêng, lưu lâu dài cho từng bot: đăng nhập các trang một lần, không đụng Chrome của người dùng.
    args: (c) => ["--browser", "chrome", "--user-data-dir", browserProfile(c)],
    readOnly: ["browser_snapshot", "browser_take_screenshot", "browser_console_messages", "browser_network_requests", "browser_network_request",
      "browser_find", "browser_wait_for", "browser_navigate", "browser_navigate_back"],
    hint: "TRÌNH DUYỆT RIÊNG của bot (Chrome hồ sơ riêng): CHỈ dùng khi không có trình duyệt Flygo nào online hoặc Sếp yêu cầu; việc trên web mặc định dùng trình duyệt Flygo (tool browser_* của Gateway)",
  },
  {
    name: "tmux", bins: ["tmux-mcp"], args: [], os: ["darwin", "linux"], needs: ["tmux"],
    readOnly: ["list-sessions", "find-session", "list-windows", "list-panes", "capture-pane", "get-command-result"],
    hint: "terminal tmux: mở phiên / cửa sổ terminal giữ lâu, chạy lệnh dài, đọc màn hình terminal đang chạy",
  },
];

const searchPath = () => {
  const extra = process.platform === "win32"
    ? [join(homedir(), ".local", "bin"), join(process.env.APPDATA ?? "", "npm")]
    : [join(homedir(), ".local", "bin"), "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"];
  return [...(process.env.PATH ?? "").split(delimiter), ...extra].filter(Boolean).join(delimiter);
};

function which(bin: string): string | null {
  const p = Bun.which(bin, { PATH: searchPath() });
  return p && existsSync(p) ? p : null;
}

export interface DesktopMcp {
  servers: Record<string, McpSpec>;
  readOnly: Record<string, string[]>; // server -> tool chỉ đọc
  hints: string[];
}

interface DesktopCfg { computerUse?: boolean; desktopMcp?: Record<string, Partial<McpSpec> | false>; botToken?: string }

/** Thư mục hồ sơ trình duyệt riêng của bot (theo mã băm token bot, không lộ token). */
function browserProfile(c: DesktopCfg): string {
  const id = createHash("sha256").update(String(c.botToken ?? "default")).digest("hex").slice(0, 12);
  const dir = join(homedir(), ".config", "flygo-agent", "browser", id);
  try { mkdirSync(dir, { recursive: true, mode: 0o700 }); } catch {}
  return dir;
}

let cached: { key: string; at: number; v: DesktopMcp } | null = null;

/** Các server điều khiển máy có trên máy này (phát hiện lại mỗi 5 phút: cài thêm không cần khởi động lại runner). */
export function desktopMcp(cfg: DesktopCfg): DesktopMcp {
  const key = JSON.stringify([cfg.computerUse, cfg.desktopMcp, createHash("sha256").update(String(cfg.botToken ?? "")).digest("hex").slice(0, 8)]);
  if (cached && cached.key === key && Date.now() - cached.at < 300_000) return cached.v;
  const v: DesktopMcp = { servers: {}, readOnly: {}, hints: [] };
  if (cfg.computerUse !== false) {
    const over = cfg.desktopMcp ?? {};
    for (const k of KNOWN) {
      if (over[k.name] === false || !k.os.includes(process.platform)) continue;
      if (k.needs?.some((n) => !which(n))) continue;
      if (k.skipIf && v.servers[k.skipIf]) continue;
      const kenv = k.env ? k.env() : {};
      if (kenv === null) continue;
      const o = over[k.name] || undefined;
      const command = o?.command ?? k.bins.map(which).find(Boolean);
      if (!command) continue;
      // PATH đủ cho server viết bằng Node (#!/usr/bin/env node): runner chạy từ app / launchd thường thiếu /opt/homebrew/bin.
      v.servers[k.name] = { command, args: o?.args ?? (typeof k.args === "function" ? k.args(cfg) : k.args), env: { PATH: searchPath(), ...kenv, ...(o?.env ?? {}) } };
      v.readOnly[k.name] = k.readOnly;
      v.hints.push(`${k.name}: ${k.hint}`);
    }
    for (const [name, o] of Object.entries(over)) { // server tự khai báo thêm
      if (!o || v.servers[name] || KNOWN.some((k) => k.name === name) || !o.command) continue;
      v.servers[name] = { command: o.command, args: o.args ?? [], ...(o.env ? { env: o.env } : {}) };
      v.readOnly[name] = [];
      v.hints.push(`${name}: MCP do chủ máy khai báo`);
    }
  }
  cached = { key, at: Date.now(), v };
  return v;
}

/** Tên tool kiểu Claude (mcp__server__tool) của các tool chỉ đọc. */
export const claudeReadOnly = (d: DesktopMcp) => Object.entries(d.readOnly).flatMap(([s, ts]) => ts.map((t) => `mcp__${s}__${t}`));

/** mcp_servers cho Codex: mọi tool hỏi duyệt, trừ tool chỉ đọc. */
export function codexServers(d: DesktopMcp) {
  return Object.fromEntries(Object.entries(d.servers).map(([name, s]) => [name, {
    command: s.command, args: s.args, ...(s.env ? { env: s.env } : {}), enabled: true,
    default_tools_approval_mode: "prompt",
    ...(d.readOnly[name]?.length ? { tools: Object.fromEntries(d.readOnly[name].map((t) => [t, { approval_mode: "approve" }])) } : {}),
  }]));
}

/** Dòng hướng dẫn cho persona: server nào có, dùng khi nào. */
export function desktopPersona(d: DesktopMcp, host: string): string {
  if (!d.hints.length) return "";
  return [
    `- Điều khiển máy ${host} (máy thật, không phải máy ảo) qua MCP, tự chọn server hợp việc:`,
    ...d.hints.map((h) => `  · ${h}`),
    `  · đọc trạng thái (liệt kê app / cửa sổ, cây giao diện) trước khi thao tác; mỗi click / gõ / mở app phải được duyệt, nói rõ sẽ làm gì; không đụng tới app / tài liệu ngoài việc được giao; không nhập mật khẩu, thông tin thanh toán`,
  ].join("\n");
}
