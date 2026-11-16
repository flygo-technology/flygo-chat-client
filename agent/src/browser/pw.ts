// Một phiên Playwright MCP cho mỗi trình duyệt đang online: createConnection(config, contextGetter) với BrowserContext lấy từ
// connectOverCDP tới CdpHub. Giữ phiên để ref của snapshot dùng được giữa các lần gọi; đóng khi rảnh lâu hoặc extension ngắt.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createConnection } from '@playwright/mcp';
import { chromium, type Browser } from 'playwright-core';
import type { CdpHub } from './relay.ts';
import type { ExtensionLink } from './link.ts';

/** Tool của Playwright không đưa cho agent: run_code_unsafe chạy code trên MÁY CHỦ; file_upload nhận đường dẫn của máy chủ
 * (thay bằng browser_file_upload_url); network_* thay bằng log mạng chạy tại trình duyệt. */
export const HIDDEN_PW_TOOLS = new Set(['browser_run_code_unsafe', 'browser_file_upload', 'browser_network_requests', 'browser_network_request']);
export const PW_CONFIG = { capabilities: ['core', 'tabs', 'pdf'] as any, imageResponses: 'allow' as const };

type Rpc = { jsonrpc: '2.0'; id?: number; method: string; params?: any };

/** Transport MCP trong bộ nhớ (đủ cho Server của Playwright MCP). */
class MemoryTransport {
  onmessage?: (m: any) => void; onclose?: () => void; onerror?: (e: Error) => void;
  private pending = new Map<number, (m: any) => void>();
  private id = 0;
  async start() {}
  async close() { this.onclose?.(); }
  async send(m: any) { const cb = m.id !== undefined ? this.pending.get(m.id) : undefined; if (cb) { this.pending.delete(m.id); cb(m); } }
  request(method: string, params?: unknown): Promise<any> {
    const id = ++this.id;
    return new Promise((ok) => { this.pending.set(id, ok); this.onmessage?.({ jsonrpc: '2.0', id, method, params } satisfies Rpc); });
  }
  notify(method: string) { this.onmessage?.({ jsonrpc: '2.0', method }); }
}

async function connect(contextGetter: () => Promise<any>, outputDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pwmcp-'))) {
  const server = await createConnection({ ...PW_CONFIG, outputDir } as any, contextGetter);
  const t = new MemoryTransport();
  await server.connect(t as any);
  await t.request('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'flygo-browser', version: '1' } });
  t.notify('notifications/initialized');
  return { server, t };
}

/** Danh sách tool của Playwright MCP (không cần trình duyệt). */
export async function playwrightTools(): Promise<any[]> {
  const { server, t } = await connect(async () => { throw new Error('chưa có trình duyệt'); });
  const r = await t.request('tools/list', {});
  await server.close().catch(() => {});
  return (r.result?.tools ?? []).filter((x: any) => !HIDDEN_PW_TOOLS.has(x.name));
}

/** Playwright ghi snapshot sau mỗi thao tác ra tệp ở máy chạy Playwright; agent ở xa không đọc được tệp đó. */
function localize(result: any) {
  for (const c of result?.content ?? []) {
    if (c?.type === 'text' && typeof c.text === 'string')
      c.text = c.text.replace(/\[Snapshot\]\([^)]*\)/g, '(trang đã cập nhật: gọi browser_snapshot để xem nội dung và ref mới)')
        .replace(/\[(Screenshot[^\]]*)\]\([^)]*\)/g, '$1 (ảnh gửi kèm bên dưới)')
        .replace(/can be handled by browser_file_upload\b/g, 'can be handled by browser_file_upload_url');
  }
  return result;
}

export class PwSession {
  private conn: Promise<{ server: any; t: MemoryTransport }> | null = null;
  private browser: Browser | null = null;
  private reg: ReturnType<CdpHub['register']>;
  // Thư mục xuất của Playwright; tệp tải lên cũng phải nằm trong đây (Playwright chỉ cho đọc tệp trong thư mục được phép).
  private tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fbb-'));
  lastUsed = Date.now();
  closed = false;

  readonly link: ExtensionLink;
  constructor(hub: CdpHub, link: ExtensionLink) {
    this.link = link;
    // Tab của agent phải là tab đang hiện: tab nền không được vẽ (requestAnimationFrame dừng) nên Playwright chờ "ổn định" mãi.
    this.reg = hub.register(link, false);
  }

  private async context() {
    if (!this.browser || !this.browser.isConnected()) {
      this.browser = await chromium.connectOverCDP(this.reg.url, { timeout: 30_000, isLocal: false, noDefaults: true } as any);
      this.browser.on('disconnected', () => { this.browser = null; });
    }
    const ctx = this.browser.contexts()[0];
    if (!ctx) throw new Error('không lấy được ngữ cảnh trình duyệt');
    return ctx;
  }

  async call(name: string, args: Record<string, unknown>): Promise<any> {
    if (this.closed) throw new Error('phiên trình duyệt đã đóng');
    this.lastUsed = Date.now();
    this.conn ??= connect(() => this.context(), this.tmp);
    const { t } = await this.conn;
    const r = await t.request('tools/call', { name, arguments: args });
    if (r.error) return { isError: true, content: [{ type: 'text', text: r.error.message }] };
    return localize(r.result);
  }

  /** Tải các URL về thư mục tạm rồi gọi browser_file_upload (Playwright gửi nội dung tệp vì isLocal = false). */
  async uploadFromUrls(files: { url?: string; name?: string; base64?: string }[], fetchImpl: typeof fetch = fetch): Promise<any> {
    const paths: string[] = [];
    let total = 0;
    for (const [i, f] of files.entries()) {
      let buf: Buffer;
      if (f.base64) buf = Buffer.from(f.base64, 'base64');
      else {
        const u = new URL(String(f.url ?? ''));
        if (u.protocol !== 'https:' && u.protocol !== 'http:') throw new Error('chỉ nhận URL http(s)');
        const r = await fetchImpl(u, { signal: AbortSignal.timeout(60_000) });
        if (!r.ok) throw new Error(`tải ${u.hostname} lỗi HTTP ${r.status}`);
        buf = Buffer.from(await r.arrayBuffer());
      }
      total += buf.length;
      if (total > 50 * 1024 * 1024) throw new Error('tổng dung lượng tệp vượt 50 MB');
      const name = path.basename(f.name || (f.url ? new URL(f.url).pathname : '') || `file-${i + 1}`).replace(/[^\w.\- ]+/g, '_') || `file-${i + 1}`;
      const dir = fs.mkdtempSync(path.join(this.tmp, 'u'));
      const p = path.join(dir, name);
      fs.writeFileSync(p, buf);
      paths.push(p);
    }
    try { return await this.call('browser_file_upload', { paths }); }
    finally { for (const p of paths) fs.rmSync(path.dirname(p), { recursive: true, force: true }); }
  }

  async close() {
    if (this.closed) return;
    this.closed = true;
    try { const c = await this.conn; await c?.server.close(); } catch {}
    try { await this.browser?.close(); } catch {}
    this.reg.dispose();
    fs.rmSync(this.tmp, { recursive: true, force: true });
  }
}
