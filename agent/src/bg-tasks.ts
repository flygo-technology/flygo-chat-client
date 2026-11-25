// Tác vụ nền của agent (Sếp 2026-11-22: "theo dõi tiến trình chạy nền và stream output của nó, tự động nhận diện output file
// để tail -f nếu có"). Runner nhận diện lệnh chạy nền từ tool Bash / Monitor của Claude Code, tìm tệp output trong lệnh, rồi
// đọc đuôi tệp (chỉ đọc; máy này hoặc qua ssh tới đúng máy trong lệnh) và đưa vào thẻ: props.flygo_agent.bg (app "agent chat ui").
//   - Chỉ theo tệp mà chính lệnh của agent nhắc tới (không tự dò thư mục); che chuỗi giống mật khẩu / token.
//   - Mỗi lượt tối đa MAX_TASKS tác vụ; mỗi tác vụ giữ ≤ TAIL_LINES dòng / TAIL_BYTES byte; theo tối đa MAX_FOLLOW_MS.
//   - Sau khi lượt xong vẫn theo tiếp cho tới khi tệp đứng yên IDLE_DONE_MS (coi như xong) hoặc hết MAX_FOLLOW_MS.
import fs from "node:fs";
import path from "node:path";

export type BgStatus = "running" | "done" | "failed" | "killed";
/** Một tác vụ nền trên thẻ (props.flygo_agent.bg[]). Hợp đồng với app: agent chat ui, feat/bg-tasks-ui. */
export interface BgTask {
  id: string;
  kind: "bash_bg" | "detached" | "monitor";
  command: string;
  label?: string;
  host?: string; // "local" hoặc tên máy ssh
  cwd?: string;
  pid?: number;
  status: BgStatus;
  exit_code?: number;
  started_at: number;
  ended_at?: number;
  updated_at: number;
  output_file?: string;
  tail: string;
  lines?: number;
  truncated?: boolean;
  note?: string; // vd. "không có tệp output", "không rõ mã thoát"
}

/** Tệp output đứng yên bao lâu thì bắt đầu hỏi còn tiến trình ghi không, và cách nhau bao lâu giữa hai lần hỏi. */
export const WRITER_IDLE_MS = 30_000, WRITER_CHECK_MS = 15_000;
export const MAX_TASKS = 6, TAIL_LINES = 60, TAIL_BYTES = 4096, MAX_FOLLOW_MS = 6 * 3600_000, IDLE_DONE_MS = 10 * 60_000;

// ------------------------------------------------------------------ nhận diện lệnh

