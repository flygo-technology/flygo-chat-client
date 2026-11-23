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
  {
    name: "integrated_browser_open",
    description: "Dự phòng cục bộ: mở TRÌNH DUYỆT TÍCH HỢP trên MÁY NÀY ở nền (không cướp focus); trình duyệt ở máy khác (hoặc mặc định) dùng vn_flygo_clients__integrated_browser_start để khởi động từ xa. Trình duyệt Ký số đa năng, đúng profile công ty (tax = MST hoặc profile = <agentId>/<tokenId>, "
      + "xem vn_flygo_clients__integrated_browser_list), url tuỳ chọn. Khi mở, trình duyệt tự đăng ký với Gateway qua Flygo Chat trên máy này; gọi vn_flygo_clients__browser_wait_online rồi "
      + "browser_select và dùng các tool browser_* như Chrome. Ký số / mã PIN luôn do người dùng xác nhận trên trình duyệt; agent không đọc, không nhập.",
    inputSchema: {
      type: "object",
      properties: {
        app: { type: "string", enum: ["kyso-desktop"], description: "Trình duyệt cần mở (mặc định kyso-desktop = Trình duyệt Ký số đa năng)" },
        tax: { type: "string", description: "MST của công ty (profile token)" },
        profile: { type: "string", description: "Hoặc profile <agentId>/<tokenId>" },
        url: { type: "string", description: "Trang mở sẵn (http/https)" },
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

const KYSO_APP = "Trinh duyet Ky so da nang";

/** Lệnh mở Trình duyệt Ký số đa năng (cờ do app Ký số đọc: --hidden, --profile-tax / --profile, --url; lần mở sau chuyển cho tiến trình đang chạy). */
export function kysoLaunch(a: { tax?: string; profile?: string; url?: string }, os: Os = OS, env = process.env): { cmd: string; args: string[] } | { error: string } {
  const tax = String(a.tax ?? "").replace(/[^\d-]/g, "");
  const profile = String(a.profile ?? "").trim();
  const url = String(a.url ?? "").trim();
  if (url && !/^https?:\/\//i.test(url)) return { error: "url phải là http(s)" };
  if (profile && !/^[\w.@-]+\/[\w.@-]+$/.test(profile)) return { error: "profile phải dạng <agentId>/<tokenId>" };
  const flags = ["--hidden", ...(tax ? [`--profile-tax=${tax}`] : profile ? [`--profile=${profile}`] : []), ...(url ? [`--url=${url}`] : [])];
  // -n: app đang chạy thì open -a bỏ qua --args; mở tiến trình mới, nó chuyển argv cho tiến trình đang chạy (second-instance) rồi thoát.
  if (os === "darwin") return { cmd: "open", args: ["-n", "-g", "-a", KYSO_APP, "--args", ...flags] };
  if (os === "win32") {
    const bases = [env["ProgramFiles"], env["ProgramFiles(x86)"], env.LOCALAPPDATA && join(env.LOCALAPPDATA, "Programs")].filter(Boolean) as string[];
    const exe = bases.map((b) => join(b, KYSO_APP, `${KYSO_APP}.exe`)).find((p) => existsSync(p));
    return exe ? { cmd: exe, args: flags } : { error: `chưa cài ${KYSO_APP} trên máy này` };
  }
  return { error: "Trình duyệt Ký số đa năng chỉ có trên macOS / Windows" };
}

export async function browserLocalTool(name: string, a: any): Promise<string> {
  if (name === "integrated_browser_open") {
    if (a?.app && a.app !== "kyso-desktop") return `Chưa hỗ trợ mở ${a.app} (hiện có: kyso-desktop).`;
    const c = kysoLaunch(a ?? {});
    if ("error" in c) return `Không mở được: ${c.error}.`;
    if (OS === "darwin" && !existsSync(`/Applications/${KYSO_APP}.app`) && !existsSync(join(homedir(), "Applications", `${KYSO_APP}.app`)))
      return `Máy này chưa cài ${KYSO_APP}.`;
    const child = spawn(c.cmd, c.args, { detached: true, stdio: "ignore" });
    child.on("error", () => {});
    child.unref();
    return `Đã mở Trình duyệt Ký số đa năng ở nền${a?.tax ? ` (MST ${a.tax})` : a?.profile ? ` (profile ${a.profile})` : ""}. Gọi vn_flygo_clients__browser_wait_online (tên dạng "Ký số · <công ty> · <máy>") rồi browser_select và làm tiếp. Cần Flygo Chat đang chạy trên máy này để trình duyệt tự đăng ký.`;
  }
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
