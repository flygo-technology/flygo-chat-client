// TeamWork (app Làm việc nhóm): lượt chạy agent do người dùng giao (nút Bắt đầu / @nhắc agent trong bình luận).
//
// - Nhận diện: tin giao việc có dòng đầu `[teamwork task=KEY run=ID comment=CID url=…]` VÀ props.flygo_teamwork.run_token
//   (JWS EdDSA do máy chủ TeamWork ký). Dòng đầu chỉ là gợi ý; mọi quyết định dựa trên token đã kiểm. URL trong tin bị bỏ qua:
//   địa chỉ TeamWork luôn suy từ máy chủ chat trong cấu hình của runner (`<serverUrl>/__apps/teamwork`).
// - Toàn quyền (không hỏi duyệt) chỉ khi: token hợp lệ (aud "flygo-agent", chưa hết hạn, bot_id = bot này, bypass = true),
//   người gửi tin là chủ bot, và cấu hình teamworkBypass = true. Thiếu điều kiện nào: chạy chế độ thường.
//   Toàn quyền ở đây vẫn giữ danh sách cấm (deny) — khác "fullAccess" của chủ máy.
// - Tiến độ: đẩy các bước (như thẻ tiến trình) + chữ đang viết lên `POST <teamwork>/api/runs/<run>/progress`, gom tối đa
//   ~2 lần / giây, luôn gửi bản cuối (final), thử lại có giãn cách, không bao giờ làm hỏng / chặn lượt.
import crypto from "node:crypto";

import { redact } from "./history";

export interface TwHeader { key: string; run: string; comment?: string }

/** Dòng đầu tin giao việc của TeamWork (chỉ gợi ý; không tin URL trong đó). */
export function parseTwHeader(text: string): TwHeader | null {
  const m = /\[teamwork task=([A-Za-z0-9-]{1,40}) run=([A-Za-z0-9_-]{1,64})(?: comment=([A-Za-z0-9_-]{1,64}))?(?: url=\S+)?\]/.exec(String(text ?? "").slice(0, 600));
  return m ? { key: m[1], run: m[2], ...(m[3] ? { comment: m[3] } : {}) } : null;
}

/** Địa chỉ TeamWork của máy chủ chat trong cấu hình (không bao giờ lấy từ tin nhắn). */
export const twBase = (serverUrl: string) => `${String(serverUrl).replace(/\/+$/, "")}/__apps/teamwork`;

export interface TwClaims { run?: string; run_id?: string; typ?: string; iss?: string; bot_id?: string; bypass?: boolean; aud?: string | string[]; exp?: number; task?: string; comment_id?: string; [k: string]: unknown }

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

/** Kiểm run_token bằng JWKS của TeamWork (cache 10 phút, tải lại khi gặp kid lạ, tối đa 1 lần / 30 giây). */
export class TwVerifier {
  private keys: Record<string, any>[] = [];
  private at = 0;
  /** [iss]: địa chỉ TeamWork mong đợi (claims.iss phải khớp, bỏ "/" cuối); null = không kiểm. */
  constructor(private jwksUrl: string, private botId: string, private fetchFn: Fetch = fetch, private now: () => number = Date.now, private iss: string | null = null) {}

  private async jwks(kid?: string) {
    const stale = this.now() - this.at > 10 * 60_000, miss = !!kid && !this.keys.some((k) => k.kid === kid);
    if ((stale || miss) && (this.now() - this.at > 30_000 || !this.keys.length)) {
      try {
        const r = await this.fetchFn(this.jwksUrl, { signal: AbortSignal.timeout(8000) });
        if (r.ok) { this.keys = (((await r.json()) as any)?.keys ?? []) as Record<string, any>[]; this.at = this.now(); }
      } catch {}
    }
    return this.keys;
  }

