// Điều khiển điện thoại Android qua adb cho agent (flygo-chat, 2026-11-23): bộ tool adb_* chạy trong runner trên máy cắm
// điện thoại / chạy emulator. Mỗi thao tác trả lại màn hình mới ở dạng chữ gọn (cây giao diện uiautomator: mã phần tử, chữ,
// toạ độ) để cả model chỉ đọc chữ cũng dùng được; ảnh chụp màn hình chỉ gửi khi xin (image=true).
// An toàn: chỉ chủ bot; mỗi thao tác ghi nhật ký; cài / gỡ / xoá dữ liệu app, đẩy tệp, lệnh shell không chỉ đọc, bấm nút
// gửi / thanh toán đều xin duyệt; khoá theo máy để hai agent không giành một điện thoại.
import { existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync, rmSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, isAbsolute, join, resolve } from "node:path";

const DEV = { type: "string", description: "serial máy (adb_devices); bỏ trống khi chỉ có một máy hoặc dùng máy đang giữ" };
const IMG = { type: "boolean", description: "kèm ảnh chụp màn hình (chỉ khi cần nhìn hình; mặc định chỉ chữ)" };
const EL = { type: "string", description: "mã phần tử ở màn hình gần nhất, vd \"e12\"" };

export const ADB_TOOLS = [
  { name: "adb_devices", description: "Liệt kê điện thoại / emulator Android nối adb với máy này: serial, model, trạng thái, ai đang giữ (khoá).", inputSchema: { type: "object", properties: {} } },
  { name: "adb_snapshot", description: "ĐỌC MÀN HÌNH điện thoại: app đang mở + danh sách phần tử [eN] vai trò \"chữ\" (x,y) cờ. Dùng mã eN cho adb_tap / adb_type. image=true để kèm ảnh. Gọi đầu tiên để giữ máy (khoá 10 phút, tự gia hạn khi thao tác).", inputSchema: { type: "object", properties: { device: DEV, image: IMG, all: { type: "boolean", description: "liệt kê cả phần tử không có chữ / không bấm được" } } } },
  { name: "adb_tap", description: "Chạm vào phần tử (element = eN) hoặc toạ độ (x, y). long=true để nhấn giữ. Trả màn hình mới. Nút gửi / thanh toán / chuyển tiền / mua phải xin duyệt.", inputSchema: { type: "object", properties: { device: DEV, element: EL, x: { type: "number" }, y: { type: "number" }, long: { type: "boolean" }, image: IMG } } },
  { name: "adb_swipe", description: "Vuốt / cuộn: direction up|down|left|right (\"down\" = xem nội dung phía dưới) trong phần tử (element, vd danh sách) hoặc cả màn hình; hoặc từ (x1,y1) tới (x2,y2). Trả màn hình mới.", inputSchema: { type: "object", properties: { device: DEV, direction: { type: "string", enum: ["up", "down", "left", "right"] }, element: EL, x1: { type: "number" }, y1: { type: "number" }, x2: { type: "number" }, y2: { type: "number" }, duration_ms: { type: "number" }, image: IMG } } },
  { name: "adb_type", description: "Gõ chữ (có dấu tiếng Việt / Unicode qua ADBKeyboard) vào ô đang chọn hoặc ô element (chạm vào trước). clear=true để xoá chữ cũ, enter=true để nhấn Enter sau khi gõ. Không gõ mật khẩu / mã OTP / thông tin thẻ.", inputSchema: { type: "object", properties: { device: DEV, text: { type: "string" }, element: EL, clear: { type: "boolean" }, enter: { type: "boolean" }, image: IMG }, required: ["text"] } },
  { name: "adb_key", description: "Nhấn phím: back, home, enter, recents, delete, tab, escape, search, menu, wakeup, sleep, volume_up, volume_down, hoặc mã KEYCODE_*. Trả màn hình mới.", inputSchema: { type: "object", properties: { device: DEV, key: { type: "string" }, image: IMG }, required: ["key"] } },
  { name: "adb_app", description: "Quản lý app: action start (package hoặc activity \"pkg/.Act\", hoặc intent như android.settings.SETTINGS) | stop | list (query lọc tên; system=true gồm app hệ thống) | info | install (apk trên máy này, cần duyệt) | uninstall / clear (xoá dữ liệu, cần duyệt).", inputSchema: { type: "object", properties: { device: DEV, action: { type: "string", enum: ["start", "stop", "list", "info", "install", "uninstall", "clear"] }, package: { type: "string" }, intent: { type: "string" }, apk: { type: "string" }, query: { type: "string" }, system: { type: "boolean" }, image: IMG }, required: ["action"] } },
  { name: "adb_find", description: "Tìm phần tử trên màn hình theo chữ (text, khớp một phần, không phân biệt hoa thường / dấu) hoặc resource_id; timeout_sec > 0 thì CHỜ tới khi xuất hiện (gone=true: chờ tới khi biến mất). Trả các phần tử khớp + màn hình.", inputSchema: { type: "object", properties: { device: DEV, text: { type: "string" }, resource_id: { type: "string" }, timeout_sec: { type: "number" }, gone: { type: "boolean" } } } },
  { name: "adb_shell", description: "Chạy lệnh adb shell trên điện thoại. Lệnh chỉ đọc (getprop, dumpsys, pm list, settings get, wm size, ls, cat…) chạy luôn; lệnh khác xin duyệt. Không dùng để xoá dữ liệu / gỡ app (dùng adb_app).", inputSchema: { type: "object", properties: { device: DEV, command: { type: "string" }, timeout_sec: { type: "number" } }, required: ["command"] } },
  { name: "adb_logcat", description: "Đọc logcat gần nhất: lines (mặc định 200), filter (chữ cần có), package (chỉ tiến trình của app), level (V/D/I/W/E).", inputSchema: { type: "object", properties: { device: DEV, lines: { type: "number" }, filter: { type: "string" }, package: { type: "string" }, level: { type: "string" } } } },
  { name: "adb_file", description: "Chép tệp: action pull (điện thoại -> thư mục làm việc trên máy này) | push (máy này -> điện thoại, cần duyệt). remote = đường dẫn trên điện thoại (vd /sdcard/Download/a.pdf), local = đường dẫn trên máy.", inputSchema: { type: "object", properties: { device: DEV, action: { type: "string", enum: ["pull", "push"] }, remote: { type: "string" }, local: { type: "string" } }, required: ["action", "remote"] } },
  { name: "adb_release", description: "Trả máy (bỏ khoá) khi xong việc để agent khác dùng.", inputSchema: { type: "object", properties: { device: DEV } } },
];
export const ADB_TOOL_NAMES = new Set(ADB_TOOLS.map((t) => t.name));

