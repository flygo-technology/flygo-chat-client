import { afterAll, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { liveCap, livePool, liveTurn, lruVictim, withResume, type Prep } from "./claude-live";
import { newTurnState, type TurnState } from "./claude";

// CLI claude giả: stream-json vào / ra; ghi PID + sự kiện vào tệp log để kiểm. CRASH_FIRST=1: lần chạy đầu thoát ngay khi nhận tin.
const dir = mkdtempSync(join(tmpdir(), "live-"));
const logf = join(dir, "log.txt");
const fake = join(dir, "claude");
writeFileSync(fake, `#!${process.execPath}
const log = (s) => require("fs").appendFileSync(${JSON.stringify(logf)}, s + "\\n");
const resume = process.argv.includes("--resume") ? process.argv[process.argv.indexOf("--resume") + 1] : "";
log("start pid=" + process.pid + " resume=" + resume);
const crashMark = ${JSON.stringify(join(dir, "crashed"))};
let sid = resume || "sess-" + process.pid, inited = false;
const out = (o) => process.stdout.write(JSON.stringify(o) + "\\n");
let buf = "";
process.stdin.on("data", (d) => {
  buf += d; let i;
  while ((i = buf.indexOf("\\n")) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1); if (!line.trim()) continue;
    const m = JSON.parse(line);
    if (m.type === "control_request") { log("control " + m.request.subtype + (m.request.model ? " " + m.request.model : "")); out({ type: "control_response", response: { subtype: "success", request_id: m.request_id } }); if (m.request.subtype === "interrupt") out({ type: "result", result: "", is_error: true, session_id: sid }); continue; }
    if (process.env.CRASH_FIRST === "1" && !require("fs").existsSync(crashMark)) { require("fs").writeFileSync(crashMark, "1"); process.exit(3); }
    const text = m.message.content[0].text;
    log("turn " + text);
    if (!inited) { inited = true; out({ type: "system", subtype: "init", session_id: sid }); }
    if (text === "slow") { setTimeout(() => {}, 60000); out({ type: "assistant", message: { id: "a" + Date.now(), content: [{ type: "text", text: "đang làm" }] } }); continue; }
    out({ type: "assistant", message: { id: "m" + Date.now(), content: [{ type: "text", text: "đã nhận: " + text }] } });
    out({ type: "result", result: "xong " + text, session_id: sid, usage: {} });
  }
});
process.stdin.on("end", () => process.exit(0));
`);
chmodSync(fake, 0o755);

const engine = { onEvent(ev: any, st: TurnState) { if (ev.type === "system" && ev.subtype === "init") st.sessionId = ev.session_id; if (ev.type === "result") { st.final = ev.result ?? ""; st.isError = !!ev.is_error; if (ev.session_id) st.sessionId = ev.session_id; } } };
const hooks: any = { step() {}, text() {}, session() {}, steerable() {} };
const prep = (o: Partial<Prep> = {}): Prep => ({ args: [fake, "-p", "--input-format", "stream-json"], env: { ...process.env, ...(o.env ?? {}) } as any, mcpFile: join(dir, `mcp-${Math.random()}.json`), streamIn: true, replay: false, sig: "A", model: "sonnet", permMode: "default", bin: fake, cwd: dir, ...o });
const input = (o: any = {}) => ({ prompt: "chào", cwd: dir, persona: "", title: "t", mcpEnv: { SCOPE: "ch:1" }, ...o }) as any;
const opts = { botKey: "bot1" };
const pids = () => readFileSync(logf, "utf8").split("\n").filter((l) => l.startsWith("start")).length;
afterAll(() => { for (const s of livePool.values()) s.close("test"); livePool.clear(); });

test("hai lượt dùng chung một tiến trình (không spawn lại); đổi model bằng set_model tại chỗ", async () => {
  const r1 = await liveTurn(engine, prep(), input({ prompt: "một" }), hooks, new AbortController().signal, opts);
  expect(r1.text).toBe("xong một");
  const r2 = await liveTurn(engine, prep({ model: "opus" }), input({ prompt: "hai", sessionId: r1.sessionId }), hooks, new AbortController().signal, opts);
  expect(r2.text).toBe("xong hai");
  expect(pids()).toBe(1);
  expect(readFileSync(logf, "utf8")).toContain("control set_model opus");
});

test("cấu hình đổi (sig) → mở lại tiến trình với --resume", async () => {
  const s = [...livePool.values()][0];
  const r = await liveTurn(engine, prep({ sig: "B", args: withResume([fake, "-p"], s.sessionId) }), input({ prompt: "ba", sessionId: s.sessionId }), hooks, new AbortController().signal, opts);
  expect(r.text).toBe("xong ba");
  expect(pids()).toBe(2);
  expect(readFileSync(logf, "utf8")).toContain(`resume=${s.sessionId}`);
});

test("🛑 dừng lượt = interrupt, tiến trình còn sống cho lượt sau", async () => {
  const ac = new AbortController();
  const p = liveTurn(engine, prep({ sig: "B" }), input({ prompt: "slow", sessionId: [...livePool.values()][0].sessionId }), hooks, ac.signal, opts);
  await Bun.sleep(150); ac.abort();
  await expect(p).rejects.toThrow(/đã dừng/);
  expect(readFileSync(logf, "utf8")).toContain("control interrupt");
  const r = await liveTurn(engine, prep({ sig: "B" }), input({ prompt: "bốn", sessionId: [...livePool.values()][0].sessionId }), hooks, new AbortController().signal, opts);
  expect(r.text).toBe("xong bốn");
  expect(pids()).toBe(2);
});

test("tiến trình chết trước khi trả lời → chạy lại lượt một lần (--resume)", async () => {
  for (const s of livePool.values()) s.close("t"); livePool.clear(); await Bun.sleep(100);
  const r = await liveTurn(engine, prep({ env: { CRASH_FIRST: "1" } as any, sig: "C" }), input({ prompt: "năm", mcpEnv: { SCOPE: "ch:2" } }), hooks, new AbortController().signal, { botKey: "bot1" });
  expect(r.text).toBe("xong năm");
  expect(existsSync(join(dir, "crashed"))).toBe(true);
});

test("trần số phiên theo RAM và chọn phiên rảnh lâu nhất để đóng", () => {
  expect(liveCap(16 * 1024 ** 3)).toBe(8);
  expect(liveCap(4 * 1024 ** 3)).toBe(2);
  expect(liveCap(128 * 1024 ** 3)).toBe(12);
  const mk = (k: string, t: number, busy = false) => ({ key: k, lastUsed: t, busy, dead: false }) as any;
  expect(lruVictim([mk("a", 5), mk("b", 1), mk("c", 0, true)], 3, 3)?.key).toBe("b");
  expect(lruVictim([mk("a", 5)], 3, 1)).toBeNull();
  expect(withResume(["x", "--resume", "old", "--fork-session", "y"], "new")).toEqual(["x", "y", "--resume", "new"]);
});
