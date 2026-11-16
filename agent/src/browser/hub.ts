// Hub trình duyệt trên máy người dùng (phần client của app "Trình duyệt", chạy trong runner flygo-agent: MỘT runner mỗi máy).
//   GET /flygo/hello   extension dò runner trên máy (chỉ trả lời extension của mình: Origin hoặc header X-Flygo-Bridge)
//   WS  /ext           extension nối vào (chỉ Origin = extension của mình). Hub giữ kết nối, chạy Playwright MCP tại máy.
// Các kết nối tới phần server (upstream.ts, mỗi cặp máy chủ + chủ tài khoản một kết nối) dùng hub qua giao diện LocalSide.
import { EventEmitter } from 'node:events';
import http from 'node:http';
import os from 'node:os';
import { WebSocketServer, type WebSocket } from 'ws';
import { ExtensionLink } from './link.ts';
import { CdpHub } from './relay.ts';
import { LocalBrowser, type ExecResult } from './exec.ts';

export const HUB_PORT = 47800;
/** ID của extension Flygo Browser Bridge (cố định nhờ "key" trong manifest.json; key là khoá CÔNG KHAI). */
export const EXTENSION_IDS = ['pknpafgfaedabfloepblchniacfknjig'];

export interface Pairing { browser_id: string; token?: string; name?: string; slug?: string; user?: string }
export interface ExtSummary {
  ext_id: string; ext_version: string;
  info: { name?: string; engine?: string; os?: string; profile?: string };
  pairings: Record<string, Pairing>; // theo URL máy chủ chat
}
export interface UpStatus { key: string; server: string; user?: string | null; state: 'connecting' | 'online' | 'offline' | 'error'; error?: string | null }

/** Phía máy (hub) mà upstream dùng. */
export interface LocalSide extends EventEmitter {
  list(): ExtSummary[];
  exec(extId: string, name: string, args: Record<string, any>): Promise<ExecResult>;
  stop(extId: string): Promise<void>;
  notifyExt(extId: string, msg: Record<string, unknown>): void;
  paired(extId: string, server: string, p: Pairing | null): void;
  claim(key: string): void;
  unclaim(key: string): void;
  status(s: UpStatus): void;
  // sự kiện: 'attach' (ExtSummary), 'detach' (extId), 'ext_msg' (extId, msg), 'leader' (key, yes)
}

interface ExtEntry { sum: ExtSummary; link: ExtensionLink; local: LocalBrowser }
type Claimant = { kind: 'local' };