// ---------- chạy adb ----------
export interface ExecResult { code: number; out: Buffer; err: string }
export type Exec = (args: string[], opt?: { timeoutMs?: number }) => Promise<ExecResult>;

/** Đường dẫn adb: PATH, rồi các SDK hay gặp (Android Studio macOS / Linux, ANDROID_HOME). */
export function adbPath(env = process.env, home = homedir()): string | null {
  const w = typeof Bun !== "undefined" ? Bun.which("adb", { PATH: [env.PATH ?? "", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].join(":") }) : null;
  if (w) return w;
  const cands = [env.ANDROID_HOME, env.ANDROID_SDK_ROOT, join(home, "Library/Android/sdk"), join(home, "Android/Sdk")].filter(Boolean).map((d) => join(String(d), "platform-tools", "adb"));
  return cands.find((p) => existsSync(p)) ?? null;
}

export function realExec(bin: string): Exec {
  return async (args, opt) => {
    const p = Bun.spawn([bin, ...args], { stdout: "pipe", stderr: "pipe", stdin: "ignore" });
    const t = setTimeout(() => { try { p.kill(); } catch {} }, opt?.timeoutMs ?? 30_000);
    const [out, err] = await Promise.all([new Response(p.stdout).arrayBuffer(), new Response(p.stderr).text()]);
    const code = await p.exited;
    clearTimeout(t);
    return { code, out: Buffer.from(out), err };
  };
}

/** Bọc một đối số cho shell của điện thoại (adb shell nối đối số thành một dòng lệnh). */
export const shq = (s: string) => `'${String(s).replace(/'/g, `'\\''`)}'`;

// ---------- thiết bị ----------
export interface Device { serial: string; state: string; model: string; product: string; transport: string }

export function parseDevices(out: string): Device[] {
  return out.split("\n").slice(1).map((l) => l.trim()).filter(Boolean).map((l) => {
    const [serial, state, ...rest] = l.split(/\s+/);
    const kv = Object.fromEntries(rest.map((x) => x.split(":")).filter((x) => x.length === 2));
    return { serial, state, model: String(kv.model ?? "").replace(/_/g, " "), product: String(kv.product ?? ""), transport: String(kv.transport_id ?? "") };
  });
}

// ---------- khoá theo máy (tệp: dùng chung mọi bot / tiến trình runner trên máy) ----------
export const LOCK_TTL_MS = 10 * 60_000;
export interface Lock { holder: string; label: string; at: number; until: number }
const safeSerial = (s: string) => s.replace(/[^\w.:-]/g, "_");

export class Locks {
  constructor(private dir = join(homedir(), ".config", "flygo-agent", "adb-locks"), private now = () => Date.now()) {}
  private file(serial: string) { return join(this.dir, `${safeSerial(serial)}.json`); }
  get(serial: string): Lock | null {
    try { const l = JSON.parse(readFileSync(this.file(serial), "utf8")) as Lock; return l.until > this.now() ? l : null; } catch { return null; }
  }
  /** Giữ / gia hạn máy; trả khoá của người khác nếu máy đang bị giữ. */
  acquire(serial: string, holder: string, label: string): { ok: true } | { ok: false; lock: Lock } {
    const cur = this.get(serial);
    if (cur && cur.holder !== holder) return { ok: false, lock: cur };
    mkdirSync(this.dir, { recursive: true, mode: 0o700 });
    const at = cur?.at ?? this.now();
    writeFileSync(this.file(serial), JSON.stringify({ holder, label, at, until: this.now() + LOCK_TTL_MS }));
    return { ok: true };
  }
  release(serial: string, holder: string): boolean {
    const cur = this.get(serial);
    if (!cur || cur.holder !== holder) return false;
    try { rmSync(this.file(serial)); } catch {}
    return true;
  }
  heldBy(holder: string): string[] {
    try { return readdirSync(this.dir).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).filter((s) => this.get(s)?.holder === holder); } catch { return []; }
  }
}

// ---------- cây giao diện ----------
export interface El {
  id: string; role: string; label: string; rid: string; cls: string; pkg: string;
  x: number; y: number; b: [number, number, number, number];
  clickable: boolean; scrollable: boolean; editable: boolean; checkable: boolean; checked: boolean; enabled: boolean; focused: boolean; selected: boolean; password: boolean;
}
interface RawNode { a: Record<string, string>; kids: RawNode[] }

const decodeXml = (s: string) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&amp;/g, "&");

export function parseXml(xml: string): RawNode[] {
  const root: RawNode = { a: {}, kids: [] };
  const stack = [root];
  for (const m of xml.matchAll(/<node\b([^>]*?)(\/?)>|<\/node>/g)) {
    if (m[0] === "</node>") { if (stack.length > 1) stack.pop(); continue; }
    const a: Record<string, string> = {};
    for (const am of m[1].matchAll(/([\w-]+)="([^"]*)"/g)) a[am[1]] = decodeXml(am[2]);
    const n = { a, kids: [] };
    stack[stack.length - 1].kids.push(n);
    if (!m[2]) stack.push(n);
  }
  return root.kids;
}

const bounds = (s: string): [number, number, number, number] | null => {
  const m = /\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]/.exec(s ?? "");
  return m ? [+m[1], +m[2], +m[3], +m[4]] : null;
};

function roleOf(cls: string, n: Record<string, string>): string {
  const c = cls.split(".").pop() ?? "";
  if (/EditText|AutoComplete/i.test(c)) return "input";
  if (/Switch|Toggle/i.test(c)) return "switch";
  if (/CheckBox/i.test(c)) return "checkbox";
  if (/RadioButton/i.test(c)) return "radio";
  if (/Button/i.test(c)) return "button";
  if (n.scrollable === "true") return "list";
  if (/Image/i.test(c)) return n.clickable === "true" ? "button" : "image";
  if (/TextView/i.test(c)) return n.clickable === "true" ? "button" : "text";
  if (n.clickable === "true" || n["long-clickable"] === "true") return "item";
  return "view";
}

const own = (a: Record<string, string>) => (a.text || a["content-desc"] || "").replace(/\s+/g, " ").trim();

/** Phần tử có ích cho agent: bấm được / cuộn được / ô nhập / có chữ. Khối bấm được không chữ lấy chữ của con (dòng cài đặt = tiêu đề · mô tả). */
export function elements(nodes: RawNode[], screen?: { w: number; h: number }, all = false): El[] {
  const out: El[] = [];
  const texts = (n: RawNode, acc: string[]) => { const t = own(n.a); if (t && !acc.includes(t)) acc.push(t); for (const k of n.kids) texts(k, acc); return acc; };
  const walk = (n: RawNode, consumed: boolean) => {
    const a = n.a;
    const b = bounds(a.bounds);
    const visible = !!b && b[2] > b[0] && b[3] > b[1] && (!screen || (b[2] > 0 && b[3] > 0 && b[0] < screen.w && b[1] < screen.h));
    const clickable = a.clickable === "true" || a["long-clickable"] === "true";
    const scrollable = a.scrollable === "true";
    const editable = /EditText|AutoComplete/i.test(a.class ?? "");
    const checkable = a.checkable === "true";
    let label = own(a);
    let eat = false;
    if (clickable && !editable && !label) { label = texts(n, []).slice(0, 3).join(" · "); eat = true; }
    const useful = clickable || scrollable || editable || checkable || (!!label && !consumed) || (all && !!a.class);
    if (visible && useful && !(consumed && !clickable && !scrollable && !editable && !checkable)) {
      const [l, t, r, bt] = b!;
      out.push({
        id: `e${out.length + 1}`, role: roleOf(a.class ?? "", a), label: label.slice(0, 120), rid: (a["resource-id"] ?? "").replace(/^.*:id\//, ""), cls: a.class ?? "", pkg: a.package ?? "",
        x: Math.round((l + r) / 2), y: Math.round((t + bt) / 2), b: b!,
        clickable, scrollable, editable, checkable, checked: a.checked === "true", enabled: a.enabled !== "false", focused: a.focused === "true", selected: a.selected === "true", password: a.password === "true",
      });
    }
    for (const k of n.kids) walk(k, consumed || eat);
  };
  // u2 trả mọi cửa sổ: bỏ thanh trạng thái / thanh điều hướng (com.android.systemui) trừ khi all.
  nodes = all ? nodes : nodes.filter((n) => n.a.package !== "com.android.systemui");
  for (const n of nodes) walk(n, false);
  // Bỏ phần tử chữ trùng hệt (cùng chữ, cùng toạ độ) do lớp bọc lặp lại.
  const seen = new Set<string>();
  return out.filter((e) => { const k = `${e.label}|${e.x}|${e.y}|${e.clickable}`; if (seen.has(k)) return false; seen.add(k); return true; }).map((e, i) => ({ ...e, id: `e${i + 1}` }));
}

export function fmtEl(e: El): string {
  const flags = [
    e.scrollable && "scroll", e.editable && "edit", e.checkable && (e.checked ? "on" : "off"), e.focused && "focused", e.selected && "selected",
    !e.enabled && "disabled", e.password && "password", e.clickable && e.role !== "button" && e.role !== "item" && "tap",
  ].filter(Boolean).join(" ");
  const rid = e.rid && (!e.label || e.editable || e.role === "list") ? ` #${e.rid}` : "";
  return `[${e.id}] ${e.role}${e.label ? ` "${e.label}"` : ""}${rid} (${e.x},${e.y})${flags ? " " + flags : ""}`;
}

