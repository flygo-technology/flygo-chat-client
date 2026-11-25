// "Giữ phiên sống" (Sếp 2026-11-25): mỗi phiên Claude giữ MỘT tiến trình `claude -p --input-format stream-json` chạy tiếp qua nhiều
// lượt (tin mới ghi vào stdin) thay vì mỗi lượt spawn + --resume. Đỡ khởi động + nối MCP mỗi lượt (chữ đầu ra sớm hơn), cache ấm.
//   - Bật bằng claude.keepAlive: true trong cấu hình bot. Tắt = như cũ (mỗi lượt một tiến trình).
//   - Model / chế độ quyền đổi tại chỗ (control request set_model / set_permission_mode); thứ khác đổi (persona, quyền đầy đủ, tool,
//     thư mục, người gọi qua Cổng AI, MCP ngoài, effort…) → mở lại tiến trình với --resume (sig trong prepare()).
//   - Rảnh quá idleMin phút (mặc định 15) thì đóng; số phiên sống mỗi máy có trần (theo RAM), vượt thì đóng phiên lâu không dùng nhất.
//   - 🛑 dừng lượt = control request interrupt (tiến trình còn sống); không dừng được trong 10 s thì giết tiến trình.
//   - Tiến trình chết giữa lượt mà chưa ra chữ → chạy lại lượt đó một lần bằng tiến trình mới (--resume).
//   - mcp-chat tự hỏi runner ngữ cảnh lượt hiện tại theo SCOPE (/ctx), nên RUN_KEY / kênh mỗi lượt vẫn đúng; ask-hook cũng vậy.
import os from "node:os";
import { rmSync } from "node:fs";
import { spawn } from "../spawn";
import type { TurnHooks, TurnInput, TurnResult } from "./types";
import { newTurnState, type TurnState } from "./claude";

export interface Prep { args: string[]; env: Record<string, string>; mcpFile: string; streamIn: boolean; replay: boolean; sig: string; model: string; permMode: string; bin: string; cwd: string }
interface EngineLike { onEvent(ev: any, st: TurnState, hooks: TurnHooks): void }
export interface LiveOpts { botKey: string; idleMin?: number; log?: (s: string) => void }

/** Một tiến trình claude sống. */
export class LiveSession {
  proc: ReturnType<typeof spawn>;
  sessionId = "";
  model: string;
  permMode: string;
  lastUsed = Date.now();
  busy = false;
  dead = false;
  private buf = "";
  private onLine: ((ev: any) => void) | null = null;
  private controls = new Map<string, (ok: boolean) => void>();
  private idleTimer: Timer | null = null;
  stderr = "";

  constructor(readonly key: string, readonly sig: string, readonly prep: Prep, private onDeath: (s: LiveSession) => void) {
    this.model = prep.model; this.permMode = prep.permMode;
    const proc = spawn(prep.args, { env: prep.env, cwd: prep.cwd, stdout: "pipe", stderr: "pipe", stdin: "pipe" } as any);
    this.proc = proc;
    void this.pump();
    void (async () => { try { this.stderr = (await new Response(proc.stderr as any).text()).slice(-2000); } catch {} })();
    void proc.exited.then(() => this.die());
  }

  private async pump() {
    const reader = (this.proc.stdout as ReadableStream<Uint8Array>).getReader();
    const dec = new TextDecoder();
    for (;;) {
      const r = await reader.read().catch(() => ({ done: true, value: undefined }));
      if (r.done) break;
      this.buf += dec.decode(r.value, { stream: true });
      let i;
      while ((i = this.buf.indexOf("\n")) >= 0) {
        const line = this.buf.slice(0, i).trim();
        this.buf = this.buf.slice(i + 1);
        if (!line) continue;
        let ev: any;
        try { ev = JSON.parse(line); } catch { continue; }
        if (ev.type === "control_response") {
          const id = ev.response?.request_id;
          const cb = id ? this.controls.get(id) : undefined;
          if (cb) { this.controls.delete(id); cb(ev.response?.subtype === "success"); }
          continue;
        }
        if (ev.type === "system" && ev.subtype === "init" && ev.session_id) this.sessionId = ev.session_id;
        this.onLine?.(ev);
      }
    }
    this.die();
  }