  /** Claims nếu token hợp lệ cho bot này; null nếu không. */
  async verify(token: unknown): Promise<TwClaims | null> {
    const parts = typeof token === "string" ? token.split(".") : [];
    if (parts.length !== 3) return null;
    try {
      const head = JSON.parse(Buffer.from(parts[0], "base64url").toString());
      if (head.alg !== "EdDSA") return null;
      const jwk = (await this.jwks(head.kid)).find((k) => k.kid === head.kid && k.kty === "OKP" && k.crv === "Ed25519");
      if (!jwk) return null;
      const key = crypto.createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: jwk.x }, format: "jwk" });
      if (!crypto.verify(null, Buffer.from(`${parts[0]}.${parts[1]}`), key, Buffer.from(parts[2], "base64url"))) return null;
      const c = JSON.parse(Buffer.from(parts[1], "base64url").toString()) as TwClaims;
      const aud = Array.isArray(c.aud) ? c.aud : [c.aud];
      if (!aud.includes("flygo-agent")) return null;
      if (typeof c.exp !== "number" || c.exp * 1000 < this.now()) return null;
      if (c.bot_id !== this.botId) return null;
      if (c.typ !== undefined && c.typ !== "teamwork-run") return null;
      if (this.iss && String(c.iss ?? "").replace(/\/+$/, "") !== this.iss.replace(/\/+$/, "")) return null;
      return c;
    } catch {
      return null;
    }
  }
}

/** Lượt TeamWork: có đẩy tiến độ không, có chạy toàn quyền không, ghi chú hiện ở bước đầu. */
export interface TwDecision { run: string; push: boolean; bypass: boolean; note: string }

export const TW_BYPASS_NOTE = "🔓 Chạy không cần duyệt (chủ bot)";
export const TW_NORMAL_NOTE = "Chạy chế độ thường";

/** Quyết định cho một lượt: chỉ dựa trên token đã kiểm, người gửi và công tắc cấu hình. */
export function twDecide(o: { claims: TwClaims | null; header: TwHeader | null; posterIsOwner: boolean; killSwitch: boolean }): TwDecision | null {
  if (!o.claims) return null; // không có token hợp lệ: không phải lượt TeamWork (không đẩy tiến độ, không toàn quyền)
  const run = String(o.claims.run ?? o.claims.run_id ?? o.header?.run ?? "");
  if (!run) return null;
  const bypass = o.claims.bypass === true && o.posterIsOwner && o.killSwitch;
  const why = o.claims.bypass !== true ? "" : !o.killSwitch ? " (bot tắt chạy không cần duyệt)" : !o.posterIsOwner ? " (người giao không phải chủ bot)" : "";
  return { run, push: true, bypass, note: bypass ? TW_BYPASS_NOTE : `${TW_NORMAL_NOTE}${why}` };
}

/** Luật cấm thêm cho lượt TeamWork không cần duyệt (Claude, agy): ngoài deny có sẵn của cấu hình. */
export const TW_CLAUDE_DENY = [
  "Bash(rm -rf:*)", "Bash(rm:*)", "Bash(sudo:*)",
  "Read(~/.ssh/**)", "Read(~/.config/flygo-agent/**)", "Read(~/.codex/auth.json)", "Read(~/.aws/**)", "Read(~/.claude/.credentials.json)",
  "Read(~/.netrc)", "Read(~/.git-credentials)", "Read(~/.docker/config.json)", "Read(~/.kube/**)", "Read(~/.gnupg/**)", "Read(~/.config/gh/**)",
  "Edit(~/.ssh/**)", "Edit(~/.config/flygo-agent/**)", "Write(~/.ssh/**)", "Write(~/.config/flygo-agent/**)",
];
export const TW_AGY_DENY = [
  "command(rm -rf)", "command(rm)", "command(sudo)",
  "read_file(~/.ssh)", "read_file(~/.config/flygo-agent)", "read_file(~/.codex/auth.json)", "read_file(~/.aws)", "read_file(~/.claude/.credentials.json)",
  "read_file(~/.netrc)", "read_file(~/.git-credentials)", "read_file(~/.docker/config.json)", "read_file(~/.kube)", "read_file(~/.gnupg)", "read_file(~/.config/gh)",
];
export const mergeDeny = (base: string[] | undefined, extra: string[]) => [...new Set([...(base ?? []), ...extra])];

// ---------------------------------------------------------------- tiến độ
export type TwStepKind = "tool" | "think" | "text" | "plan" | "approval";
export interface TwStep { id: string; kind: TwStepKind; title: string; detail?: string; status: "running" | "done" | "error"; at: number }

/** Bước của thẻ tiến trình → bước tiến độ TeamWork (cùng tiêu đề / trạng thái), đã che bí mật. */
export function twStepOf(s: { id: string; kind: string; title: string; detail?: string; status: string; started_at?: number }, now = Date.now()): TwStep {
  const kind: TwStepKind = s.kind === "thinking" ? "think" : s.kind === "approval" ? "approval" : s.kind === "message" ? "text" : s.kind === "plan" ? "plan" : "tool";
  const status = s.status === "error" ? "error" : s.status === "done" ? "done" : "running";
  const detail = s.detail ? redact(s.detail).slice(0, 600) : undefined;
  return { id: s.id, kind, title: redact(s.title).slice(0, 300), ...(detail ? { detail } : {}), status, at: s.started_at ?? now };
}

