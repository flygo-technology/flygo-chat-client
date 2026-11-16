// Kết nối của một tiến trình flygo-agent tới PHẦN SERVER của app Trình duyệt trên máy chủ chat của nó
// (<máy chủ chat>/__apps/browser/client/ws). Chỉ giữ khi hub cấp "leader" cho cặp (máy chủ, chủ tài khoản).
// Xác thực: token bot (runner) hoặc vé Flygo ID của người dùng (chế độ "flygo-agent apps" do app chạy).
// Luôn dùng địa chỉ CÔNG KHAI của máy chủ (wss), không dùng IP LAN (macOS chặn quyền mạng cục bộ của binary).
import { WebSocket } from 'ws';
import { ExtensionLink } from './link.ts';
import type { ExtSummary, LocalSide } from './hub.ts';
import { machineId, machineName } from '../machine.ts';

export type UpAuth = { botToken: string } | { ticket: () => Promise<string> };

export class Upstream {
  private link: ExtensionLink | null = null;
  private leader = false;
  private stopped = false;
  private retry = 1000;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private authTimer: ReturnType<typeof setInterval> | null = null;
  private byBrowser = new Map<string, string>(); // browser id (của máy chủ này) -> ext_id
  private refs = new Map<number, (m: any) => void>();
  private ref = 0;
  readonly key: string;
  readonly server: string;
  private wsUrl: string;
  private user: string | null = null;

  private onAttach = (s: ExtSummary) => void this.attach(s);
  private onDetach = (extId: string) => {
    for (const [b, e] of this.byBrowser) if (e === extId) { this.byBrowser.delete(b); this.link?.notify({ t: 'detach', browser_id: b }); }
  };
  private onExtMsg = (extId: string, msg: any) => {
    for (const [b, e] of this.byBrowser) if (e === extId) this.link?.notify({ ...msg, browser_id: b });
  };
  private onLeader = (key: string, yes: boolean) => {
    if (key !== this.key) return;
    this.leader = yes;
    if (yes) this.connect(); else this.disconnect();
  };

  constructor(private o: {
    serverUrl: string; owner: string; local: LocalSide; auth: UpAuth; version: string; log: (s: string) => void;
    /** Mặc định <serverUrl>/__apps/browser */
    browserUrl?: string;
  }) {
    this.server = o.serverUrl.replace(/\/+$/, '');
    this.key = `${this.server}|${o.owner}`;
    const base = (o.browserUrl ?? `${this.server}/__apps/browser`).replace(/\/+$/, '');
    this.wsUrl = `${base.replace(/^http/, 'ws')}/client/ws`;
    o.local.on('attach', this.onAttach);
    o.local.on('detach', this.onDetach);
    o.local.on('ext_msg', this.onExtMsg);
    o.local.on('leader', this.onLeader);
    o.local.claim(this.key);
  }

  stop() {
    this.stopped = true;
    this.o.local.off('attach', this.onAttach); this.o.local.off('detach', this.onDetach);
    this.o.local.off('ext_msg', this.onExtMsg); this.o.local.off('leader', this.onLeader);
    this.o.local.unclaim(this.key);
    this.disconnect();
  }

  private status(state: 'connecting' | 'online' | 'offline' | 'error', error?: string) {
    this.o.local.status({ key: this.key, server: this.server, user: this.user, state, error: error ?? null });
  }

