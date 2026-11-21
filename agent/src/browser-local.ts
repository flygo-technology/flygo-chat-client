// Mở lại Chrome khi trình duyệt Flygo đang tắt (Sếp, 2026-11-21): agent gọi browser_open_profiles trên chính máy có Chrome,
// runner mở các profile Chrome đã cài extension Flygo Browser Bridge để extension tự nối lại Gateway. Chỉ mở Chrome (không chạy
// lệnh tuỳ ý, không đọc mật khẩu / cookie): đọc "Local State" + Preferences của Chrome để biết profile nào có extension.
import { spawn } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { homedir, platform } from "node:os";
import { join } from "node:path";

export const BRIDGE_EXTENSION_ID = "pknpafgfaedabfloepblchniacfknjig";

export const BROWSER_LOCAL_TOOLS = [
  {
    name: "browser_open_profiles",
    description: "Trình duyệt Flygo đang tắt / offline (browser_list báo offline, tool trình duyệt báo không có trình duyệt online): mở Chrome trên MÁY NÀY "
      + "với các profile đã cài extension Flygo Browser Bridge để extension tự nối lại, rồi gọi vn_flygo_clients__browser_wait_online (hoặc browser_list) và thử lại. "
      + "profiles: chỉ mở các profile này (tên thư mục như \"Profile 8\", tên hiển thị hoặc email, vd \"ba@thangmaydndvina.com\"); bỏ trống = mọi profile có extension. "
      + "list=true: chỉ liệt kê, không mở. Chỉ dùng được khi trình duyệt nằm trên cùng máy với bạn (machine_name trong browser_list).",
    inputSchema: {
      type: "object",
      properties: {
        profiles: { type: "array", items: { type: "string" }, description: "Thư mục / tên / email của profile cần mở; bỏ trống = tất cả" },
        list: { type: "boolean", description: "Chỉ liệt kê profile có extension, không mở" },
      },
    },
  },
];
export const BROWSER_LOCAL_TOOL_NAMES = new Set(BROWSER_LOCAL_TOOLS.map((t) => t.name));

export interface ChromeProfile { dir: string; name: string; email: string; userData: string; browser: string }

type Os = "darwin" | "linux" | "win32";
const OS = platform() as Os;

/** Thư mục dữ liệu của Chrome / Chromium trên máy này (theo thứ tự ưu tiên). */
export function userDataDirs(os: Os = OS, home = homedir(), env = process.env): { browser: string; dir: string }[] {
  if (os === "darwin") return [
    { browser: "Google Chrome", dir: join(home, "Library/Application Support/Google/Chrome") },
    { browser: "Chromium", dir: join(home, "Library/Application Support/Chromium") },
  ];
  if (os === "win32") {
    const local = env.LOCALAPPDATA ?? join(home, "AppData", "Local");
    return [{ browser: "Google Chrome", dir: join(local, "Google", "Chrome", "User Data") }, { browser: "Chromium", dir: join(local, "Chromium", "User Data") }];
  }
  return [{ browser: "Google Chrome", dir: join(home, ".config/google-chrome") }, { browser: "Chromium", dir: join(home, ".config/chromium") }];
}

function readJson(p: string): any { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; } }

/** Profile có extension (đang bật) trong một thư mục dữ liệu Chrome. */
export function profilesWithExtension(userData: string, browser = "Google Chrome", extId = BRIDGE_EXTENSION_ID): ChromeProfile[] {
  if (!existsSync(userData)) return [];
  const info = readJson(join(userData, "Local State"))?.profile?.info_cache ?? {};
  const dirs = new Set<string>(Object.keys(info));
  try { for (const d of readdirSync(userData)) if (d === "Default" || /^Profile \d+$/.test(d)) dirs.add(d); } catch {}
  const out: ChromeProfile[] = [];
  for (const dir of [...dirs].sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))) {
    const has = ["Secure Preferences", "Preferences"].some((f) => {
      const s = readJson(join(userData, dir, f))?.extensions?.settings?.[extId];
      // state 0 / disable_reasons khác rỗng = đã tắt; extension giải nén (location 4) không có state thì coi là bật.
      return !!s && s.state !== 0 && !(Array.isArray(s.disable_reasons) ? s.disable_reasons.length : s.disable_reasons);
    });
    if (has) out.push({ dir, name: String(info[dir]?.name ?? dir), email: String(info[dir]?.user_name ?? ""), userData, browser });
  }
  return out;
}