export class Hub extends EventEmitter implements LocalSide {
  private http = http.createServer((q, r) => this.onHttp(q, r));
  private wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 * 1024 });
  private cdp = new CdpHub();
  private exts = new Map<string, ExtEntry>();
  private claims = new Map<string, Claimant[]>(); // key -> hàng đợi; phần tử đầu là leader
  private statuses = new Map<string, UpStatus>();
  private origins: Set<string>;
  private version: string; private log: (s: string) => void; private port: number;

  constructor(o: { version: string; log: (s: string) => void; extensionIds?: string[]; port?: number }) {
    super();
    this.version = o.version; this.log = o.log; this.port = o.port ?? HUB_PORT;
    this.origins = new Set([...EXTENSION_IDS, ...(o.extensionIds ?? [])].map((id) => `chrome-extension://${id}`));
  }

  /** true: đã làm hub. false: cổng đã có tiến trình khác giữ. */
  async start(): Promise<boolean> {
    const ok = await new Promise<boolean>((resolve) => {
      this.http.once('error', (e: any) => resolve(e?.code === 'EADDRINUSE' ? false : (this.log(`browser hub: ${e?.message}`), false)));
      this.http.listen(this.port, '127.0.0.1', () => resolve(true));
    });
    if (!ok) return false;
    await this.cdp.start();
    this.http.on('upgrade', (req, sock, head) => this.onUpgrade(req, sock as any, head));
    this.log(`browser hub: nghe 127.0.0.1:${this.port}`);
    return true;
  }

  async close() {
    for (const e of this.exts.values()) { await e.local.close(); e.link.close('runner dừng', 1001); }
    this.wss.close(); this.http.close(); this.cdp.stop();
  }

  // ---------------------------------------------------------------- HTTP / WS
  private originOk(req: http.IncomingMessage) { return this.origins.has(String(req.headers.origin ?? '')); }
  /** fetch GET của extension (có host_permissions) không gửi Origin: nhận khi không có Origin mà có header riêng.
   * Trang web không gửi được header riêng tới 127.0.0.1 mà không qua preflight CORS (hub không trả lời preflight). */
  private helloOk(req: http.IncomingMessage) {
    return this.originOk(req) || (!req.headers.origin && req.method === 'GET' && this.origins.has(`chrome-extension://${String(req.headers['x-flygo-bridge'] ?? '')}`));
  }

  private onHttp(req: http.IncomingMessage, res: http.ServerResponse) {
    const url = new URL(req.url ?? '/', 'http://x');
    if (url.pathname === '/flygo/hello' && this.helloOk(req)) {
      res.writeHead(200, { 'Content-Type': 'application/json', ...(req.headers.origin ? { 'Access-Control-Allow-Origin': String(req.headers.origin) } : {}), 'Cache-Control': 'no-store', Vary: 'Origin' });
      return res.end(JSON.stringify({ app: 'flygo-agent', role: 'browser-hub', version: this.version, machine_name: os.hostname().replace(/\.(local|lan|home)$/i, ''), servers: [...this.statuses.values()] }));
    }
    // Không có CORS cho mọi origin khác: trang web không đọc được gì.
    res.writeHead(404); res.end();
  }

  private onUpgrade(req: http.IncomingMessage, sock: any, head: Buffer) {
    const p = new URL(req.url ?? '/', 'http://x').pathname;
    if (p === '/ext') {
      if (!this.originOk(req)) return sock.destroy();
      return this.wss.handleUpgrade(req, sock, head, (ws) => this.onExt(ws));
    }
    sock.destroy();
  }

  private onExt(ws: WebSocket) {
    const t = setTimeout(() => ws.close(4408, 'chưa chào'), 10_000);
    ws.once('message', (data) => {
      clearTimeout(t);
      let h: any;
      try { h = JSON.parse(String(data)); } catch { return ws.close(4400, 'sai định dạng'); }
      if (h?.t !== 'hello' || typeof h.ext_id !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(h.ext_id)) return ws.close(4400, 'cần hello');
      const old = this.exts.get(h.ext_id);
      if (old) { old.link.close('kết nối mới thay thế', 4409); void old.local.close(); }
      const link = new ExtensionLink(ws, h.ext_id, String(h.ext_version ?? '0'));
      const sum: ExtSummary = {
        ext_id: h.ext_id, ext_version: String(h.ext_version ?? '0'),
        info: { name: str(h.info?.name, 60), engine: str(h.info?.engine, 40), os: str(h.info?.os, 40), profile: str(h.info?.profile, 60) },
        pairings: sanitizePairings(h.pairings),
      };
      const entry: ExtEntry = { sum, link, local: new LocalBrowser(this.cdp, link) };
      this.exts.set(h.ext_id, entry);
      link.notify({ t: 'welcome', hub: { version: this.version, machine_name: os.hostname() }, servers: [...this.statuses.values()] });
      this.log(`browser hub: extension ${h.ext_id.slice(0, 6)} nối (${sum.info.engine ?? '?'})`);
      this.broadcast('attach', sum);
      link.on('flygo', (msg: any) => {
        if (msg.t === 'rename' && typeof msg.name === 'string') sum.info.name = msg.name.slice(0, 60);
        if (msg.t === 'stop') void entry.local.stop();
        if (['rename', 'stop', 'rtt'].includes(msg.t)) this.broadcast('ext_msg', h.ext_id, msg);
      });
      link.on('close', () => {
        if (this.exts.get(h.ext_id) !== entry) return;
        this.exts.delete(h.ext_id);
        void entry.local.close();
        this.broadcast('detach', h.ext_id);
      });
    });
  }

  // ---------------------------------------------------------------- LocalSide
  private broadcast(ev: 'attach' | 'detach' | 'ext_msg', ...args: any[]) { this.emit(ev, ...args); }
  list(): ExtSummary[] { return [...this.exts.values()].map((e) => e.sum); }
  async exec(extId: string, name: string, args: Record<string, any>): Promise<ExecResult> {
    const e = this.exts.get(extId);
    if (!e) throw new Error('trình duyệt vừa ngắt kết nối khỏi máy (đang nối lại), thử lại sau vài giây');
    return e.local.exec(name, args);
  }
  async stop(extId: string) { await this.exts.get(extId)?.local.stop(); }
  notifyExt(extId: string, msg: Record<string, unknown>) { this.exts.get(extId)?.link.notify(msg); }
  paired(extId: string, server: string, p: Pairing | null) {
    const e = this.exts.get(extId);
    if (!e) return;
    if (p) e.sum.pairings[server] = { ...e.sum.pairings[server], ...p };
    else delete e.sum.pairings[server];
    e.link.notify({ t: 'paired', server, pairing: p });
  }
  claim(key: string) { this.addClaim(key, { kind: 'local' }); }
  unclaim(key: string) { this.dropClaim(key, (c) => c.kind === 'local'); }
  status(s: UpStatus) {
    this.statuses.set(s.key, s);
    for (const e of this.exts.values()) e.link.notify({ t: 'status', servers: [...this.statuses.values()] });
  }

  private tellLeader(_c: Claimant, key: string, yes: boolean) { this.emit('leader', key, yes); }
  private addClaim(key: string, c: Claimant) {
    const q = this.claims.get(key) ?? [];
    q.push(c);
    this.claims.set(key, q);
    if (q.length === 1) this.tellLeader(c, key, true);
  }
  private dropClaim(key: string, pred: (c: Claimant) => boolean) {
    const q = this.claims.get(key);
    if (!q) return;
    const wasLeader = q.length && pred(q[0]);
    const next = q.filter((c) => !pred(c));
    this.claims.set(key, next);
    if (wasLeader && next.length) this.tellLeader(next[0], key, true);
    if (!next.length) { this.claims.delete(key); this.statuses.delete(key); }
  }
}

const str = (v: unknown, max: number) => (typeof v === 'string' ? v.slice(0, max) : undefined);
function sanitizePairings(v: any): Record<string, Pairing> {
  const out: Record<string, Pairing> = {};
  if (!v || typeof v !== 'object') return out;
  for (const [server, p] of Object.entries(v as Record<string, any>)) {
    if (!/^https?:\/\/[^\s/]+/.test(server) || typeof p?.browser_id !== 'string') continue;
    out[server.replace(/\/+$/, '')] = { browser_id: p.browser_id.slice(0, 40), token: typeof p.token === 'string' ? p.token.slice(0, 200) : undefined, name: str(p.name, 60), slug: str(p.slug, 60) };
  }
  return out;
}
