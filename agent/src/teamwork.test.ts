import crypto from "node:crypto";
import { describe, expect, test } from "bun:test";

import { claudePerms } from "./engines/claude";
import { codexTurnPerms } from "./engines/codex";
import { hookPlan } from "./engines/antigravity";
import { parseTwHeader, twBase, twDecide, TwProgress, TwVerifier, TW_BYPASS_NOTE } from "./teamwork";

// ---------------------------------------------------------------- khoá + token giả như máy chủ TeamWork ký
const kp = crypto.generateKeyPairSync("ed25519");
const jwk = { ...(kp.publicKey.export({ format: "jwk" }) as any), kid: "k1", alg: "EdDSA", use: "sig" };
const other = crypto.generateKeyPairSync("ed25519");
const b64u = (x: string | Buffer) => Buffer.from(x).toString("base64url");
function sign(claims: Record<string, unknown>, key = kp.privateKey, kid = "k1") {
  const h = b64u(JSON.stringify({ alg: "EdDSA", typ: "JWT", kid }));
  const p = b64u(JSON.stringify({ iss: "https://chat.example.com/__apps/teamwork", aud: "flygo-agent", typ: "teamwork-run", exp: Math.floor(Date.now() / 1000) + 600, ...claims }));
  return `${h}.${p}.${b64u(crypto.sign(null, Buffer.from(`${h}.${p}`), key))}`;
}
let jwksCalls = 0;
const jwksFetch = (async (url: string) => {
  jwksCalls++;
  expect(url).toBe("https://chat.example.com/__apps/teamwork/.well-known/jwks.json");
  return new Response(JSON.stringify({ keys: [jwk] }), { status: 200 });
}) as any;
const ISS = "https://chat.example.com/__apps/teamwork";
const verifier = () => new TwVerifier(`${twBase("https://chat.example.com/")}/.well-known/jwks.json`, "bot-1", jwksFetch, Date.now, ISS);

describe("TeamWork: nhận diện + token", () => {
  test("dòng đầu tin giao việc (chỉ gợi ý, bỏ qua url)", () => {
    expect(parseTwHeader("[teamwork task=ZLMCP-105 run=r_9 comment=c1 url=https://evil.example/t/x]\nViệc…")).toEqual({ key: "ZLMCP-105", run: "r_9", comment: "c1" });
    expect(parseTwHeader("[teamwork task=RA-1 run=abc]")).toEqual({ key: "RA-1", run: "abc" });
    expect(parseTwHeader("chào")).toBeNull();
    expect(twBase("https://chat.example.com/")).toBe("https://chat.example.com/__apps/teamwork");
  });

  test("token hợp lệ cho đúng bot; sai bot / hết hạn / sai aud / khoá lạ / hỏng → từ chối", async () => {
    const v = verifier();
    const ok = await v.verify(sign({ bot_id: "bot-1", run: "r1", bypass: true }));
    expect(ok?.run).toBe("r1");
    expect(await v.verify(sign({ bot_id: "bot-2", run: "r1", bypass: true }))).toBeNull();
    expect(await v.verify(sign({ bot_id: "bot-1", run: "r1", exp: Math.floor(Date.now() / 1000) - 5 }))).toBeNull();
    expect(await v.verify(sign({ bot_id: "bot-1", run: "r1", aud: "vn.flygo.teamwork" }))).toBeNull();
    expect(await v.verify(sign({ bot_id: "bot-1", run: "r1" }, other.privateKey))).toBeNull();
    expect(await v.verify(sign({ bot_id: "bot-1", run: "r1", iss: "https://evil.example/__apps/teamwork" }))).toBeNull();
    expect(await v.verify(sign({ bot_id: "bot-1", run: "r1", typ: "other" }))).toBeNull();
    expect(await v.verify("a.b.c")).toBeNull();
    expect(await v.verify(undefined)).toBeNull();
    expect(jwksCalls).toBeGreaterThan(0);
  });
});

