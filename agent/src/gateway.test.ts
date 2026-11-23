import { describe, expect, test } from "bun:test";
import { createGatewayRuns } from "./gateway";

const SERVER = "https://chat.test", ID = "https://chat.test/flygo-id", GW = "http://gw.test/mcp";

function setup(opts: { receipt?: string | null; gatewayDown?: boolean; expiresIn?: number; failLists?: number } = {}) {
  let failLists = opts.failLists ?? 0;
  let t = 1_000_000;
  const calls: { url: string; body?: any; auth?: string; ctx?: string }[] = [];
  const logs: string[] = [];
  let n = 0;
  const fetchImpl = (async (input: any, init?: any) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(init.body) : undefined;
    calls.push({ url, body, auth: init?.headers?.Authorization, ctx: init?.headers?.["X-Flygo-Context"] });
    if (url.startsWith(`${SERVER}/plugins/vn.flygo.sso/flygo/receipts/`)) {
      return Response.json({ post_id: "p1", receipts: opts.receipt ? [{ bot_id: "b1", receipt: opts.receipt }] : [] });
    }
    if (url === `${ID}/v1/token/agent`) return Response.json({ token: `tk${++n}`, expires_in: opts.expiresIn ?? 600, scope: [] });
    if (url === GW) {
      if (opts.gatewayDown) return new Response("down", { status: 502 });
      if (body.method === "tools/list" && failLists-- > 0) throw new Error("The operation timed out.");
      if (body.method === "tools/list") return Response.json({ jsonrpc: "2.0", id: 1, result: { tools: [{ name: "vn_x__read", inputSchema: { type: "object" }, _meta: { "vn.flygo/kind": "read" } }] } });
      if (body.params.name === "vn_x__nope") return Response.json({ jsonrpc: "2.0", id: 1, error: { code: -32003, message: "no", data: { kind: "forbidden" } } });
      return Response.json({ jsonrpc: "2.0", id: 1, result: { content: [{ type: "text", text: "ok" }] } });
    }
    return new Response("nf", { status: 404 });
  }) as typeof fetch;
  const gw = createGatewayRuns({ flygoId: { url: ID, gatewayUrl: GW }, serverUrl: SERVER, botToken: "bot-tok", log: (s) => logs.push(s), fetchImpl, now: () => t });
  return { gw, calls, logs, advance: (ms: number) => { t += ms; }, failNext: (k: number) => { failLists = k; } };
}