export interface TwPushOpts {
  base: string; run: string; botToken: string; serverUrl: string;
  fetchFn?: Fetch; minGapMs?: number; retries?: number; log?: (s: string) => void;
  setTimer?: (fn: () => void, ms: number) => unknown; clearTimer?: (t: unknown) => void; now?: () => number;
}

/** Đẩy tiến độ của một lượt: gom thay đổi, tối đa 1 lần / minGapMs, bản cuối luôn gửi (final), không bao giờ ném lỗi. */
export class TwProgress {
  private steps = new Map<string, TwStep>();
  private text = "";
  private state = "running";
  private seq = 0;
  private dirty = false;
  private timer: unknown = null;
  private lastAt = 0;
  private sending: Promise<void> = Promise.resolve();
  private done = false;
  readonly sent: { seq: number; final: boolean }[] = []; // để kiểm thử / ghi log
  private o: Required<Omit<TwPushOpts, "log">> & { log?: (s: string) => void };

  constructor(opts: TwPushOpts) {
    this.o = {
      fetchFn: fetch, minGapMs: 500, retries: 3,
      setTimer: (fn: () => void, ms: number) => setTimeout(fn, ms), clearTimer: (t: unknown) => clearTimeout(t as any), now: Date.now,
      ...opts,
    } as any;
  }

  step(s: Parameters<typeof twStepOf>[0]) {
    if (this.done) return;
    this.steps.set(s.id, twStepOf(s, this.o.now()));
    this.kick();
  }

  /** Chữ trả lời đang viết (thay toàn bộ). */
  setText(t: string) {
    if (this.done) return;
    this.text = redact(String(t ?? "")).slice(0, 20000);
    this.kick();
  }

  setState(st: string) { if (!this.done) { this.state = st; this.kick(); } }

  private kick() {
    this.dirty = true;
    if (this.timer) return;
    const wait = Math.max(0, this.lastAt + this.o.minGapMs - this.o.now());
    this.timer = this.o.setTimer(() => { this.timer = null; void this.flush(false); }, wait);
  }

  private body(final: boolean) {
    return { seq: ++this.seq, state: this.state, steps: [...this.steps.values()].slice(-60), text: this.text, ...(final ? { final: true } : {}) };
  }

  private flush(final: boolean): Promise<void> {
    if (!this.dirty && !final) return this.sending;
    this.dirty = false;
    this.lastAt = this.o.now();
    const b = this.body(final);
    this.sending = this.sending.then(() => this.post(b));
    return this.sending;
  }

  private async post(b: { seq: number; final?: boolean }) {
    const url = `${this.o.base}/api/runs/${encodeURIComponent(this.o.run)}/progress`;
    for (let i = 0; i <= this.o.retries; i++) {
      try {
        const r = await this.o.fetchFn(url, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${this.o.botToken}`, "X-MM-Server": this.o.serverUrl },
          body: JSON.stringify(b),
          signal: AbortSignal.timeout(10_000),
        });
        if (r.ok || (r.status >= 400 && r.status < 500 && r.status !== 429)) { this.sent.push({ seq: b.seq, final: !!b.final }); return; } // 4xx (409 not_active…): không thử lại
        if (r.status === 429) {
          const ms = Number(((await r.json().catch(() => ({}))) as any)?.retry_after_ms) || 1000;
          if (i < this.o.retries) { await new Promise((res) => this.o.setTimer(res as () => void, Math.min(ms, 10_000))); continue; }
        }
      } catch {}
      if (i < this.o.retries) await new Promise((res) => this.o.setTimer(res as () => void, 300 * 2 ** i));
    }
    this.o.log?.(`teamwork: không đẩy được tiến độ run ${this.o.run} (seq ${b.seq})`);
  }

  /** Kết thúc lượt: gửi bản cuối (final: true) với trạng thái [state]. */
  async finish(state: string, text?: string) {
    if (this.done) return this.sending;
    if (text !== undefined) this.text = redact(text).slice(0, 20000);
    this.state = state;
    this.done = true;
    if (this.timer) { this.o.clearTimer(this.timer); this.timer = null; }
    return this.flush(true);
  }
}
