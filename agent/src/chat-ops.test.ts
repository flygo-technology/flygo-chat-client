import { afterAll, beforeEach, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createChatOps, isTextFile, safeFileName, type ChatCtx } from "./chat-ops";

// Máy chủ giả: kênh, thành viên, tin, tệp; fetch giả cho tải về / tải lên tệp.
const id = (p: string) => (p + "0".repeat(26)).slice(0, 26);
const SERVER = "https://chat.example.test";
const BOT = id("bot"), OWNER = id("owner"), OTHER_USER = id("stranger");
const HERE = id("here"), OTHER = id("other"), SECRET = id("secret");

let channels: Record<string, any>, members: Set<string>, posts: Record<string, any>, files: Record<string, any>, blobs: Record<string, string>;
let created: any[], uploads: { channel: string; name: string; body: string }[], downloads: string[], asks: any[], approveAnswer: "accept" | "decline";
let seq = 0;
// Tin theo kênh cho chat_history theo khoảng thời gian / chat_export (API phân trang before=).
let chanPosts: Record<string, any[]> = {}, pageCalls = 0, refList: any[] = [], refPosts: any[] = [];

function reset() {
  channels = {
    [HERE]: { id: HERE, type: "O", display_name: "Chat này", team_id: "t" },
    [OTHER]: { id: OTHER, type: "P", display_name: "Nhóm khác", team_id: "t" },
    [SECRET]: { id: SECRET, type: "P", display_name: "Nhóm bí mật", team_id: "t" },
  };
  members = new Set([`${HERE}:${BOT}`, `${HERE}:${OWNER}`, `${OTHER}:${BOT}`, `${OTHER}:${OWNER}`, `${SECRET}:${OWNER}`]);
  files = {
    [id("fnote")]: { id: id("fnote"), name: "ghi chu.txt", mime_type: "text/plain", size: 9, post_id: id("pother"), channel_id: OTHER, creator_id: OWNER },
    [id("fimg")]: { id: id("fimg"), name: "anh.png", mime_type: "image/png", size: 4, post_id: id("pother"), channel_id: OTHER, creator_id: OWNER },
    [id("fsec")]: { id: id("fsec"), name: "mat.pdf", mime_type: "application/pdf", size: 3, post_id: id("psecret"), channel_id: SECRET, creator_id: OWNER },
    [id("floose")]: { id: id("floose"), name: "nhap.csv", mime_type: "text/csv", size: 3, post_id: "", channel_id: HERE, creator_id: BOT },
  };
  blobs = { [id("fnote")]: "xin chao!", [id("fimg")]: "PNG!", [id("fsec")]: "pdf", [id("floose")]: "a,b" };
  posts = {
    [id("pother")]: { id: id("pother"), channel_id: OTHER, user_id: OWNER, message: "báo cáo", root_id: "", file_ids: [id("fnote"), id("fimg")], metadata: { files: [files[id("fnote")], files[id("fimg")]] }, create_at: 1 },
    [id("psecret")]: { id: id("psecret"), channel_id: SECRET, user_id: OWNER, message: "bí mật", root_id: "", file_ids: [id("fsec")], metadata: { files: [files[id("fsec")]] }, create_at: 1 },
    // Tin không có metadata.files (chỉ file_ids): runner phải tự hỏi info.
    [id("pbare")]: { id: id("pbare"), channel_id: OTHER, user_id: OWNER, message: "tệp trần", root_id: "", file_ids: [id("fimg")], create_at: 1 },
  };
  created = []; uploads = []; downloads = []; asks = []; approveAnswer = "accept";
  chanPosts = {}; pageCalls = 0; refList = []; refPosts = [];
}