describe("TeamWork: quyết định chế độ", () => {
  const claims = { run: "r1", bot_id: "bot-1", bypass: true };
  test("dòng đầu giả không có token → không đẩy tiến độ, không toàn quyền", () => {
    expect(twDecide({ claims: null, header: parseTwHeader("[teamwork task=RA-1 run=r1]"), posterIsOwner: true, killSwitch: true })).toBeNull();
  });
  test("đủ điều kiện → không cần duyệt + ghi chú 🔓", () => {
    expect(twDecide({ claims, header: null, posterIsOwner: true, killSwitch: true })).toEqual({ run: "r1", push: true, bypass: true, note: TW_BYPASS_NOTE });
  });
  test("người gửi không phải chủ bot → chế độ thường (vẫn đẩy tiến độ)", () => {
    const d = twDecide({ claims, header: null, posterIsOwner: false, killSwitch: true })!;
    expect(d.bypass).toBe(false);
    expect(d.push).toBe(true);
    expect(d.note).toContain("Chạy chế độ thường");
  });
  test("công tắc teamworkBypass tắt → chế độ thường", () => {
    expect(twDecide({ claims, header: null, posterIsOwner: true, killSwitch: false })!.bypass).toBe(false);
  });
  test("lượt kiểu project (khung AI dự án, không gắn việc) dùng như lượt khác", async () => {
    const v = verifier();
    const c = await v.verify(sign({ bot_id: "bot-1", run: "rp1", kind: "project", task: null, bypass: true }));
    expect(c?.kind).toBe("project");
    expect(twDecide({ claims: c, header: parseTwHeader("[teamwork project=RA run=rp1]"), posterIsOwner: true, killSwitch: true })).toMatchObject({ run: "rp1", push: true, bypass: true });
  });
  test("token không cho bypass → chế độ thường", () => {
    expect(twDecide({ claims: { ...claims, bypass: false }, header: null, posterIsOwner: true, killSwitch: true })!.bypass).toBe(false);
  });
});

describe("TeamWork: danh sách cấm vẫn giữ khi không cần duyệt", () => {
  const cfg: any = { claude: { deny: ["Bash(rm:*)", "Read(~/.ssh/**)"], fullAccess: false }, codex: { network: true } };
  test("Claude: bypassPermissions + deny (khác fullAccess)", () => {
    const p = claudePerms(cfg, { twBypass: true });
    expect(p.permMode).toBe("bypassPermissions");
    expect(p.permissions).toMatchObject({ defaultMode: "bypassPermissions" });
    const deny = (p.permissions as any).deny as string[];
    for (const r of ["Bash(rm:*)", "Read(~/.ssh/**)", "Read(~/.config/flygo-agent/**)", "Read(~/.codex/auth.json)", "Read(~/.aws/**)", "Bash(sudo:*)"]) expect(deny).toContain(r);
    // Chủ máy bật fullAccess: như trước, không deny.
    expect((claudePerms({ claude: { ...cfg.claude, fullAccess: true } } as any, { twBypass: true }).permissions as any).deny).toBeUndefined();
    // Lượt thường: deny của cấu hình.
    expect(claudePerms(cfg, {}).permissions).toEqual({ defaultMode: "default", deny: cfg.claude.deny });
  });
  test("Codex: không hỏi duyệt nhưng sandbox workspace-write (không toàn quyền đĩa)", () => {
    expect(codexTurnPerms(cfg, { twBypass: true, cwd: "/w" })).toEqual({ approvalPolicy: "never", approvalsReviewer: "user", sandboxPolicy: { type: "workspaceWrite", writableRoots: ["/w"], networkAccess: true } });
    expect(codexTurnPerms(cfg, { cwd: "/w" }).approvalPolicy).toBe("on-request");
  });
  test("agy: hook tự duyệt trừ lệnh xoá / sudo / đọc khoá", () => {
    expect(hookPlan("run_command", "teamwork", { CommandLine: "rm -rf ~/x" })).toMatchObject({ decision: "deny" });
    expect(hookPlan("run_command", "teamwork", { CommandLine: "sudo apt install x" })).toMatchObject({ decision: "deny" });
    expect(hookPlan("view_file", "teamwork", { AbsolutePath: "/home/u/.ssh/id_ed25519" })).toMatchObject({ decision: "deny" });
    expect(hookPlan("run_command", "teamwork", { CommandLine: "cat ~/.config/flygo-agent/config.json" })).toMatchObject({ decision: "deny" });
    expect(hookPlan("run_command", "teamwork", { CommandLine: "ls -la && npm test" })).toEqual({ decision: "auto_approve" });
  });
});