describe("gateway runs", () => {
  test("tools/list lỗi một lần: thử lại; lỗi hẳn: dùng danh sách lần trước (không để agent tưởng mất tool)", async () => {
    const { gw, failNext, logs } = setup({ receipt: "rc.jwt", failLists: 1 });
    gw.start("r1", "p1");
    expect((await gw.tools("r1")).map((x) => x.name)).toEqual(["vn_x__read"]);
    gw.start("r2", "p2");
    failNext(2);
    expect((await gw.tools("r2")).map((x) => x.name)).toEqual(["vn_x__read"]);
    expect(logs.some((l) => l.includes("dùng danh sách tool lần trước"))).toBe(true);
  });

  test("không có flygoId thì tắt hẳn", async () => {
    const gw = createGatewayRuns({ serverUrl: SERVER, botToken: "x", log: () => {}, fetchImpl: (async () => { throw new Error("không được gọi"); }) as any });
    gw.start("r1", "p1");
    expect(gw.enabled).toBe(false);
    expect(await gw.tools("r1")).toEqual([]);
  });

  test("có biên nhận: xin vé bằng receipt, gửi vé tới gateway, vé không lộ ra tool", async () => {
    const { gw, calls } = setup({ receipt: "rc.jwt" });
    gw.start("r1", "p1");
    const tools = await gw.tools("r1");
    expect(tools.map((x) => x.name)).toEqual(["vn_x__read"]);
    const mint = calls.find((c) => c.url.endsWith("/v1/token/agent"))!;
    expect(mint.body).toEqual({ audience: "vn.flygo.gateway", receipt: "rc.jwt" });
    expect(mint.auth).toBe("Bearer bot-tok");
    expect(calls.find((c) => c.url === GW)!.auth).toBe("Bearer tk1");
    expect(JSON.stringify(tools)).not.toContain("tk1");
  });

  test("trình duyệt được tag (props.flygo_browser) đi kèm mọi lệnh gọi gateway của lượt (X-Flygo-Context)", async () => {
    const { gw, calls } = setup({ receipt: "rc.jwt" });
    gw.start("r1", "p1", { flygo_browser: { id: "br1", slug: "chrome-van-phong", name: "Chrome văn phòng" } });
    await gw.tools("r1");
    await gw.call("r1", "vn_x__read", {});
    const ctx = calls.filter((c) => c.url === GW).map((c) => JSON.parse(Buffer.from(String(c.ctx), "base64url").toString()));
    expect(ctx).toEqual([{ run: "r1", browser: "br1" }, { run: "r1", browser: "br1" }]);
    gw.start("r2", "p2");
    await gw.tools("r2");
    expect(JSON.parse(Buffer.from(String(calls.filter((c) => c.url === GW).at(-1)!.ctx), "base64url").toString())).toEqual({ run: "r2" });
  });

  test("gần hết hạn thì gia hạn bằng renew; hết hạn hẳn thì xin lại bằng biên nhận", async () => {
    const { gw, calls, advance } = setup({ receipt: "rc.jwt" });
    gw.start("r1", "p1");
    await gw.tools("r1");
    advance(500_000); // còn 100 s
    await gw.call("r1", "vn_x__read", {});
    const mints = calls.filter((c) => c.url.endsWith("/v1/token/agent")).map((c) => c.body);
    expect(mints[1]).toEqual({ audience: "vn.flygo.gateway", renew: "tk1" });
    advance(700_000); // tk2 đã hết hạn
    await gw.call("r1", "vn_x__read", {});
    expect(calls.filter((c) => c.url.endsWith("/v1/token/agent")).at(-1)!.body).toEqual({ audience: "vn.flygo.gateway", receipt: "rc.jwt" });
  });

  test("không có biên nhận: vé của riêng agent", async () => {
    const { gw, calls } = setup({ receipt: null });
    gw.start("r1", "p1");
    await gw.tools("r1");
    expect(calls.find((c) => c.url.endsWith("/v1/token/agent"))!.body).toEqual({ audience: "vn.flygo.gateway" });
  });

  test("gateway lỗi: tools/list rỗng, log một lần, call trả isError", async () => {
    const { gw, logs } = setup({ receipt: "rc", gatewayDown: true });
    gw.start("r1", "p1");
    expect(await gw.tools("r1")).toEqual([]);
    expect(await gw.tools("r1")).toEqual([]);
    expect(logs.length).toBe(1);
    expect(logs[0]).not.toContain("tk");
    const r = await gw.call("r1", "vn_x__read", {});
    expect(r.isError).toBe(true);
  });

  test("forbidden trả lời đọc được; lượt đã xong thì không gọi", async () => {
    const { gw } = setup({ receipt: "rc" });
    gw.start("r1", "p1");
    expect((await gw.call("r1", "vn_x__nope", {})).content[0].text).toContain("Không có quyền");
    gw.end("r1");
    expect((await gw.call("r1", "vn_x__read", {})).isError).toBe(true);
  });
});

