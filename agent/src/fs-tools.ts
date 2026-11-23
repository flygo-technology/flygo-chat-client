// Bộ công cụ tệp + lệnh dùng chung cho mọi engine (Sếp, 2026-11-10): đọc, ghi, sao chép, di chuyển, xoá (luôn vào
// thùng rác của hệ điều hành, không xoá hẳn) và chạy lệnh. Ghi / chép / chuyển / xoá / chạy lệnh xin người giao việc
// duyệt qua runner như mọi thay đổi khác; đọc thì không, trừ thư mục khoá / token (cấm hẳn).
import { commandLimit, envDefaultSec, envMaxSec, type Limit } from "./cmd-limits";
import { spawn } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync, appendFileSync, readdirSync } from "node:fs";
import { homedir, platform } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";

export const FS_TOOLS = [
  { name: "file_read", description: "Đọc tệp chữ trên máy (UTF-8). offset / limit theo dòng (mặc định 2000 dòng đầu). Thư mục thì trả danh sách tệp.", inputSchema: { type: "object", properties: { path: { type: "string" }, offset: { type: "number" }, limit: { type: "number" } }, required: ["path"] } },
  { name: "file_write", description: "Ghi tệp chữ (tạo mới hoặc ghi đè; append=true để ghi nối). Tự tạo thư mục cha. Cần duyệt.", inputSchema: { type: "object", properties: { path: { type: "string" }, content: { type: "string" }, append: { type: "boolean" } }, required: ["path", "content"] } },
  { name: "file_copy", description: "Sao chép tệp hoặc thư mục (đệ quy) tới đích. overwrite=true để ghi đè đích đã có. Cần duyệt.", inputSchema: { type: "object", properties: { from: { type: "string" }, to: { type: "string" }, overwrite: { type: "boolean" } }, required: ["from", "to"] } },
  { name: "file_move", description: "Di chuyển / đổi tên tệp hoặc thư mục. overwrite=true để thay đích đã có (đích cũ vào thùng rác). Cần duyệt.", inputSchema: { type: "object", properties: { from: { type: "string" }, to: { type: "string" }, overwrite: { type: "boolean" } }, required: ["from", "to"] } },
  { name: "file_trash", description: "XOÁ tệp / thư mục bằng cách chuyển vào THÙNG RÁC của máy (khôi phục được). Luôn dùng tool này để xoá, không dùng rm / del. Cần duyệt.", inputSchema: { type: "object", properties: { path: { type: "string" }, paths: { type: "array", items: { type: "string" } } } } },
  { name: "run_command", description: "Chạy một lệnh shell trên máy (bash -lc trên macOS / Linux, PowerShell trên Windows) trong cwd, trả stdout + stderr + mã thoát. LUÔN ước tính thời gian chạy và đặt timeout_sec phù hợp cho từng lệnh: expected_sec = ước tính (giây), timeout_sec = hạn cứng (thiếu thì gấp 3 lần ước tính, tối thiểu 30). Quá hạn thì lệnh bị DỪNG (cả tiến trình con) và trả phần output đã có; việc lâu hơn vài phút thì chạy nền. Lệnh nhanh: kiểm kích thước trước (du -sh); tìm chữ bằng rg -l (giới hạn thư mục, -g '*.log', không quét data/, node_modules, .git, tệp nhị phân lớn) thay vì grep -r; find có -maxdepth; cắt output bằng head; bọc lệnh có thể lâu bằng timeout N; việc thật sự lâu thì chạy nền rồi xem lại. Không dùng để xoá tệp (dùng file_trash). Cần duyệt.", inputSchema: { type: "object", properties: { command: { type: "string" }, cwd: { type: "string" }, expected_sec: { type: "number", description: "ước tính lệnh chạy bao lâu (giây)" }, timeout_sec: { type: "number", description: "hạn cứng (giây); thiếu thì max(3 × expected_sec, 30)" } }, required: ["command"] } },
];
export const FS_TOOL_NAMES = new Set(FS_TOOLS.map((t) => t.name));
export const FS_READ_ONLY = ["file_read"];

const MAX_OUT = 60_000;
const home = homedir();

