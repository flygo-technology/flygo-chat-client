// Runner chung (`flygo-agent machine`): MỘT tiến trình mỗi máy chạy mọi bot của chủ runner trong runner.json.
// - Mỗi bot là một BotHandle riêng (runner.ts): kết nối chat, engine, DB phiên, cổng HTTP nội bộ riêng.
// - Nạp nóng: sửa runner.json (hoặc `flygo-agent ctl reload`) -> bot mới khởi động, bot bị xoá / tắt thì drain rồi dừng,
//   bot bị sửa thì drain rồi khởi động lại; bot khác không bị động tới.
// - Lỗi của một bot không làm chết bot khác: bot lỗi được khởi động lại thưa dần (15 giây → 10 phút);
//   lỗi "không bao giờ chạy được" (token hỏng, gắn máy khác, khác chủ runner…) thì dừng hẳn tới khi đổi cấu hình.
// - Điều khiển tại chỗ: HTTP 127.0.0.1 cổng ngẫu nhiên + khoá trong ~/.config/flygo-agent/machine.json (600).
import { existsSync, mkdirSync, readFileSync, unlinkSync, watch, writeFileSync } from "node:fs";
import { basename, dirname } from "node:path";
import { CONFIG_DIR } from "./config";
import { MACHINE_CONFIG, parseMachineConfig, resolveBots, type MachineConfig, type ResolvedBot } from "./machine-config";
import { BotFatal, startRunner, type BotHandle, type RunnerIO } from "./runner";

/** Lỗi mà khởi động lại cũng không chữa được: chờ người sửa cấu hình. */
const PERMANENT = new Set(["auth_revoked", "bound_elsewhere", "owner_mismatch", "already_running", "config"]);
const DRAIN_MS = 10 * 60_000;

export interface SupervisorIO {
  emit(ev: Record<string, any>): void;
  log(s: string): void;
  selfCommand: string[];
}

type Phase = "starting" | "running" | "draining" | "stopped" | "error" | "waiting";
interface Slot {
  key: string;
  hash: string;
  phase: Phase;
  handle?: BotHandle;
  error?: { code: string; message: string };
  backoff: number;
  retry?: ReturnType<typeof setTimeout>;
  /** Dừng có chủ đích (nạp lại / xoá / tắt máy): không tự khởi động lại. */
  intentional?: boolean;
  starting?: Promise<void>;
  lastCode?: string;
  /** Huỷ lúc bot đang khởi động (đang chờ nối máy chủ chat). */
  ac: AbortController;
}

export interface Supervisor {
  reload(): Promise<{ started: string[]; stopped: string[]; restarted: string[]; errors: Record<string, string> }>;
  status(): any;
  drain(key: string): Promise<boolean>;
  stopAll(reason?: string): Promise<void>;
  config(): MachineConfig | null;
  bot(key: string): BotHandle | undefined;
  bots(): BotHandle[];
  /** Báo khi trạng thái bot đổi (app / bridge). */
  onChange(cb: () => void): void;
}