const mm: any = {
  async api(method: string, path: string, body?: any) {
    let m: RegExpMatchArray | null;
    if ((m = path.match(/^\/channels\/(\w+)\/members\/(\w+)$/)) && method === "GET") { if (members.has(`${m[1]}:${m[2]}`)) return {}; throw new Error("404"); }
    if ((m = path.match(/^\/posts\/(\w+)$/)) && method === "GET") { if (posts[m[1]]) return posts[m[1]]; throw new Error("404"); }
    if ((m = path.match(/^\/files\/(\w+)\/info$/))) { if (files[m[1]]) return files[m[1]]; throw new Error("404"); }
    if (path.startsWith("/config/client")) return { MaxFileSize: "1000000" };
    if ((m = path.match(/^\/channels\/(\w+)\/posts\?(.*)$/)) && method === "GET") {
      pageCalls++;
      const q = new URLSearchParams(m[2]);
      const all = [...(chanPosts[m[1]] ?? [])].sort((a, b) => b.create_at - a.create_at); // mới -> cũ như máy chủ
      const before = q.get("before");
      const start = before ? all.findIndex((p) => p.id === before) + 1 : 0;
      const page = all.slice(start, start + Number(q.get("per_page") || 60));
      return { order: page.map((p) => p.id), posts: Object.fromEntries(page.map((p) => [p.id, p])) };
    }
    throw new Error(`api giả chưa hỗ trợ ${method} ${path}`);
  },
  async channel(cid: string) { if (channels[cid]) return channels[cid]; throw new Error("404"); },
  async createPost(p: any) { const r = { ...p, id: id(`new${++seq}`) }; created.push(r); return r; },
  async displayName(uid: string) { return uid === OWNER ? "Sếp" : "Ai đó"; },
};

const realFetch = globalThis.fetch;
globalThis.fetch = (async (url: any, init?: any) => {
  const u = String(url);
  let m: RegExpMatchArray | null;
  if ((m = u.match(/\/api\/v4\/files\/(\w+)$/)) && (!init || !init.method || init.method === "GET")) {
    downloads.push(m[1]);
    return blobs[m[1]] !== undefined ? new Response(blobs[m[1]]) : new Response("", { status: 404 });
  }
  if (u.endsWith("/api/v4/files") && init?.method === "POST") {
    const form = init.body as FormData;
    const f = form.get("files") as File;
    const nid = id(`up${++seq}`);
    uploads.push({ channel: String(form.get("channel_id")), name: f.name, body: await f.text() });
    return Response.json({ file_infos: [{ id: nid, name: f.name }] });
  }
  return new Response("", { status: 500 });
}) as any;
afterAll(() => { globalThis.fetch = realFetch; rmSync(dir, { recursive: true, force: true }); });

const dir = mkdtempSync(join(tmpdir(), "chat-ops-test-"));
const ops = createChatOps({
  mm, serverUrl: SERVER, botToken: "tok", botId: BOT, botName: () => "bot", ownerIds: [OWNER],
  isOwner: (x) => x === OWNER, isAllowed: () => true, db: new Database(":memory:"), log: () => {},
  chatName: async (ch) => ch.display_name, refs: () => refList, refCall: async () => "", onCloseMark: () => {}, kickTurn: async () => {},
  refPage: async (_ref, before, limit) => {
    const all = [...refPosts].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
    const start = before ? all.findIndex((p) => p.id === before) + 1 : 0;
    const page = all.slice(start, start + limit);
    return { posts: page.reverse(), more: page.length === limit };
  },
});
const ctx = (over: Partial<ChatCtx> = {}): ChatCtx => ({
  card: { step() {} } as any, dir, key: `ch:${HERE}`, channelId: HERE, threadRoot: "", assigner: OWNER, runKey: "rk",
  ask: async (req) => { asks.push(req); return approveAnswer; }, ...over,
});

beforeEach(reset);

test("chat-ops: nhận diện tệp văn bản và tên tệp an toàn", () => {
  expect(isTextFile("text/plain", "a.bin")).toBe(true);
  expect(isTextFile("application/octet-stream", "x.md")).toBe(true);
  expect(isTextFile("image/png", "a.png")).toBe(false);
  expect(safeFileName("a/b:c.txt", "f")).toBe("a_b_c.txt");
  expect(safeFileName("", "fallback")).toBe("fallback");
});

