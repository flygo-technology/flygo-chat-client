import { expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { BgTracker, appendTail, detectLaunch, isDetachedLaunch, outputFileOf, redact, sshOf, IDLE_DONE_MS } from "./bg-tasks";

test("tìm tệp output trong lệnh", () => {
  expect(outputFileOf("nohup ./dial.sh > /tmp/dial.log 2>&1 &")).toBe("/tmp/dial.log");
  expect(outputFileOf("(./run.sh >> run.log 2>&1 &)")).toBe("run.log");
  expect(outputFileOf("./build.sh 2>&1 | tee -a out/build.txt &")).toBe("out/build.txt");
  expect(outputFileOf("nohup python3 worker.py &")).toBe("nohup.out");
  expect(outputFileOf("setsid pppd call x --logfile /var/log/ppp.log &")).toBe("/var/log/ppp.log");
  expect(outputFileOf("curl -o /tmp/x.bin https://a &")).toBe("/tmp/x.bin");
  expect(outputFileOf("./x > /dev/null 2>&1 &")).toBeNull();
  expect(outputFileOf("ls -la")).toBeNull();
  expect(outputFileOf('nohup ./x > "$L" 2>&1 &')).toBeNull(); // biến shell: không đoán
  expect(outputFileOf("nohup ./x > $(date).log &")).toBeNull();
});

test("nhận ra lệnh tách nền, bỏ qua && / 2>&1", () => {
  expect(isDetachedLaunch("nohup ./a.sh > a.log 2>&1 &")).toBe(true);
  expect(isDetachedLaunch("(./a.sh > a.log &)")).toBe(true);
  expect(isDetachedLaunch("./a.sh & echo started")).toBe(true); // "& echo" ở giữa: vẫn là chạy nền
  expect(isDetachedLaunch("echo 'a & b'")).toBe(false);
  expect(isDetachedLaunch("make && make test 2>&1 | tail")).toBe(false);
  expect(isDetachedLaunch("echo ok")).toBe(false);
});

test("lệnh ssh: máy + lệnh bên trong", () => {
  expect(sshOf("ssh -o BatchMode=yes flygo-02 'nohup /opt/dial.sh > /tmp/d.log 2>&1 &'")).toEqual({ host: "flygo-02", inner: "nohup /opt/dial.sh > /tmp/d.log 2>&1 &" });
  expect(sshOf("ls /tmp")).toBeNull();
});

test("detectLaunch: Bash run_in_background lấy tệp tasks/*.output trong kết quả; ssh tách nền theo máy trong lệnh", () => {
  const a = detectLaunch("Bash", { command: "sleep 100; echo hi", run_in_background: true }, "Command running in background with ID: b1. Output is being written to: /tmp/claude-1000/x/tasks/b1.output");
  expect(a).toEqual({ kind: "bash_bg", command: "sleep 100; echo hi", host: "local", file: "/tmp/claude-1000/x/tasks/b1.output" });
  const b = detectLaunch("Bash", { command: "ssh flygo-02 'nohup /opt/autodial.sh > /tmp/autodial.log 2>&1 &'" }, "");
  expect(b).toMatchObject({ kind: "detached", host: "flygo-02", file: "/tmp/autodial.log" });
  expect(detectLaunch("Bash", { command: "ls -la" }, "")).toBeNull();
  expect(detectLaunch("Read", { file_path: "/x" }, "")).toBeNull();
});

test("che bí mật trong output", () => {
  const s = redact("password=hunter22 token: abcdef123 Authorization: Bearer abcdefghijklmnop sk-ant-api03-XYZXYZXYZ wpa_key=secretpsk -p S3cret!");
  for (const x of ["hunter22", "abcdef123", "abcdefghijklmnop", "sk-ant-api03-XYZXYZXYZ", "secretpsk", "S3cret!"]) expect(s).not.toContain(x);
});

test("đuôi output: giữ ≤ 60 dòng / 4 KB", () => {
  const r = appendTail("", Array.from({ length: 200 }, (_, i) => `dòng ${i}`).join("\n") + "\n");
  expect(r.tail.split("\n").length).toBeLessThanOrEqual(60);
  expect(r.tail).toContain("dòng 199");
  expect(r.truncated).toBe(true);
  expect(Buffer.byteLength(appendTail("", "x".repeat(300) + "\n").tail)).toBeLessThanOrEqual(4096);
});

test("theo tệp trên máy này: thêm dòng thì cập nhật; lượt xong + tệp đứng yên thì xong", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bg-"));
  const f = path.join(dir, "dial.log");
  fs.writeFileSync(f, "bắt đầu\n");
  let t = 1_000_000, changes = 0;
  const tr = new BgTracker(dir, () => changes++, undefined, () => t, 20);
  const task = tr.add({ kind: "detached", command: "nohup ./dial.sh > dial.log 2>&1 &", host: "local", file: "dial.log" })!;
  expect(task.output_file).toBe(f);
  await Bun.sleep(60);
  fs.appendFileSync(f, "ppp331 up 1.2.3.4\npassword=abc123\n");
  await Bun.sleep(80);
  expect(task.tail).toContain("ppp331 up");
  expect(task.tail).not.toContain("abc123");
  expect(task.status).toBe("running");
  tr.endTurn();
  expect(task.status).toBe("running"); // tách nền: theo tiếp sau lượt
  t += IDLE_DONE_MS + 1;
  await Bun.sleep(60);
  expect(task.status).toBe("done");
  expect(task.note).toContain("không rõ mã thoát");
  expect(changes).toBeGreaterThan(2);
  fs.rmSync(dir, { recursive: true });
});

