// Kết nối RPC qua WebSocket (dùng cho extension, phần client trong runner, và các runner cùng máy). Khung JSON giống relay
// của Playwright MCP: yêu cầu {id, method, params} -> trả lời {id, result | error}; sự kiện (không id) {method, params}.
// Hai chiều: bên nào cũng gửi yêu cầu được; yêu cầu đến được xử lý bằng handle(method, fn).
// Tệp này dùng chung: flygo-chat-client agent/src/browser/link.ts là bản gốc, flygo-chat-server browser/src/link.ts chép lại.
// Thêm của Flygo: {t:"ping"}/{t:"pong"}, {t:"part", k, i, n, d} (chuỗi > PART bị chia nhỏ vì Cloudflare giới hạn kích thước
// một message), {t:"control", ...} báo popup ai đang điều khiển, {t:"rename", name}, {t:"stop"} (người dùng bấm Dừng).
import { EventEmitter } from 'node:events';
import type { WebSocket } from 'ws';

export const PART = 200_000;
const RPC_TIMEOUT = 60_000;

export function sendFramed(ws: { send(s: string): void }, obj: unknown, seq: { n: number }) {
  const s = JSON.stringify(obj);
  if (s.length <= PART) return ws.send(s);
  const k = `p${++seq.n}`, n = Math.ceil(s.length / PART);
  for (let i = 0; i < n; i++) ws.send(JSON.stringify({ t: 'part', k, i, n, d: s.slice(i * PART, (i + 1) * PART) }));
}

/** Ghép các mảnh {t:"part"}; trả object hoàn chỉnh hoặc null khi còn thiếu. */
export function joiner(maxBytes = 64 * 1024 * 1024) {
  const parts = new Map<string, { n: number; got: number; d: string[]; size: number }>();
  return (msg: any): any => {
    if (msg?.t !== 'part') return msg;
    let p = parts.get(msg.k);
    if (!p) parts.set(msg.k, (p = { n: msg.n, got: 0, d: new Array(msg.n), size: 0 }));
    if (p.d[msg.i] === undefined) { p.d[msg.i] = String(msg.d); p.got++; p.size += String(msg.d).length; }
    if (p.size > maxBytes) { parts.delete(msg.k); throw new Error('message quá lớn'); }
    if (p.got < p.n) return null;
    parts.delete(msg.k);
    return JSON.parse(p.d.join(''));
  };
}

export class ExtensionLink extends EventEmitter {
  private callbacks = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  private handlers = new Map<string, (params: any) => any>();
  private lastId = 0;
  private seq = { n: 0 };
  private join = joiner();
  closed = false;
  readonly connectedAt = Date.now();
  lastPing = Date.now();

  private ws: WebSocket; readonly browserId: string; readonly extVersion: string;
  /** Xử lý yêu cầu đến (bên kia gọi send(method)). */
  handle(method: string, fn: (params: any) => any) { this.handlers.set(method, fn); return this; }
  constructor(ws: WebSocket, browserId: string, extVersion: string) {
    super();
    this.ws = ws; this.browserId = browserId; this.extVersion = extVersion;
    ws.on('message', (data) => this.onMessage(data.toString()));
    ws.on('close', () => this.dispose('đóng kết nối'));
    ws.on('error', () => this.dispose('lỗi kết nối'));
  }

  send(method: string, params?: unknown, timeoutMs = RPC_TIMEOUT): Promise<any> {
    if (this.closed) return Promise.reject(new Error('trình duyệt đã ngắt kết nối'));
    const id = ++this.lastId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.callbacks.delete(id); reject(new Error(`trình duyệt không trả lời ${method}`)); }, timeoutMs);
      this.callbacks.set(id, { resolve, reject, timer });
      sendFramed(this.ws, { id, method, params }, this.seq);
    });
  }

  notify(obj: Record<string, unknown>) { if (!this.closed) sendFramed(this.ws, obj, this.seq); }

  close(reason: string, code = 1000) {
    try { this.ws.close(code, reason.slice(0, 120)); } catch {}
    this.dispose(reason);
  }

  private onMessage(raw: string) {
    let msg: any;
    try { msg = this.join(JSON.parse(raw)); } catch { return this.close('dữ liệu hỏng', 1003); }
    if (!msg) return;
    if (msg.t === 'ping') { this.lastPing = Date.now(); this.notify({ t: 'pong' }); return; }
    if (msg.t) { this.emit('flygo', msg); return; }
    if (msg.id === undefined || msg.id === null) { this.emit('event', msg); return; }
    if (msg.method !== undefined) { void this.answer(msg); return; }
    const cb = this.callbacks.get(msg.id);
    if (!cb) return;
    this.callbacks.delete(msg.id);
    clearTimeout(cb.timer);
    if (msg.error) cb.reject(new Error(typeof msg.error === 'string' ? msg.error : msg.error.message ?? 'lỗi trình duyệt'));
    else cb.resolve(msg.result);
  }

  private async answer(msg: any) {
    const fn = this.handlers.get(msg.method);
    try {
      if (!fn) throw new Error(`không hỗ trợ ${msg.method}`);
      const result = await fn(msg.params);
      this.notify({ id: msg.id, result: result ?? null });
    } catch (e: any) { this.notify({ id: msg.id, error: { message: String(e?.message ?? e) } }); }
  }

  private dispose(reason: string) {
    if (this.closed) return;
    this.closed = true;
    for (const cb of this.callbacks.values()) { clearTimeout(cb.timer); cb.reject(new Error('trình duyệt đã ngắt kết nối')); }
    this.callbacks.clear();
    this.emit('close', reason);
  }
}