test("chat_get_files: tải tệp của tin ở chat khác, trả nội dung tệp văn bản", async () => {
  const r = await ops.tool("chat_get_files", { post_id: id("pother") }, ctx());
  expect(r).toContain("ghi chu.txt");
  expect(r).toContain(`file_id=${id("fimg")}`);
  expect(r).toContain("xin chao!");
  const saved = join(dir, "attachments", `${id("fnote")}-ghi chu.txt`);
  expect(existsSync(saved)).toBe(true);
  expect(readFileSync(saved, "utf8")).toBe("xin chao!");
  expect(r).not.toContain("PNG!"); // ảnh: chỉ đường dẫn, không nội dung
});

test("chat_get_files: download=false chỉ liệt kê; file_id tự tìm tin; metadata thiếu thì hỏi info", async () => {
  const list = await ops.tool("chat_get_files", { post_id: id("pother"), download: false }, ctx());
  expect(list).toContain("anh.png");
  expect(downloads.length).toBe(0);
  const one = await ops.tool("chat_get_files", { file_id: id("fnote") }, ctx());
  expect(one).toContain("ghi chu.txt");
  expect(one).not.toContain("anh.png");
  const bare = await ops.tool("chat_get_files", { post_id: id("pbare"), download: false }, ctx());
  expect(bare).toContain("anh.png");
});

test("chat_get_files: cùng luật phạm vi — bot không ở chat / người giao việc không ở chat thì từ chối", async () => {
  await expect(ops.tool("chat_get_files", { post_id: id("psecret") }, ctx())).rejects.toThrow(/bot không là thành viên/);
  await expect(ops.tool("chat_get_files", { post_id: id("pother") }, ctx({ assigner: OTHER_USER }))).rejects.toThrow(/người giao việc không là thành viên/);
  expect(downloads.length).toBe(0);
});

test("chat_send file_ids sang chat khác: xin duyệt, tải về rồi tải lên chat đích", async () => {
  const r = await ops.tool("chat_send", { to: OTHER, message: "gửi lại", file_ids: [id("fnote")] }, ctx());
  expect(asks.length).toBe(1);
  expect(asks[0].detail).toContain("ghi chu.txt");
  expect(uploads).toEqual([{ channel: OTHER, name: "ghi chu.txt", body: "xin chao!" }]);
  expect(created.length).toBe(1);
  expect(created[0].channel_id).toBe(OTHER);
  expect(created[0].file_ids.length).toBe(1);
  expect(created[0].file_ids[0]).not.toBe(id("fnote")); // tệp đã gắn tin khác: không gắn lại id cũ
  expect(r).toContain("Đã gửi");
});

test("chat_send file_ids vào chat hiện tại: không cần duyệt, tệp đã gắn tin vẫn phải tải lại", async () => {
  await ops.tool("chat_send", { to: "here", message: "", file_ids: [id("fimg")] }, ctx());
  expect(asks.length).toBe(0);
  expect(uploads.map((u) => u.channel)).toEqual([HERE]);
  expect(created[0].file_ids.length).toBe(1);
});

test("chat_send file_ids: tệp chưa gắn tin do bot tải lên đúng kênh đích thì dùng lại id", async () => {
  await ops.tool("chat_send", { to: "here", message: "x", file_ids: [id("floose")] }, ctx());
  expect(downloads.length).toBe(0);
  expect(uploads.length).toBe(0);
  expect(created[0].file_ids).toEqual([id("floose")]);
});

test("chat_send file_ids: tin nguồn ngoài phạm vi thì từ chối trước khi xin duyệt", async () => {
  await expect(ops.tool("chat_send", { to: OTHER, message: "x", file_ids: [id("fsec")] }, ctx())).rejects.toThrow(/bot không là thành viên/);
  await expect(ops.tool("chat_send", { to: OTHER, message: "x", file_ids: ["khong-hop-le"] }, ctx())).rejects.toThrow(/không hợp lệ/);
  expect(asks.length).toBe(0);
  expect(created.length).toBe(0);
  expect(uploads.length).toBe(0);
});

