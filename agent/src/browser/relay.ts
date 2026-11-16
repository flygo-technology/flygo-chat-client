// CDP relay: giả lập một trình duyệt CDP cho Playwright (connectOverCDP), chuyển lệnh thành RPC chrome.debugger.* / chrome.tabs.*
// tới extension. Phần BrowserModel chép và rút gọn từ playwright-core src/tools/mcp/browserModel.ts + cdpRelay.ts
// (Copyright (c) Microsoft Corporation, Apache License 2.0, http://www.apache.org/licenses/LICENSE-2.0). Thay đổi của Flygo:
// extension nối qua WebSocket của dịch vụ (ExtensionLink) thay vì localhost; điểm CDP chỉ nghe trên 127.0.0.1 với đường dẫn bí mật.
import crypto from 'node:crypto';
import http from 'node:http';
import { WebSocketServer, type WebSocket } from 'ws';
import type { ExtensionLink } from './link.ts';

interface TabSession { tabId: number; sessionId: string; targetInfo: any; childSessions: Set<string> }

export class BrowserModel {
  private knownTabIds = new Set<number>();
  private tabSessions = new Map<number, TabSession>();
  private autoAttach = false;
  private nextSessionId = 1;
  private onEvent = (e: any) => this.onExtensionEvent(e);

  private ext: ExtensionLink; private send: (msg: any) => void; private background: boolean;
  constructor(ext: ExtensionLink, send: (msg: any) => void, background = true) {
    this.ext = ext; this.send = send; this.background = background;
    ext.on('event', this.onEvent);
  }
  dispose() { this.ext.off('event', this.onEvent); }

  /** Tab mà người dùng đưa cho agent (popup "Đưa tab này cho agent"). */
  addKnownTab(tabId: number) {
    this.knownTabIds.add(tabId);
    if (this.autoAttach) void this.attachTab(tabId).catch(() => {});
  }
  attachedTabs() { return [...this.tabSessions.keys()]; }

  async handleCDPCommand(method: string, params: any, sessionId?: string): Promise<any> {
    switch (method) {
      case 'Browser.getVersion': return { protocolVersion: '1.3', product: 'Chrome/Flygo-Browser-Bridge', userAgent: 'Flygo-Browser-Bridge/1.0' };
      case 'Browser.setDownloadBehavior': return {};
      case 'Target.setAutoAttach':
        if (sessionId) break;
        await this.enableAutoAttach();
        return {};
      case 'Target.createTarget': return await this.createTarget(params?.url);
      case 'Target.closeTarget': return await this.closeTarget(params?.targetId);
      case 'Target.getTargetInfo': return sessionId ? this.findTabSession((s) => s.sessionId === sessionId)?.targetInfo : undefined;
      case 'Page.bringToFront':
      case 'Target.activateTarget':
        if (this.background) return {};
        break;
    }
    return await this.ext.send('chrome.debugger.sendCommand', [this.debuggerTarget(method, sessionId), method, params]);
  }