export function findProfiles(want?: string[]): ChromeProfile[] {
  const all = userDataDirs().flatMap((u) => profilesWithExtension(u.dir, u.browser));
  const w = (want ?? []).map((s) => String(s).trim().toLowerCase()).filter(Boolean);
  if (!w.length) return all;
  return all.filter((p) => w.some((x) => [p.dir, p.name, p.email].some((v) => v.toLowerCase() === x || (x.length >= 4 && v.toLowerCase().includes(x)))));
}

function chromeExe(browser: string): string | null {
  if (OS === "win32") {
    const env = process.env;
    const cands = [env["ProgramFiles"], env["ProgramFiles(x86)"], env.LOCALAPPDATA].filter(Boolean).map((b) =>
      join(String(b), browser === "Chromium" ? "Chromium\\Application\\chrome.exe" : "Google\\Chrome\\Application\\chrome.exe"));
    return cands.find((c) => existsSync(c)) ?? null;
  }
  if (OS === "linux") {
    for (const c of browser === "Chromium" ? ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/snap/bin/chromium"] : ["/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/opt/google/chrome/chrome"])
      if (existsSync(c)) return c;
    return null;
  }
  return null;
}

/** Lệnh mở một profile (không chạy qua shell: tham số tách sẵn). macOS: open -gna để không cướp focus của người dùng. */
export function launchCommand(p: ChromeProfile, os: Os = OS): { cmd: string; args: string[] } | null {
  const prof = `--profile-directory=${p.dir}`;
  if (os === "darwin") return { cmd: "open", args: ["-gna", p.browser, "--args", prof] };
  const exe = chromeExe(p.browser);
  return exe ? { cmd: exe, args: [prof] } : null;
}

export async function browserLocalTool(name: string, a: any): Promise<string> {
  if (name !== "browser_open_profiles") throw new Error(`không có tool ${name}`);
  const want = Array.isArray(a?.profiles) ? a.profiles.map(String) : [];
  const found = findProfiles(want);
  const desc = (p: ChromeProfile) => `${p.dir} (${p.name}${p.email ? ", " + p.email : ""})`;
  if (!found.length) {
    const all = findProfiles();
    return want.length && all.length
      ? `Không có profile nào khớp ${JSON.stringify(want)}. Profile có extension trên máy này: ${all.map(desc).join("; ")}.`
      : "Máy này không có profile Chrome nào cài extension Flygo Browser Bridge (hoặc trình duyệt nằm ở máy khác): báo người dùng mở Chrome trên máy có trình duyệt.";
  }
  if (a?.list) return `Profile có extension trên máy này: ${found.map(desc).join("; ")}.`;
  const opened: string[] = [], failed: string[] = [];
  for (const p of found) {
    const c = launchCommand(p);
    if (!c) { failed.push(`${desc(p)}: không tìm thấy ${p.browser}`); continue; }
    try {
      // Linux: runner có thể chạy dưới systemd, thiếu DISPLAY; mặc định :0 (phiên đồ hoạ của chủ máy).
      const env = OS === "linux" && !process.env.DISPLAY && !process.env.WAYLAND_DISPLAY ? { ...process.env, DISPLAY: ":0" } : process.env;
      const child = spawn(c.cmd, c.args, { detached: true, stdio: "ignore", windowsHide: false, env });
      child.on("error", () => {});
      child.unref();
      opened.push(desc(p));
      await new Promise((r) => setTimeout(r, 1500)); // mở lần lượt: Chrome nhận từng profile vào cùng một tiến trình
    } catch (e: any) { failed.push(`${desc(p)}: ${e?.message ?? e}`); }
  }
  return [
    opened.length ? `Đã mở ${opened.length} profile Chrome: ${opened.join("; ")}.` : "",
    failed.length ? `Không mở được: ${failed.join("; ")}.` : "",
    "Extension cần vài giây để nối lại: gọi vn_flygo_clients__browser_wait_online (hoặc browser_list) rồi làm tiếp.",
  ].filter(Boolean).join("\n");
}