export function absPath(p: string, cwd = process.cwd()): string {
  const s = String(p ?? "").trim();
  if (!s) throw new Error("thiếu đường dẫn");
  const x = s === "~" ? home : s.startsWith("~/") || s.startsWith("~\\") ? join(home, s.slice(2)) : s;
  return isAbsolute(x) ? resolve(x) : resolve(cwd, x);
}

/** Khoá / token của máy: cấm đọc, ghi, chép, chuyển, xoá qua bộ công cụ này. */
export function forbidden(p: string): boolean {
  const n = p.replace(/\\/g, "/");
  const h = home.replace(/\\/g, "/");
  return [`${h}/.ssh`, `${h}/.config/flygo-agent`, `${h}/.codex/auth.json`, `${h}/.aws`, `${h}/.gnupg`].some((b) => n === b || n.startsWith(b + "/"));
}

function guard(p: string): string {
  if (forbidden(p)) throw new Error(`không được đụng vào ${p} (khoá / token của máy)`);
  return p;
}

function uniqueIn(dir: string, name: string): string {
  let t = join(dir, name);
  for (let i = 1; existsSync(t); i++) {
    const dot = name.lastIndexOf(".");
    t = join(dir, dot > 0 ? `${name.slice(0, dot)} ${i}${name.slice(dot)}` : `${name} ${i}`);
  }
  return t;
}

/** Hạn mặc định của run_command (giây): FLYGO_CMD_TIMEOUT_SEC (runner đặt theo cấu hình bot commandTimeoutSec), không có thì 120. */
export const defaultCmdTimeoutSec = envDefaultSec;
export const CMD_HINT = "Lệnh nhanh: kiểm kích thước trước (du -sh); tìm chữ bằng rg -l (giới hạn thư mục, -g '*.log', không quét data/, node_modules, .git, tệp nhị phân lớn) thay vì grep -r; find có -maxdepth; cắt output bằng head; bọc lệnh có thể lâu bằng timeout N; việc thật sự lâu thì chạy nền rồi xem lại.";

/** Dừng cả cây tiến trình: nhóm tiến trình (macOS / Linux, spawn detached) hoặc taskkill /T (Windows). */
function killGroup(c: ReturnType<typeof spawn>) {
  if (!c.pid) return;
  if (platform() === "win32") { try { spawn("taskkill", ["/T", "/F", "/PID", String(c.pid)], { stdio: "ignore", windowsHide: true }); } catch {} return; }
  try { process.kill(-c.pid, "SIGTERM"); } catch { try { c.kill("SIGTERM"); } catch {} }
  setTimeout(() => { try { process.kill(-c.pid!, "SIGKILL"); } catch {} }, 2000).unref?.();
}

export function run(cmd: string, args: string[], timeoutMs = 60_000): Promise<{ code: number; out: string; timedOut: boolean }> {
  return new Promise((res) => {
    // detached: lệnh là trưởng nhóm tiến trình riêng, hết giờ thì dừng cả các tiến trình con (grep / find dưới bash -lc).
    const c = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: true, detached: platform() !== "win32" });
    let out = "", timedOut = false, done = false;
    const add = (b: Buffer) => { if (out.length < MAX_OUT * 2) out += b.toString(); };
    c.stdout?.on("data", add); c.stderr?.on("data", add);
    const finish = (code: number) => { if (done) return; done = true; clearTimeout(t); res({ code, out, timedOut }); };
    const t = setTimeout(() => {
      timedOut = true;
      killGroup(c);
      // Tiến trình cháu có thể giữ ống output: không chờ "close" quá 3 s.
      setTimeout(() => finish(-1), 3000).unref?.();
    }, timeoutMs);
    c.on("error", (e) => { out += String(e?.message ?? e); finish(-1); });
    c.on("close", (code) => finish(code ?? -1));
  });
}

