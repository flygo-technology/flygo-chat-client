import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Adb, elements, fmtScreen, inputTextArg, isRisky, keyCode, Locks, parseDevices, parseXml, readOnlyShell, type AdbCtx, type Exec } from "./adb-tools";

const XML = `<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0">
<node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="com.android.settings" clickable="false" scrollable="false" enabled="true" bounds="[0,0][1080,2400]">
  <node index="0" text="Settings" resource-id="com.android.settings:id/title" class="android.widget.TextView" package="com.android.settings" clickable="false" enabled="true" bounds="[60,420][412,510]" />
  <node index="1" text="" resource-id="com.android.settings:id/recycler" class="androidx.recyclerview.widget.RecyclerView" package="com.android.settings" clickable="false" scrollable="true" enabled="true" bounds="[0,560][1080,2400]">
    <node index="0" text="" resource-id="" class="android.widget.LinearLayout" package="com.android.settings" clickable="true" enabled="true" bounds="[0,770][1080,1000]">
      <node index="0" text="Network &amp; internet" resource-id="android:id/title" class="android.widget.TextView" package="com.android.settings" clickable="false" enabled="true" bounds="[200,800][700,860]" />
      <node index="1" text="Mobile, Wi‑Fi" resource-id="android:id/summary" class="android.widget.TextView" package="com.android.settings" clickable="false" enabled="true" bounds="[200,870][700,920]" />
    </node>
    <node index="1" text="" resource-id="" class="android.widget.LinearLayout" package="com.android.settings" clickable="true" enabled="true" bounds="[0,1000][1080,1230]">
      <node index="0" text="Giới thiệu về điện thoại" resource-id="android:id/title" class="android.widget.TextView" package="com.android.settings" clickable="false" enabled="true" bounds="[200,1030][900,1090]" />
    </node>
    <node index="2" text="" resource-id="com.x:id/q" class="android.widget.EditText" package="com.android.settings" clickable="true" enabled="true" password="false" bounds="[0,1300][1080,1400]" />
    <node index="3" text="Wi-Fi" resource-id="" class="android.widget.Switch" package="com.android.settings" checkable="true" checked="true" clickable="true" enabled="true" bounds="[900,1500][1040,1560]" />
    <node index="4" text="Hidden" resource-id="" class="android.widget.TextView" package="com.android.settings" clickable="false" enabled="true" bounds="[0,0][0,0]" />
  </node>
</node></hierarchy>`;

test("elements: dòng bấm được lấy chữ của con, không lặp chữ con, bỏ phần tử không có diện tích", () => {
  const els = elements(parseXml(XML), { w: 1080, h: 2400 });
  const lines = els.map((e) => `${e.role}|${e.label}`);
  expect(lines).toEqual([
    "text|Settings", "list|", "item|Network & internet · Mobile, Wi‑Fi", "item|Giới thiệu về điện thoại", "input|", "switch|Wi-Fi",
  ]);
  const sw = els.find((e) => e.role === "switch")!;
  expect([sw.x, sw.y, sw.checked]).toEqual([970, 1530, true]);
  const s = fmtScreen({ serial: "emu", app: "com.android.settings/.Settings", w: 1080, h: 2400, els, at: 0, keyboard: false });
  expect(s).toContain("[e2] list #recycler (540,1480) scroll");
  expect(s).toContain("[e5] input #q (540,1350) edit");
  expect(s).toContain("[e6] switch \"Wi-Fi\" (970,1530) on");
});

test("parseDevices", () => {
  const d = parseDevices("List of devices attached\nemulator-5564          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa transport_id:1\nR5CR618NHTA unauthorized usb:1-1 transport_id:2\n\n");
  expect(d).toEqual([
    { serial: "emulator-5564", state: "device", model: "sdk gphone64 x86 64", product: "sdk_gphone64_x86_64", transport: "1" },
    { serial: "R5CR618NHTA", state: "unauthorized", model: "", product: "", transport: "2" },
  ]);
});

