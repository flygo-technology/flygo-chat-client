// Flygo Gateway (MCP) cho từng lượt: runner xin vé Flygo ID mang danh người nhờ (biên nhận của plugin vn.flygo.sso),
// rồi chuyển tools/list và tools/call của MCP flygo_chat tới gateway. Vé chỉ nằm trong bộ nhớ runner: không vào argv, env hay log.
//   - Có biên nhận (người nhắn riêng hoặc @nhắc bot): vé mang quyền của người đó; gia hạn bằng {renew} tới 2 giờ sau tin.
//   - Không có biên nhận: vé của riêng agent (quyền gán thẳng cho agent).
//   - Lỗi gateway không làm hỏng lượt: tools/list bỏ tool của gateway, chỉ ghi log một lần mỗi lượt.
//   - Lượt vắng mặt (lịch hẹn, nhắc hẹn… không có biên nhận) của CHỦ bot: vé làm thay chủ theo "đồng ý chạy thay" (Flygo ID
//     /v1/agent/consents), quyền là quyền hiện tại của chủ, như lượt thường (Sếp 2026-11-17: "Bot lên lịch hẹn cũng có đủ các công cụ
//     như bình thường"). Đồng ý được lập / làm mới tự động mỗi khi chủ nhắn bot (biên nhận), tối đa 12 giờ một lần.
//     Không có đồng ý (người tạo không phải chủ, chưa lập, bị thu hồi) thì dùng vé của riêng agent như trước, và báo lý do.
// Không có cfg.flygoId thì không làm gì (như cũ).

export interface FlygoIdConfig {
  url: string;        // Flygo ID công khai của máy chủ chat, vd https://chat.flygo.vn/flygo-id
  gatewayUrl: string; // Flygo Gateway /mcp, vd http://gateway.example:18789/mcp
}

interface Ticket { token: string; exp: number; receipt: boolean; via: "receipt" | "consent" | "agent" }
interface Run { postId: string; ctx?: string; assigner?: string; schedule?: string; ticket?: Ticket; pending?: Promise<Ticket>; failed?: string; logged?: boolean; reduced?: string }
/** Nơi runner giữ id đồng ý chạy thay theo người (bảng kv của bot). */
export interface ConsentStore { get(user: string): { id: string; at: number } | null; set(user: string, v: { id: string; at: number } | null): void }
const CONSENT_REFRESH_MS = 12 * 3600_000;

export interface GatewayTool { name: string; description?: string; inputSchema: any; outputSchema?: any; annotations?: any; _meta?: Record<string, unknown> }

const REFRESH_BEFORE_MS = 120_000;
const AUDIENCE = "vn.flygo.gateway";

export class GatewayError extends Error {}