export async function startSupervisor(o: { path?: string; stdinConfig?: any; io: SupervisorIO; watchFile?: boolean; ctl?: boolean }): Promise<Supervisor> {
  const path = o.path ?? MACHINE_CONFIG;
  const { io } = o;
  const slots = new Map<string, Slot>();
  const listeners: (() => void)[] = [];
  const changed = () => { for (const l of listeners) try { l(); } catch {} };
  let mc: MachineConfig | null = null;
  let inline = o.stdinConfig ?? null; // --config-stdin: không có file, app gửi cấu hình mới qua ctl POST /config
  let closing = false;

  const read = (): { mc: MachineConfig; bots: ResolvedBot[] } => {
    const raw = inline ?? JSON.parse(readFileSync(path, "utf8"));
    const m = parseMachineConfig(raw);
    return { mc: m, bots: resolveBots(m, dirname(path)) };
  };

  function botIO(key: string): RunnerIO {
    return {
      selfCommand: io.selfCommand,
      log: (s) => io.log(`[${key}] ${s}`),
      emit: (ev) => {
        const sl = slots.get(key);
        if (sl && ev.event === "error" && typeof ev.code === "string") sl.lastCode = ev.code;
        io.emit({ ...ev, bot: key, ...(ev.bot && typeof ev.bot === "object" ? { bot_info: ev.bot } : {}) });
      },
    };
  }

  function schedule(sl: Slot, cfgOf: () => ResolvedBot | undefined) {
    if (closing || sl.intentional) return;
    const wait = sl.backoff;
    sl.backoff = Math.min(sl.backoff * 2, 10 * 60_000);
    sl.phase = "waiting";
    io.log(`[${sl.key}] khởi động lại sau ${Math.round(wait / 1000)}s`);
    sl.retry = setTimeout(() => { sl.retry = undefined; const rb = cfgOf(); if (rb && slots.get(sl.key) === sl) launch(sl, rb); }, wait);
    changed();
  }

  function current(key: string): ResolvedBot | undefined {
    try { return read().bots.find((b) => b.key === key); } catch { return undefined; }
  }

  function launch(sl: Slot, rb: ResolvedBot) {
    if (!rb.cfg) { sl.phase = "error"; sl.error = { code: "config", message: rb.error ?? "cấu hình lỗi" }; io.emit({ event: "error", bot: sl.key, code: "config", message: sl.error.message }); changed(); return; }
    sl.phase = "starting";
    sl.error = undefined;
    sl.lastCode = undefined;
    changed();
    sl.starting = (async () => {
      try {
        const h = await startRunner(rb.cfg!, { ...botIO(sl.key), signal: sl.ac.signal });
        sl.handle = h;
        if (sl.intentional || closing) { await h.stop("stop"); sl.handle = undefined; sl.phase = "stopped"; changed(); return; }
        sl.phase = "running";
        sl.backoff = 15_000;
        changed();
        h.done.then((why) => {
          if (slots.get(sl.key) !== sl || sl.handle !== h) return;
          sl.handle = undefined;
          if (sl.intentional || closing) { sl.phase = "stopped"; changed(); return; }
          // Bot tự dừng (chủ không khớp…): lỗi vĩnh viễn thì chờ sửa cấu hình, còn lại chạy lại.
          const code = sl.lastCode ?? why;
          if (PERMANENT.has(code)) { sl.phase = "error"; sl.error = { code, message: `bot đã dừng: ${code}` }; changed(); return; }
          schedule(sl, () => current(sl.key));
        });
      } catch (e: any) {
        sl.handle = undefined;
        if (e instanceof BotFatal) {
          sl.error = { code: e.code, message: e.message };
          if (sl.intentional || closing || e.code === "stopped") { sl.phase = "stopped"; changed(); return; }
          if (e.retry) { sl.backoff = Math.max(sl.backoff, 10 * 60_000); schedule(sl, () => current(sl.key)); return; } // thiếu engine: chờ đăng nhập engine
          if (PERMANENT.has(e.code)) { sl.phase = "error"; changed(); return; }
          schedule(sl, () => current(sl.key));
          return;
        }
        sl.error = { code: "fatal", message: String(e?.message ?? e) };
        io.log(`[${sl.key}] lỗi khởi động: ${e?.stack ?? e}`);
        io.emit({ event: "error", bot: sl.key, code: "fatal", message: sl.error.message });
        schedule(sl, () => current(sl.key));
      } finally { sl.starting = undefined; }
    })();
  }

  async function stopSlot(sl: Slot, why: string, drainMs: number) {
    sl.intentional = true;
    sl.ac.abort();
    if (sl.retry) { clearTimeout(sl.retry); sl.retry = undefined; }
    if (sl.starting) await sl.starting.catch(() => {});
    const h = sl.handle;
    if (h) { sl.phase = "draining"; changed(); await h.stop(why, drainMs).catch((e) => io.log(`[${sl.key}] dừng lỗi: ${e}`)); }
    sl.handle = undefined;
    sl.phase = "stopped";
    changed();
  }

  async function reload() {
    const res = { started: [] as string[], stopped: [] as string[], restarted: [] as string[], errors: {} as Record<string, string> };
    let next: { mc: MachineConfig; bots: ResolvedBot[] };
    try { next = read(); } catch (e: any) {
      const message = String(e?.message ?? e);
      io.emit({ event: "config_error", message });
      io.log(`runner.json lỗi, giữ cấu hình đang chạy: ${message}`);
      res.errors["*"] = message;
      return res;
    }
    mc = next.mc;
    const want = new Map(next.bots.filter((b) => b.enabled).map((b) => [b.key, b]));
    const jobs: Promise<void>[] = [];
    for (const [key, sl] of [...slots]) {
      const rb = want.get(key);
      if (!rb) { res.stopped.push(key); jobs.push(stopSlot(sl, "removed", DRAIN_MS).then(() => { slots.delete(key); changed(); })); continue; }
      if (rb.hash !== sl.hash || sl.phase === "error") {
        res.restarted.push(key);
        jobs.push(stopSlot(sl, "reload", DRAIN_MS).then(() => {
          const ns: Slot = { key, hash: rb.hash, phase: "starting", backoff: 15_000, ac: new AbortController() };
          slots.set(key, ns);
          launch(ns, rb);
        }));
      }
    }
    for (const [key, rb] of want) {
      if (slots.has(key)) continue;
      const sl: Slot = { key, hash: rb.hash, phase: "starting", backoff: 15_000, ac: new AbortController() };
      slots.set(key, sl);
      res.started.push(key);
      launch(sl, rb);
      if (rb.error) res.errors[key] = rb.error;
    }
    for (const rb of next.bots) if (rb.error && !res.errors[rb.key]) res.errors[rb.key] = rb.error;
    // Không chờ drain xong mới trả lời: ctl reload trả ngay, việc dừng chạy nền.
    Promise.all(jobs).catch(() => {});
    io.log(`nạp cấu hình: +${res.started.length} −${res.stopped.length} ↻${res.restarted.length}${Object.keys(res.errors).length ? ` · lỗi: ${Object.entries(res.errors).map(([k, v]) => `${k}: ${v}`).join("; ")}` : ""}`);
    changed();
    return res;
  }

  function status() {
    return {
      pid: process.pid,
      config: inline ? "(stdin)" : path,
      machine: mc?.machine?.name ?? null,
      owners: mc?.owners ?? {},
      bots: [...slots.values()].map((s) => ({
        key: s.key, phase: s.phase, id: s.handle?.id ?? null, username: s.handle?.username ?? null,
        active: s.handle?.active() ?? 0, error: s.error ?? null,
      })),
    };
  }

  async function drain(key: string) {
    const sl = slots.get(key);
    if (!sl) return false;
    await stopSlot(sl, "drain", DRAIN_MS);
    return true;
  }

  async function stopAll(reason = "SIGTERM") {
    closing = true;
    await Promise.all([...slots.values()].map((s) => stopSlot(s, reason, 0)));
  }

  // ---- lỗi lạc của một bot không được làm chết cả runner ----
  process.on("unhandledRejection", (e: any) => io.log(`lỗi chưa bắt (unhandledRejection): ${e?.stack ?? e}`));
  process.on("uncaughtException", (e: any) => io.log(`lỗi chưa bắt (uncaughtException): ${e?.stack ?? e}`));

  // ---- theo dõi runner.json ----
  if (!inline && o.watchFile !== false && existsSync(path)) {
    let t: ReturnType<typeof setTimeout> | null = null;
    const kick = () => { if (t) clearTimeout(t); t = setTimeout(() => { t = null; if (!closing) reload().catch(() => {}); }, 1000); };
    // Theo dõi thư mục (trình soạn thảo / app ghi file mới rồi đổi tên đè lên): lọc đúng tên file.
    try { watch(dirname(path), (_ev, f) => { if (!f || String(f) === basename(path)) kick(); }); } catch (e) { io.log(`không theo dõi được ${path}: ${e}`); }
  }

  // ---- điều khiển tại chỗ ----
  const ctlFile = `${CONFIG_DIR}/machine.json`;
  const key = crypto.randomUUID();
  const sup: Supervisor = {
    reload, status, drain, stopAll,
    config: () => mc,
    bot: (k) => slots.get(k)?.handle,
    bots: () => [...slots.values()].map((s) => s.handle).filter((h): h is BotHandle => !!h),
    onChange: (cb) => { listeners.push(cb); },
  };
  if (o.ctl !== false) {
    mkdirSync(CONFIG_DIR, { recursive: true });
    const srv = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      async fetch(req) {
        if (req.headers.get("x-flygo-key") !== key) return Response.json({ ok: false, error: "sai khoá" }, { status: 403 });
        const u = new URL(req.url);
        if (u.pathname === "/status") return Response.json({ ok: true, ...status() });
        if (u.pathname === "/reload" && req.method === "POST") return Response.json({ ok: true, ...(await reload()) });
        if (u.pathname === "/config" && req.method === "POST") { // --config-stdin: app gửi cấu hình mới
          const b = await req.json().catch(() => null);
          try { parseMachineConfig(b); } catch (e: any) { return Response.json({ ok: false, error: String(e?.message ?? e) }, { status: 400 }); }
          inline = b;
          return Response.json({ ok: true, ...(await reload()) });
        }
        if (u.pathname === "/drain" && req.method === "POST") {
          const b: any = await req.json().catch(() => ({}));
          return Response.json({ ok: await drain(String(b.bot ?? "")) });
        }
        return Response.json({ ok: false, error: "không có lệnh này" }, { status: 404 });
      },
    });
    writeFileSync(ctlFile, JSON.stringify({ pid: process.pid, port: srv.port, key, config: inline ? null : path }), { mode: 0o600 });
    const cleanup = () => { try { if (JSON.parse(readFileSync(ctlFile, "utf8")).key === key) unlinkSync(ctlFile); } catch {} };
    process.on("exit", cleanup);
  }

  await reload();
  return sup;
}

/** `flygo-agent ctl …`: gọi runner chung đang chạy trên máy. */
export async function ctl(cmd: string, body?: any): Promise<any> {
  const f = `${CONFIG_DIR}/machine.json`;
  if (!existsSync(f)) throw new Error("runner chung chưa chạy trên máy này");
  const { port, key } = JSON.parse(readFileSync(f, "utf8"));
  const r = await fetch(`http://127.0.0.1:${port}/${cmd}`, {
    method: body === undefined && cmd === "status" ? "GET" : "POST",
    headers: { "x-flygo-key": key, "content-type": "application/json" },
    ...(body === undefined && cmd === "status" ? {} : { body: JSON.stringify(body ?? {}) }),
    signal: AbortSignal.timeout(30_000),
  });
  return r.json();
}