  private disconnect() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    if (this.authTimer) { clearInterval(this.authTimer); this.authTimer = null; }
    const l = this.link; this.link = null;
    l?.close('ngắt', 1000);
    this.byBrowser.clear();
  }

  private later() {
    if (this.stopped || !this.leader || this.timer) return;
    const wait = this.retry + Math.random() * 500;
    this.retry = Math.min(this.retry * 2, 60_000);
    this.timer = setTimeout(() => { this.timer = null; this.connect(); }, wait);
  }

  private async connect() {
    if (this.stopped || !this.leader || this.link) return;
    this.status('connecting');
    let hello: Record<string, unknown>;
    try {
      hello = { t: 'hello', role: 'client', machine: machineId(), machine_name: machineName(), client_version: this.o.version,
        ...('botToken' in this.o.auth ? { bot_token: this.o.auth.botToken } : { ticket: await this.o.auth.ticket() }) };
    } catch (e: any) { this.status('error', `không lấy được vé: ${e?.message ?? e}`); return this.later(); }
    const ws = new WebSocket(this.wsUrl);
    const opened = await new Promise<boolean>((resolve) => {
      const t = setTimeout(() => { try { ws.terminate(); } catch {} resolve(false); }, 15_000);
      ws.once('open', () => { clearTimeout(t); resolve(true); });
      ws.once('error', () => { clearTimeout(t); resolve(false); });
    });
    if (!opened || this.stopped || !this.leader) { try { ws.close(); } catch {} this.status('offline'); return this.later(); }
    ws.send(JSON.stringify(hello));
    const link = new ExtensionLink(ws, `server:${this.server}`, '');
    this.link = link;
    link.handle('tool', async (p: any) => {
      const extId = this.byBrowser.get(String(p.browser));
      if (!extId) throw new Error('trình duyệt không còn nối với máy này');
      return this.o.local.exec(extId, String(p.name), p.args ?? {});
    });
    link.handle('stop', async (p: any) => { const extId = this.byBrowser.get(String(p.browser)); if (extId) await this.o.local.stop(extId); return { ok: true }; });
    link.on('flygo', (msg: any) => {
      if (msg.t === 'welcome') {
        this.retry = 1000;
        this.status('online');
        for (const s of this.o.local.list()) void this.attach(s);
        if (!('botToken' in this.o.auth)) {
          const get = this.o.auth.ticket;
          this.authTimer = setInterval(() => { void get().then((ticket) => link.notify({ t: 'auth', ticket })).catch(() => {}); }, 5 * 60_000);
        }
        return;
      }
      if (msg.t === 'error') { this.status('error', String(msg.message ?? msg.code)); this.o.log(`browser ${this.server}: ${msg.message ?? msg.code}`); return; }
      if (msg.t === 'res') { const cb = this.refs.get(msg.ref); if (cb) { this.refs.delete(msg.ref); cb(msg); } return; }
      const extId = msg.browser_id ? this.byBrowser.get(String(msg.browser_id)) : undefined;
      if (!extId) return;
      if (msg.t === 'renamed') this.o.local.paired(extId, this.server, { browser_id: msg.browser_id, name: msg.name, slug: msg.slug });
      if (msg.t === 'revoked') { this.byBrowser.delete(msg.browser_id); this.o.local.paired(extId, this.server, null); }
      // control / renamed / revoked: báo cho popup biết máy chủ nào.
      this.o.local.notifyExt(extId, { ...msg, server: this.server });
    });
    link.on('close', () => {
      if (this.link === link) this.link = null;
      if (this.authTimer) { clearInterval(this.authTimer); this.authTimer = null; }
      this.byBrowser.clear();
      for (const cb of this.refs.values()) cb({ ok: false, message: 'mất kết nối' });
      this.refs.clear();
      this.status('offline');
      this.later();
    });
  }

  private request(msg: Record<string, unknown>): Promise<any> {
    const l = this.link;
    if (!l) return Promise.resolve({ ok: false, message: 'chưa nối máy chủ' });
    const ref = ++this.ref;
    return new Promise((resolve) => {
      const t = setTimeout(() => { this.refs.delete(ref); resolve({ ok: false, message: 'máy chủ không trả lời' }); }, 20_000);
      this.refs.set(ref, (m) => { clearTimeout(t); resolve(m); });
      l.notify({ ...msg, ref });
    });
  }

  private async attach(s: ExtSummary) {
    if (!this.link) return;
    const mine = s.pairings[this.server];
    const r = await this.request({ t: 'attach', token: mine?.token ?? null, ext_version: s.ext_version, info: s.info });
    if (!r.ok) {
      this.o.log(`browser ${this.server}: không gắn được trình duyệt (${r.message ?? r.code})`);
      if (r.code === 'outdated') this.o.local.notifyExt(s.ext_id, { t: 'update', server: this.server, required: true, download_url: r.download_url ?? null, message: r.message });
      return;
    }
    this.byBrowser.set(r.browser.id, s.ext_id);
    this.o.local.paired(s.ext_id, this.server, { browser_id: r.browser.id, name: r.browser.name, slug: r.browser.slug, ...(r.token ? { token: r.token } : {}) });
    if (r.latest_version) this.o.local.notifyExt(s.ext_id, { t: 'update', server: this.server, latest_version: r.latest_version, download_url: r.download_url ?? null });
    if (r.new_pair) this.o.local.notifyExt(s.ext_id, { t: 'notice', server: this.server, text: `Đã kết nối trình duyệt với ${this.server.replace(/^https:\/\//, '')} (${r.browser.name}).` });
  }
}
