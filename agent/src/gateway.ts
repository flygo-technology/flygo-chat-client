// Flygo Gateway (MCP) cho từng lượt: runner xin vé Flygo ID mang danh người nhờ (biên nhận của plugin vn.flygo.sso),
// rồi chuyển tools/list và tools/call của MCP flygo_chat tới gateway. Vé chỉ nằm trong bộ nhớ runner: không vào argv, env hay log.
//   - Có biên nhận (người nhắn riêng hoặc @nhắc bot): vé mang quyền của người đó; gia hạn bằng {renew} tới 2 giờ sau tin.
//   - Không có biên nhận: vé của riêng agent (quyền gán thẳng cho agent).
//   - Lỗi gateway không làm hỏng lượt: tools/list bỏ tool của gateway, chỉ ghi log một lần mỗi lượt.
// Không có cfg.flygoId thì không làm gì (như cũ).

export interface FlygoIdConfig {
  url: string;        // Flygo ID công khai của máy chủ chat, vd https://chat.flygo.vn/flygo-id
  gatewayUrl: string; // Flygo Gateway /mcp, vd http://gateway.example:18789/mcp
}

interface Ticket { token: string; exp: number; receipt: boolean }
interface Run { postId: string; ticket?: Ticket; pending?: Promise<Ticket>; failed?: string; logged?: boolean }

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
}) {
  const f = o.fetchImpl ?? fetch;
  const now = o.now ?? Date.now;
  const runs = new Map<string, Run>();
  const server = o.serverUrl.replace(/\/+$/, "");
  const enabled = !!(o.flygoId?.url && o.flygoId?.gatewayUrl);
  const idUrl = (o.flygoId?.url ?? "").replace(/\/+$/, "");
  const bot = { Authorization: `Bearer ${o.botToken}`, "X-MM-Server": server, "content-type": "application/json" };

  async function receipt(postId: string): Promise<string | null> {
    const r = await f(`${server}/plugins/vn.flygo.sso/flygo/receipts/${encodeURIComponent(postId)}`, { headers: { Authorization: `Bearer ${o.botToken}` }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 404) return null; // plugin chưa cài / bản cũ
    if (!r.ok) throw new GatewayError(`biên nhận: HTTP ${r.status}`);
    const j = (await r.json()) as { receipts?: { receipt: string }[] };
    return j.receipts?.[0]?.receipt ?? null;
  }

  async function mint(body: Record<string, unknown>): Promise<{ token: string; expires_in: number }> {
    const r = await f(`${idUrl}/v1/token/agent`, { method: "POST", headers: bot, body: JSON.stringify({ audience: AUDIENCE, ...body }), signal: AbortSignal.timeout(10_000) });
    const j = (await r.json().catch(() => ({}))) as any;
    if (!r.ok || !j.token) throw new GatewayError(`Flygo ID: ${j.error ?? `HTTP ${r.status}`}`);
    return j;
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
        got = await mint(rc ? { receipt: rc } : {});
        viaReceipt = !!rc;
      }
      const next = { token: got.token, exp: now() + got.expires_in * 1000, receipt: viaReceipt };
      run.ticket = next;
      return next;
    })().finally(() => { run.pending = undefined; });
    return run.pending;
  }

  async function rpc(run: Run, method: string, params: unknown, retried = false): Promise<any> {
    const t = await fresh(run);
    const r = await f(o.flygoId!.gatewayUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${t.token}`, "content-type": "application/json", Accept: "application/json, text/event-stream" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: AbortSignal.timeout(120_000),
    });
    if (r.status === 401 && !retried) { run.ticket = undefined; return rpc(run, method, params, true); }
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
    /** Lượt mới theo tin kích hoạt (để lấy biên nhận). */
    start(key: string, postId: string) { if (enabled && postId) runs.set(key, { postId }); },
    end(key: string) { runs.delete(key); },
    /** Tool của gateway cho lượt; lỗi thì trả rỗng (ghi log một lần). */
    async tools(key: string): Promise<GatewayTool[]> {
      const run = runs.get(key);
      if (!run) return [];
      try {
        const j = await rpc(run, "tools/list", {});
        if (j.error) throw new GatewayError(j.error.message);
        return (j.result?.tools ?? []) as GatewayTool[];
      } catch (e) { note(key, run, e); return []; }
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