describe("đồng ý chạy thay (lượt vắng mặt có đủ tool)", () => {
  function setup2(o: { receipt?: string | null; consentStatus?: number; tokenFail?: number; listed?: boolean; receipts401?: boolean } = {}) {
    const calls: { url: string; body?: any }[] = [];
    const logs: string[] = [];
    const store = new Map<string, { id: string; at: number }>();
    let t = 5_000_000;
    const fetchImpl = (async (input: any, init?: any) => {
      const url = String(input), body = init?.body ? JSON.parse(init.body) : undefined;
      calls.push({ url, body });
      if (url.startsWith(`${SERVER}/plugins/vn.flygo.sso/flygo/receipts/`)) return o.receipts401 ? Response.json({ error: "no" }, { status: 401 }) : Response.json({ receipts: o.receipt ? [{ bot_id: "b1", receipt: o.receipt }] : [] });
      if (url === `${ID}/v1/agent/consents` && !body) return Response.json({ consents: o.listed ? [{ id: "ac_bu", user_id: "owner" }] : [] });
      if (url === `${ID}/v1/agent/consents`) return o.consentStatus && o.consentStatus !== 200 ? Response.json({ error: "x" }, { status: o.consentStatus }) : Response.json({ id: "ac_1" });
      if (url === `${ID}/v1/token/agent`) {
        if (body.consent && o.tokenFail) return Response.json({ error: "thu hồi" }, { status: o.tokenFail });
        return Response.json({ token: "tk", expires_in: 600, scope: [] });
      }
      if (url === GW) return Response.json({ jsonrpc: "2.0", id: 1, result: { tools: [] } });
      return new Response("nf", { status: 404 });
    }) as typeof fetch;
    const gw = createGatewayRuns({ flygoId: { url: ID, gatewayUrl: GW }, serverUrl: SERVER, botToken: "bot-tok", log: (s) => logs.push(s), fetchImpl, now: () => t,
      owners: ["owner"], consents: { get: (u) => store.get(u) ?? null, set: (u, v) => { v ? store.set(u, v) : store.delete(u); } } });
    return { gw, calls, logs, store, advance: (ms: number) => { t += ms; } };
  }
  const mints = (calls: any[]) => calls.filter((c) => c.url.endsWith("/v1/token/agent")).map((c) => c.body);

  test("chủ nhắn (có biên nhận): tự lập đồng ý; lượt lịch hẹn sau đó xin vé bằng đồng ý, kèm id lịch", async () => {
    const a = setup2({ receipt: "rc" });
    a.gw.start("r1", "p1", {}, { assigner: "owner" });
    expect((await a.gw.mode("r1"))!.via).toBe("receipt");
    await Bun.sleep(5);
    expect(a.store.get("owner")!.id).toBe("ac_1");
    // lượt vắng mặt (không biên nhận)
    const b = setup2({ receipt: null });
    b.store.set("owner", { id: "ac_1", at: 0 });
    b.gw.start("r2", "sched-post", {}, { assigner: "owner", schedule: "s1" });
    expect(await b.gw.mode("r2")).toEqual({ via: "consent" });
    expect(mints(b.calls)).toEqual([{ audience: "vn.flygo.gateway", consent: "ac_1", schedule: "s1" }]);
  });

  test("làm mới đồng ý tối đa 12 giờ một lần; lượt của người không phải chủ thì không lập", async () => {
    const a = setup2({ receipt: "rc" });
    a.gw.start("r1", "p1", {}, { assigner: "owner" }); await a.gw.mode("r1"); await Bun.sleep(5);
    a.gw.start("r2", "p2", {}, { assigner: "owner" }); await a.gw.mode("r2"); await Bun.sleep(5);
    expect(a.calls.filter((c) => c.url.endsWith("/v1/agent/consents"))).toHaveLength(1);
    a.advance(13 * 3600_000);
    a.gw.start("r3", "p3", {}, { assigner: "owner" }); await a.gw.mode("r3"); await Bun.sleep(5);
    expect(a.calls.filter((c) => c.url.endsWith("/v1/agent/consents"))).toHaveLength(2);
    const b = setup2({ receipt: "rc" });
    b.gw.start("r1", "p1", {}, { assigner: "guest" }); await b.gw.mode("r1"); await Bun.sleep(5);
    expect(b.calls.filter((c) => c.url.endsWith("/v1/agent/consents"))).toHaveLength(0);
  });

  test("plugin từ chối biên nhận (401, bot chưa có trong ReceiptBots): vẫn dùng đồng ý chạy thay", async () => {
    const a = setup2({ receipt: null, listed: true, receipts401: true });
    a.gw.start("r1", "p", {}, { assigner: "owner" });
    expect(await a.gw.mode("r1")).toEqual({ via: "consent" });
    expect(a.logs.join()).toContain("ReceiptBots");
  });

  test("chưa có id trong máy nhưng Flygo ID có (quản trị lập bù): hỏi rồi dùng", async () => {
    const a = setup2({ receipt: null, listed: true });
    a.gw.start("r1", "p", {}, { assigner: "owner", schedule: "s9" });
    expect(await a.gw.mode("r1")).toEqual({ via: "consent" });
    expect(a.store.get("owner")!.id).toBe("ac_bu");
  });

  test("không có đồng ý / không phải chủ / đồng ý bị thu hồi: vé riêng của agent và ghi lý do", async () => {
    const a = setup2({ receipt: null });
    a.gw.start("r1", "p", {}, { assigner: "owner" });
    expect((await a.gw.mode("r1"))!.reduced).toContain("chưa lập đồng ý");
    a.gw.start("r2", "p", {}, { assigner: "guest" });
    expect((await a.gw.mode("r2"))!.reduced).toContain("không phải chủ bot");
    const b = setup2({ receipt: null, tokenFail: 403 });
    b.store.set("owner", { id: "ac_1", at: 0 });
    b.gw.start("r3", "p", {}, { assigner: "owner" });
    const m = await b.gw.mode("r3");
    expect(m!.via).toBe("agent");
    expect(m!.reduced).toContain("không dùng được đồng ý");
    expect(b.store.has("owner")).toBe(false); // bị thu hồi: bỏ id, chủ nhắn lại là lập mới
    expect(mints(b.calls).at(-1)).toEqual({ audience: "vn.flygo.gateway" });
  });
});