export interface Screen { serial: string; app: string; w: number; h: number; els: El[]; at: number; keyboard: boolean }

export function fmtScreen(s: Screen, max = 12_000): string {
  const head = `Máy ${s.serial} · ${s.app || "?"} · ${s.w}x${s.h}${s.keyboard ? " · bàn phím đang mở" : ""} · ${s.els.length} phần tử`;
  const lines = [head];
  let n = head.length;
  for (const e of s.els) {
    const l = fmtEl(e);
    if (n + l.length > max) { lines.push(`… còn ${s.els.length - lines.length + 1} phần tử (cuộn hoặc adb_find để tìm)`); break; }
    lines.push(l); n += l.length + 1;
  }
  return lines.join("\n");
}

const fold = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();
export const matchText = (e: El, q: string) => fold(e.label).includes(fold(q));

/** Nút có vẻ là gửi / thanh toán / chuyển tiền / mua / xoá: bấm phải xin duyệt (quy tắc đồng ý của agent). */
export const RISKY = /\b(send|pay|payment|purchase|buy|checkout|order|transfer|confirm|submit|post|publish|delete|remove|uninstall|reset|erase|factory|gui|thanh toan|chuyen tien|chuyen khoan|mua|dat hang|xac nhan|dang bai|dang|xoa|go cai dat|khoi phuc)\b/;
export const isRisky = (label: string) => RISKY.test(fold(label));