test("chat_send file_ids: không duyệt thì không tải gì, không gửi", async () => {
  approveAnswer = "decline";
  const r = await ops.tool("chat_send", { to: OTHER, message: "x", file_ids: [id("fnote")] }, ctx());
  expect(r).toContain("không duyệt");
  expect(downloads.length + uploads.length + created.length).toBe(0);
});

test("chat_send: quá 10 tệp (files + file_ids) thì báo lỗi", async () => {
  const many = Array.from({ length: 11 }, (_, i) => id(`f${i}x`));
  await expect(ops.tool("chat_send", { to: OTHER, message: "x", file_ids: many }, ctx())).rejects.toThrow(/Tối đa 10/);
});

test("chat_reply file_ids: trả lời trong luồng kèm tệp của tin khác", async () => {
  const r = await ops.tool("chat_reply", { post_id: id("pother"), message: "đây", file_ids: [id("fimg")] }, ctx());
  expect(asks.length).toBe(1); // tin ở chat khác: cần duyệt
  expect(created[0].root_id).toBe(id("pother"));
  expect(created[0].channel_id).toBe(OTHER);
  expect(uploads.map((u) => u.name)).toEqual(["anh.png"]);
  expect(r).toContain("Đã trả lời");
});

test("chat_forward: mang theo đủ tệp của tin (kể cả tin chỉ có file_ids) và báo tệp lỗi", async () => {
  await ops.tool("chat_forward", { post_id: id("pother"), to: "here" }, ctx());
  expect(uploads.map((u) => u.name).sort()).toEqual(["anh.png", "ghi chu.txt"]);
  expect(created[0].file_ids.length).toBe(2);
  expect(created[0].props.flygo_forwarded).toBe(true);
  reset();
  await ops.tool("chat_forward", { post_id: id("pbare"), to: "here" }, ctx());
  expect(created[0].file_ids.length).toBe(1);
  reset();
  delete blobs[id("fimg")];
  const r = await ops.tool("chat_forward", { post_id: id("pother"), to: "here" }, ctx());
  expect(created[0].file_ids.length).toBe(1);
  expect(r).toContain("anh.png: tải về lỗi 404");
});

// ---- lịch sử theo khoảng thời gian / xuất lịch sử (0.6.73) ----
const T0 = Date.parse("2026-11-01T00:00:00+07:00");
function seedOther(n: number) {
  chanPosts[OTHER] = Array.from({ length: n }, (_, i) => ({
    id: id(`h${String(i).padStart(4, "0")}`), channel_id: OTHER, user_id: i % 2 ? OWNER : OTHER_USER, create_at: T0 + i * 3600_000,
    message: `tin ${i}`, root_id: i % 10 === 5 ? id("h0000") : "", metadata: i === 3 ? { files: [{ id: id("fx"), name: "bao-cao.pdf", size: 10 }], reactions: [{ user_id: OWNER, emoji_name: "+1" }] } : {},
    ...(i === 4 ? { edit_at: T0 + i * 3600_000 + 60_000 } : {}),
  }));
  chanPosts[OTHER].push({ id: id("hsys"), channel_id: OTHER, user_id: BOT, create_at: T0 + 30 * 60_000, message: "", type: "system_join_channel" });
}

test("chat_history from/to: đọc xuôi từ from, lọc theo khoảng, gợi ý đọc tiếp bằng mốc ms", async () => {
  seedOther(500);
  const r = await ops.tool("chat_history", { chat: OTHER, from: "2026-11-02", to: "2026-11-03", limit: 5 }, ctx());
  // 2026-11-02 00:00 (+7) = giờ thứ 24 -> tin 24..28; to = hết ngày 03 -> 72 tin trong khoảng.
  expect(r).toContain("5/48 tin");
  expect(r).toMatch(/tin 24\b[\s\S]*tin 28\b/);
  expect(r).not.toContain("tin 23 ");
  expect(r).not.toContain("tin 29");
  expect(r).toContain(`from=${T0 + 28 * 3600_000 + 1}`);
  const back = await ops.tool("chat_history", { chat: OTHER, to: T0 + 10 * 3600_000, limit: 3 }, ctx());
  expect(back).toMatch(/tin 8\b[\s\S]*tin 10\b/);
  expect(back).toContain(`to=${T0 + 8 * 3600_000 - 1}`);
});

