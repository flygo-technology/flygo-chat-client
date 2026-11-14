// MCP bên ngoài (Streamable HTTP) của chủ bot: thêm từ app (Trang chủ › Cá nhân › MCP & tiện ích, qua relay
// POST /a2a/extensions → {t:"ext"}) hoặc do agent đề xuất bằng tool mcp_add (chủ bot duyệt trên app).
// Lưu ở ~/.config/flygo-agent/ext-<bot>.json (khoá / token chỉ nằm trên máy này, không qua máy chủ chat).
// Xác thực: không cần / header (API key) / OAuth2 theo đặc tả MCP: 401 + WWW-Authenticate → metadata tài nguyên
// (RFC 9728) → metadata máy chủ cấp quyền (RFC 8414) → đăng ký client động (RFC 7591) nếu có → PKCE (S256), trình
// duyệt đăng nhập, mã trả về relay /a2a/oauth/callback rồi chuyển xuống runner ({t:"oauth_cb"}); token tự làm mới.
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export interface ExtOAuth {
  authServer: string;
  tokenEndpoint: string;
  clientId: string;
  clientSecret?: string;
  scope?: string;
  resource?: string;
  accessToken?: string;
  refreshToken?: string;
  expiresAt?: number;
}

export interface Ext {
  id: string;
  name: string;
  url: string;
  enabled: boolean;
  /** API key / header tĩnh (vd. Authorization: Bearer …). */
  headers?: Record<string, string>;
  oauth?: ExtOAuth;
  addedAt: number;
  addedBy?: string; // "app" | "agent"
}

export type AuthKind = "none" | "key" | "oauth";

export interface ProbeResult {
  ok: boolean;
  auth: AuthKind;
  tools?: { name: string; description?: string }[];
  serverName?: string;
  error?: string;
  /** OAuth: URL metadata tài nguyên (từ WWW-Authenticate resource_metadata=…) */
  resourceMetadata?: string;
}

const b64url = (b: Buffer) => b.toString("base64url");
export const extIdOf = (name: string) =>
  name.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/gi, "d").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "mcp";

export class ExtStore {
  private list: Ext[] = [];
  /** OAuth đang chờ trình duyệt: state → {extId, verifier, redirectUri, …}. */
  private pending = new Map<string, { ext: Ext; verifier: string; redirectUri: string; at: number; onDone?: (r: { ok: boolean; error?: string }) => void }>();

  constructor(private file: string, private log: (...a: any[]) => void = () => {}) {
    try { this.list = JSON.parse(readFileSync(file, "utf8")); } catch { this.list = []; }
  }

  private save() {
    mkdirSync(dirname(this.file), { recursive: true });
    writeFileSync(this.file, JSON.stringify(this.list, null, 1), { mode: 0o600 });
  }

  all(): Ext[] { return this.list; }
  get(id: string) { return this.list.find((e) => e.id === id); }

  /** Danh sách cho app (không có khoá / token). */
  view() {
    return this.list.map((e) => ({
      id: e.id, name: e.name, url: e.url, enabled: e.enabled, added_at: e.addedAt, added_by: e.addedBy ?? "app",
      auth: (e.oauth ? "oauth" : e.headers && Object.keys(e.headers).length ? "key" : "none") as AuthKind,
      connected: e.oauth ? !!e.oauth.accessToken : true,
    }));
  }

  upsert(e: Omit<Ext, "addedAt"> & { addedAt?: number }): Ext {
    let id = e.id || extIdOf(e.name);
    const old = this.get(id);
    if (old && old.url !== e.url) { let n = 2; while (this.get(`${id}-${n}`)) n++; id = `${id}-${n}`; }
    const v: Ext = { ...old, ...e, id, addedAt: old?.addedAt ?? e.addedAt ?? Date.now() };
    this.list = [...this.list.filter((x) => x.id !== id), v];
    this.save();
    return v;
  }

  setEnabled(id: string, on: boolean) { const e = this.get(id); if (!e) return false; e.enabled = on; this.save(); return true; }
  remove(id: string) { const n = this.list.length; this.list = this.list.filter((e) => e.id !== id); this.save(); return this.list.length < n; }

  /** Header gửi tới MCP (làm mới token OAuth nếu sắp hết hạn). */
  async headersFor(e: Ext): Promise<Record<string, string> | null> {
    if (!e.oauth) return e.headers ?? {};
    const o = e.oauth;
    if (!o.accessToken) return null;
    if (o.expiresAt && o.expiresAt - Date.now() < 60_000 && o.refreshToken) {
      try {
        const t = await tokenRequest(o, { grant_type: "refresh_token", refresh_token: o.refreshToken });
        o.accessToken = t.access_token;
        if (t.refresh_token) o.refreshToken = t.refresh_token;
        o.expiresAt = t.expires_in ? Date.now() + Number(t.expires_in) * 1000 : undefined;
        this.save();
      } catch (err: any) {
        this.log(`mcp ${e.id}: làm mới token lỗi ${err?.message ?? err}`);
      }
    }
    return { Authorization: `Bearer ${o.accessToken}` };
  }