/** Lệnh shell chỉ đọc (không cần duyệt): một lệnh, không nối / chuyển hướng / thay thế. */
export function readOnlyShell(cmd: string): boolean {
  const c = cmd.trim();
  if (!c || /[;&|><`$\n\\]/.test(c)) return false;
  return /^(getprop|dumpsys|pm (list|path|dump)|settings (get|list)|wm (size|density)|ls|cat|stat|df|du|ps|top -n 1|id|whoami|date|uptime|ip (a|addr|route|link)|ifconfig|cmd (package (list|resolve-activity)|wifi status|connectivity)|service list|uiautomator dump|screencap|input keyevent KEYCODE_WAKEUP)\b/.test(c)
    && !/\b(rm|mv|cp|dd|chmod|chown|setprop|put|delete|clear|install|uninstall|reboot)\b/.test(c.replace(/^(getprop|dumpsys|cat|ls)\s/, ""));
}

const KEYS: Record<string, string> = {
  back: "KEYCODE_BACK", home: "KEYCODE_HOME", enter: "KEYCODE_ENTER", recents: "KEYCODE_APP_SWITCH", app_switch: "KEYCODE_APP_SWITCH",
  delete: "KEYCODE_DEL", backspace: "KEYCODE_DEL", tab: "KEYCODE_TAB", escape: "KEYCODE_ESCAPE", search: "KEYCODE_SEARCH", menu: "KEYCODE_MENU",
  wakeup: "KEYCODE_WAKEUP", sleep: "KEYCODE_SLEEP", volume_up: "KEYCODE_VOLUME_UP", volume_down: "KEYCODE_VOLUME_DOWN", up: "KEYCODE_DPAD_UP",
  down: "KEYCODE_DPAD_DOWN", left: "KEYCODE_DPAD_LEFT", right: "KEYCODE_DPAD_RIGHT",
};
export function keyCode(k: string): string | null {
  const s = String(k ?? "").trim();
  if (KEYS[s.toLowerCase()]) return KEYS[s.toLowerCase()];
  if (/^KEYCODE_[A-Z0-9_]+$/.test(s)) return s;
  if (/^\d{1,3}$/.test(s)) return s;
  return null;
}

/** Chữ cho `input text`: chỉ ASCII in được; dấu cách thành %s. */
export const asciiTypable = (s: string) => /^[\x20-\x7e]*$/.test(s);
export const inputTextArg = (s: string) => shq(s.replace(/%/g, "\\%").replace(/ /g, "%s"));

// ---------- công cụ ----------
export interface AdbCtx {
  holder: string; // bot + phiên đang làm: khoá máy theo nó
  label: string; // tên hiển thị của người giữ (bot · người giao)
  workdir: string;
  approve: (title: string, detail?: string) => Promise<boolean>;
  audit: (e: Record<string, unknown>) => void;
}
export interface AdbResult { text: string; image?: string } // image = PNG base64

const ADBKBD = "com.android.adbkeyboard/.AdbIME";
const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n) + "\n…(cắt bớt)" : s);

// ---------- uiautomator2 (openatx u2.jar): đọc được cả màn hình không bao giờ "idle" (đồng hồ chạy, video, hiệu ứng) ----------
// Không cài app: chép u2.jar vào /data/local/tmp (một lần mỗi máy, xin duyệt) và chạy bằng app_process dưới quyền shell.
export const U2_JAR_URL = "https://github.com/openatx/android-uiautomator-server-jar/releases/download/0.4.1/u2.jar";
export const U2_JAR_SHA256 = "87c8ac9505970d42aa5922baa90114808fda6f47f9e5fbd4caa0f621c2c8d30d";
const U2_REMOTE = "/data/local/tmp/u2.jar";

export class U2 {
  private procs = new Map<string, { kill(): void }>();
  private ports = new Map<string, number>();
  constructor(private bin: string, private exec: Exec, private cacheDir = join(homedir(), ".config", "flygo-agent", "u2")) {}

  /** u2.jar trên máy này (tải một lần, kiểm sha256). */
  async localJar(): Promise<string> {
    const f = join(this.cacheDir, "u2-0.4.1.jar");
    const ok = (b: Buffer) => new Bun.CryptoHasher("sha256").update(b).digest("hex") === U2_JAR_SHA256;
    if (existsSync(f) && ok(readFileSync(f))) return f;
    const r = await fetch(U2_JAR_URL, { signal: AbortSignal.timeout(60_000) });
    const b = Buffer.from(await r.arrayBuffer());
    if (!r.ok || !ok(b)) throw new Error("tải u2.jar lỗi hoặc sai sha256");
    mkdirSync(this.cacheDir, { recursive: true, mode: 0o700 });
    writeFileSync(f, b);
    return f;
  }

  private have = new Set<string>();
  async present(serial: string): Promise<boolean> {
    if (this.have.has(serial)) return true;
    const r = await this.exec(["-s", serial, "shell", `sha256sum ${U2_REMOTE} 2>/dev/null`], { timeoutMs: 10_000 });
    const ok = r.out.toString().includes(U2_JAR_SHA256);
    if (ok) this.have.add(serial);
    return ok;
  }

  async push(serial: string) {
    const r = await this.exec(["-s", serial, "push", await this.localJar(), U2_REMOTE], { timeoutMs: 120_000 });
    if (r.code !== 0) throw new Error(`chép u2.jar lỗi: ${r.err.trim()}`);
    this.have.add(serial);
  }

  running(serial: string) { return this.procs.has(serial); }

  async rpc(serial: string, method: string, params: unknown[] = [], timeoutMs = 15_000): Promise<any> {
    const port = this.ports.get(serial);
    if (!port) throw new Error("u2 chưa chạy");
    const r = await fetch(`http://127.0.0.1:${port}/jsonrpc/0`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }), signal: AbortSignal.timeout(timeoutMs) });
    const j: any = await r.json();
    if (j.error) throw new Error(`u2 ${method}: ${j.error.message ?? JSON.stringify(j.error)}`);
    return j.result;
  }

  /** Chạy server trên điện thoại (tiến trình adb shell sống cùng runner) + forward cổng 9008. */
  async start(serial: string) {
    if (this.procs.has(serial)) return;
    const p = Bun.spawn([this.bin, "-s", serial, "shell", `CLASSPATH=${U2_REMOTE} exec app_process / com.wetest.uia2.Main -p 9008`], { stdout: "ignore", stderr: "ignore", stdin: "ignore" });
    this.procs.set(serial, p);
    p.exited.then(() => { this.procs.delete(serial); this.ports.delete(serial); });
    const f = await this.exec(["-s", serial, "forward", "tcp:0", "tcp:9008"], { timeoutMs: 10_000 });
    const port = parseInt(f.out.toString().trim(), 10);
    if (!port) { this.stop(serial); throw new Error(`adb forward lỗi: ${f.err.trim()}`); }
    this.ports.set(serial, port);
    for (let i = 0; i < 40; i++) {
      const pong = await fetch(`http://127.0.0.1:${port}/ping`, { signal: AbortSignal.timeout(2000) }).then((r) => r.text()).catch(() => "");
      if (pong === "pong") return;
      if (!this.procs.has(serial)) break;
      await Bun.sleep(500);
    }
    this.stop(serial);
    throw new Error("server uiautomator2 không lên (có phiên uiautomator khác đang chạy trên máy?)");
  }

  stop(serial: string) {
    const p = this.procs.get(serial);
    try { p?.kill(); } catch {}
    this.procs.delete(serial);
    const port = this.ports.get(serial);
    this.ports.delete(serial);
    if (port) this.exec(["-s", serial, "forward", "--remove", `tcp:${port}`]).catch(() => {});
    this.exec(["-s", serial, "shell", "pkill -f com.wetest.uia2.Main"]).catch(() => {});
  }

  dump(serial: string): Promise<string> { return this.rpc(serial, "dumpWindowHierarchy", [false, 50], 20_000); }
}

export class Adb {
  private last = new Map<string, Screen>();
  /** allow: serial được phép (cấu hình adbDevices của bot); máy ngoài danh sách bị ẩn hẳn, không đọc / bấm được. */
  constructor(public exec: Exec, public locks = new Locks(), private sleep = (ms: number) => Bun.sleep(ms), public u2?: U2, public allow: () => string[] = () => []) {}
  private approveU2 = new Map<string, AdbCtx>(); // máy -> ngữ cảnh lượt đang làm (xin duyệt chép u2.jar)

  async devices(): Promise<Device[]> {
    const r = await this.exec(["devices", "-l"], { timeoutMs: 10_000 });
    if (r.code !== 0) throw new Error(`adb devices lỗi: ${r.err.trim() || r.code}`);
    const ok = new Set(this.allow());
    return parseDevices(r.out.toString()).filter((d) => ok.has(d.serial));
  }

  async sh(serial: string, cmd: string, timeoutMs = 20_000): Promise<string> {
    const r = await this.exec(["-s", serial, "shell", cmd], { timeoutMs });
    if (r.code !== 0 && !r.out.length) throw new Error(r.err.trim() || `adb shell thoát ${r.code}`);
    return r.out.toString();
  }

  /** Chọn máy: serial được nêu; không thì máy đang giữ; không thì máy duy nhất đang online. */
  async pick(want: string | undefined, holder: string): Promise<string> {
    const ds = (await this.devices()).filter((d) => d.state === "device");
    const w = String(want ?? "").trim();
    if (w) {
      const d = ds.find((x) => x.serial === w) ?? ds.find((x) => x.model.toLowerCase().includes(w.toLowerCase()));
      if (!d) throw new Error(`không thấy máy "${w}" trong các máy bot được phép dùng (đang online: ${ds.map((x) => `${x.serial} ${x.model}`).join(", ") || "không có"})`);
      return d.serial;
    }
    const mine = ds.filter((d) => this.locks.get(d.serial)?.holder === holder);
    if (mine.length === 1) return mine[0].serial;
    if (ds.length === 1) return ds[0].serial;
    if (!ds.length) throw new Error("không có điện thoại / emulator nào online trên máy này (adb devices)");
    throw new Error(`có ${ds.length} máy, chọn device: ${ds.map((x) => `${x.serial} (${x.model})`).join(", ")}`);
  }

  private hold(serial: string, ctx: AdbCtx) {
    const r = this.locks.acquire(serial, ctx.holder, ctx.label);
    if (!r.ok) throw new Error(`máy ${serial} đang được ${r.lock.label} dùng (tới ${new Date(r.lock.until).toLocaleTimeString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh", hour12: false })}); chờ hoặc dùng máy khác`);
  }

  async screen(serial: string, all = false): Promise<Screen> {
    let xml = "";
    // u2.jar đã có trên máy (đã duyệt trước đó): dùng luôn, nhanh hơn dump thường nhiều (≈0,1 s so với 2 s).
    if (this.u2 && !this.u2.running(serial) && (await this.u2.present(serial).catch(() => false))) await this.u2.start(serial).catch(() => {});
    if (this.u2?.running(serial)) xml = await this.u2.dump(serial).catch(() => "");
    for (let i = 0; i < 2 && !xml.includes("<hierarchy") && !this.u2?.running(serial); i++) {
      // Màn hình đang chạy hiệu ứng thì uiautomator báo "could not get idle state": thử lại một lần, rồi chuyển sang u2.
      if (i) await this.sleep(400);
      xml = await this.sh(serial, "rm -f /data/local/tmp/flygo-ui.xml; uiautomator dump /data/local/tmp/flygo-ui.xml >/dev/null 2>&1; cat /data/local/tmp/flygo-ui.xml 2>/dev/null", 25_000).catch(() => "");
    }
    if (!xml.includes("<hierarchy") && this.u2 && !this.u2.running(serial)) {
      const ctx = this.approveU2.get(serial);
      if (!(await this.u2.present(serial))) {
        if (!ctx || !(await ctx.approve(`Điện thoại ${serial}: chép bộ đọc màn hình uiautomator2`, `Màn hình này không đọc được bằng uiautomator dump (luôn có hiệu ứng). Chép u2.jar (openatx, 3,7 MB, sha256 ${U2_JAR_SHA256.slice(0, 12)}…) vào ${U2_REMOTE}; không cài app, không cần root.`)))
          throw new Error("không đọc được cây giao diện (màn hình không idle) và chưa được duyệt chép u2.jar: dùng adb_snapshot image=true để nhìn ảnh");
        await this.u2.push(serial);
      }
      await this.u2.start(serial);
      xml = await this.u2.dump(serial).catch(() => "");
    }
    if (!xml.includes("<hierarchy")) throw new Error("không đọc được cây giao diện (màn hình khoá / app chặn?): dùng adb_snapshot image=true để nhìn ảnh");
    const info = await this.sh(serial, "wm size; dumpsys window | grep -E 'mCurrentFocus|mInputMethodWindow|isVisible|mIsShowing' | head -8; dumpsys input_method | grep -m1 mInputShown").catch(() => "");
    const sz = /(?:Override|Physical) size: (\d+)x(\d+)/.exec(info);
    const w = sz ? +sz[1] : 0, h = sz ? +sz[2] : 0;
    const focus = /mCurrentFocus=Window\{\S+ \S+ ([^}\s]+)\}/.exec(info)?.[1] ?? "";
    const s: Screen = { serial, app: focus, w, h, els: elements(parseXml(xml), w && h ? { w, h } : undefined, all), at: Date.now(), keyboard: /mInputShown=true/.test(info) };
    this.last.set(serial, s);
    return s;
  }

  async screenshot(serial: string): Promise<string> {
    const r = await this.exec(["-s", serial, "exec-out", "screencap", "-p"], { timeoutMs: 20_000 });
    if (r.code !== 0 || r.out.length < 100) throw new Error(`chụp màn hình lỗi: ${r.err.trim() || r.code}`);
    return r.out.toString("base64");
  }

  private el(serial: string, id: string): El {
    const s = this.last.get(serial);
    const e = s?.els.find((x) => x.id === String(id).trim());
    if (!e) throw new Error(`không có phần tử ${id} ở màn hình gần nhất (gọi adb_snapshot lại)`);
    return e;
  }

  private async after(serial: string, a: any, note: string, settleMs = 700): Promise<AdbResult> {
    const sig = (x?: Screen) => (x ? x.els.map((e) => `${e.label}@${e.x},${e.y}`).join("|") : "");
    const before = sig(this.last.get(serial));
    await this.sleep(settleMs);
    let s = await this.screen(serial);
    // Đang chuyển màn hình thì uiautomator có thể còn trả cây của cửa sổ cũ: trông như chưa đổi gì thì chờ thêm, đọc lại.
    for (let i = 0; i < 2 && before && sig(s) === before; i++) { await this.sleep(900); s = await this.screen(serial); }
    return { text: `${note}\n${fmtScreen(s)}`, ...(a?.image ? { image: await this.screenshot(serial) } : {}) };
  }

  async tool(name: string, a: any, ctx: AdbCtx): Promise<AdbResult> {
    const t0 = Date.now();
    let serial = "";
    try {
      const r = await this.run(name, a ?? {}, ctx, (s) => (serial = s));
      ctx.audit({ tool: name, device: serial, args: auditArgs(a), ok: true, ms: Date.now() - t0 });
      return r;
    } catch (e: any) {
      ctx.audit({ tool: name, device: serial, args: auditArgs(a), ok: false, error: String(e?.message ?? e).slice(0, 300), ms: Date.now() - t0 });
      throw e;
    }
  }

  private async run(name: string, a: any, ctx: AdbCtx, setSerial: (s: string) => void): Promise<AdbResult> {
    if (name === "adb_devices") {
      const ds = await this.devices();
      if (!ds.length) return { text: "Không có điện thoại / emulator nào (trong danh sách adbDevices của bot) đang nối adb với máy này." };
      return { text: ds.map((d) => { const l = this.locks.get(d.serial); return `${d.serial} · ${d.model || d.product || "?"} · ${d.state}${l ? ` · đang giữ: ${l.holder === ctx.holder ? "bạn" : l.label}` : ""}`; }).join("\n") };
    }
    const serial = await this.pick(a.device, ctx.holder);
    setSerial(serial);
    this.approveU2.set(serial, ctx);
    if (name === "adb_release") {
      if (!this.locks.release(serial, ctx.holder)) return { text: `Bạn không giữ máy ${serial}.` };
      this.u2?.stop(serial); // trả cho uiautomator dump thường (u2 đang chạy thì dump thường của người khác bị chặn)
      return { text: `Đã trả máy ${serial}.` };
    }
    this.hold(serial, ctx);

    switch (name) {
      case "adb_snapshot": {
        const s = await this.screen(serial, !!a.all);
        return { text: fmtScreen(s, a.all ? 30_000 : 12_000), ...(a.image ? { image: await this.screenshot(serial) } : {}) };
      }
      case "adb_tap": {
        let x = Number(a.x), y = Number(a.y), what = `(${x},${y})`;
        if (a.element) {
          const e = this.el(serial, a.element);
          if (!e.enabled) throw new Error(`${e.id} đang bị tắt (disabled)`);
          x = e.x; y = e.y; what = `${e.id} ${e.role}${e.label ? ` "${e.label}"` : ""}`;
          if (isRisky(e.label) && !(await ctx.approve(`Điện thoại ${serial}: bấm ${e.label}`, `Agent muốn bấm "${e.label}" trong ${this.last.get(serial)?.app ?? "app"} (có thể gửi / thanh toán / xoá).`)))
            throw new Error("người giao việc không duyệt thao tác này");
        } else if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error("cần element hoặc x, y");
        await this.sh(serial, a.long ? `input swipe ${x} ${y} ${x} ${y} 800` : `input tap ${x} ${y}`);
        return this.after(serial, a, `Đã ${a.long ? "nhấn giữ" : "chạm"} ${what}.`);
      }
      case "adb_swipe": {
        let [x1, y1, x2, y2] = [a.x1, a.y1, a.x2, a.y2].map(Number);
        if (a.direction) {
          const s = this.last.get(serial) ?? await this.screen(serial);
          // Không nêu element: danh sách cuộn được lớn nhất (vd Cài đặt có 2 lớp cuộn), không có thì giữa màn hình.
          const area = (e: El) => (e.b[2] - e.b[0]) * (e.b[3] - e.b[1]);
          const big = s.els.filter((e) => e.scrollable).sort((p, q) => area(q) - area(p))[0];
          const box = a.element ? this.el(serial, a.element).b : big ? big.b : [0, Math.round(s.h * 0.15), s.w, Math.round(s.h * 0.85)];
          const [l, t, r, b] = box, cx = Math.round((l + r) / 2), cy = Math.round((t + b) / 2);
          const dx = Math.round((r - l) * 0.35), dy = Math.round((b - t) * 0.35);
          // "down" = xem nội dung phía dưới: ngón tay vuốt từ dưới lên.
          [x1, y1, x2, y2] = ({ down: [cx, cy + dy, cx, cy - dy], up: [cx, cy - dy, cx, cy + dy], right: [cx + dx, cy, cx - dx, cy], left: [cx - dx, cy, cx + dx, cy] } as any)[a.direction];
        }
        if (![x1, y1, x2, y2].every(Number.isFinite)) throw new Error("cần direction hoặc x1, y1, x2, y2");
        const ms = Math.min(Math.max(Number(a.duration_ms) || 500, 50), 5000);
        await this.sh(serial, `input swipe ${x1} ${y1} ${x2} ${y2} ${ms}`);
        return this.after(serial, a, `Đã vuốt ${a.direction ?? `(${x1},${y1})→(${x2},${y2})`}.`, 600);
      }
      case "adb_type": {
        const text = String(a.text ?? "");
        if (a.element) {
          const e = this.el(serial, a.element);
          if (e.password) throw new Error("không gõ vào ô mật khẩu");
          await this.sh(serial, `input tap ${e.x} ${e.y}`);
          await this.sleep(300);
        }
        if (a.clear) await this.sh(serial, `input keyevent KEYCODE_MOVE_END; input keyevent ${Array(80).fill("KEYCODE_DEL").join(" ")}`);
        if (text) await this.typeText(serial, text);
        if (a.enter) await this.sh(serial, "input keyevent KEYCODE_ENTER");
        return this.after(serial, a, `Đã gõ ${text.length} ký tự${a.enter ? " + Enter" : ""}.`, 500);
      }
      case "adb_key": {
        const k = keyCode(a.key);
        if (!k) throw new Error(`phím không hợp lệ: ${a.key}`);
        await this.sh(serial, `input keyevent ${k}`);
        return this.after(serial, a, `Đã nhấn ${a.key}.`);
      }
      case "adb_app": return this.app(serial, a, ctx);
      case "adb_find": {
        const q = String(a.text ?? "").trim(), rid = String(a.resource_id ?? "").trim();
        if (!q && !rid) throw new Error("cần text hoặc resource_id");
        const hit = (s: Screen) => s.els.filter((e) => (q ? matchText(e, q) : true) && (rid ? e.rid === rid.replace(/^.*:id\//, "") : true));
        const until = Date.now() + Math.min(Math.max(Number(a.timeout_sec) || 0, 0), 120) * 1000;
        for (;;) {
          const s = await this.screen(serial);
          const h = hit(s);
          const done = a.gone ? !h.length : h.length > 0;
          if (done || Date.now() >= until) {
            const head = a.gone ? (h.length ? `Vẫn còn ${h.length} phần tử khớp.` : "Đã không còn phần tử khớp.") : h.length ? `Thấy ${h.length} phần tử khớp:\n${h.map(fmtEl).join("\n")}` : "Không thấy phần tử khớp.";
            return { text: `${head}\n\n${fmtScreen(s)}` };
          }
          await this.sleep(700);
        }
      }
      case "adb_shell": {
        const cmd = String(a.command ?? "").trim();
        if (!cmd) throw new Error("thiếu command");
        if (/\b(pm\s+(clear|uninstall)|rm\s+-[a-z]*r[a-z]*\s+\/(sdcard|data|storage)?\/?\s*$|wipe|recovery|factory)/.test(cmd)) throw new Error("lệnh xoá dữ liệu / gỡ app: dùng adb_app (có xin duyệt)");
        if (!readOnlyShell(cmd) && !(await ctx.approve(`Điện thoại ${serial}: $ ${cmd}`, "Lệnh adb shell (không chỉ đọc)."))) throw new Error("người giao việc không duyệt lệnh này");
        const r = await this.exec(["-s", serial, "shell", cmd], { timeoutMs: Math.min(Math.max(Number(a.timeout_sec) || 30, 1), 300) * 1000 });
        return { text: clip(`${r.out.toString()}${r.err ? `\n[stderr] ${r.err}` : ""}\n[exit ${r.code}]`, 40_000) };
      }
      case "adb_logcat": {
        const n = Math.min(Math.max(Number(a.lines) || 200, 1), 2000);
        let pid = "";
        if (a.package) { pid = (await this.sh(serial, `pidof ${shq(String(a.package))}`).catch(() => "")).trim().split(/\s+/)[0] ?? ""; if (!pid) return { text: `App ${a.package} không chạy.` }; }
        const lv = /^[VDIWEF]$/i.test(String(a.level ?? "")) ? ` *:${String(a.level).toUpperCase()}` : "";
        let out = await this.sh(serial, `logcat -d -t ${n}${pid ? ` --pid=${pid}` : ""}${lv}`, 30_000);
        if (a.filter) out = out.split("\n").filter((l) => fold(l).includes(fold(String(a.filter)))).join("\n");
        return { text: clip(out || "(trống)", 40_000) };
      }
      case "adb_file": {
        const remote = String(a.remote ?? "").trim();
        if (!remote.startsWith("/")) throw new Error("remote phải là đường dẫn tuyệt đối trên điện thoại");
        if (a.action === "pull") {
          const local = a.local ? (isAbsolute(a.local) ? a.local : resolve(ctx.workdir, a.local)) : join(ctx.workdir, basename(remote));
          const r = await this.exec(["-s", serial, "pull", remote, local], { timeoutMs: 300_000 });
          if (r.code !== 0) throw new Error(r.err.trim() || r.out.toString().trim());
          return { text: `Đã chép ${remote} -> ${local} (${statSync(local).size} byte).` };
        }
        if (a.action === "push") {
          const local = isAbsolute(String(a.local ?? "")) ? a.local : resolve(ctx.workdir, String(a.local ?? ""));
          if (!a.local || !existsSync(local)) throw new Error(`không thấy tệp ${a.local ?? ""}`);
          if (!(await ctx.approve(`Điện thoại ${serial}: chép ${basename(local)} lên ${remote}`))) throw new Error("người giao việc không duyệt");
          const r = await this.exec(["-s", serial, "push", local, remote], { timeoutMs: 300_000 });
          if (r.code !== 0) throw new Error(r.err.trim() || r.out.toString().trim());
          return { text: `Đã chép ${local} -> ${remote}.` };
        }
        throw new Error("action phải là pull hoặc push");
      }
    }
    throw new Error(`không có tool ${name}`);
  }

  /** Gõ chữ: ASCII qua `input text`; có dấu / Unicode qua ADBKeyboard (bật tạm làm bàn phím rồi trả lại bàn phím cũ). */
  async typeText(serial: string, text: string) {
    if (asciiTypable(text)) {
      for (let i = 0; i < text.length; i += 200) await this.sh(serial, `input text ${inputTextArg(text.slice(i, i + 200))}`);
      return;
    }
    const imes = await this.sh(serial, "ime list -s -a");
    if (!imes.includes(ADBKBD)) throw new Error("chữ có dấu / Unicode cần ADBKeyboard (com.android.adbkeyboard) trên điện thoại: cài bằng adb_app action=install (cần duyệt), hoặc gõ không dấu");
    const prev = (await this.sh(serial, "settings get secure default_input_method")).trim();
    await this.sh(serial, `ime enable ${ADBKBD} >/dev/null; ime set ${ADBKBD} >/dev/null`);
    try {
      await this.sleep(300);
      await this.sh(serial, `am broadcast -a ADB_INPUT_B64 --es msg ${shq(Buffer.from(text, "utf8").toString("base64"))} >/dev/null`);
      await this.sleep(200);
    } finally {
      if (prev && prev !== ADBKBD && prev !== "null") await this.sh(serial, `ime set ${shq(prev)} >/dev/null`).catch(() => {});
    }
  }

  private async app(serial: string, a: any, ctx: AdbCtx): Promise<AdbResult> {
    const pkg = String(a.package ?? "").trim();
    const pkgOk = (p: string) => /^[\w.]+(\/[\w.$]+)?$/.test(p);
    const need = () => { if (!pkg || !pkgOk(pkg)) throw new Error("cần package hợp lệ (vd com.android.settings)"); return pkg; };
    switch (a.action) {
      case "list": {
        const out = await this.sh(serial, `pm list packages${a.system ? "" : " -3"}`);
        let ps = out.split("\n").map((l) => l.replace(/^package:/, "").trim()).filter(Boolean).sort();
        if (a.query) ps = ps.filter((p) => fold(p).includes(fold(String(a.query))));
        return { text: ps.length ? `${ps.length} app:\n${ps.join("\n")}` : "Không có app khớp." };
      }
      case "info": {
        const p = need();
        const out = await this.sh(serial, `dumpsys package ${shq(p)} | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime|enabled=' | head -8`);
        return { text: out.trim() ? `${p}\n${out.trim()}` : `Không có app ${p}.` };
      }
      case "start": {
        const intent = String(a.intent ?? "").trim();
        if (intent) {
          if (!/^[\w.]+$/.test(intent)) throw new Error("intent không hợp lệ");
          await this.sh(serial, `am start -a ${intent}${pkg ? ` -p ${shq(need())}` : ""}`);
        } else if (need().includes("/")) await this.sh(serial, `am start -n ${shq(pkg)}`);
        else {
          const out = await this.sh(serial, `monkey -p ${shq(pkg)} -c android.intent.category.LAUNCHER 1`);
          if (/No activities found|monkey aborted/i.test(out)) throw new Error(`không mở được ${pkg} (chưa cài / không có màn hình chính)`);
        }
        return this.after(serial, a, `Đã mở ${intent || pkg}.`, 1500);
      }
      case "stop": await this.sh(serial, `am force-stop ${shq(need())}`); return this.after(serial, a, `Đã dừng ${pkg}.`);
      case "install": {
        const apk = String(a.apk ?? "").trim();
        const local = isAbsolute(apk) ? apk : resolve(ctx.workdir, apk);
        if (!apk || !existsSync(local) || !/\.apk$/i.test(local)) throw new Error("cần apk = đường dẫn tệp .apk trên máy này");
        if (!(await ctx.approve(`Điện thoại ${serial}: cài ${basename(local)}`, `adb install -r ${local}`))) throw new Error("người giao việc không duyệt cài app");
        const r = await this.exec(["-s", serial, "install", "-r", local], { timeoutMs: 300_000 });
        if (r.code !== 0 || !/Success/.test(r.out.toString())) throw new Error(`cài lỗi: ${(r.out.toString() + r.err).trim().slice(-300)}`);
        return { text: `Đã cài ${basename(local)}.` };
      }
      case "uninstall": case "clear": {
        const p = need();
        const what = a.action === "clear" ? "XOÁ TOÀN BỘ DỮ LIỆU" : "GỠ";
        if (!(await ctx.approve(`Điện thoại ${serial}: ${what} app ${p}`, "Không khôi phục được."))) throw new Error("người giao việc không duyệt");
        const out = await this.sh(serial, a.action === "clear" ? `pm clear ${shq(p)}` : `pm uninstall ${shq(p)}`);
        return { text: `${a.action === "clear" ? "Xoá dữ liệu" : "Gỡ"} ${p}: ${out.trim()}` };
      }
    }
    throw new Error("action không hợp lệ");
  }
}

/** Nhật ký thao tác (JSON lines) cho chủ máy xem lại; chữ gõ chỉ ghi độ dài. */
export function auditArgs(a: any): Record<string, unknown> {
  const o: Record<string, unknown> = { ...(a ?? {}) };
  delete o.key;
  if (typeof o.text === "string" && o.text.length) o.text = `<${(o.text as string).length} ký tự>`;
  return o;
}

export function auditWriter(file = join(homedir(), ".config", "flygo-agent", "adb-audit.jsonl")) {
  return (e: Record<string, unknown>) => {
    try { mkdirSync(join(file, ".."), { recursive: true, mode: 0o700 }); appendFileSync(file, JSON.stringify({ at: new Date().toISOString(), ...e }) + "\n"); } catch {}
  };
}
