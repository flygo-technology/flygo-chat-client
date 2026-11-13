// Điều khiển máy thật (computer-use) và terminal: MCP server mã nguồn mở đã cài trên máy chạy runner được tự phát hiện
// và gắn vào mọi engine (Claude / Codex / Antigravity), agent tự chọn tool hợp với việc.
// Tool chỉ đọc (liệt kê app / cửa sổ, đọc cây giao diện…) chạy luôn; click, gõ phím, mở app… phải xin duyệt
// (Claude: ngoài allowedTools; Codex: default_tools_approval_mode = "prompt"; agy: hook hỏi như tool lạ).
// Tắt hẳn: "computerUse": false trong config bot. Ghi đè / thêm server: "desktopMcp": { "<tên>": { command, args } | false }.
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";
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
    hint: "điều khiển app desktop CHẠY NGẦM, không giành chuột / bàn phím của người đang dùng máy (Mac / Windows / Linux): đọc cây giao diện, click, gõ, menu, kéo thả, trình duyệt; ưu tiên dùng cái này",
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
    hint: "TRÌNH DUYỆT RIÊNG của bot (Chrome hồ sơ riêng, giữ đăng nhập giữa các lượt): mở trang, đọc nội dung (browser_snapshot), bấm, điền form; mặc định dùng cái này cho việc trên web. Trang cần đăng nhập mà chưa đăng nhập thì nhờ Sếp đăng nhập một lần trong cửa sổ đó",
  },
  {
    // Chrome thật của chủ máy qua tiện ích Playwright MCP Bridge; token trong tệp (chủ máy chép từ tiện ích) cho nối tự động, không hỏi.
    name: "chrome", bins: ["playwright-mcp", "mcp-server-playwright"], args: ["--extension"], os: ["darwin", "win32", "linux"],
    env: () => { const t = extensionToken(); return t ? { PLAYWRIGHT_MCP_EXTENSION_TOKEN: t } : null; },
    readOnly: ["browser_snapshot", "browser_take_screenshot", "browser_console_messages", "browser_network_requests", "browser_network_request",
      "browser_find", "browser_wait_for", "browser_navigate", "browser_navigate_back"],
    hint: "CHROME THẬT của Sếp (tab đang mở, cookie, đăng nhập sẵn), nối tự động: dùng khi việc cần chính phiên đăng nhập / tab của Sếp; việc web thường dùng playwright (trình duyệt riêng của bot)",
  },
  {
    name: "chrome-devtools", bins: ["chrome-devtools-mcp"], args: ["--autoConnect"], os: ["darwin", "win32", "linux"], skipIf: "chrome",
    readOnly: ["list_pages", "select_page", "take_snapshot", "take_screenshot", "list_console_messages", "get_console_message",
      "list_network_requests", "get_network_request", "get_css_styles", "wait_for", "navigate_page", "new_page"],
    hint: "CHROME ĐANG MỞ của Sếp (dùng cookie / đăng nhập sẵn có của Sếp, Chrome hỏi Cho phép khi nối): chỉ dùng khi việc cần chính phiên đăng nhập của Sếp hoặc tab Sếp đang mở; còn lại dùng playwright",
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

const tokenFile = () => join(homedir(), ".config", "flygo-agent", "playwright-extension-token");

export const BRIDGE_ID = "mmlmfjhmonkocbjadbfplnigmagldckm"; // tiện ích Playwright MCP Bridge trên Chrome Web Store
const STORE_URL = `https://chromewebstore.google.com/detail/playwright-mcp-bridge/${BRIDGE_ID}`;

/** Thư mục dữ liệu Chrome của người dùng trên máy này. */
function chromeDataDir(): string {
  if (process.platform === "darwin") return join(homedir(), "Library", "Application Support", "Google", "Chrome");
  if (process.platform === "win32") return join(process.env.LOCALAPPDATA ?? join(homedir(), "AppData", "Local"), "Google", "Chrome", "User Data");
  return join(homedir(), ".config", "google-chrome");
}

const chromeProfiles = (): string[] => {
  const root = chromeDataDir();
  try { return readdirSync(root).filter((d) => d === "Default" || /^Profile \d+$/.test(d)).map((d) => join(root, d)); } catch { return []; }
};

/** Hồ sơ Chrome đã cài tiện ích (mới dùng gần nhất trước). */
function bridgeProfiles(): string[] {
  return chromeProfiles().filter((p) => existsSync(join(p, "Extensions", BRIDGE_ID)))
    .sort((a, b) => mtime(join(b, "Local Storage", "leveldb")) - mtime(join(a, "Local Storage", "leveldb")));
}
const mtime = (p: string) => { try { return statSync(p).mtimeMs; } catch { return 0; } };

/** Đọc token tiện ích từ Local Storage của nó trong hồ sơ Chrome (khoá "auth-token"). Tệp .log của leveldb không nén;
 *  sau khi Chrome gộp tệp (.ldb nén) có thể không đọc được nữa: khi đó tiện ích vẫn hiện token để chép tay. */
export function detectBridgeToken(): { token: string; profile: string } | null {
  const key = Buffer.from(`_chrome-extension://${BRIDGE_ID}\u0000\u0001auth-token`, "latin1");
  let best: { token: string; profile: string; at: number } | null = null;
  for (const prof of bridgeProfiles()) {
    const dir = join(prof, "Local Storage", "leveldb");
    let files: string[] = [];
    try { files = readdirSync(dir).filter((f) => /\.(log|ldb)$/.test(f)); } catch { continue; }
    for (const f of files) {
      let buf: Buffer;
      try { buf = readFileSync(join(dir, f)); } catch { continue; }
      for (let i = buf.indexOf(key); i >= 0; i = buf.indexOf(key, i + 1)) {
        const m = /^[\s\S]{1,3}?\u0001([A-Za-z0-9_-]{20,200})/.exec(buf.subarray(i + key.length, i + key.length + 220).toString("latin1"));
        const at = mtime(join(dir, f));
        if (m && (!best || at >= best.at)) best = { token: m[1], profile: prof.split(/[\\/]/).pop()!, at };
      }
    }
  }
  return best ? { token: best.token, profile: best.profile } : null;
}

/** Token của tiện ích Playwright MCP Bridge: tệp đã lưu, không có thì tự đọc từ hồ sơ Chrome và lưu lại. */
function extensionToken(): string {
  try { const t = readFileSync(tokenFile(), "utf8").trim(); if (t) return t; } catch {}
  const d = detectBridgeToken();
  if (d) { saveExtensionToken(d.token); return d.token; }
  return "";
}

/** browser_extension_setup: tự cài tiện ích (Chrome hỏi bật một lần) và tự lấy token. */
export function setupBridge(): string {
  const found = detectBridgeToken();
  if (found) {
    let cur = ""; try { cur = readFileSync(tokenFile(), "utf8").trim(); } catch {}
    if (cur !== found.token) saveExtensionToken(found.token);
    return `Tiện ích Playwright MCP Bridge đã cài trong hồ sơ Chrome "${found.profile}" và đã lấy token${cur === found.token ? " (giữ nguyên)" : " mới"}. Từ lượt sau server "chrome" nối Chrome thật tự động, không cần bấm Cho phép.`;
  }
  const installed = bridgeProfiles();
  if (installed.length) {
    openInChrome(`chrome-extension://${BRIDGE_ID}/status.html`);
    return `Tiện ích đã cài (hồ sơ "${installed.map((p) => p.split(/[\\/]/).pop()).join(", ")}") nhưng chưa đọc được token. Em vừa mở trang của tiện ích; nếu chưa thấy, Sếp bấm biểu tượng tiện ích một lần rồi bảo em chạy lại browser_extension_setup (hoặc chép PLAYWRIGHT_MCP_EXTENSION_TOKEN gửi em để lưu bằng browser_token_set).`;
  }
  const how = registerExternal();
  openInChrome(STORE_URL);
  return `Chưa có tiện ích Playwright MCP Bridge. ${how} Em đã mở trang tiện ích trên Chrome Web Store: Sếp bấm "Thêm vào Chrome" (Chrome bắt buộc người dùng xác nhận khi cài tiện ích), rồi bảo em chạy lại browser_extension_setup để tự lấy token.`;
}

/** Đăng ký cài tiện ích từ ngoài (external extension): Chrome cài ở lần mở sau và hỏi bật một lần. */
function registerExternal(): string {
  try {
    if (process.platform === "win32") {
      Bun.spawnSync(["reg", "add", `HKCU\\Software\\Google\\Chrome\\Extensions\\${BRIDGE_ID}`, "/v", "update_url", "/t", "REG_SZ", "/d", "https://clients2.google.com/service/update2/crx", "/f"]);
    } else {
      const dir = process.platform === "darwin" ? join(chromeDataDir(), "External Extensions") : join(homedir(), ".config", "google-chrome", "External Extensions");
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, `${BRIDGE_ID}.json`), JSON.stringify({ external_update_url: "https://clients2.google.com/service/update2/crx" }));
    }
    return "Em đã đăng ký cho Chrome tự cài tiện ích (lần mở Chrome sau sẽ hỏi bật).";
  } catch (e: any) {
    return `Không đăng ký cài tự động được (${e?.message ?? e}).`;
  }
}