test("tác vụ nền của Claude Code dừng cùng lượt; ssh dùng tail -F qua đúng máy", async () => {
  const calls: string[][] = [];
  const enc = new TextEncoder();
  const spawn = (c: string[]) => { calls.push(c); return { stdout: new ReadableStream<Uint8Array>({ start(ctl) { ctl.enqueue(enc.encode("dòng từ xa\n")); } }), kill() {}, exited: Promise.resolve(0) }; };
  const tr = new BgTracker("/tmp", () => {}, spawn as any, Date.now, 20);
  const a = tr.add({ kind: "bash_bg", command: "sleep 5", host: "local", file: "/nonexistent/tasks/b1.output" })!;
  const b = tr.add({ kind: "detached", command: "ssh flygo-02 'nohup x > /tmp/x.log &'", host: "flygo-02", file: "/tmp/x.log" })!;
  await Bun.sleep(30);
  expect(calls[0].slice(0, 1)).toEqual(["ssh"]);
  expect(calls[0]).toContain("flygo-02");
  expect(calls[0].at(-1)).toContain("tail -n 60 -F -- '/tmp/x.log'");
  expect(b.tail).toContain("dòng từ xa");
  tr.endTurn();
  expect(a.status).toBe("killed");
  tr.stopAll();
  expect(b.status).toBe("killed");
});

// ---- Dừng tác vụ nền (nút Dừng trên thẻ) ----
import { parseLsofWriters as _parseLsof, BgTracker as _Tracker } from "./bg-tasks";

test("lsof -F pca: chỉ lấy tiến trình mở tệp để ghi", () => {
  const out = "p100\ncbash\nf1\naw\np200\nctail\nf3\nar\np300\ncnode\nf1\nau\nf2\nau\n";
  expect(_parseLsof(out)).toEqual([{ pid: 100, cmd: "bash" }, { pid: 300, cmd: "node" }]);
});

test("stop: dừng tiến trình ghi tệp output rồi đánh dấu đã dừng; không tệp thì báo lỗi", async () => {
  const tr = new _Tracker("/tmp", () => {}, undefined, () => 1000, 60_000);
  const a = tr.add({ kind: "detached", command: "nohup ./srv > /tmp/x-never.log 2>&1 &", host: "local", file: "/tmp/x-never.log" })!;
  const calls: string[] = [];
  const r = await tr.stop(a.id, "@sep", async (f, h) => { calls.push(`${h}:${f}`); return { ok: true, pids: [42] }; });
  expect(r).toEqual({ ok: true, pids: [42] });
  expect(calls).toEqual(["local:/tmp/x-never.log"]);
  expect(a.status).toBe("killed");
  expect(a.note).toContain("@sep");
  expect((await tr.stop(a.id, "x", async () => ({ ok: false, error: "không gọi" }))).ok).toBe(true); // đã dừng: không gọi lại
  const b = tr.add({ kind: "bash_bg", command: "sleep 100", host: "local" })!;
  expect((await tr.stop(b.id)).ok).toBe(false);
  expect(b.status).toBe("running");
  expect((await tr.stop("bg-khong-co")).ok).toBe(false);
  tr.stopAll();
});

test("tiến trình ghi tệp đã thoát (lsof không còn ai ghi, hai lần liền): chốt xong ngay, kể cả khi lượt chưa xong", async () => {
  const { WRITER_IDLE_MS, WRITER_CHECK_MS } = await import("./bg-tasks");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bg-"));
  const f = path.join(dir, "build.log");
  fs.writeFileSync(f, "đang build\n");
  let t = 1_000_000, writing = true, asked = 0;
  const tr = new BgTracker(dir, () => {}, undefined, () => t, 20, async () => { asked++; return writing; });
  const task = tr.add({ kind: "detached", command: "nohup ./build.sh > build.log 2>&1 &", host: "local", file: "build.log" })!;
  await Bun.sleep(60);
  t += WRITER_IDLE_MS + 1;
  await Bun.sleep(60);
  expect(asked).toBeGreaterThan(0);
  expect(task.status).toBe("running"); // còn tiến trình ghi
  writing = false;
  t += WRITER_CHECK_MS + 1; await Bun.sleep(60);
  expect(task.status).toBe("running"); // mới một lần không thấy
  t += WRITER_CHECK_MS + 1; await Bun.sleep(60);
  expect(task.status).toBe("done");
  expect(task.note).toContain("đã kết thúc");
  fs.rmSync(dir, { recursive: true });
});