export function createGatewayRuns(o: {
  flygoId?: FlygoIdConfig;
  serverUrl: string;
  botToken: string;
  log: (s: string) => void;
  fetchImpl?: typeof fetch;
  now?: () => number;
  /** Chủ bot (ownerUserIds): chỉ lượt của chủ mới dùng / lập đồng ý chạy thay. */
  owners?: string[];
  consents?: ConsentStore;
}) {
  const f = o.fetchImpl ?? fetch;
  const now = o.now ?? Date.now;
  const runs = new Map<string, Run>();
  /** Danh sách tool lấy được lần gần nhất: mạng chập chờn lúc đầu lượt thì agent vẫn thấy tool (gọi lỗi thì báo rõ), không
   * kết luận nhầm "không có tool trình duyệt" (2026-11-23). */
  let lastTools: GatewayTool[] = [];
  const server = o.serverUrl.replace(/\/+$/, "");
  const enabled = !!(o.flygoId?.url && o.flygoId?.gatewayUrl);
  const idUrl = (o.flygoId?.url ?? "").replace(/\/+$/, "");
  const bot = { Authorization: `Bearer ${o.botToken}`, "X-MM-Server": server, "content-type": "application/json" };

  let receiptLogged = false;
  async function receipt(postId: string): Promise<string | null> {
    const r = await f(`${server}/plugins/vn.flygo.sso/flygo/receipts/${encodeURIComponent(postId)}`, { headers: { Authorization: `Bearer ${o.botToken}` }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 404) return null; // plugin chưa cài / bản cũ
    // 401/403: bot chưa có trong danh sách bot nhận biên nhận của plugin (ReceiptBots): coi như không có biên nhận
    // (vẫn dùng được đồng ý chạy thay hoặc vé riêng của agent), ghi log một lần.
    if (r.status === 401 || r.status === 403) { if (!receiptLogged) { receiptLogged = true; o.log(`gateway: plugin không cấp biên nhận cho bot này (HTTP ${r.status}, bot chưa có trong ReceiptBots?)`); } return null; }
    if (!r.ok) throw new GatewayError(`biên nhận: HTTP ${r.status}`);
    const j = (await r.json()) as { receipts?: { receipt: string }[] };
    return j.receipts?.[0]?.receipt ?? null;
  }

  async function mint(body: Record<string, unknown>): Promise<{ token: string; expires_in: number }> {
    const r = await f(`${idUrl}/v1/token/agent`, { method: "POST", headers: bot, body: JSON.stringify({ audience: AUDIENCE, ...body }), signal: AbortSignal.timeout(10_000) });
    const j = (await r.json().catch(() => ({}))) as any;
    if (!r.ok || !j.token) throw Object.assign(new GatewayError(`Flygo ID: ${j.error ?? `HTTP ${r.status}`}`), { status: r.status });
    return j;
  }

  const isOwner = (u?: string) => !!u && (o.owners ?? []).includes(u);
  let consentLogged = false;
  /** Chưa có id đồng ý trong máy (vd. quản trị lập bù cho lịch hẹn có từ trước): hỏi Flygo ID, tối đa 10 phút một lần mỗi người. */
  const looked = new Map<string, number>();
  async function lookupConsent(user: string): Promise<{ id: string; at: number } | null> {
    if (!o.consents || now() - (looked.get(user) ?? -Infinity) < 600_000) return null;
    looked.set(user, now());
    try {
      const r = await f(`${idUrl}/v1/agent/consents`, { headers: bot, signal: AbortSignal.timeout(10_000) });
      if (!r.ok) return null;
      const c = (((await r.json()) as any).consents ?? []).find((x: any) => x.user_id === user);
      if (!c?.id) return null;
      const v = { id: String(c.id), at: now() };
      o.consents.set(user, v);
      return v;
    } catch { return null; }
  }
  /** Chủ vừa nhắn (có biên nhận): lập / làm mới đồng ý chạy thay, tối đa 12 giờ một lần. Lỗi không ảnh hưởng lượt. */
  async function refreshConsent(user: string, rc: string) {
    if (!o.consents) return;
    const cur = o.consents.get(user);
    if (cur && now() - cur.at < CONSENT_REFRESH_MS) return;
    try {
      const r = await f(`${idUrl}/v1/agent/consents`, { method: "POST", headers: bot, body: JSON.stringify({ receipt: rc }), signal: AbortSignal.timeout(10_000) });
      const j = (await r.json().catch(() => ({}))) as any;
      if (r.ok && j.id) { o.consents.set(user, { id: j.id, at: now() }); return; }
      if (r.status === 404 && !consentLogged) { consentLogged = true; o.log("gateway: Flygo ID chưa có đồng ý chạy thay (bản cũ): lịch hẹn chạy với quyền riêng của agent"); return; }
      if (!consentLogged) { consentLogged = true; o.log(`gateway: không lập được đồng ý chạy thay: ${j.error ?? `HTTP ${r.status}`}`); }
    } catch (e: any) { if (!consentLogged) { consentLogged = true; o.log(`gateway: đồng ý chạy thay: ${e?.message ?? e}`); } }
  }

  async function fresh(run: Run): Promise<Ticket> {
    const t = run.ticket;
    if (t && t.exp - now() > REFRESH_BEFORE_MS) return t;
    run.pending ??= (async () => {
      let got: { token: string; expires_in: number };
      let viaReceipt = false;
      if (t?.receipt && t.exp > now()) got = await mint({ renew: t.token }), viaReceipt = true; // gia hạn tới 2 giờ sau tin
      else {
        const rc = await receipt(run.postId);
        if (rc) {
          got = await mint({ receipt: rc });
          viaReceipt = true;
          if (isOwner(run.assigner)) refreshConsent(run.assigner!, rc).catch(() => {});
        } else {
          // Lượt vắng mặt: làm thay chủ theo đồng ý chạy thay; không được thì vé riêng của agent (ít tool) và ghi lý do.
          const c = isOwner(run.assigner) ? (o.consents?.get(run.assigner!) ?? await lookupConsent(run.assigner!)) : null;
          if (c) {
            try {
              got = await mint({ consent: c.id, ...(run.schedule ? { schedule: run.schedule } : {}) });
              const next = { token: got.token, exp: now() + got.expires_in * 1000, receipt: false, via: "consent" as const };
              run.ticket = next;
              return next;
            } catch (e: any) {
              if (e?.status === 401 || e?.status === 403) o.consents?.set(run.assigner!, null);
              run.reduced = `không dùng được đồng ý chạy thay (${String(e?.message ?? e).slice(0, 120)})`;
            }
          } else run.reduced = !run.assigner ? "lượt không có người giao việc"
            : !isOwner(run.assigner) ? "người tạo lịch / giao việc không phải chủ bot"
            : "chủ bot chưa lập đồng ý chạy thay (nhắn bot một tin là tự lập)";
          got = await mint({});
        }
      }
      const next = { token: got.token, exp: now() + got.expires_in * 1000, receipt: viaReceipt, via: (viaReceipt ? "receipt" : "agent") as Ticket["via"] };
      run.ticket = next;
      return next;
    })().finally(() => { run.pending = undefined; });
    return run.pending;
  }

  async function rpc(run: Run, method: string, params: unknown, retried = false, timeoutMs = 120_000): Promise<any> {
    const t = await fresh(run);
    const r = await f(o.flygoId!.gatewayUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${t.token}`, "content-type": "application/json", Accept: "application/json, text/event-stream", ...(run.ctx ? { "X-Flygo-Context": run.ctx } : {}) },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (r.status === 401 && !retried) { run.ticket = undefined; return rpc(run, method, params, true, timeoutMs); }
    if (!r.ok) throw new GatewayError(`gateway: HTTP ${r.status}`);
    return r.json();
  }

  function note(key: string, run: Run, e: any) {
    const m = String(e?.message ?? e).slice(0, 200);
    run.failed = m;
    if (!run.logged) { run.logged = true; o.log(`gateway ${key}: ${m}`); }
  }

  return {
    enabled,
    /** Lượt mới theo tin kích hoạt (để lấy biên nhận). [props] của tin: trình duyệt được tag (props.flygo_browser) đi kèm
     * mọi lệnh gọi gateway của lượt trong header X-Flygo-Context (gợi ý cho app, không cấp quyền). */
    start(key: string, postId: string, props?: Record<string, any>, who?: { assigner?: string; schedule?: string }) {
      if (!enabled || !postId) return;
      const b = props?.flygo_browser;
      const browser = b && typeof b === "object" ? String(b.id ?? b.slug ?? "") || undefined : typeof b === "string" ? b : undefined;
      runs.set(key, { postId, assigner: who?.assigner, schedule: who?.schedule, ctx: Buffer.from(JSON.stringify({ run: key, ...(browser ? { browser } : {}) })).toString("base64url") });
    },
    /** Vé của lượt mang quyền ai: "receipt" (người vừa nhắn), "consent" (chủ, lượt vắng mặt), "agent" (riêng agent: ít tool) + lý do. */
    async mode(key: string): Promise<{ via: "receipt" | "consent" | "agent"; reduced?: string } | null> {
      const run = runs.get(key);
      if (!run) return null;
      try { const t = await fresh(run); return { via: t.via, ...(run.reduced ? { reduced: run.reduced } : {}) }; }
      catch (e: any) { note(key, run, e); return null; }
    },
    end(key: string) { runs.delete(key); },
    /** Tool của gateway cho lượt; lỗi thì trả rỗng (ghi log một lần). */
    async tools(key: string): Promise<GatewayTool[]> {
      const run = runs.get(key);
      if (!run) return [];
      for (let i = 0; i < 2; i++) {
        try {
          const j = await rpc(run, "tools/list", {}, false, 20_000);
          if (j.error) throw new GatewayError(j.error.message);
          const tools = (j.result?.tools ?? []) as GatewayTool[];
          if (tools.length) lastTools = tools;
          return tools;
        } catch (e) {
          if (i === 1) {
            note(key, run, e);
            if (lastTools.length) o.log(`gateway ${key}: dùng danh sách tool lần trước (${lastTools.length} tool)`);
            return lastTools;
          }
        }
      }
      return lastTools;
    },
    /** tools/call qua gateway. Trả result MCP; lỗi trả result isError để agent đọc được. */
    async call(key: string, name: string, args: unknown): Promise<any> {
      const run = runs.get(key);
      const err = (s: string) => ({ isError: true, content: [{ type: "text", text: s }] });
      if (!run) return err("Lượt này không dùng được Flygo Gateway (không có tin kích hoạt). Dùng công cụ ContextForge nếu có.");
      try {
        const j = await rpc(run, "tools/call", { name, arguments: args ?? {} });
        if (j.error) {
          const kind = j.error.data?.kind;
          if (kind === "forbidden") return err(`Không có quyền dùng tool ${name}: ${j.error.message}`);
          return err(`Gateway báo lỗi${kind ? ` (${kind})` : ""}: ${j.error.message}`);
        }
        return j.result;
      } catch (e: any) {
        note(key, run, e);
        return err(`Không gọi được Flygo Gateway (${String(e?.message ?? e).slice(0, 160)}). Vé có thể đã quá 2 giờ sau tin nhắn; dùng công cụ ContextForge nếu có, hoặc nhờ người dùng nhắn lại.`);
      }
    },
  };
}
export type GatewayRuns = ReturnType<typeof createGatewayRuns>;