test("readOnlyShell: chỉ một lệnh đọc, không nối / chuyển hướng", () => {
  for (const c of ["getprop ro.product.model", "dumpsys battery", "pm list packages -3", "settings get global adb_enabled", "wm size", "ls /sdcard"]) expect(readOnlyShell(c)).toBe(true);
  for (const c of ["settings put global x 1", "getprop; rm -rf /sdcard", "cat /x > /y", "pm clear com.x", "rm /sdcard/a", "ls $(rm x)", "am start -n x/.Y"]) expect(readOnlyShell(c)).toBe(false);
});

test("isRisky: nút gửi / thanh toán (cả tiếng Việt có dấu)", () => {
  for (const l of ["Send", "Gửi", "Thanh toán", "Chuyển tiền", "Xác nhận", "Mua ngay", "Đặt hàng", "Xoá"]) expect(isRisky(l)).toBe(true);
  for (const l of ["About phone", "Giới thiệu về điện thoại", "Network & internet", "Sender info"]) expect(isRisky(l)).toBe(false);
});

test("keyCode + inputTextArg", () => {
  expect(keyCode("back")).toBe("KEYCODE_BACK");
  expect(keyCode("KEYCODE_CAMERA")).toBe("KEYCODE_CAMERA");
  expect(keyCode("rm -rf")).toBeNull();
  expect(inputTextArg("it's 5% off")).toBe(`'it'\\''s%s5\\%%soff'`);
});

test("Locks: người khác giữ thì từ chối, hết hạn thì nhận, chỉ người giữ được trả", () => {
  let now = 1_000;
  const l = new Locks(mkdtempSync(join(tmpdir(), "adb-locks-")), () => now);
  expect(l.acquire("emu", "a", "bot A").ok).toBe(true);
  const r = l.acquire("emu", "b", "bot B");
  expect(r.ok).toBe(false);
  expect(l.release("emu", "b")).toBe(false);
  now += 11 * 60_000;
  expect(l.acquire("emu", "b", "bot B").ok).toBe(true);
  expect(l.heldBy("b")).toEqual(["emu"]);
  expect(l.release("emu", "b")).toBe(true);
});

function fake(devs = "List of devices attached\nemu device model:Pixel_6 transport_id:1\n") {
  const calls: string[][] = [];
  const exec: Exec = async (args) => {
    calls.push(args);
    const sh = args[2] === "shell" ? args[3] : "";
    const out = args[0] === "devices" ? devs
      : sh.includes("uiautomator dump") ? XML
      : sh.startsWith("wm size") ? "Physical size: 1080x2400\n  mCurrentFocus=Window{1 u0 com.android.settings/.Settings}\n"
      : sh.startsWith("ime list") ? "com.android.adbkeyboard/.AdbIME\ncom.google.android.inputmethod.latin/.LatinIME\n"
      : sh.startsWith("settings get secure default_input_method") ? "com.google.android.inputmethod.latin/.LatinIME\n"
      : "";
    return { code: 0, out: Buffer.from(out), err: "" };
  };
  return { exec, calls, shells: () => calls.filter((c) => c[2] === "shell").map((c) => c[3]) };
}
const ctx = (over: Partial<AdbCtx> = {}): AdbCtx & { asked: string[]; log: any[] } => {
  const asked: string[] = [], log: any[] = [];
  return { holder: "bot:1", label: "bot", workdir: tmpdir(), approve: async (t) => { asked.push(t); return false; }, audit: (e) => log.push(e), asked, log, ...over };
};
const mk = (f = fake()) => new Adb(f.exec, new Locks(mkdtempSync(join(tmpdir(), "adb-locks-"))), async () => {});