function openInChrome(url: string) {
  try {
    if (process.platform === "darwin") Bun.spawn(["open", "-a", "Google Chrome", url]);
    else if (process.platform === "win32") Bun.spawn(["cmd", "/c", "start", "", "chrome", url]);
    else Bun.spawn(["google-chrome", url], { stdout: "ignore", stderr: "ignore" });
  } catch {}
}

/** browser_token_set: lưu (hoặc xoá khi rỗng) token tiện ích; lượt sau server "chrome" nối Chrome thật tự động, không hỏi. */
export function saveExtensionToken(token: string): string {
  const t = token.trim().replace(/^PLAYWRIGHT_MCP_EXTENSION_TOKEN=/, "");
  if (!t) { try { unlinkSync(tokenFile()); } catch {} cached = null; return "Đã xoá token Chrome: agent quay lại dùng trình duyệt riêng của bot."; }
  if (!/^[A-Za-z0-9_-]{20,200}$/.test(t)) return "Token không hợp lệ (chép đúng giá trị PLAYWRIGHT_MCP_EXTENSION_TOKEN trong tiện ích Playwright MCP Bridge).";
  mkdirSync(join(homedir(), ".config", "flygo-agent"), { recursive: true, mode: 0o700 });
  writeFileSync(tokenFile(), t, { mode: 0o600 });
  try { chmodSync(tokenFile(), 0o600); } catch {}
  cached = null;
  return "Đã lưu token Chrome. Từ lượt sau agent nối thẳng Chrome của Sếp qua server \"chrome\", không cần bấm Cho phép.";
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