test("chat_history from/to: tin hệ thống bị bỏ, ngoài phạm vi thì từ chối", async () => {
  seedOther(3);
  const r = await ops.tool("chat_history", { chat: OTHER, from: T0 - 1 }, ctx());
  expect(r).toContain("3 tin");
  await expect(ops.tool("chat_history", { chat: SECRET, from: "1d" }, ctx())).rejects.toThrow(/bot không là thành viên/);
  expect(await ops.tool("chat_history", { chat: OTHER, from: "không phải ngày" }, ctx())).toContain("không hợp lệ");
});

test("chat_export: phân trang hết khoảng, ghi tệp md kèm luồng, tệp, cảm xúc, sửa", async () => {
  seedOther(450); // 3 trang 200
  const steps: any[] = [];
  const r = await ops.tool("chat_export", { chat: OTHER, threads: "nested" }, ctx({ card: { step: (s: any) => steps.push(s) } as any }));
  expect(pageCalls).toBe(3);
  const path = r.match(/ra tệp md: (\S+\.md)/)![1];
  const body = readFileSync(path, "utf8");
  expect(r).toContain("450 tin");
  expect(r).toContain("405 ở chat chính, 45 trả lời");
  expect(body).toContain("bao-cao.pdf (file_id=");
  expect(body).toContain(":+1: Sếp");
  expect(body).toMatch(/#h0004\w* \(sửa /);
  // nested: các trả lời của luồng h0000 nằm ngay sau tin gốc
  const lines = body.split("\n");
  const rootAt = lines.findIndex((l) => l.includes(`#${id("h0000")}`));
  expect(lines[rootAt + 1]).toMatch(/^ {4}- .*tin 5\b/);
  expect(body).not.toContain("system_join");
  expect(steps.at(-1).status).toBe("done");
});

test("chat_export: jsonl, khoảng thời gian và trần max_posts (giữ phần mới nhất, ghi lệnh xuất tiếp)", async () => {
  seedOther(300);
  const r = await ops.tool("chat_export", { chat: OTHER, from: T0 + 100 * 3600_000, format: "jsonl", max_posts: 50, threads: "none" }, ctx());
  const path = r.match(/ra tệp jsonl: (\S+\.jsonl)/)![1];
  const rows = readFileSync(path, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  expect(rows.length).toBeLessThanOrEqual(50);
  expect(rows.every((x) => !x.root_id)).toBe(true);
  expect(rows[rows.length - 1].message).toBe("tin 299");
  expect(r).toContain("CHƯA ĐỦ");
  expect(r).toContain(`to=${Date.parse(rows[0].at) - 1}`);
});

test("chat_export: chat được tag đi qua relay theo trang 50 tin", async () => {
  refList = [{ ref_id: "r1", name: "Nhóm đối tác", write: false, kind: "chat", channel_id: "x" }];
  refPosts = Array.from({ length: 120 }, (_, i) => ({ id: id(`rp${String(i).padStart(3, "0")}x`), user: "Khách", at: new Date(T0 + i * 60_000).toISOString(), message: `ref ${i}`, root_id: "", file_list: i === 7 ? [{ id: id("rf"), name: "hd.xlsx", size: 5 }] : [] }));
  const r = await ops.tool("chat_export", { chat: "r1" }, ctx());
  expect(r).toContain("120 tin");
  expect(r).toContain("quyền tạm");
  const body = readFileSync(r.match(/ra tệp md: (\S+\.md)/)![1], "utf8");
  expect(body).toContain("hd.xlsx");
  expect(body).toContain("ref 0");
  expect(body).toContain("ref 119");
});
