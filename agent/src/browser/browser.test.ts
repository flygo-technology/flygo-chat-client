import { test, expect } from "bun:test";
import WebSocket from "ws";
import { createBrowserModule, type CallCtx } from "./index.ts";
import { EXTENSION_IDS } from "./hub.ts";

const ORIGIN = `chrome-extension://${EXTENSION_IDS[0]}`;

/** Extension giả: chào hub, trả lời flygo.net.ruleList. */
async function fakeExt(port: number, name: string, extId: string) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ext`, { headers: { Origin: ORIGIN } });
  await new Promise((r, j) => { ws.once("open", r); ws.once("error", j); });
  ws.on("message", (d) => {
    const m = JSON.parse(String(d));
    if (m.id && m.method === "flygo.net.ruleList") ws.send(JSON.stringify({ id: m.id, result: { rules: [{ id: "r1", from: name }] } }));
  });
  ws.send(JSON.stringify({ t: "hello", ext_id: extId, ext_version: "0.1.0", info: { name, engine: "Chrome 150", os: "macOS" }, pairings: {} }));
  await new Promise((r) => setTimeout(r, 100));
  return ws;
}
const json = (r: any) => JSON.parse(String(r?.content?.[0]?.text ?? "{}"));

test("hub chỉ nhận extension của mình (Origin)", async () => {
  const m = createBrowserModule({ version: "t", log: () => {}, port: 47911 });
  expect(await m.start()).toBe(true);
  try {
    const bad = new WebSocket("ws://127.0.0.1:47911/ext", { headers: { Origin: "https://evil.example" } });
    bad.on("error", () => {});
    const ok = await new Promise((r) => { bad.once("open", () => r(true)); bad.once("error", () => r(false)); bad.once("close", () => r(false)); });
    expect(ok).toBe(false);
    const hello = await fetch("http://127.0.0.1:47911/flygo/hello", { headers: { Origin: "https://evil.example" } });
    expect(hello.status).toBe(404);
    const good = await fetch("http://127.0.0.1:47911/flygo/hello", { headers: { "X-Flygo-Bridge": EXTENSION_IDS[0] } });
    expect((await good.json()).role).toBe("browser-hub");
  } finally { await m.stop(); }
});

test("bridge: browser_list gộp trình duyệt máy khác; tag trình duyệt máy khác thì lệnh chuyển qua bridge", async () => {
  const A = createBrowserModule({ version: "t", log: () => {}, port: 47912 });
  const B = createBrowserModule({ version: "t", log: () => {}, port: 47913 });
  await A.start(); await B.start();
  A.setBridge({
    machines: async () => [{ id: "mB", name: "macmini", online: true, exports: ["browser"] }],
    call: (_m, _mod, tool, args, ctx) => B.callTool(tool, args, { ...ctx, caller: { ...ctx.caller, remote: true } }),
  });
  const e1 = await fakeExt(47912, "Chrome macbook", "extAAAAAAAA");
  const e2 = await fakeExt(47913, "Chrome mac mini", "extBBBBBBBB");
  try {
    const ctx: CallCtx = { caller: { botId: "bot1", name: "Coca" }, run: "r1" };
    const list = json(await A.callTool("browser_list", {}, ctx)).browsers;
    expect(list.map((b: any) => b.id)).toEqual(["extAAAAAAAA", "mB/extBBBBBBBB"]);
    expect(list[1].location.same_machine_as_agent).toBe(false);
    expect(list[1].machine).toBe("macmini");
    // Có 2 trình duyệt (1 tại máy, 1 máy khác): không tag thì dùng trình duyệt tại máy.
    expect(json(await A.callTool("browser_net_rule_list", {}, ctx)).rules[0].from).toBe("Chrome macbook");
    // Tag trình duyệt máy khác: chuyển qua bridge, và lượt này ghim trình duyệt đó.
    const ctx2: CallCtx = { caller: { botId: "bot1", name: "Coca" }, run: "r2", browser: "chrome-mac-mini" };
    expect(json(await A.callTool("browser_net_rule_list", {}, ctx2)).rules[0].from).toBe("Chrome mac mini");
    expect(json(await A.callTool("browser_net_rule_list", {}, { ...ctx2, browser: undefined })).rules[0].from).toBe("Chrome mac mini");
    // Bot khác giành trình duyệt ở máy kia: bận (khoá nằm ở máy có trình duyệt).
    const busy = await A.callTool("browser_select", { browser: "mB/extBBBBBBBB" }, { caller: { botId: "bot2", name: "Pepsi" }, run: "x" });
    expect(busy.isError).toBe(true);
    expect(busy.content[0].text).toContain("Coca");
    // Lệnh từ máy khác không gọi tiếp sang máy khác (không vòng).
    const remoteView = json(await B.callTool("browser_list", {}, { caller: { botId: "bot9", name: "X", remote: true } })).browsers;
    expect(remoteView.length).toBe(1);
  } finally { e1.close(); e2.close(); await A.stop(); await B.stop(); }
});