/** Kết quả run_command khi hết giờ: ước tính vs thực tế, gợi ý (thu hẹp / tăng hạn / chạy nền), phần output đã có. */
export function timeoutReport(command: string, sec: number, out: string, lim?: Limit): string {
  const cmd = command.replace(/\s+/g, " ").trim();
  const est = lim?.expected !== undefined ? `Ước tính ${lim.expected} s, hạn ${sec} s, đã chạy ${sec} s.` : lim?.source === "default" ? `Không đặt hạn nên dùng mặc định ${sec} s.` : `Hạn ${sec} s.`;
  return `⏱ Lệnh chạy quá ${sec} s nên đã bị dừng (cả tiến trình con): ${cmd.length > 300 ? cmd.slice(0, 300) + "…" : cmd}\n${est}\n`
    + `Chọn một: thu hẹp phạm vi / dùng lệnh nhanh hơn (rg -l với -g, giới hạn thư mục, head, find -maxdepth); đặt timeout_sec lớn hơn nếu lệnh đúng là cần lâu${lim?.capped ? ` (tối đa ${envMaxSec()} s)` : ""}; hoặc chạy nền rồi xem lại tệp log.\n`
    + `--- output tới lúc dừng ---\n${out.trim() || "(chưa có output)"}\n⏱ đã dừng sau ${sec} s`;
}

/** Chuyển [p] vào thùng rác của hệ điều hành; trả mô tả nơi đã đưa vào. */
export async function trash(p: string): Promise<string> {
  if (!existsSync(p)) throw new Error(`không có ${p}`);
  const os = platform();
  if (os === "win32") {
    const isDir = statSync(p).isDirectory();
    const q = p.replace(/'/g, "''");
    const ps = `Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::${isDir ? "DeleteDirectory" : "DeleteFile"}('${q}','OnlyErrorDialogs','SendToRecycleBin')`;
    const r = await run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps]);
    if (r.code !== 0 || existsSync(p)) throw new Error(`không chuyển được vào Thùng rác: ${r.out.trim()}`);
    return "Thùng rác (Recycle Bin)";
  }
  if (os === "darwin") {
    const dir = join(home, ".Trash");
    mkdirSync(dir, { recursive: true });
    const t = uniqueIn(dir, basename(p));
    try { renameSync(p, t); } catch { cpSync(p, t, { recursive: true }); rmSync(p, { recursive: true, force: true }); }
    return t;
  }
  // Linux: gio trash (đúng chuẩn, có "Khôi phục" trong trình quản lý tệp); không có thì tự làm theo chuẩn freedesktop.
  const g = await run("gio", ["trash", p]).catch(() => ({ code: -1, out: "" }));
  if (g.code === 0 && !existsSync(p)) return "Thùng rác";
  const base = join(process.env.XDG_DATA_HOME || join(home, ".local/share"), "Trash");
  mkdirSync(join(base, "files"), { recursive: true }); mkdirSync(join(base, "info"), { recursive: true });
  const t = uniqueIn(join(base, "files"), basename(p));
  const when = new Date().toISOString().slice(0, 19);
  writeFileSync(join(base, "info", `${basename(t)}.trashinfo`), `[Trash Info]\nPath=${encodeURI(p)}\nDeletionDate=${when}\n`);
  try { renameSync(p, t); } catch { cpSync(p, t, { recursive: true }); rmSync(p, { recursive: true, force: true }); }
  return t;
}

export function describeFsTool(name: string, a: any): string {
  switch (name) {
    case "file_write": return `${a.append ? "Ghi nối" : "Ghi"} ${a.path}`;
    case "file_copy": return `Chép ${a.from} → ${a.to}`;
    case "file_move": return `Chuyển ${a.from} → ${a.to}`;
    case "file_trash": return `Bỏ vào thùng rác: ${[a.path, ...(a.paths ?? [])].filter(Boolean).join(", ")}`;
    case "run_command": return `Chạy lệnh: ${a.command}${a.cwd ? ` (trong ${a.cwd})` : ""}`;
    default: return name;
  }
}

