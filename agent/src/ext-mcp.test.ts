import { afterAll, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ExtStore, probeMcp } from "./ext-mcp";

const server = Bun.serve({
  port: 0,
  async fetch(req) {
    const u = new URL(req.url);
    if (u.pathname === "/.well-known/oauth-protected-resource") return Response.json({ resource: `${u.origin}/oauth/mcp`, authorization_servers: [u.origin] });
    if (u.pathname === "/oauth/mcp") return new Response("", { status: 401, headers: { "www-authenticate": `Bearer resource_metadata="${u.origin}/.well-known/oauth-protected-resource"` } });
    if (u.pathname === "/key/mcp" && req.headers.get("authorization") !== "Bearer k") return new Response("", { status: 401, headers: { "www-authenticate": "Bearer" } });
    const body: any = await req.json();
    if (body.method === "initialize") return Response.json({ jsonrpc: "2.0", id: body.id, result: { serverInfo: { name: "demo" }, capabilities: {} } }, { headers: { "mcp-session-id": "s1" } });
    if (body.method === "tools/list") {
      // trả dạng SSE để thử cả hai kiểu
      const data = JSON.stringify({ jsonrpc: "2.0", id: body.id, result: { tools: [{ name: "search", description: "tìm" }, { name: "get" }] } });
      return new Response(`event: message\ndata: ${data}\n\n`, { headers: { "content-type": "text/event-stream" } });
    }
    return new Response("", { status: 202 });
  },
});
afterAll(() => server.stop());
const base = `http://localhost:${server.port}`;

test("không cần xác thực: liệt kê tool (SSE)", async () => {
  const r = await probeMcp(`${base}/open/mcp`);
  expect(r.ok).toBe(true);
  expect(r.auth).toBe("none");
  expect(r.serverName).toBe("demo");
  expect(r.tools?.map((t) => t.name)).toEqual(["search", "get"]);
});

test("401 + resource_metadata = OAuth2", async () => {
  const r = await probeMcp(`${base}/oauth/mcp`);
  expect(r.ok).toBe(false);
  expect(r.auth).toBe("oauth");
  expect(r.resourceMetadata).toContain("oauth-protected-resource");
});

test("401 không có OAuth = API key; đúng key thì kết nối được", async () => {
  expect((await probeMcp(`${base}/key/mcp`)).auth).toBe("oauth"); // máy chủ thử này công bố oauth-protected-resource ở gốc
  const ok = await probeMcp(`${base}/key/mcp`, { Authorization: "Bearer k" });
  expect(ok.ok).toBe(true);
  expect(ok.auth).toBe("key");
});

test("kho MCP: thêm / tắt / xoá, header cho engine, không lộ khoá ở view()", async () => {
  const s = new ExtStore(join(mkdtempSync(join(tmpdir(), "ext-")), "ext.json"));
  const e = s.upsert({ id: "", name: "Linear Tốt", url: `${base}/key/mcp`, enabled: true, headers: { Authorization: "Bearer k" } });
  expect(e.id).toBe("linear-tot");
  expect(Object.keys(await s.servers())).toEqual(["ext_linear_tot"]);
  expect(JSON.stringify(s.view())).not.toContain("Bearer k");
  s.setEnabled(e.id, false);
  expect(await s.servers()).toEqual({});
  expect(s.remove(e.id)).toBe(true);
});