  private die() {
    if (this.dead) return;
    this.dead = true;
    for (const cb of this.controls.values()) cb(false);
    this.controls.clear();
    if (this.idleTimer) clearTimeout(this.idleTimer);
    try { rmSync(this.prep.mcpFile, { force: true }); } catch {}
    this.onLine?.({ type: "__exit__" });
    this.onDeath(this);
  }

  write(obj: any) { const s = this.proc.stdin as any; s.write(JSON.stringify(obj) + "\n"); s.flush?.(); }

  /** Gửi control request (set_model, set_permission_mode, interrupt); true = claude nhận. */
  control(request: Record<string, unknown>, timeoutMs = 10_000): Promise<boolean> {
    if (this.dead) return Promise.resolve(false);
    const request_id = crypto.randomUUID();
    return new Promise((resolve) => {
      const t = setTimeout(() => { this.controls.delete(request_id); resolve(false); }, timeoutMs);
      this.controls.set(request_id, (ok) => { clearTimeout(t); resolve(ok); });
      try { this.write({ type: "control_request", request_id, request }); } catch { clearTimeout(t); this.controls.delete(request_id); resolve(false); }
    });
  }

  /** Lượt: ghi tin, nhận sự kiện tới "result" (hoặc tiến trình thoát). */
  turn(text: string, handle: (ev: any) => void): Promise<"result" | "exit"> {
    this.busy = true; this.lastUsed = Date.now();
    if (this.idleTimer) { clearTimeout(this.idleTimer); this.idleTimer = null; }
    return new Promise((resolve) => {
      this.onLine = (ev) => {
        if (ev.type === "__exit__") { this.onLine = null; this.busy = false; resolve("exit"); return; }
        handle(ev);
        if (ev.type === "result") { this.onLine = null; this.busy = false; this.lastUsed = Date.now(); resolve("result"); }
      };
      try { this.write(userMsg(text)); } catch { this.onLine = null; this.busy = false; resolve("exit"); }
    });
  }

  idleAfter(ms: number) {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => { if (!this.busy) this.close("rảnh quá lâu"); }, ms);
  }

  close(_why: string) {
    if (this.dead) return;
    try { (this.proc.stdin as any).end?.(); } catch {}
    setTimeout(() => { if (!this.dead) try { this.proc.kill(); } catch {} }, 3000);
  }
}

export const userMsg = (text: string, uuid?: string) => ({ type: "user", ...(uuid ? { uuid } : {}), message: { role: "user", content: [{ type: "text", text }] } });

/** Trần số phiên sống mỗi máy: ~20% RAM / 400 MB mỗi phiên, trong khoảng 2–12 (vd. 16 GB → 8). Ghi đè: FLYGO_LIVE_MAX. */
export function liveCap(totalBytes = os.totalmem()): number {
  const env = Number(process.env.FLYGO_LIVE_MAX);
  if (env > 0) return Math.floor(env);
  return Math.max(2, Math.min(12, Math.floor((totalBytes * 0.2) / (400 * 1024 * 1024))));
}

/** Kho phiên sống dùng chung cả tiến trình runner (runner chung chạy nhiều bot). */
export const livePool = new Map<string, LiveSession>();

/** Phiên cần đóng để có chỗ cho phiên mới (LRU, bỏ qua phiên đang chạy lượt). */
export function lruVictim(pool: Iterable<LiveSession>, cap: number, size: number): LiveSession | null {
  if (size < cap) return null;
  const idle = [...pool].filter((s) => !s.busy && !s.dead).sort((a, b) => a.lastUsed - b.lastUsed);
  return idle[0] ?? null;
}

const keyOf = (o: LiveOpts, input: TurnInput) => `${o.botKey}|${input.mcpEnv.SCOPE ?? input.cwd}`;