test("tap theo mã phần tử: chạm đúng tâm, trả màn hình mới, ghi nhật ký", async () => {
  const f = fake(), adb = mk(f), c = ctx();
  await adb.tool("adb_snapshot", {}, c);
  const r = await adb.tool("adb_tap", { element: "e4" }, c);
  expect(f.shells()).toContain("input tap 540 1115");
  expect(r.text).toContain("Đã chạm e4 item \"Giới thiệu về điện thoại\"");
  expect(r.text).toContain("[e6] switch");
  expect(c.log.map((e) => [e.tool, e.ok])).toEqual([["adb_snapshot", true], ["adb_tap", true]]);
});

test("xoá dữ liệu app / lệnh shell ghi / cài app phải xin duyệt; bị từ chối thì không chạy", async () => {
  const f = fake(), adb = mk(f), c = ctx();
  await expect(adb.tool("adb_app", { action: "clear", package: "com.x" }, c)).rejects.toThrow("không duyệt");
  await expect(adb.tool("adb_shell", { command: "settings put global x 1" }, c)).rejects.toThrow("không duyệt");
  await expect(adb.tool("adb_shell", { command: "pm clear com.x" }, c)).rejects.toThrow("adb_app");
  expect(c.asked.length).toBe(2);
  expect(f.shells().some((s) => s.includes("pm clear") || s.includes("settings put"))).toBe(false);
  await adb.tool("adb_shell", { command: "getprop ro.product.model" }, c);
  expect(c.asked.length).toBe(2);
});

test("gõ tiếng Việt: bật ADBKeyboard tạm, gửi base64, trả lại bàn phím cũ", async () => {
  const f = fake(), adb = mk(f);
  await adb.tool("adb_type", { text: "Xin chào" }, ctx());
  const sh = f.shells();
  const b64 = Buffer.from("Xin chào").toString("base64");
  expect(sh.some((s) => s.includes(`ADB_INPUT_B64 --es msg '${b64}'`))).toBe(true);
  expect(sh.some((s) => s === "ime set 'com.google.android.inputmethod.latin/.LatinIME' >/dev/null")).toBe(true);
});

test("hai máy thì phải chọn device; máy đang bị bot khác giữ thì báo", async () => {
  const f = fake("List of devices attached\nemu device model:Pixel_6\nR5CR618NHTA device model:SM_G998B\n");
  const adb = mk(f);
  await expect(adb.tool("adb_snapshot", {}, ctx())).rejects.toThrow("chọn device");
  await adb.tool("adb_snapshot", { device: "emu" }, ctx({ holder: "other", label: "@jessica" }));
  await expect(adb.tool("adb_snapshot", { device: "emu" }, ctx())).rejects.toThrow("@jessica");
});

test("màn hình không idle: xin duyệt chép u2.jar; từ chối thì báo dùng ảnh", async () => {
  const f = fake();
  const base = f.exec;
  const exec: Exec = async (args, o) => (args[2] === "shell" && args[3].includes("uiautomator dump") ? { code: 0, out: Buffer.from(""), err: "" } : base(args, o));
  const { U2 } = await import("./adb-tools");
  const adb = new Adb(exec, new Locks(mkdtempSync(join(tmpdir(), "adb-locks-"))), async () => {}, new U2("adb", exec, mkdtempSync(join(tmpdir(), "u2-"))));
  const c = ctx();
  await expect(adb.tool("adb_snapshot", {}, c)).rejects.toThrow("image=true");
  expect(c.asked[0]).toContain("uiautomator2");
});

test("u2 trả cả thanh trạng thái: bỏ com.android.systemui trừ khi all", () => {
  const xml = `<hierarchy><node package="com.android.systemui" class="android.widget.TextView" text="3:05" bounds="[0,0][100,50]" /><node package="com.x" class="android.widget.Button" text="OK" clickable="true" bounds="[0,100][100,200]" /></hierarchy>`;
  expect(elements(parseXml(xml)).map((e) => e.label)).toEqual(["OK"]);
  expect(elements(parseXml(xml), undefined, true).map((e) => e.label)).toEqual(["3:05", "OK"]);
});