  private async enableAutoAttach() {
    this.autoAttach = true;
    await Promise.all([...this.knownTabIds].map((id) => this.attachTab(id).catch(() => {})));
  }
  private async createTarget(url?: string) {
    const tab = await this.ext.send('chrome.tabs.create', [{ url, active: !this.background }]);
    if (tab?.id === undefined) throw new Error('Failed to create tab');
    this.knownTabIds.add(tab.id);
    const s = await this.attachTab(tab.id);
    return { targetId: s.targetInfo?.targetId };
  }
  private async closeTarget(targetId?: string) {
    const s = targetId ? this.findTabSession((x) => x.targetInfo?.targetId === targetId) : undefined;
    if (!s) return { success: false };
    await this.ext.send('chrome.tabs.remove', [s.tabId]);
    return { success: true };
  }
  private debuggerTarget(method: string, sessionId?: string) {
    if (!sessionId) {
      const first = this.tabSessions.values().next().value as TabSession | undefined;
      if (!first) throw new Error(`No attached tab to forward browser-level command: ${method}`);
      return { tabId: first.tabId };
    }
    const own = this.findTabSession((s) => s.sessionId === sessionId);
    if (own) return { tabId: own.tabId };
    const parent = this.findTabSession((s) => s.childSessions.has(sessionId));
    if (parent) return { tabId: parent.tabId, sessionId };
    throw new Error(`No tab found for sessionId: ${sessionId}`);
  }
  private onExtensionEvent(event: any) {
    const p = event.params ?? [];
    switch (event.method) {
      case 'chrome.tabs.onCreated': {
        const tab = p[0];
        // Chỉ tab do agent mở (openerTabId là tab đã gắn) hoặc tab người dùng bấm "Đưa tab này cho agent" (flygoShared) mới gắn.
        if (tab?.id === undefined) break;
        if (tab.flygoShared || (tab.openerTabId !== undefined && this.tabSessions.has(tab.openerTabId))) {
          this.knownTabIds.add(tab.id);
          if (this.autoAttach) void this.attachTab(tab.id).catch(() => {});
        }
        break;
      }
      case 'chrome.tabs.onRemoved': this.knownTabIds.delete(p[0]); this.detachTab(p[0]); break;
      case 'chrome.debugger.onEvent': this.onDebuggerEvent(p[0], p[1], p[2]); break;
      case 'chrome.debugger.onDetach': if (p[0]?.tabId !== undefined) { this.knownTabIds.delete(p[0].tabId); this.detachTab(p[0].tabId); } break;
    }
  }
  private onDebuggerEvent(source: any, method: string, params: any) {
    if (source?.tabId === undefined) return;
    const s = this.tabSessions.get(source.tabId);
    if (!s) return;
    const child = params?.sessionId;
    if (method === 'Target.attachedToTarget' && child) s.childSessions.add(child);
    else if (method === 'Target.detachedFromTarget' && child) s.childSessions.delete(child);
    this.send({ sessionId: source.sessionId || s.sessionId, method, params });
  }
  private async attachTab(tabId: number): Promise<TabSession> {
    const existing = this.tabSessions.get(tabId);
    if (existing) return existing;
    await this.ext.send('chrome.debugger.attach', [{ tabId }, '1.3']);
    const r = await this.ext.send('chrome.debugger.sendCommand', [{ tabId }, 'Target.getTargetInfo']);
    const s: TabSession = { tabId, sessionId: `pw-tab-${this.nextSessionId++}`, targetInfo: r?.targetInfo, childSessions: new Set() };
    this.tabSessions.set(tabId, s);
    this.send({ method: 'Target.attachedToTarget', params: { sessionId: s.sessionId, targetInfo: { ...s.targetInfo, attached: true }, waitingForDebugger: false } });
    return s;
  }
  private detachTab(tabId: number) {
    const s = this.tabSessions.get(tabId);
    if (!s) return;
    this.tabSessions.delete(tabId);
    this.send({ method: 'Target.detachedFromTarget', params: { sessionId: s.sessionId, targetId: s.targetInfo?.targetId } });
  }
  private findTabSession(pred: (s: TabSession) => boolean) {
    for (const s of this.tabSessions.values()) if (pred(s)) return s;
    return undefined;
  }
}

/** Điểm CDP nội bộ (127.0.0.1, cổng ngẫu nhiên) dùng chung cho mọi trình duyệt; mỗi trình duyệt một đường dẫn bí mật. */
export class CdpHub {
  private server = http.createServer((_q, r) => { r.statusCode = 404; r.end(); });
  private wss = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 * 1024 });
  private routes = new Map<string, (ws: WebSocket) => void>();
  port = 0;

  async start() {
    this.server.on('upgrade', (req, sock, head) => {
      const fn = this.routes.get(new URL(req.url ?? '/', 'http://x').pathname);
      if (!fn) return sock.destroy();
      this.wss.handleUpgrade(req, sock, head, (ws) => fn(ws));
    });
    await new Promise<void>((ok) => this.server.listen(0, '127.0.0.1', ok));
    this.port = (this.server.address() as any).port;
  }
  stop() { this.server.close(); }

  /** Đăng ký một trình duyệt; trả URL CDP để connectOverCDP và hàm huỷ. Chỉ nhận MỘT client CDP mỗi lần. */
  register(ext: ExtensionLink, background = true) {
    const path = `/cdp/${crypto.randomBytes(18).toString('base64url')}`;
    let model: BrowserModel | null = null;
    let client: WebSocket | null = null;
    this.routes.set(path, (ws) => {
      if (client) return ws.close(1000, 'Another CDP client already connected');
      client = ws;
      model = new BrowserModel(ext, (m) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(m)); }, background);
      ws.on('message', async (data) => {
        let msg: any;
        try { msg = JSON.parse(data.toString()); } catch { return; }
        const { id, sessionId, method, params } = msg;
        try {
          const result = await model!.handleCDPCommand(method, params, sessionId);
          ws.send(JSON.stringify({ id, sessionId, result }));
        } catch (e: any) {
          ws.send(JSON.stringify({ id, sessionId, error: { message: String(e?.message ?? e) } }));
        }
      });
      ws.on('close', () => { model?.dispose(); model = null; client = null; });
    });
    return {
      url: `ws://127.0.0.1:${this.port}${path}`,
      model: () => model,
      dispose: () => { this.routes.delete(path); try { client?.close(); } catch {} model?.dispose(); },
    };
  }
}