/** Một lượt qua phiên sống. */
export async function liveTurn(engine: EngineLike, prep: Prep, input: TurnInput, hooks: TurnHooks, signal: AbortSignal, o: LiveOpts): Promise<TurnResult> {
  const log = o.log ?? (() => {});
  const idleMs = Math.max(1, Number(o.idleMin) || 15) * 60_000;
  const key = keyOf(o, input);
  let live = livePool.get(key);
  // Phiên sống khác phiên Claude (bot vừa mở phiên mới / tách phiên) hoặc cấu hình đổi → mở lại.
  if (live && (live.dead || live.sig !== prep.sig || (input.sessionId && live.sessionId && live.sessionId !== input.sessionId) || (!input.sessionId && live.sessionId))) {
    log(`phiên sống ${key}: mở lại (${live.dead ? "đã dừng" : live.sig !== prep.sig ? "cấu hình đổi" : "phiên khác"})`);
    if (!live.dead) live.close("mở lại");
    livePool.delete(key);
    live = undefined;
  }
  if (live) {
    try { rmSync(prep.mcpFile, { force: true }); } catch {} // tệp MCP của lượt này không dùng: tiến trình sống giữ tệp của nó
    if (prep.model && prep.model !== live.model) {
      if (await live.control({ subtype: "set_model", model: prep.model })) live.model = prep.model;
      else { log(`phiên sống ${key}: set_model lỗi, mở lại`); live.close("set_model"); livePool.delete(key); live = undefined; }
    }
    if (live && prep.permMode !== live.permMode) {
      if (await live.control({ subtype: "set_permission_mode", mode: prep.permMode })) live.permMode = prep.permMode;
      else { log(`phiên sống ${key}: set_permission_mode lỗi, mở lại`); live.close("perm"); livePool.delete(key); live = undefined; }
    }
  }
  if (!live) {
    const v = lruVictim(livePool.values(), liveCap(), livePool.size);
    if (v) { log(`phiên sống: đầy (${livePool.size}/${liveCap()}), đóng ${v.key}`); v.close("lru"); livePool.delete(v.key); }
    live = new LiveSession(key, prep.sig, prep, (s) => { if (livePool.get(s.key) === s) livePool.delete(s.key); });
    livePool.set(key, live);
  }

  const st = newTurnState(input.sessionId);
  let sawOutput = false;
  const onAbort = () => {
    void live!.control({ subtype: "interrupt" }).then((ok) => {
      if (!ok) live!.close("interrupt lỗi");
      setTimeout(() => { if (live!.busy) { live!.close("interrupt chậm"); try { live!.proc.kill(); } catch {} } }, 10_000);
    });
  };
  signal.addEventListener("abort", onAbort);
  const cur = live;
  // Phiên sống: control request dùng được cả sau lượt (sub-agent chạy nền còn sống) tới khi tiến trình đóng.
  hooks.controllable?.((request) => cur.control(request));
  hooks.steerable?.(async (text, onRead) => {
    if (!cur.busy || cur.dead) return false;
    try { cur.write(userMsg(text)); } catch { return false; }
    onRead?.();
    return true;
  });
  try {
    const end = await cur.turn(input.prompt, (ev) => {
      if (ev.type === "assistant" || ev.type === "stream_event") sawOutput = true;
      engine.onEvent(ev, st, hooks);
    });
    if (signal.aborted) throw new Error("đã dừng");
    if (end === "exit") {
      livePool.delete(key);
      if (!sawOutput) {
        // Tiến trình chết trước khi ra gì: chạy lại lượt một lần bằng tiến trình mới (claude --resume).
        log(`phiên sống ${key}: tiến trình thoát trước khi trả lời (${cur.stderr.slice(-200)}), chạy lại`);
        const again = livePool.get(key);
        if (!again) {
          const prep2 = { ...prep, args: withResume(prep.args, st.sessionId || cur.sessionId || input.sessionId) };
          return liveTurn(engine, prep2, { ...input, sessionId: st.sessionId || cur.sessionId || input.sessionId }, hooks, signal, o);
        }
      }
      if (!st.final) throw new Error(`claude thoát giữa lượt: ${cur.stderr.slice(-300)}`);
    }
    if (st.isError) throw new Error(st.final || "claude báo lỗi");
    return { sessionId: st.sessionId || cur.sessionId, text: st.final, usage: st.usage };
  } finally {
    signal.removeEventListener("abort", onAbort);
    hooks.steerable?.(null);
    if (!cur.dead) cur.idleAfter(idleMs);
  }
}

/** Đổi / thêm --resume <id> trong tham số (bỏ --fork-session). */
export function withResume(args: string[], id?: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--resume") { i++; continue; }
    if (args[i] === "--fork-session") continue;
    out.push(args[i]);
  }
  return id ? [...out, "--resume", id] : out;
}
