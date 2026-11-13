import { describe, expect, test } from "bun:test";
import { createGatewayRuns } from "./gateway";

const SERVER = "https://chat.test", ID = "https://chat.test/flygo-id", GW = "http://gw.test/mcp";

function setup(opts: { receipt?: string | null; gatewayDown?: boolean; expiresIn?: number } = {}) {
  let t = 1_000_000;
  const calls: { url: string; body?: any; auth?: string }[] = [];
  const logs: string[] = [];
  let n = 0;
  const fetchImpl = (async (input: any, init?: any) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(init.body) : undefined;
    calls.push({ url, body, auth: init?.headers?.Authorization });
    if (url.startsWith(`${SERVER}/plugins/vn.flygo.sso/flygo/receipts/`)) {
      return Response.json({ post_id: "p1", receipts: opts.receipt ? [{ bot_id: "b1", receipt: opts.receipt }] : [] });
    }
    if (url === `${ID}/v1/token/agent`) return Response.json({ token: `tk${++n}`, expires_in: opts.expiresIn ?? 600, scope: [] });
    if (url === GW) {
      if (opts.gatewayDown) return new Response("down", { status: 502 });
      if (body.method === "tools/list") return Response.json({ jsonrpc: "2.0", id: 1, result: { tools: [{ name: "vn_x__read", inputSchema: { type: "object" }, _meta: { "vn.flygo/kind": "read" } }] } });
      if (body.params.name === "vn_x__nope") return Response.json({ jsonrpc: "2.0", id: 1, error: { code: -32003, message: "no", data: { kind: "forbidden" } } });
      return Response.json({ jsonrpc: "2.0", id: 1, result: { content: [{ type: "text", text: "ok" }] } });
    }
    return new Response("nf", { status: 404 });
  }) as typeof fetch;
  const gw = createGatewayRuns({ flygoId: { url: ID, gatewayUrl: GW }, serverUrl: SERVER, botToken: "bot-tok", log: (s) => logs.push(s), fetchImpl, now: () => t });
  return { gw, calls, logs, advance: (ms: number) => { t += ms; } };
}

describe("gateway runs", () => {
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
