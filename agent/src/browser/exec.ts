// Chạy tool trên MỘT trình duyệt có extension nối trực tiếp (ExtensionLink). Dùng chung cho phần client (máy người dùng,
// extension nối 127.0.0.1) và phần server (đường dự phòng: extension nối thẳng lên server).
import { NET_METHODS } from './tools.ts';
import { PwSession } from './pw.ts';
import type { CdpHub } from './relay.ts';
import type { ExtensionLink } from './link.ts';

export interface ExecResult { result: any; file?: { base64: string; name: string; type: string; bytes: number; status?: number } }

const text = (s: string, isError = false) => ({ ...(isError ? { isError: true } : {}), content: [{ type: 'text', text: s }] });

export class LocalBrowser {
  pw: PwSession | null = null;
  latency: number | null = null;
  private hub: CdpHub; readonly link: ExtensionLink; private fetchImpl: typeof fetch;
  constructor(hub: CdpHub, link: ExtensionLink, fetchImpl: typeof fetch = fetch) { this.hub = hub; this.link = link; this.fetchImpl = fetchImpl; }

  private session(): PwSession {
    if (!this.pw || this.pw.closed) this.pw = new PwSession(this.hub, this.link);
    return this.pw;
  }
  get lastUsed() { return this.pw?.lastUsed ?? 0; }

  /** Dừng điều khiển: đóng phiên Playwright, gỡ debugger khỏi mọi tab (tab vẫn mở). */
  async stop() {
    const pw = this.pw; this.pw = null;
    await pw?.close();
    await this.link.send('flygo.detachAll', {}).catch(() => {});
  }

  async exec(name: string, args: Record<string, any>): Promise<ExecResult> {
    if (name === 'browser_release') { await this.stop(); return { result: text('Đã trả quyền điều khiển.') }; }
    if (NET_METHODS[name]) return { result: text(JSON.stringify(await this.link.send(NET_METHODS[name], args, 30_000), null, 1)) };
    if (name === 'browser_file_upload_url') return { result: await this.session().uploadFromUrls(Array.isArray(args.files) ? args.files : [], this.fetchImpl) };
    if (name === 'browser_download') {
      const r = await this.link.send('flygo.fetch', { url: String(args.url ?? ''), max_bytes: 50 * 1024 * 1024 }, 120_000);
      return { result: null, file: { base64: String(r.base64 ?? ''), name: String(args.name || r.name || 'download'), type: String(r.type || 'application/octet-stream'), bytes: Number(r.bytes) || 0, status: r.status } };
    }
    return { result: await this.session().call(name, args) };
  }

  async close() { await this.pw?.close(); this.pw = null; }
}