  /** MCP đang bật, sẵn sàng (đủ token) → {tên: {url, headers}} cho engine. */
  async servers(): Promise<Record<string, { url: string; headers: Record<string, string> }>> {
    const out: Record<string, { url: string; headers: Record<string, string> }> = {};
    for (const e of this.list) {
      if (!e.enabled) continue;
      const h = await this.headersFor(e);
      if (h) out[`ext_${e.id.replace(/-/g, "_")}`] = { url: e.url, headers: h };
    }
    return out;
  }

  /** Bắt đầu OAuth2: tìm máy chủ cấp quyền, đăng ký client (nếu cần), trả URL đăng nhập. */
  async oauthStart(e: Ext, probe: ProbeResult, redirectUri: string, botId: string, onDone?: (r: { ok: boolean; error?: string }) => void): Promise<string> {
    const resMetaUrl = probe.resourceMetadata ?? new URL("/.well-known/oauth-protected-resource", e.url).toString();
    const resMeta: any = await getJson(resMetaUrl).catch(() => null);
    const authServer = String(resMeta?.authorization_servers?.[0] ?? new URL(e.url).origin);
    const asMeta: any = await getJson(new URL("/.well-known/oauth-authorization-server", authServer).toString())
      .catch(() => getJson(new URL("/.well-known/openid-configuration", authServer).toString()));
    if (!asMeta?.authorization_endpoint || !asMeta?.token_endpoint) throw new Error("máy chủ MCP không công bố OAuth (thiếu authorization / token endpoint)");
    let clientId = e.oauth?.clientId ?? "", clientSecret = e.oauth?.clientSecret;
    if (!clientId) {
      if (!asMeta.registration_endpoint) throw new Error("máy chủ MCP không cho đăng ký client tự động; cần client id cấp sẵn");
      const reg = await fetch(asMeta.registration_endpoint, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ client_name: "Flygo Chat agent", redirect_uris: [redirectUri], grant_types: ["authorization_code", "refresh_token"], response_types: ["code"], token_endpoint_auth_method: "none" }),
        signal: AbortSignal.timeout(15_000),
      });
      const rj: any = await reg.json().catch(() => ({}));
      if (!reg.ok || !rj.client_id) throw new Error(`đăng ký client lỗi ${reg.status}`);
      clientId = rj.client_id; clientSecret = rj.client_secret;
    }
    const scope = (resMeta?.scopes_supported ?? asMeta.scopes_supported ?? []).join(" ") || undefined;
    e.oauth = { ...e.oauth, authServer, tokenEndpoint: asMeta.token_endpoint, clientId, clientSecret, scope, resource: resMeta?.resource ?? e.url };
    const verifier = b64url(randomBytes(32));
    const state = `${botId}.${b64url(randomBytes(18))}`;
    for (const [k, p] of this.pending) if (Date.now() - p.at > 15 * 60_000) this.pending.delete(k);
    this.pending.set(state, { ext: e, verifier, redirectUri, at: Date.now(), onDone });
    const u = new URL(asMeta.authorization_endpoint);
    u.search = new URLSearchParams({
      response_type: "code", client_id: clientId, redirect_uri: redirectUri, state,
      code_challenge: b64url(createHash("sha256").update(verifier).digest()), code_challenge_method: "S256",
      ...(scope ? { scope } : {}), ...(e.oauth.resource ? { resource: e.oauth.resource } : {}),
    }).toString();
    return u.toString();
  }

  /** Mã từ trình duyệt (relay chuyển xuống): đổi lấy token, lưu MCP. */
  async oauthCallback(state: string, code?: string, error?: string): Promise<{ ok: boolean; name?: string; error?: string }> {
    const p = this.pending.get(state);
    if (!p) return { ok: false, error: "phiên đăng nhập đã hết hạn, thử lại từ app" };
    this.pending.delete(state);
    const done = (r: { ok: boolean; name?: string; error?: string }) => { p.onDone?.(r); return r; };
    if (error || !code) return done({ ok: false, name: p.ext.name, error: error || "thiếu mã đăng nhập" });
    try {
      const o = p.ext.oauth!;
      const t = await tokenRequest(o, { grant_type: "authorization_code", code, redirect_uri: p.redirectUri, code_verifier: p.verifier });
      o.accessToken = t.access_token;
      o.refreshToken = t.refresh_token;
      o.expiresAt = t.expires_in ? Date.now() + Number(t.expires_in) * 1000 : undefined;
      this.upsert({ ...p.ext, enabled: true });
      return done({ ok: true, name: p.ext.name });
    } catch (err: any) {
      return done({ ok: false, name: p.ext.name, error: err?.message ?? String(err) });
    }
  }
}