// ---------------------------------------------------------------- đẩy tiến độ
function fakeTimers() {
  let t = 1000;
  const q: { at: number; fn: () => void }[] = [];
  return {
    now: () => t,
    setTimer: (fn: () => void, ms: number) => { q.push({ at: t + ms, fn }); return q.length; },
    clearTimer: () => {},
    async advance(ms: number) {
      t += ms;
      for (let guard = 0; guard < 50; guard++) {
        const i = q.findIndex((x) => x.at <= t);
        if (i < 0) break;
        q.splice(i, 1)[0].fn();
        await new Promise((r) => setImmediate(r));
      }
    },
  };
}

describe("TeamWork: tiến độ", () => {
  test("gom nhiều bước thành ít lần đẩy (≤ 2 lần / giây), bản cuối final, đúng địa chỉ + header", async () => {
    const tm = fakeTimers();
    const bodies: any[] = [];
    const p = new TwProgress({
      base: "https://chat.example.com/__apps/teamwork", run: "r1", botToken: "BOT", serverUrl: "https://chat.example.com",
      ...tm,
      fetchFn: (async (url: string, init: any) => {
        expect(url).toBe("https://chat.example.com/__apps/teamwork/api/runs/r1/progress");
        expect(init.headers.Authorization).toBe("Bearer BOT");
        expect(init.headers["X-MM-Server"]).toBe("https://chat.example.com");
        bodies.push(JSON.parse(init.body));
        return new Response("{}", { status: 200 });
      }) as any,
    });
    for (let i = 0; i < 10; i++) p.step({ id: `s${i}`, kind: "command", title: `Chạy lệnh ${i}`, status: "running" });
    p.setText("Đang viết… token=abcd1234efgh5678ijkl");
    await tm.advance(10);
    expect(bodies).toHaveLength(1);
    expect(bodies[0].steps).toHaveLength(10);
    expect(bodies[0].steps[0]).toMatchObject({ kind: "tool", status: "running", title: "Chạy lệnh 0" });
    p.step({ id: "s0", kind: "command", title: "Chạy lệnh 0", status: "done" });
    p.step({ id: "t", kind: "thinking", title: "Suy nghĩ", status: "running" });
    await tm.advance(100);
    expect(bodies).toHaveLength(1); // chưa đủ 500 ms
    await tm.advance(500);
    expect(bodies).toHaveLength(2);
    expect(bodies[1].steps.find((s: any) => s.id === "t").kind).toBe("think");
    await p.finish("done", "Xong rồi.");
    expect(bodies.at(-1)).toMatchObject({ final: true, state: "done", text: "Xong rồi." });
    expect(bodies.map((b) => b.seq)).toEqual([1, 2, 3]);
    p.step({ id: "late", kind: "command", title: "sau khi xong", status: "done" });
    await tm.advance(1000);
    expect(bodies).toHaveLength(3); // xong rồi thì không đẩy nữa
  });

  test("TeamWork không với tới: thử lại có giới hạn, không bao giờ ném lỗi", async () => {
    const tm = fakeTimers();
    let calls = 0;
    const logs: string[] = [];
    const p = new TwProgress({
      base: "https://x/__apps/teamwork", run: "r2", botToken: "B", serverUrl: "https://x", retries: 2, ...tm, log: (s) => logs.push(s),
      fetchFn: (async () => { calls++; throw new Error("ECONNREFUSED"); }) as any,
    });
    p.step({ id: "a", kind: "command", title: "x", status: "running" });
    const f = p.finish("error");
    for (let i = 0; i < 10; i++) await tm.advance(2000);
    await f;
    expect(calls).toBe(3);
    expect(logs.join()).toContain("không đẩy được");
  });

  test("bí mật trong tiêu đề / chữ được che", async () => {
    const tm = fakeTimers();
    let body: any;
    const p = new TwProgress({ base: "https://x/__apps/teamwork", run: "r3", botToken: "B", serverUrl: "https://x", ...tm, fetchFn: (async (_u: string, i: any) => { body = JSON.parse(i.body); return new Response("{}"); }) as any });
    p.step({ id: "a", kind: "command", title: "curl -H 'Authorization: Bearer sk-ant-abcdefghijklmnopqrstuvwxyz123456'", status: "running" });
    await p.finish("done");
    expect(JSON.stringify(body)).not.toContain("sk-ant-abcdefghijklmnopqrstuvwxyz123456");
  });
});