/** Che chuỗi giống bí mật trong một dòng (token, mật khẩu, khoá API). */
export function redact(s: string): string {
  return s
    .replace(/\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}/gi, "$1 ***")
    .replace(/\b(sk-[A-Za-z0-9_-]{8,}|sk-ant-[A-Za-z0-9_-]{8,}|fgk_[A-Za-z0-9_-]{6,}|gh[pousr]_[A-Za-z0-9]{10,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{12,})/g, "***")
    .replace(/((?:pass(?:word|wd)?|pwd|secret|token|api[_-]?key|auth|psk|wpa[_-]?key)\s*["']?\s*[:=]\s*["']?)([^\s"'&;,]{3,})/gi, "$1***")
    .replace(/(-p\s*|--password[= ])(["']?)[^\s"']{3,}\2/g, "$1***");
}

const unquote = (s: string) => s.replace(/^(['"])(.*)\1$/, "$2");

/** Tệp output của một lệnh (chuyển hướng / tee / cờ log / nohup.out); null nếu không thấy. */
export function outputFileOf(cmd: string): string | null {
  const c = cmd.replace(/\\\n/g, " ");
  // tee [-a] file
  const tee = /\|\s*tee\s+(?:-a\s+|--append\s+)*(['"]?[^\s'"|;&<>]+['"]?)/.exec(c);
  // > file / >> file / &> file / 1> file (bỏ 2>&1, > /dev/null)
  const reds = [...c.matchAll(/(?:^|[^0-9&>])(?:[1&]?>>?|>>?)\s*(['"]?[^\s'"|;&<>]+['"]?)/g)].map((m) => unquote(m[1])).filter((f) => f && !/^&\d$/.test(f) && f !== "/dev/null");
  const flag = /(?:--log(?:-file)?|--logfile|--output|--out-file|-o|--log-path)(?:=|\s+)(['"]?[^\s'"|;&<>]+['"]?)/.exec(c);
  // Bỏ "tệp" là biến / biểu thức shell ($L, $(…), `…`, {…}): không đọc được đúng đường dẫn.
  const ok = (f: string) => !!f && !/[$`{}()*?\[\]"']/.test(f);
  const pick = reds.filter(ok);
  if (pick.length) return pick[pick.length - 1];
  if (reds.length) return null;
  if (tee && ok(unquote(tee[1]))) return unquote(tee[1]);
  if (flag && ok(unquote(flag[1]))) return unquote(flag[1]);
  if (/\bnohup\b/.test(c)) return "nohup.out";
  return null;
}

/** Lệnh khởi chạy tách nền (nohup … &, setsid, (… &), disown): chạy tiếp sau khi lệnh Bash trả về. */
export function isDetachedLaunch(cmd: string): boolean {
  const c = cmd.replace(/\\\n/g, " ");
  // Sau khi bỏ &&, 2>&1, >&2, &>, chuỗi trong nháy: còn "&" là chạy nền.
  const bare = c.replace(/'[^']*'|"[^"]*"/g, "''").replace(/&&|[0-9]?>&[0-9]?|&>>?/g, " ");
  return /\b(nohup|setsid|disown)\b/.test(c) || /&/.test(bare);
}

/** ssh host '…' → { host, inner }; null nếu không phải lệnh ssh đơn giản. */
export function sshOf(cmd: string): { host: string; inner: string } | null {
  const m = /^\s*ssh\s+((?:-[A-Za-z](?:\s+[^\s-][^\s]*)?\s+)*)([A-Za-z0-9._@-]+)\s+(['"])([\s\S]*)\3\s*$/.exec(cmd.trim());
  if (!m) return null;
  return { host: m[2], inner: m[4] };
}

/** Ngắn gọn để hiện: bỏ xuống dòng, cắt. */
export const shortCmd = (c: string, n = 120) => { const s = redact(c.replace(/\s+/g, " ").trim()); return s.length > n ? `${s.slice(0, n - 1)}…` : s; };

export interface Launch { kind: BgTask["kind"]; command: string; host: string; file?: string; note?: string }

/** Từ một lần gọi tool đã xong (tên, input, kết quả) → tác vụ nền cần theo dõi, hoặc null. */
export function detectLaunch(tool: string, input: any, result: string): Launch | null {
  const cmd = String(input?.command ?? "");
  if (tool === "Bash" && input?.run_in_background) {
    const f = /(\/[^\s'"]+\/tasks\/[A-Za-z0-9_-]+\.output)/.exec(result)?.[1] ?? outputFileOf(cmd) ?? undefined;
    return { kind: "bash_bg", command: cmd, host: "local", file: f, ...(f ? {} : { note: "không thấy tệp output" }) };
  }
  if (tool === "Monitor") {
    const f = /(\/[^\s'"]+\.output)\b/.exec(result)?.[1];
    return { kind: "monitor", command: String(input?.command ?? input?.description ?? "Monitor"), host: "local", file: f, ...(f ? {} : { note: "theo dõi trong lượt" }) };
  }
  if (tool !== "Bash" || !cmd) return null;
  const ssh = sshOf(cmd);
  const inner = ssh ? ssh.inner : cmd;
  if (!isDetachedLaunch(inner)) return null;
  const f = outputFileOf(inner) ?? undefined;
  return { kind: "detached", command: cmd, host: ssh ? ssh.host : "local", file: f, ...(f ? {} : { note: "không thấy tệp output trong lệnh" }) };
}

// ------------------------------------------------------------------ theo dõi

/** Ghép thêm chữ vào đuôi: giữ ≤ TAIL_LINES dòng, ≤ TAIL_BYTES byte, che bí mật. */
export function appendTail(prev: string, chunk: string): { tail: string; added: number; truncated: boolean } {
  const lines = (prev + chunk).replace(/\r\n?/g, "\n").replace(/\u0000/g, "").split("\n");
  const added = chunk.split("\n").length - 1;
  let out = lines.slice(-TAIL_LINES).map((l) => redact(l.length > 400 ? `${l.slice(0, 400)}…` : l));
  let tail = out.join("\n");
  while (Buffer.byteLength(tail) > TAIL_BYTES && out.length > 1) { out = out.slice(1); tail = out.join("\n"); }
  return { tail, added, truncated: lines.length > out.length };
}

type Spawn = (cmd: string[]) => { stdout: ReadableStream<Uint8Array>; kill(): void; exited: Promise<number> };

/** Theo dõi các tác vụ nền của MỘT lượt; onChange gọi khi có dòng mới / đổi trạng thái (runner cập nhật thẻ, có giãn nhịp). */
export class BgTracker {
  tasks: BgTask[] = [];
  private stops = new Map<string, () => void>();
  private turnEnded = false;
  constructor(private cwd: string, private onChange: () => void, private spawn: Spawn = (c) => Bun.spawn(c, { stdout: "pipe", stderr: "ignore" }) as any,
    private now = () => Date.now(), private pollMs = 1000, private hasWriter: (file: string) => Promise<boolean> = localHasWriter) {}

  get active() { return this.tasks.some((t) => t.status === "running"); }

  add(l: Launch): BgTask | null {
    if (this.tasks.length >= MAX_TASKS) return null;
    const t0 = this.now();
    const file = l.file && l.host === "local" && !path.isAbsolute(l.file) ? path.resolve(this.cwd, l.file) : l.file;
    const t: BgTask = { id: `bg-${t0.toString(36)}-${this.tasks.length}`, kind: l.kind, command: shortCmd(l.command, 300), label: shortCmd(l.command, 60), host: l.host, cwd: this.cwd,
      status: "running", started_at: t0, updated_at: t0, tail: "", lines: 0, ...(file ? { output_file: file } : {}), ...(l.note ? { note: l.note } : {}) };
    this.tasks.push(t);
    if (file) this.follow(t, file); else if (l.kind === "detached") this.finish(t, "done", "không thấy tệp output trong lệnh");
    this.onChange();
    return t;
  }

  private bump(t: BgTask, chunk: string) {
    if (!chunk) return;
    const r = appendTail(t.tail, chunk);
    t.tail = r.tail; t.lines = (t.lines ?? 0) + r.added; t.truncated = t.truncated || r.truncated; t.updated_at = this.now();
    this.onChange();
  }

  finish(t: BgTask, status: BgStatus, note?: string, exit?: number) {
    if (t.status !== "running") return;
    t.status = status; t.ended_at = this.now(); t.updated_at = t.ended_at;
    if (note) t.note = note;
    if (exit !== undefined) t.exit_code = exit;
    this.stops.get(t.id)?.(); this.stops.delete(t.id);
    this.onChange();
  }

  private follow(t: BgTask, file: string) {
    const started = this.now();
    let lastGrow = started;
    const idleOrExpired = () => {
      const n = this.now();
      if (n - started > MAX_FOLLOW_MS) { this.finish(t, "done", "đã ngừng theo dõi (quá 6 giờ)"); return true; }
      if (this.turnEnded && n - lastGrow > IDLE_DONE_MS) { this.finish(t, "done", "tệp output đứng yên, coi như xong (không rõ mã thoát)"); return true; }
      return false;
    };
    if (t.host === "local") {
      let off = -1;
      // Tệp đứng yên ≥ WRITER_IDLE_MS: hỏi lsof còn tiến trình nào ghi tệp không; hai lần liền không còn = tiến trình đã
      // xong, chốt ngay (trước đây phải chờ hết lượt + 10 phút đứng yên, thẻ treo "đang chạy"; Sếp 25/11).
      let lastCheck = 0, noWriter = 0, checking = false;
      const writerGone = () => {
        const n = this.now();
        if (checking || off < 0 || n - lastGrow < WRITER_IDLE_MS || n - lastCheck < WRITER_CHECK_MS) return;
        checking = true; lastCheck = n;
        this.hasWriter(file).then((w) => {
          noWriter = w ? 0 : noWriter + 1;
          if (noWriter >= 2 && t.status === "running") this.finish(t, "done", "tiến trình ghi tệp output đã kết thúc (không rõ mã thoát)");
        }, () => {}).finally(() => { checking = false; });
      };
      const tick = () => {
        if (t.status !== "running") return;
        try {
          const st = fs.statSync(file);
          if (off < 0) off = Math.max(0, st.size - TAIL_BYTES); // lần đầu: chỉ đọc đuôi
          if (st.size < off) off = 0; // tệp bị ghi đè
          if (st.size > off) {
            const fd = fs.openSync(file, "r");
            const n = Math.min(st.size - off, 64 * 1024);
            const b = Buffer.alloc(n);
            fs.readSync(fd, b, 0, n, st.size - n > off ? st.size - n : off);
            fs.closeSync(fd);
            off = st.size; lastGrow = this.now();
            this.bump(t, b.toString("utf8"));
          }
        } catch { /* tệp chưa có: chờ */ }
        if (!idleOrExpired()) writerGone();
      };
      tick();
      const timer = setInterval(tick, this.pollMs);
      this.stops.set(t.id, () => clearInterval(timer));
      return;
    }
    // ssh: tail -F qua đúng máy trong lệnh (BatchMode: không hỏi mật khẩu; chỉ đọc).
    const q = `'${file.replace(/'/g, `'\\''`)}'`;
    let proc: ReturnType<Spawn>;
    try { proc = this.spawn(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=30", t.host!, `tail -n ${TAIL_LINES} -F -- ${q} 2>/dev/null`]); }
    catch { this.finish(t, "done", "không theo được qua ssh"); return; }
    const timer = setInterval(() => { if (t.status === "running") idleOrExpired(); }, Math.max(this.pollMs, 5000));
    this.stops.set(t.id, () => { clearInterval(timer); try { proc.kill(); } catch {} });
    (async () => {
      const dec = new TextDecoder();
      const rd = proc.stdout.getReader();
      for (;;) {
        const r = await rd.read().catch(() => ({ done: true, value: undefined }));
        if (r.done) break;
        lastGrow = this.now();
        this.bump(t, dec.decode(r.value, { stream: true }));
      }
      if (t.status === "running") this.finish(t, "done", "kết nối ssh theo dõi đã đóng");
    })();
  }

  /** Lượt kết thúc: tác vụ nền của chính Claude Code (bash_bg / monitor) dừng theo tiến trình claude; tách nền thì theo tiếp. */
  endTurn(claudeAlive = false) {
    this.turnEnded = true;
    // Phiên sống (claude.keepAlive): tiến trình claude còn chạy nên tác vụ nền của nó cũng còn — theo tiếp như tách nền.
    if (claudeAlive) return;
    for (const t of this.tasks) if (t.kind !== "detached" && t.status === "running") this.finish(t, "killed", "dừng cùng lượt");
  }

  stopAll() { for (const t of this.tasks) this.finish(t, "killed", "đã ngừng theo dõi"); }

  /** Người dùng bấm Dừng trên một tác vụ nền: dừng các tiến trình đang ghi vào tệp output của nó (máy này hoặc qua ssh),
   *  rồi đánh dấu "đã dừng". Không có tệp output thì không biết tiến trình nào nên không dừng. */
  async stop(id: string, by = "người dùng", kill: KillWriters = killWriters): Promise<{ ok: boolean; error?: string; pids?: number[] }> {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return { ok: false, error: "không có tác vụ nền này" };
    if (t.status !== "running") return { ok: true, pids: [] };
    if (!t.output_file) return { ok: false, error: "tác vụ không có tệp output nên không biết tiến trình nào để dừng" };
    const r = await kill(t.output_file, t.host ?? "local");
    if (!r.ok) return r;
    this.finish(t, "killed", r.pids?.length ? `${by} đã dừng (${r.pids.length} tiến trình)` : "không còn tiến trình nào ghi tệp output, coi như đã dừng");
    return r;
  }
}

// ------------------------------------------------------------------ dừng tiến trình

export type KillWriters = (file: string, host: string) => Promise<{ ok: boolean; error?: string; pids?: number[] }>;
/** Không bao giờ dừng các tiến trình này dù chúng mở tệp (engine, runner, công cụ chỉ đọc / chỉ mục của hệ thống). */
const KEEP = /^(claude|codex|flygo-agent|tail|less|cat|lsof|ssh|sshd|Finder|mds|mds_stores|mdworker.*)$/i;

const sh = async (cmd: string[], ms = 15_000): Promise<string> => {
  const p = Bun.spawn(cmd, { stdout: "pipe", stderr: "ignore" });
  const timer = setTimeout(() => { try { p.kill(); } catch {} }, ms);
  try { return await new Response(p.stdout).text(); } finally { clearTimeout(timer); await p.exited.catch(() => {}); }
};

/** Đọc `lsof -F pca`: tiến trình (pid, tên) đang mở tệp để GHI (chế độ w / u). */
export function parseLsofWriters(out: string): { pid: number; cmd: string }[] {
  const res: { pid: number; cmd: string }[] = [];
  let pid = 0, cmd = "";
  for (const line of out.split("\n")) {
    const k = line[0], v = line.slice(1);
    if (k === "p") { pid = Number(v); cmd = ""; }
    else if (k === "c") cmd = v;
    else if (k === "a" && (v === "w" || v === "u") && pid && !res.some((x) => x.pid === pid)) res.push({ pid, cmd });
  }
  return res;
}

/** Còn tiến trình (ngoài runner / engine / công cụ chỉ đọc) mở [file] để ghi trên máy này không. */
export async function localHasWriter(file: string): Promise<boolean> {
  const out = await sh(["lsof", "-F", "pca", "--", file], 10_000);
  const mine = new Set([process.pid, process.ppid]);
  return parseLsofWriters(out).some((w) => !mine.has(w.pid) && !KEEP.test(w.cmd));
}

/** Tiến trình con cháu của [pid] (pgrep -P, đệ quy), con trước cha. */
async function descendants(pid: number, depth = 0): Promise<number[]> {
  if (depth > 6) return [];
  const kids = (await sh(["pgrep", "-P", String(pid)], 5000).catch(() => "")).split("\n").map(Number).filter((n) => n > 0);
  const out: number[] = [];
  for (const k of kids) out.push(...(await descendants(k, depth + 1)), k);
  return out;
}

/** Dừng các tiến trình đang ghi [file]: SIGTERM cả cây, 3 giây sau còn sống thì SIGKILL. Trên máy khác: cùng việc đó qua ssh. */
export const killWriters: KillWriters = async (file, host) => {
  if (host !== "local") {
    const q = `'${file.replace(/'/g, `'\\''`)}'`;
    // Máy xa: lsof (hoặc fuser) tìm tiến trình mở tệp, bỏ tail / ssh / lsof; dừng cả con cháu.
    const script = `F=${q}; P=$( (lsof -t -- "$F" 2>/dev/null || fuser "$F" 2>/dev/null) | tr -s ' ' '\\n' | sort -u ); K=""; ` +
      `for p in $P; do c=$(ps -o comm= -p $p 2>/dev/null | xargs basename 2>/dev/null); case "$c" in tail|ssh|sshd|lsof|less|cat|claude|codex|flygo-agent) continue;; esac; ` +
      `K="$K $(pgrep -P $p 2>/dev/null | tr '\\n' ' ') $p"; done; [ -n "$K" ] && kill -TERM $K 2>/dev/null; sleep 3; [ -n "$K" ] && kill -KILL $K 2>/dev/null; echo "PIDS:$K"`;
    const out = await sh(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host, script], 30_000).catch((e) => `ERR:${e?.message ?? e}`);
    const m = /PIDS:(.*)/.exec(out);
    if (!m) return { ok: false, error: `không dừng được qua ssh tới ${host}` };
    return { ok: true, pids: m[1].trim().split(/\s+/).map(Number).filter((n) => n > 0) };
  }
  const writers = parseLsofWriters(await sh(["lsof", "-F", "pca", "--", file]).catch(() => ""));
  const mine = new Set([process.pid, process.ppid]);
  const targets: number[] = [];
  for (const w of writers) {
    if (mine.has(w.pid) || KEEP.test(w.cmd)) continue;
    for (const p of [...(await descendants(w.pid)), w.pid]) if (!mine.has(p) && !targets.includes(p)) targets.push(p);
  }
  const alive = (p: number) => { try { process.kill(p, 0); return true; } catch { return false; } };
  for (const p of targets) try { process.kill(p, "SIGTERM"); } catch {}
  if (targets.length) {
    await Bun.sleep(3000);
    for (const p of targets) if (alive(p)) try { process.kill(p, "SIGKILL"); } catch {}
  }
  return { ok: true, pids: targets };
};