async function getJson(url: string) {
  const r = await fetch(url, { headers: { accept: "application/json" }, signal: AbortSignal.timeout(10_000) });
  if (!r.ok) throw new Error(`${url} -> ${r.status}`);
  return r.json();
}

async function tokenRequest(o: ExtOAuth, params: Record<string, string>) {
  const body = new URLSearchParams({ ...params, client_id: o.clientId, ...(o.clientSecret ? { client_secret: o.clientSecret } : {}), ...(o.resource ? { resource: o.resource } : {}) });
  const r = await fetch(o.tokenEndpoint, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" }, body, signal: AbortSignal.timeout(15_000) });
  const j: any = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error(`đổi token lỗi ${r.status}${j.error ? ` ${j.error}` : ""}`);
  return j;
}

/** Đọc một phản hồi JSON-RPC (JSON thường hoặc SSE "data: {…}"). */
function parseRpc(text: string, ctype: string): any {
  if (ctype.includes("text/event-stream")) {
    for (const line of text.split("\n")) {
      if (!line.startsWith("data:")) continue;
      try { const j = JSON.parse(line.slice(5).trim()); if (j.result || j.error) return j; } catch {}
    }
    return null;
  }
  try { return JSON.parse(text); } catch { return null; }
}

/** Thử kết nối MCP (initialize + tools/list): trả danh sách tool, hoặc cần xác thực kiểu nào. */
export async function probeMcp(url: string, headers: Record<string, string> = {}): Promise<ProbeResult> {
  let u: URL;
  try { u = new URL(url); } catch { return { ok: false, auth: "none", error: "URL không hợp lệ" }; }
  if (u.protocol !== "https:" && u.protocol !== "http:") {
    return { ok: false, auth: "none", error: "chỉ hỗ trợ http(s)" };
  }
  const base = { "content-type": "application/json", accept: "application/json, text/event-stream", ...headers };
  const call = async (body: any, session?: string) => {
    const r = await fetch(url, { method: "POST", headers: { ...base, ...(session ? { "mcp-session-id": session } : {}), "mcp-protocol-version": "2025-06-18" }, body: JSON.stringify(body), signal: AbortSignal.timeout(15_000) });
    return { r, text: await r.text() };
  };
  try {
    const init = await call({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "flygo-agent", version: "1" } } });
    if (init.r.status === 401 || init.r.status === 403) {
      const www = init.r.headers.get("www-authenticate") ?? "";
      const rm = /resource_metadata="?([^",\s]+)"?/i.exec(www)?.[1];
      const oauth = !!rm || /bearer/i.test(www) && !Object.keys(headers).length && (await looksOAuth(url));
      return { ok: false, auth: oauth ? "oauth" : "key", resourceMetadata: rm, error: Object.keys(headers).length ? "khoá / token bị từ chối" : "cần xác thực" };
    }
    if (!init.r.ok) return { ok: false, auth: "none", error: `máy chủ trả ${init.r.status}` };
    const ij = parseRpc(init.text, init.r.headers.get("content-type") ?? "");
    if (!ij?.result) return { ok: false, auth: "none", error: ij?.error?.message ?? "không phải máy chủ MCP (Streamable HTTP)" };
    const session = init.r.headers.get("mcp-session-id") ?? undefined;
    await call({ jsonrpc: "2.0", method: "notifications/initialized" }, session).catch(() => null);
    const tl = await call({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }, session);
    const tj = parseRpc(tl.text, tl.r.headers.get("content-type") ?? "");
    const tools = ((tj?.result?.tools ?? []) as any[]).map((t) => ({ name: String(t.name), description: t.description ? String(t.description).slice(0, 200) : undefined }));
    return { ok: true, auth: Object.keys(headers).length ? "key" : "none", tools, serverName: ij.result.serverInfo?.name };
  } catch (err: any) {
    return { ok: false, auth: "none", error: err?.name === "TimeoutError" ? "hết thời gian chờ máy chủ MCP" : (err?.message ?? String(err)) };
  }
}

async function looksOAuth(url: string) {
  const j: any = await getJson(new URL("/.well-known/oauth-protected-resource", url).toString()).catch(() => null);
  return !!j?.authorization_servers?.length;
}

export const extFileFor = (configDir: string, botId: string) => `${configDir}/ext-${botId}.json`;
export const hasExtFile = (configDir: string, botId: string) => existsSync(extFileFor(configDir, botId));