/** Chạy một tool tệp / lệnh. [approve] được gọi trước mọi thay đổi; trả false = không làm. */
export async function fsTool(name: string, a: any, approve: (name: string, input: any) => Promise<boolean>, cwd = process.cwd()): Promise<string> {
  if (name !== "file_read" && !(await approve(name, a))) return `Người giao việc không duyệt: ${describeFsTool(name, a)}`;
  switch (name) {
    case "file_read": {
      const p = guard(absPath(a.path, cwd));
      if (!existsSync(p)) throw new Error(`không có ${p}`);
      if (statSync(p).isDirectory()) {
        const items = readdirSync(p, { withFileTypes: true }).slice(0, 500).map((d) => d.isDirectory() ? `${d.name}/` : d.name);
        return `Thư mục ${p} (${items.length} mục):\n${items.join("\n")}`;
      }
      const lines = readFileSync(p, "utf8").split("\n");
      const from = Math.max(0, Number(a.offset ?? 0));
      const n = Math.min(5000, Math.max(1, Number(a.limit ?? 2000)));
      const part = lines.slice(from, from + n).map((l, i) => `${from + i + 1}\t${l}`).join("\n");
      return (part.length > MAX_OUT ? part.slice(0, MAX_OUT) + "\n[…cắt bớt]" : part) + (from + n < lines.length ? `\n[còn ${lines.length - from - n} dòng, đọc tiếp bằng offset=${from + n}]` : "");
    }
    case "file_write": {
      const p = guard(absPath(a.path, cwd));
      mkdirSync(dirname(p), { recursive: true });
      (a.append ? appendFileSync : writeFileSync)(p, String(a.content ?? ""));
      return `Đã ${a.append ? "ghi nối vào" : "ghi"} ${p} (${Buffer.byteLength(String(a.content ?? ""))} byte).`;
    }
    case "file_copy": case "file_move": {
      const from = guard(absPath(a.from, cwd));
      let to = guard(absPath(a.to, cwd));
      if (!existsSync(from)) throw new Error(`không có ${from}`);
      if (existsSync(to) && statSync(to).isDirectory() && !statSync(from).isDirectory()) to = join(to, basename(from));
      if (existsSync(to)) {
        if (!a.overwrite) throw new Error(`đích đã có: ${to} (overwrite=true để thay)`);
        await trash(to);
      }
      mkdirSync(dirname(to), { recursive: true });
      if (name === "file_copy") cpSync(from, to, { recursive: true });
      else try { renameSync(from, to); } catch { cpSync(from, to, { recursive: true }); await trash(from); }
      return `Đã ${name === "file_copy" ? "chép" : "chuyển"} ${from} → ${to}${a.overwrite ? " (đích cũ đã vào thùng rác)" : ""}.`;
    }
    case "file_trash": {
      const list = [a.path, ...(Array.isArray(a.paths) ? a.paths : [])].filter((x) => String(x ?? "").trim());
      if (!list.length) throw new Error("thiếu path / paths");
      const out: string[] = [];
      for (const x of list) {
        const p = guard(absPath(x, cwd));
        if (p === home || p === "/" || /^[A-Za-z]:\\?$/.test(p)) throw new Error(`không xoá thư mục gốc / thư mục nhà: ${p}`);
        out.push(`${p} → ${await trash(p)}`);
      }
      return `Đã chuyển vào thùng rác (khôi phục được):\n${out.join("\n")}`;
    }
    case "run_command": {
      const dir = a.cwd ? absPath(a.cwd, cwd) : cwd;
      const lim = commandLimit(a);
      const sec = lim.sec;
      const t0 = Date.now();
      const r = platform() === "win32"
        ? await run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", `Set-Location -LiteralPath '${dir.replace(/'/g, "''")}'; ${a.command}`], sec * 1000)
        : await run("bash", ["-lc", `cd ${JSON.stringify(dir)} && ${a.command}`], sec * 1000);
      const out = r.out.length > MAX_OUT ? r.out.slice(0, MAX_OUT / 2) + "\n[…cắt bớt…]\n" + r.out.slice(-MAX_OUT / 2) : r.out;
      if (r.timedOut) return timeoutReport(String(a.command), sec, out.slice(-8000), lim);
      const took = Math.round((Date.now() - t0) / 100) / 10;
      const note = lim.source === "default" ? `\n(Lệnh này không có ước tính: lần sau hãy đặt expected_sec / timeout_sec cho từng lệnh.)` : "";
      return `Mã thoát ${r.code} · xong sau ${took} s\n${out}${note}`;
    }
  }
  throw new Error(`tool lạ: ${name}`);
}
